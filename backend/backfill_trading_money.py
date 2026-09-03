"""
補上 prices 表裡的真實成交金額（trading_money）。

用的是你一直在用的 TaiwanStockPrice 這個資料集，只是這次額外
把 Trading_money 這個欄位存起來（之前只存了 Trading_Volume）。

只做 UPDATE，不重新 INSERT，不會動到既有的 open/high/low/
close/volume 資料，也不影響K線、股價、財報等其他功能。

第一次跑是「補歷史」，之後重複跑會自動從「這支股票上次補到
哪天」繼續往後補，可以排程當成日常更新用，不用另外寫一支。

用法：
    python backfill_trading_money.py           # 補全部股票
    python backfill_trading_money.py 2330 2317 # 只補指定股票
"""

import sys

from finmind import request_dataset
from database import get_connection


def get_all_stock_codes():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT code FROM stocks WHERE asset_type IS NULL OR asset_type != 'INDEX'")

    rows = cur.fetchall()
    conn.close()

    return [r["code"] for r in rows]


def has_any_price_data(code):
    """這支股票的 prices 表裡，有沒有任何一筆股價資料（不管有
    沒有 trading_money）。如果完全沒有，UPDATE 註定補不進去
    （UPDATE 只能改已存在的列，不能新增），要先跳過並提醒。"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) as c FROM prices WHERE code = ?", (code,))
    row = cur.fetchone()
    conn.close()

    return row["c"] > 0


def get_last_trading_money_date(code):
    """這支股票目前已經補到哪一天了（trading_money 不是NULL的
    最新一筆），沒有的話就從最早的股價資料開始補。"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT MAX(date) as d FROM prices
        WHERE code = ? AND trading_money IS NOT NULL
    """, (code,))
    row = cur.fetchone()

    if row and row["d"]:
        conn.close()
        return row["d"]

    cur.execute("SELECT MIN(date) as d FROM prices WHERE code = ?", (code,))
    row = cur.fetchone()
    conn.close()

    return row["d"] if row and row["d"] else "2000-01-01"


def backfill_one_stock(code):

    # 先確認這支股票有沒有任何既有股價資料，沒有的話 UPDATE
    # 注定補不進去，直接回報原因、不要浪費一次API呼叫。
    if not has_any_price_data(code):
        return 0, "沒有既有股價資料（prices表裡完全沒有這支股票），UPDATE補不進去，需要先跑股價回補"

    start_date = get_last_trading_money_date(code)

    try:
        rows = request_dataset("TaiwanStockPrice", code, start_date)
    except Exception as e:
        return 0, f"抓取失敗：{e}"

    if not rows:
        return 0, f"FinMind沒有回傳任何資料（從{start_date}開始查）"

    conn = get_connection()
    cur = conn.cursor()

    updated = 0
    fetched_but_no_match = 0

    for row in rows:

        money = row.get("Trading_money")

        if money is None:
            continue

        cur.execute("""
            UPDATE prices SET trading_money = ?
            WHERE code = ? AND date = ?
        """, (money, code, row.get("date")))

        if cur.rowcount > 0:
            updated += 1
        else:
            fetched_but_no_match += 1

    conn.commit()
    conn.close()

    if updated == 0 and fetched_but_no_match > 0:
        return 0, f"FinMind回傳了{fetched_but_no_match}筆，但日期都對不上既有股價資料"

    if updated == 0:
        return 0, "已經是最新的，沒有新資料要補（正常情況，不是問題）"

    return updated, None


def main():

    codes = sys.argv[1:] if len(sys.argv) > 1 else get_all_stock_codes()

    print(f"共 {len(codes)} 支股票要處理")

    total_updated = 0
    no_price_data_count = 0
    already_current_count = 0
    other_zero_count = 0

    for i, code in enumerate(codes):

        updated, reason = backfill_one_stock(code)
        total_updated += updated

        if updated > 0:
            print(f"[{i+1}/{len(codes)}] {code}: 更新 {updated} 筆")
        else:
            print(f"[{i+1}/{len(codes)}] {code}: 0 筆 —— {reason}")

            if reason and "沒有既有股價資料" in reason:
                no_price_data_count += 1
            elif reason and "已經是最新的" in reason:
                already_current_count += 1
            else:
                other_zero_count += 1

    print(f"\n完成，總共更新 {total_updated} 筆")
    print(f"其中 0 筆的原因統計：")
    print(f"  沒有既有股價資料（需要先補股價）：{no_price_data_count} 支")
    print(f"  已經是最新的（正常）：{already_current_count} 支")
    print(f"  其他原因（抓取失敗/日期對不上）：{other_zero_count} 支")


if __name__ == "__main__":
    main()