"""
缺口偵測：找出「股價跳空但沒有對應公司行動」的日子。

分割和減資 FinMind 沒有資料集，所以 corporate_actions 表裡
永遠不會自己長出這兩種事件。漏掉的話，那幾檔的長期回測會在
某一天憑空多出或少掉幾十趴的報酬。

偵測方式是對帳：

    理論參考價 = (前日收盤 − cash_per_share) / share_ratio
    實際收盤價 = prices 表裡的價格

台股單日漲跌幅限制是 ±10%，超過就一定不是正常交易——不是
除權息就是資料有問題，沒有第三種可能。這讓門檻很好設。

這支程式只產生「待確認清單」，不會自動改資料。誤判一定會有
（興櫃轉上市、長期停牌後復牌、資料源本身缺漏），要人工看過
再用 add_manual_action() 補進去。

用法：
    python detect_gaps.py              # 掃全部有股價的股票
    python detect_gaps.py 2330 2317    # 只掃指定幾檔
"""

import sys
from datetime import datetime

from database import get_connection
from corporate_actions import get_actions, merge_same_day

# 台股漲跌幅限制 10%，設 15% 留緩衝
THRESHOLD = 0.15

# 沒有漲跌幅限制的標的（國外成分/槓桿反向/期貨 ETF、興櫃）
# 單日本來就可能大幅波動，門檻要放寬很多
NO_LIMIT_THRESHOLD = 0.60

# 同一天有這麼多檔一起跳空 → 全市場事件，不是公司行動
MARKET_EVENT_MIN_STOCKS = 5

# 單一標的被標記超過這個次數 → 它不是有很多次公司行動，而是
# 這檔本身沒有漲跌幅限制（興櫃）或資料有問題。台股一檔股票
# 二十幾年下來的除權次數不會超過這個量級。
MAX_FLAGS_PER_STOCK = 10

# 前後兩個交易日相隔超過這麼多天，就當作停牌
SUSPENSION_DAYS = 30


def build_market_calendar():
    """
    用整個 prices 表反推市場的交易日。單日只有零星幾檔有資料的
    日期不算數（那是資料缺漏，不是真的開市）。

    回傳 (交易日排序清單, {日期: 前一個交易日})
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT date, COUNT(*) AS n FROM prices
        GROUP BY date ORDER BY date ASC
    """)

    rows = [(r["date"], r["n"]) for r in cur.fetchall()]

    conn.close()

    if not rows:
        return [], {}

    peak = max(n for _, n in rows)
    floor = max(3, peak * 0.1)

    days = [d for d, n in rows if n >= floor]

    prev_map = {days[i]: days[i - 1] for i in range(1, len(days))}

    return days, prev_map


def load_asset_types():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT code, asset_type FROM stocks")

    out = {r["code"]: (r["asset_type"] or "").upper() for r in cur.fetchall()}

    conn.close()

    return out


