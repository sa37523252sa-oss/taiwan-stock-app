from finmind import request_dataset
from datetime import date, datetime, timedelta

from database import (
    get_connection,
    insert_price,
)
from fetch_cache import (
    ensure_fetch_log,
    last_trading_day,
    latest_price_in_db,
    mark_fetch,
    price_queue,
    queue_summary,
    block_quota,
    quota_blocked,
    QuotaReached,
)

# 免費會員每小時 600 次，留一點餘裕
HOURLY_LIMIT = 550

# 資料停在這天數之前 → 視為已停止交易，進入冷卻不再每天重抓
STALE_DAYS = 30



def market_last_date(probe="2330"):
    """
    先抓一檔確認市場真正的最新交易日。花 1 次 API，
    換掉「國定假日時 3118 檔全部湧進佇列空轉」的風險。
    抓不到就退回用日曆推算。
    """

    try:
        rows = request_dataset(
            "TaiwanStockPrice",
            probe,
            (date.today() - timedelta(days=14)).isoformat(),
        )
    except Exception as e:
        print("探路失敗，改用日曆推算:", e)
        return last_trading_day()

    if not rows:
        return last_trading_day()

    return rows[-1]["date"]


def get_all_stocks():

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT code
        FROM stocks
        ORDER BY code
    """)

    stocks = [
        row["code"]
        for row in cursor.fetchall()
    ]

    conn.close()

    return stocks


def get_last_date(code):

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT MAX(date)
        FROM prices
        WHERE code=?
    """, (code,))

    row = cursor.fetchone()

    conn.close()

    if row and row[0]:
        last = datetime.strptime(row[0], "%Y-%m-%d")
        return (last - timedelta(days=7)).strftime("%Y-%m-%d")

    return "2000-01-01"


def update_one_stock(code, force=False):
    """
    回傳 True 代表有寫入新資料。
    額度用完時丟 QuotaReached，讓外層停止整批執行。
    """

    if quota_blocked():
        raise QuotaReached(code)

    start_date = get_last_date(code)

    try:
        rows = request_dataset(
            "TaiwanStockPrice",
            code,
            start_date,
        )
    except Exception as e:

        msg = str(e)

        if "402" in msg or "upper limit" in msg or "額度用完" in msg:
            block_quota()
            raise QuotaReached(code)

        raise

    if not rows:
        mark_fetch(code, "price", False)
        return False

    count = 0

    for row in rows:

        insert_price(
            code,
            row["date"],
            row["open"],
            row["max"],
            row["min"],
            row["close"],
            row["Trading_Volume"],
        )

        count += 1

    after = latest_price_in_db(code)

    # 抓到資料但最新一筆還是很舊 → 這檔應該已經下市或停止買賣，
    # 標記起來進冷卻，否則它每天都會再吃掉一次額度。
    stale_before = (
        date.today() - timedelta(days=STALE_DAYS)
    ).isoformat()

    is_live = after is not None and after > stale_before

    mark_fetch(code, "price", is_live)

    if not is_live:
        print(f"{code} 最新僅到 {after}，視為停止交易")
    else:
        print(f"{code} 新增/更新 {count} 筆，至 {after}")

    return True


def show_latest_price(code):

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT *
        FROM prices
        WHERE code=?
        ORDER BY date DESC
        LIMIT 5
    """, (code,))

    rows = cursor.fetchall()

    conn.close()

    print("\n===== 最新資料 =====")

    if rows:

        for row in rows:
            print(dict(row))

    else:

        print("沒有資料")


def update_price():

    ensure_fetch_log()

    code = input("股票代號 (Enter=全部)：").strip()

    if code:
        stocks = [code]
    else:
        raw = input(f"本次上限 (Enter={HOURLY_LIMIT})：").strip()
        limit = int(raw) if raw else HOURLY_LIMIT

        as_of = market_last_date()
        print(f"市場最新交易日：{as_of}")

        total_stocks, empty_count = queue_summary("price")

        stocks = price_queue(limit=limit, as_of=as_of, cooldown_days=7)

        pending = len(price_queue(as_of=as_of, cooldown_days=7))

        print(f"\n全部 {total_stocks} 檔")
        print(f"已知無資料/停止交易 {empty_count} 檔（冷卻中）")
        print(f"待處理 {pending} 檔，本次跑 {len(stocks)} 檔")

        if pending > limit:
            hours = -(-pending // limit)
            print(f"約需再執行 {hours} 次才會跑完")

    print(f"\n共 {len(stocks)} 檔股票")

    success = 0
    failed = []
    quota_hit = False

    total = len(stocks)

    for i, code_ in enumerate(stocks, 1):

        print(f"\n[{i}/{total}] {code_}")

        try:

            if update_one_stock(code_):
                success += 1
            else:
                failed.append(code_)
                print("沒有資料")

        except QuotaReached:

            quota_hit = True

            print("\n!!! FinMind 額度用完，停止本次執行")
            print(f"已完成 {i-1}/{total}，下次執行會自動從這裡接續")

            break

        except Exception as e:

            failed.append(code_)
            print(e)

    if code:
        show_latest_price(code)

    print("\n========================")
    print(f"成功：{success}")
    print(f"失敗：{len(failed)}")

    if failed:
        print("\n失敗股票：")
        for stock in failed:
            print(stock)

    if quota_hit:
        print("\n額度已滿，等一小時後再執行一次即可接續")
    else:
        left = len(price_queue())
        print(f"\n剩餘待處理：{left} 檔")

    print("========================")


if __name__ == "__main__":
    update_price()