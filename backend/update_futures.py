"""
抓取台指期（TX）日成交資訊，存進獨立的 futures_prices 表
（跟一般股價 prices 表分開，因為欄位結構不一樣：有合約月份、
結算價、未平倉量）。

注意兩個資料特性：
1. TaiwanFuturesDaily 同一天會回傳多個合約（近月、遠月、跨月
   價差組合），我們只要「近月」這個大家平常講的「台指期」，
   跨月價差合約的 contract_date 會長得像 "202609/202706"
   （帶斜線），要過濾掉。
2. 當天還沒收盤結算完的話，那一筆 open/max/min/close 全部是 0
   （不是抓取錯誤，是資料本身還沒產生），查詢「最新收盤」時
   要跳過這種空值列，往前找最近一筆真正有數字的。
"""

from finmind import request_dataset
from database import get_connection

FUTURES_ID = "TX"


def ensure_table():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS futures_prices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            futures_id TEXT NOT NULL,
            date TEXT NOT NULL,
            contract_date TEXT NOT NULL,
            open REAL,
            high REAL,
            low REAL,
            close REAL,
            volume INTEGER,
            settlement_price REAL,
            open_interest INTEGER,
            UNIQUE(futures_id, date, contract_date)
        )
    """)

    conn.commit()
    conn.close()


def get_last_date():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "SELECT MAX(date) as d FROM futures_prices WHERE futures_id = ?",
        (FUTURES_ID,),
    )
    row = cur.fetchone()

    conn.close()

    if row and row["d"]:
        return row["d"]

    return "2000-01-01"


def update_futures():

    ensure_table()

    start_date = get_last_date()

    print(f"抓取台指期，起始日期：{start_date}")

    rows = request_dataset("TaiwanFuturesDaily", FUTURES_ID, start_date)

    print(f"共 {len(rows)} 筆原始資料（含所有合約月份）")

    conn = get_connection()
    cur = conn.cursor()

    saved = 0
    skipped_spread = 0

    for row in rows:

        contract_date = row.get("contract_date", "")

        # 跨月價差合約（帶斜線），不是我們要的「近月台指期」，跳過
        if "/" in contract_date:
            skipped_spread += 1
            continue

        cur.execute("""
            INSERT OR REPLACE INTO futures_prices(
                futures_id, date, contract_date,
                open, high, low, close,
                volume, settlement_price, open_interest
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            FUTURES_ID,
            row.get("date"),
            contract_date,
            row.get("open"),
            row.get("max"),
            row.get("min"),
            row.get("close"),
            row.get("volume"),
            row.get("settlement_price"),
            row.get("open_interest"),
        ))

        saved += 1

    conn.commit()
    conn.close()

    print(f"存入：{saved} 筆（跳過跨月價差合約：{skipped_spread} 筆）")


if __name__ == "__main__":
    update_futures()