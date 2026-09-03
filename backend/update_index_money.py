"""
補抓「成交金額」（不是股數/張數），只給大盤指數頁用。

背景：現有的 prices 表存的是 Trading_Volume（股數），
不是 Trading_money（成交金額），兩者是不同的數字。大盤指數頁
想顯示的是金額，不是股數，所以另外開一張小表存這個欄位，
不影響現有的股票資料表跟 update_price.py 的邏輯。

用法：
    python update_index_money.py
"""

from finmind import request_dataset
from database import get_connection

INDEX_CODES = ["TAIEX", "TPEx"]


def ensure_table():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS index_trading_money (
            code TEXT NOT NULL,
            date TEXT NOT NULL,
            trading_money REAL,
            UNIQUE(code, date)
        )
    """)

    conn.commit()
    conn.close()


def get_last_date(code):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "SELECT MAX(date) as d FROM index_trading_money WHERE code = ?",
        (code,),
    )
    row = cur.fetchone()

    conn.close()

    if row and row["d"]:
        return row["d"]

    return "2000-01-01"


def update_one(code):

    start_date = get_last_date(code)

    rows = request_dataset("TaiwanStockPrice", code, start_date)

    print(f"{code}: 共 {len(rows)} 筆")

    conn = get_connection()
    cur = conn.cursor()

    for row in rows:
        cur.execute("""
            INSERT OR REPLACE INTO index_trading_money(code, date, trading_money)
            VALUES(?, ?, ?)
        """, (code, row.get("date"), row.get("Trading_money")))

    conn.commit()
    conn.close()


def update_index_money():

    ensure_table()

    for code in INDEX_CODES:
        update_one(code)


if __name__ == "__main__":
    update_index_money()