def flag_exempt_stocks(window_days=30, cluster_min=3, min_days=250,
                       clear_first=True):
    """
    從價格資料反推哪些標的沒有漲跌幅限制。

    判別依據是「群聚性」，不是總次數——這兩件事很容易混淆：

      沒有漲跌幅限制（興櫃、國外成分 ETF、槓桿 ETF）
        → 大波動擠在同一段時間，00672L 在 2020 年 3 月一個月
          內就有十幾天

      有限制但除權沒登記
        → 一年一次、分散在二十年裡，一個月內不可能三次

    所以條件改成「任一 30 天視窗內出現 3 次以上超過 ±10.5%」。
    用總次數比率會把 1269（13/2217，都是年度除權）誤判成興櫃。

    結果寫進 stocks.price_limit_exempt。
    """

    conn = get_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            "ALTER TABLE stocks ADD COLUMN price_limit_exempt INTEGER DEFAULT 0"
        )
    except Exception:
        pass

    if clear_first:
        cur.execute("UPDATE stocks SET price_limit_exempt = 0")

    cur.execute("SELECT DISTINCT code FROM prices")
    codes = [r["code"] for r in cur.fetchall()]

    flagged, borderline = [], []

    for code in codes:

        cur.execute("""
            SELECT date, close FROM prices
            WHERE code=? AND close > 0 ORDER BY date ASC
        """, (code,))

        rows = [(r["date"], r["close"]) for r in cur.fetchall()]

        if len(rows) < min_days:
            continue

        events = {
            e["ex_date"]: e
            for e in merge_same_day(get_actions(code))
        }

        big_dates = []

        for i in range(1, len(rows)):

            d, px = rows[i]
            _, prev = rows[i - 1]

            ev = events.get(d)
            cash = ev["cash"] if ev else 0.0
            ratio = ev["ratio"] if ev and ev["ratio"] else 1.0

            expected = (prev - cash) / ratio

            if expected > 0 and abs(px / expected - 1) > 0.105:
                big_dates.append(datetime.strptime(d, "%Y-%m-%d"))

        if len(big_dates) < cluster_min:
            continue

        # 滑動視窗找最密集的一段
        best, best_at = 0, None

        for i, d0 in enumerate(big_dates):

            j = i
            while (j + 1 < len(big_dates)
                   and (big_dates[j + 1] - d0).days <= window_days):
                j += 1

            if j - i + 1 > best:
                best = j - i + 1
                best_at = d0

        entry = (code, best, best_at.strftime("%Y-%m"), len(big_dates), len(rows))

        if best >= cluster_min:
            flagged.append(entry)
        elif len(big_dates) >= 5:
            borderline.append(entry)

    for code, *_ in flagged:
        cur.execute(
            "UPDATE stocks SET price_limit_exempt=1 WHERE code=?", (code,)
        )

    conn.commit()
    conn.close()

    print(f"\n標記 {len(flagged)} 檔為「無漲跌幅限制」")
    print(f"{'代號':<9}{'最密集':>7}{'月份':>10}{'總次數':>8}{'交易日':>8}")
    print("-" * 44)

    for code, best, at, total, days in sorted(flagged, key=lambda x: -x[1]):
        print(f"{code:<9}{best:>7}{at:>10}{total:>8}{days:>8}")

    if borderline:
        print(f"\n以下 {len(borderline)} 檔沒有群聚，判定為「有限制但除權未登記」，"
              f"保留在候選清單裡：")
        for code, best, at, total, days in sorted(borderline, key=lambda x: -x[3]):
            print(f"  {code:<8} {total} 次分散在 {days} 個交易日，"
                  f"最密集 {best} 次/{window_days}天")

    return flagged


def load_exempt():

    conn = get_connection()
    cur = conn.cursor()

    try:
        cur.execute("SELECT code FROM stocks WHERE price_limit_exempt=1")
        out = {r["code"] for r in cur.fetchall()}
    except Exception:
        out = set()

    conn.close()

    return out


def has_no_price_limit(code, asset_type="", exempt=()):
    """
    這檔標的有沒有漲跌幅限制。

    台股的 ±10% 限制不適用於：國外成分證券 ETF、槓桿/反向 ETF、
    期貨 ETF、興櫃股票。這些標的單日跌 30% 是正常行情，不是
    公司行動——2020 年 3 月的原油和 VIX ETF 就是最好的例子。
    """

    # 資料反推的結果優先。asset_type 不可靠——興櫃股票在你的
    # 資料裡全被標成 STOCK。
    if code in exempt:
        return True

    # 用代號後綴判斷，不要用 asset_type 一刀切——國內成分 ETF
    # （0050、0056、006208、00878）跟普通股一樣受 ±10% 限制，
    # 把它們一起排除掉的話，0050 那種真的分割就永遠偵測不到。
    if code.startswith("00") and code[-1] in ("L", "R", "U", "B"):
        return True

    # 創新板/受益證券
    if code.startswith("02"):
        return True

    # 存託憑證
    if asset_type in ("TDR", "DR"):
        return True

    return False


