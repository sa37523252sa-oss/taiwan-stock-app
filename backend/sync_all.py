"""
一次跑完所有資料下載。

FinMind 免費會員每小時 600 次請求，而完整回補需要：

    股價    每檔 1 次   × 待處理檔數
    股利    每檔 1 次   × 待處理檔數
    財報    每檔 5 次   × 待處理檔數

所以不可能一次跑完。這支程式的做法是：設定本次的額度預算，
依優先順序把預算花掉，花完就停，狀態全部存在資料庫裡，下次
執行自動接續。

優先順序是有理由的：
    1. 股價  ── 什麼都要用到，缺了連偵測都不能跑
    2. 股利  ── 還原股價的關鍵；小額除權只能靠這個
    3. 財報  ── 最貴（每檔 5 次），但更新頻率最低

用法：
    python sync_all.py                    # 預設 550 次額度
    python sync_all.py --budget 300       # 只花 300 次
    python sync_all.py --wait             # 額度用完就等一小時繼續
    python sync_all.py --only price       # 只跑股價
    python sync_all.py --skip-detect      # 不跑偵測與還原
"""

import sys
import time
from datetime import datetime

from schema import ensure_schema
from fetch_cache import (
    ensure_fetch_log,
    price_queue,
    financial_queue,
    quota_blocked,
    clear_quota_block,
    QuotaReached,
)

HOURLY_LIMIT = 550
FINANCIAL_CALLS_PER_STOCK = 5


class Budget:
    """本次執行還能打幾次 API"""

    def __init__(self, total):
        self.total = total
        self.used = 0

    def left(self):
        return self.total - self.used

    def spend(self, n=1):
        self.used += n

    def can(self, n=1):
        return self.left() >= n

    def __str__(self):
        return f"{self.used}/{self.total}"


def banner(title):
    print()
    print("=" * 58)
    print(f"  {title}")
    print("=" * 58)


def wait_for_reset(minutes=61):
    """額度是滾動一小時，睡過頭一點比較保險"""

    print(f"\n等待額度回補，{minutes} 分鐘後繼續 "
          f"（{datetime.now().strftime('%H:%M')} 開始）")

    for remaining in range(minutes, 0, -10):
        print(f"  還有 {remaining} 分鐘...")
        time.sleep(min(10, remaining) * 60)

    clear_quota_block()
    print("繼續執行\n")


# ==========================================================
# 各階段
# ==========================================================

def step_prices(budget):

    from update_price import update_one_stock

    banner("股價")

    pending = price_queue(cooldown_days=7)

    if not pending:
        print("已是最新，沒有待處理的股票")
        return True

    take = min(len(pending), budget.left())

    print(f"待處理 {len(pending)} 檔，本次跑 {take} 檔（額度 {budget}）")

    codes = pending[:take]

    ok, empty = 0, 0

    for i, code in enumerate(codes, 1):

        if not budget.can():
            break

        try:
            if update_one_stock(code):
                ok += 1
            else:
                empty += 1

        except QuotaReached:
            print(f"\n額度用完，停在 {i}/{len(codes)}")
            budget.used = budget.total
            return False

        except Exception as e:
            print(f"  {code} 失敗: {str(e)[:80]}")

        budget.spend()

        if i % 50 == 0:
            print(f"  ...{i}/{len(codes)}  額度 {budget}")

    remaining = len(price_queue(cooldown_days=7))

    print(f"\n成功 {ok}，無資料 {empty}，剩餘待處理 {remaining} 檔")

    return remaining == 0


def step_dividends(budget):

    from detect_gaps import (
        fetch_dividends_for, stocks_with_actions, get_codes_with_prices,
    )

    banner("股利與公司行動")

    have = stocks_with_actions()
    pending = [c for c in get_codes_with_prices() if c not in have]

    if not pending:
        print("已是最新，沒有待處理的股票")
        return True

    take = min(len(pending), budget.left())

    print(f"待處理 {len(pending)} 檔，本次跑 {take} 檔（額度 {budget}）")

    done = fetch_dividends_for(pending[:take])

    budget.spend(take)

    remaining = len(pending) - take

    print(f"剩餘待處理 {remaining} 檔")

    return remaining == 0


def step_financials(budget):

    from update_financial import update_one_financial

    banner("財報與月營收")

    pending = financial_queue()

    if not pending:
        print("已是最新，沒有待處理的股票")
        return True

    take = min(len(pending), budget.left() // FINANCIAL_CALLS_PER_STOCK)

    if take <= 0:
        print(f"額度不足（剩 {budget.left()} 次，每檔要 "
              f"{FINANCIAL_CALLS_PER_STOCK} 次），這階段跳過")
        return False

    print(f"待處理 {len(pending)} 檔，本次跑 {take} 檔（額度 {budget}）")

    ok = 0

    for i, code in enumerate(pending[:take], 1):

        if not budget.can(FINANCIAL_CALLS_PER_STOCK):
            break

        try:
            if update_one_financial(code):
                ok += 1

        except QuotaReached:
            print(f"\n額度用完，停在 {i}/{take}")
            budget.used = budget.total
            return False

        except Exception as e:
            print(f"  {code} 失敗: {str(e)[:80]}")

        budget.spend(FINANCIAL_CALLS_PER_STOCK)

        if i % 10 == 0:
            print(f"  ...{i}/{take}  額度 {budget}")

    remaining = len(financial_queue())

    print(f"\n成功 {ok}，剩餘待處理 {remaining} 檔")

    return remaining == 0


def step_detect():
    """偵測與還原都只讀資料庫，不打 API，額度用完也能跑"""

    from detect_gaps import (
        flag_exempt_stocks, build_market_calendar, load_asset_types,
        load_exempt, get_codes_with_prices, scan_one, classify,
        report, auto_apply,
    )

    banner("跳空偵測與還原")

    flag_exempt_stocks()

    days, prev_map = build_market_calendar()
    asset_types = load_asset_types()
    exempt = load_exempt()

    findings = []

    for code in get_codes_with_prices():
        findings.extend(
            scan_one(code, prev_map, asset_types.get(code, ""), exempt=exempt)
        )

    buckets, market_days, offenders = classify(findings)

    report(buckets, market_days, offenders)

    auto_apply(buckets, dry_run=False, fill_uncovered=True)


# ==========================================================

def main():

    flags = {a for a in sys.argv[1:] if a.startswith("--")}

    budget_total = HOURLY_LIMIT

    for a in sys.argv[1:]:
        if a.startswith("--budget="):
            budget_total = int(a.split("=", 1)[1])

    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = a.split("=", 1)[1]

    wait = "--wait" in flags

    print(f"開始：{datetime.now().strftime('%Y-%m-%d %H:%M')}")

    ensure_schema()
    ensure_fetch_log()

    steps = [
        ("price", step_prices),
        ("dividend", step_dividends),
        ("financial", step_financials),
    ]

    while True:

        budget = Budget(budget_total)

        all_done = True

        for name, fn in steps:

            if only and name != only:
                continue

            if not budget.can():
                all_done = False
                break

            if quota_blocked():
                all_done = False
                break

            if not fn(budget):
                all_done = False

        if all_done:
            print("\n所有資料都是最新的")
            break

        if not wait:
            banner("本次額度用完")
            print("等一小時後再執行一次，會自動從斷點接續：")
            print("  python sync_all.py")
            break

        wait_for_reset()

    if "--skip-detect" not in flags and not only:
        step_detect()

    print(f"\n結束：{datetime.now().strftime('%Y-%m-%d %H:%M')}")


if __name__ == "__main__":
    main()