def action_count():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) AS n FROM corporate_actions")
    n = cur.fetchone()["n"]

    conn.close()

    return n


def get_codes_with_prices():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT DISTINCT code FROM prices ORDER BY code")

    codes = [r["code"] for r in cur.fetchall()]

    conn.close()

    return codes


def get_closes(code):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT date, close FROM prices
        WHERE code=? AND close IS NOT NULL AND close > 0
        ORDER BY date ASC
    """, (code,))

    rows = [(r["date"], r["close"]) for r in cur.fetchall()]

    conn.close()

    return rows


# 新股上市前幾天沒有漲跌幅限制，不能拿來推論公司行動
IPO_FREE_DAYS = 10

# 推估乘數跟常見比例差在這個範圍內就吸附過去。0050 那天算出來
# 是 3.966，正確答案是 4.0，那 0.86% 是當天真實漲幅。
#
# 容差設 2% 而不是更寬：減資比例本來就不一定乾淨，放太寬會把
# 乘數 0.855 硬說成「減資 10%」，等於用猜的蓋掉真相。
SNAP_TOLERANCE = 0.02

COMMON_RATIOS = {
    2.0: "1 股拆 2 股", 3.0: "1 股拆 3 股",
    4.0: "1 股拆 4 股", 5.0: "1 股拆 5 股",
    10.0: "面額 10→1 元（1 拆 10）",
    0.9: "減資 10%", 0.8: "減資 20%", 0.75: "減資 25%",
    0.7: "減資 30%", 0.6: "減資 40%", 0.5: "減資 50%",
}


def snap_ratio(ratio):
    """回傳 (吸附後乘數, 說明, 是否吸附成功)。乾淨比例＝信心較高"""

    for k, label in COMMON_RATIOS.items():
        if abs(ratio - k) / k < SNAP_TOLERANCE:
            return k, label, True

    if ratio > 1:
        return ratio, f"疑似除權/分割（乘數 {ratio:.3f}）", False

    return ratio, f"疑似減資（乘數 {ratio:.3f}）", False


def guess_action(prev_close, actual, cash=0.0):
    """
    從跳空幅度反推事件。假設現金部分已知，剩下的偏離全部歸給
    股數變動：

        actual = (prev_close − cash) / ratio
    =>  ratio = (prev_close − cash) / actual
    """

    if actual <= 0:
        return "資料異常", None, False

    snapped, label, clean = snap_ratio((prev_close - cash) / actual)

    return label, snapped, clean


def scan_one(code, prev_map, asset_type="", threshold=None, exempt=()):
    """回傳這支股票的可疑日子清單（尚未分類）"""

    closes = get_closes(code)

    if len(closes) < 2:
        return []

    no_limit = has_no_price_limit(code, asset_type, exempt)

    if threshold is None:
        threshold = NO_LIMIT_THRESHOLD if no_limit else THRESHOLD

    events = {
        e["ex_date"]: e
        for e in merge_same_day(get_actions(code))
    }

    findings = []

    for i in range(1, len(closes)):

        ipo_window = i < IPO_FREE_DAYS

        prev_date, prev_close = closes[i - 1]
        curr_date, curr_close = closes[i]

        ev = events.get(curr_date)

        cash = ev["cash"] if ev else 0.0
        ratio = ev["ratio"] if ev and ev["ratio"] else 1.0

        expected = (prev_close - cash) / ratio

        if expected <= 0:
            continue

        deviation = curr_close / expected - 1

        if abs(deviation) <= threshold:
            continue

        # 資料庫裡相鄰的兩列不一定是相鄰的交易日。中間缺日的話
        # 累積漲跌本來就會超過門檻，那是資料缺漏不是公司行動。
        expected_prev = prev_map.get(curr_date)
        contiguous = (expected_prev == prev_date)

        gap_days = (
            datetime.strptime(curr_date, "%Y-%m-%d")
            - datetime.strptime(prev_date, "%Y-%m-%d")
        ).days

        label, implied, clean = guess_action(prev_close, curr_close, cash)

        findings.append({
            "code": code,
            "date": curr_date,
            "prev_date": prev_date,
            "prev_close": prev_close,
            "actual": curr_close,
            "expected": round(expected, 2),
            "deviation": round(deviation * 100, 1),
            "has_event": ev is not None,
            "guess": label,
            "implied_ratio": implied,
            "clean_ratio": clean,
            "contiguous": contiguous,
            "no_limit": no_limit,
            "asset_type": asset_type,
            "ipo_window": ipo_window,
            "suspended": gap_days > SUSPENSION_DAYS,
            "gap_days": gap_days,
        })

    return findings


def classify(findings):
    """
    把原始清單分成四類。分類的關鍵是這條觀察：

      真的公司行動只有那一檔股票會跳空，
      全市場事件是幾十檔同一天一起跳。

    2025-04-07（關稅衝擊）、2024-08-05（日圓套利平倉）、
    2020-03（疫情崩盤）在原始清單裡佔了很大比例，用這個規則
    可以整批濾掉。
    """

    by_date = {}

    for f in findings:
        by_date.setdefault(f["date"], []).append(f)

    market_days = {
        d for d, fs in by_date.items()
        if len(fs) >= MARKET_EVENT_MIN_STOCKS
    }

    # 慣犯：被標記太多次的標的，整檔歸類掉
    by_code = {}
    for f in findings:
        by_code[f["code"]] = by_code.get(f["code"], 0) + 1

    repeat_offenders = {
        c for c, n in by_code.items() if n > MAX_FLAGS_PER_STOCK
    }

    buckets = {
        "candidate": [],   # 值得人工確認
        "market": [],      # 全市場事件
        "data_gap": [],    # 資料缺日或停牌
        "no_limit": [],    # 無漲跌幅限制或資料有問題的標的
    }

    for f in findings:

        if f["code"] in repeat_offenders:
            buckets["no_limit"].append(f)
        elif f["date"] in market_days:
            buckets["market"].append(f)
        elif f["ipo_window"]:
            buckets["data_gap"].append(f)
        elif not f["contiguous"]:
            buckets["data_gap"].append(f)
        elif f["no_limit"]:
            buckets["no_limit"].append(f)
        else:
            buckets["candidate"].append(f)

    return buckets, market_days, repeat_offenders


def add_manual_action(code, ex_date, share_ratio, cash_per_share=0.0,
                      action_type="SPLIT", note=None, quiet=False):
    """
    人工確認之後把事件補進去。source 標 manual，之後重跑
    update_financial 不會把它蓋掉（FinMind 的資料只會寫
    CASH 和 STOCK_DIVIDEND 兩種 action_type）。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        INSERT INTO corporate_actions(
            code, ex_date, action_type,
            cash_per_share, share_ratio, raw_value,
            pay_date, source, updated_at
        )
        VALUES(?, ?, ?, ?, ?, ?, NULL, 'manual', ?)
        ON CONFLICT(code, ex_date, action_type)
        DO UPDATE SET
            cash_per_share = excluded.cash_per_share,
            share_ratio    = excluded.share_ratio,
            source         = 'manual',
            updated_at     = excluded.updated_at
    """, (
        code, ex_date, action_type,
        cash_per_share, share_ratio, note,
        datetime.today().strftime("%Y-%m-%d"),
    ))

    conn.commit()
    conn.close()

    if not quiet:
        print(f"已補上 {code} {ex_date} {action_type} 乘數={share_ratio}")


def stocks_with_actions():
    """
    已經抓過股利的股票。沒抓過的不能自動套用——正常的除權
    （股票股利）本來就會讓股價跳空 20%，如果只是還沒下載，
    自動套用會把它誤記成一次分割，等於用錯誤資料蓋掉真相。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT DISTINCT code FROM corporate_actions")
    have = {r["code"] for r in cur.fetchall()}

    cur.execute("""
        SELECT code FROM fetch_log
        WHERE dataset='financials' AND last_try IS NOT NULL
    """)
    have |= {r["code"] for r in cur.fetchall()}

    conn.close()

    return have


def fetch_dividends_for(codes):
    """
    只抓股利，不抓整套財報。

    TaiwanStockDividend 是獨立資料集，每檔只要 1 次 API——
    跑完整的 update_financial 是 5 次（損益、資產、現金流、
    估值、股利）。要讓偵測器能運作，只需要股利這一份。
    """

    from finmind import request_dataset
    from update_financial import save_corporate_actions
    from fetch_cache import block_quota, quota_blocked

    done, empty, failed = 0, 0, []

    for i, code in enumerate(sorted(codes), 1):

        if quota_blocked():
            print(f"  額度用完，停在 {i}/{len(codes)}，"
                  f"等一小時後再跑一次即可接續")
            break

        try:
            rows = request_dataset("TaiwanStockDividend", code)

        except Exception as e:

            msg = str(e)

            if "402" in msg or "額度用完" in msg or "upper limit" in msg:
                block_quota()
                print(f"  額度用完，停在 {i}/{len(codes)}")
                break

            failed.append(code)
            print(f"  {code} 失敗: {msg[:80]}")
            continue

        if not rows:
            empty += 1
            continue

        n = save_corporate_actions(code, rows)
        done += 1

        print(f"  [{i}/{len(codes)}] {code} 寫入 {n} 筆事件")

    print(f"\n完成 {done} 檔，無股利資料 {empty} 檔，失敗 {len(failed)} 檔")

    return done


def existing_ratio_dates():
    """已經有股數調整事件的 (代號, 日期)，不分來源"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT code, ex_date FROM corporate_actions
        WHERE share_ratio IS NOT NULL AND share_ratio != 1.0
    """)

    out = {(r["code"], r["ex_date"]) for r in cur.fetchall()}

    conn.close()

    return out


def dividend_coverage():
    """
    每檔股票的股利資料涵蓋範圍：最早的除權息日。

    比這個日期更早的跳空，代表 FinMind 根本沒有那個年代的資料
    ——2330 抓了 47 筆事件，但最早的也只到 2004 年左右，所以
    2000-05-15 的除權查不到。這種缺漏可以安全地用推估乘數補上，
    因為我們確定那裡「本來就該有事件而資料沒有」。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT code, MIN(ex_date) AS first_date
        FROM corporate_actions
        WHERE source = 'finmind'
        GROUP BY code
    """)

    out = {r["code"]: r["first_date"] for r in cur.fetchall()}

    conn.close()

    return out


def auto_apply(buckets, dry_run=True, require_clean=True, fill_uncovered=False):
    """
    把高信心的候選自動寫進 corporate_actions。

    只有同時滿足這些條件才會套用：

      1. 這檔有漲跌幅限制（普通股，不是槓桿/期貨 ETF 或興櫃）
      2. 前後兩筆是相鄰交易日（不是資料缺日）
      3. 不是全市場崩跌日（不是幾十檔一起跳）
      4. 不在上市初期的免限制期間
      5. 這檔已經抓過股利（否則分不清是分割還是還沒下載的除權）
      6. require_clean=True 時，推估乘數要吸附到常見比例

    前四項在 classify() 就篩掉了，這裡處理第 5、6 項。

    寫入時 action_type 用 AUTO_ADJUST，跟 FinMind 的 CASH /
    STOCK_DIVIDEND 和你手動補的 SPLIT 分開，隨時可以整批撤銷。
    """

    have_dividends = stocks_with_actions()

    existing = existing_ratio_dates()

    coverage = dividend_coverage()

    applied = []
    skipped_nodiv, skipped_unclean, skipped_dup, skipped_etf = [], [], [], []

    for f in buckets["candidate"]:

        # 同一天已經有會改變股數的事件了（你手動補的 SPLIT，或是
        # FinMind 的 STOCK_DIVIDEND）。再加一筆會讓兩個乘數相乘，
        # 4 倍變成 16 倍。
        if (f["code"], f["date"]) in existing:
            skipped_dup.append(f)
            continue

        # ETF 一律不自動套用。國外成分 ETF（0080 恒中國、0081
        # 恒香港、00712 美國 REITs⋯）沒有漲跌幅限制，2020-03 的
        # 美股熔斷、2015-04 的港股暴漲都會被誤判成減資。用代號
        # 區分國內外成分不可靠，所以整類交給人工確認。
        # ETF 真正的分割（像 0050 那次）罕見且會公告。
        if f["asset_type"] and f["asset_type"] != "STOCK":
            skipped_etf.append(f)
            continue

        if f["code"] not in have_dividends:
            skipped_nodiv.append(f)
            continue

        # 乘數不乾淨通常代表這是除權（股票股利比例本來就任意），
        # 而不是分割。但如果這一天早於 FinMind 對這檔的資料涵蓋
        # 範圍，那就是「本來該有事件而資料沒有」，補上是安全的。
        uncovered = (
            fill_uncovered
            and f["code"] in coverage
            and f["date"] < coverage[f["code"]]
        )

        if require_clean and not f["clean_ratio"] and not uncovered:
            skipped_unclean.append(f)
            continue

        if not f["implied_ratio"] or f["implied_ratio"] <= 0:
            continue

        applied.append(f)

        if not dry_run:
            add_manual_action(
                f["code"], f["date"],
                share_ratio=f["implied_ratio"],
                action_type="AUTO_ADJUST",
                note=f"auto: {f['deviation']}% {f['guess']}",
                quiet=True,
            )

    verb = "可自動套用" if dry_run else "已自動套用"

    print(f"\n{verb} {len(applied)} 筆")

    for f in applied:
        print(f"  {f['code']:<8}{f['date']}  乘數 {f['implied_ratio']:<8.3f}"
              f"偏離 {f['deviation']:>7.1f}%  {f['guess']}")

    if skipped_nodiv:
        codes = sorted({f["code"] for f in skipped_nodiv})
        print(f"\n跳過 {len(skipped_nodiv)} 筆：這 {len(codes)} 檔還沒抓過股利，"
              f"分不清是分割還是未下載的除權")
        print("  " + " ".join(codes[:20]) + (" ..." if len(codes) > 20 else ""))

    if skipped_etf:
        codes = sorted({f["code"] for f in skipped_etf})
        print(f"\n跳過 {len(skipped_etf)} 筆：ETF 一律人工確認"
              f"（國外成分 ETF 無漲跌幅限制，容易誤判）")
        print("  " + " ".join(codes))

    if skipped_dup:
        print(f"\n跳過 {len(skipped_dup)} 筆：同一天已經有股數調整事件，"
              f"重複加會讓乘數相乘")
        for f in skipped_dup[:20]:
            print(f"  {f['code']:<8}{f['date']}")

    if skipped_unclean:
        print(f"\n跳過 {len(skipped_unclean)} 筆：乘數不是常見比例，需要人工確認")
        for f in skipped_unclean[:20]:
            print(f"  {f['code']:<8}{f['date']}  {f['guess']}")

    if dry_run and applied:
        print("\n確認無誤後用 --apply 實際寫入")

    return applied


def clear_auto():
    """撤銷所有自動套用的紀錄。手動補的 SPLIT 不受影響。"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("DELETE FROM corporate_actions WHERE action_type='AUTO_ADJUST'")
    n = cur.rowcount

    conn.commit()
    conn.close()

    print(f"已撤銷 {n} 筆自動套用的紀錄")


def report(buckets, market_days, offenders=()):

    cand = sorted(buckets["candidate"], key=lambda x: (x["code"], x["date"]))

    print()
    print(f"待確認      {len(cand):>5} 筆   ← 只要看這些")
    print(f"全市場事件  {len(buckets['market']):>5} 筆   "
          f"（{len(market_days)} 個交易日，整體行情不是公司行動）")
    print(f"資料缺日    {len(buckets['data_gap']):>5} 筆   "
          f"（前後兩筆不是相鄰交易日）")
    print(f"標的本身有問題{len(buckets['no_limit']):>3} 筆   "
          f"（槓桿/期貨 ETF、興櫃、或跳空過於頻繁）")

    if offenders:
        print(f"  其中跳空過於頻繁而整檔排除：{' '.join(sorted(offenders))}")

    if not cand:
        print("\n沒有需要人工確認的跳空")
        return

    header = (
        f"\n{'代號':<8}{'日期':<12}{'前收':>9}{'實際':>9}"
        f"{'偏離%':>8}  說明"
    )
    print(header)
    print("-" * 62)

    for f in cand:

        note = f["guess"]

        if f["has_event"]:
            note += " [已有事件但仍偏離]"

        print(
            f"{f['code']:<8}{f['date']:<12}"
            f"{f['prev_close']:>9.2f}{f['actual']:>9.2f}"
            f"{f['deviation']:>8.1f}  {note}"
        )

    by_code = {}
    for f in cand:
        by_code[f["code"]] = by_code.get(f["code"], 0) + 1

    print(f"\n涉及 {len(by_code)} 檔股票")

    print("\n確認之後用這個補上事件：")
    print("  from detect_gaps import add_manual_action")
    print("  add_manual_action('0050', '2025-06-18', share_ratio=4.0)")


def main():

    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}

    if "--clear-auto" in flags:
        clear_auto()
        return

    if "--flag-exempt" in flags:
        flag_exempt_stocks()
        return

    if "--fetch-all-dividends" in flags:

        # 跳空偵測抓不到小額除權：配股 1 元只讓股價跌 9%，低於
        # ±10% 漲跌幅限制，跟正常交易無法區分。台積電 2002-2008
        # 那幾年的配股都在這個盲區裡。
        #
        # 唯一的解法是把股利資料抓齊。每檔 1 次 API。
        have = stocks_with_actions()

        need = [c for c in get_codes_with_prices() if c not in have]

        print(f"有股價的股票 {len(get_codes_with_prices())} 檔，"
              f"已有股利資料 {len(have)} 檔")
        print(f"待抓 {len(need)} 檔（每檔 1 次 API）\n")

        fetch_dividends_for(need)
        return

    n_actions = action_count()

    if n_actions == 0:
        print("!! corporate_actions 是空的，所有正常除權息都會被誤報。")
        print("   建議先跑過 update_financial.py 再來偵測。\n")
    else:
        print(f"已登記 {n_actions} 筆公司行動\n")

    print("建立市場交易日曆...")
    days, prev_map = build_market_calendar()
    print(f"  共 {len(days)} 個交易日 "
          f"({days[0] if days else '?'} ~ {days[-1] if days else '?'})")

    asset_types = load_asset_types()
    exempt = load_exempt()

    if exempt:
        print(f"  {len(exempt)} 檔已標記為無漲跌幅限制")

    codes = args or get_codes_with_prices()

    print(f"掃描 {len(codes)} 檔股票...")

    findings = []

    for i, code in enumerate(codes, 1):

        if i % 200 == 0:
            print(f"  ...{i}/{len(codes)}")

        findings.extend(
            scan_one(code, prev_map, asset_types.get(code, ""), exempt=exempt)
        )

    print(f"\n原始跳空 {len(findings)} 筆，開始分類")

    buckets, market_days, offenders = classify(findings)

    report(buckets, market_days, offenders)

    if "--fetch-dividends" in flags:

        need = sorted({
            f["code"] for f in buckets["candidate"]
        } - stocks_with_actions())

        print(f"\n這 {len(need)} 檔需要先抓股利（每檔 1 次 API）")

        fetch_dividends_for(need)

        print("\n股利抓完了，重跑一次偵測：")
        print("  python detect_gaps.py")
        return

    auto_apply(
        buckets,
        dry_run="--apply" not in flags,
        require_clean="--loose" not in flags,
        fill_uncovered="--fill-uncovered" in flags,
    )


if __name__ == "__main__":
    main()