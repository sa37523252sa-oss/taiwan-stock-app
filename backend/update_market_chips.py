"""
抓取大盤（整體市場）層級的三大法人買賣超、資券資料。

三大法人買賣超：外資、投信直接對應，自營商是「自行買賣＋避險」
兩筆加總（台灣慣例上「自營商」講的就是這兩者合計）。

資券：融資用「元」（金額），融券用「股數」（畫面顯示時要自己
換算成「張」，1張=1000股）——這是資料源本身的限制，融券
沒有對應的金額欄位，只能顯示股數/張數，跟融資的金額單位不同，
畫面上要清楚標示單位，不要讓人誤會兩者是同樣的度量。

用法：
    python update_market_chips.py
"""

from finmind import request_dataset
from database import get_connection


def ensure_tables():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS market_institutional (
            date TEXT PRIMARY KEY,
            foreign_buy REAL,
            foreign_sell REAL,
            trust_buy REAL,
            trust_sell REAL,
            dealer_buy REAL,
            dealer_sell REAL,
            total_buy REAL,
            total_sell REAL
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS market_margin (
            date TEXT PRIMARY KEY,
            margin_money_buy REAL,
            margin_money_sell REAL,
            margin_money_today_balance REAL,
            margin_money_yes_balance REAL,
            short_shares_buy REAL,
            short_shares_sell REAL,
            short_shares_today_balance REAL,
            short_shares_yes_balance REAL
        )
    """)

    conn.commit()
    conn.close()


def get_last_date(table):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(f"SELECT MAX(date) as d FROM {table}")
    row = cur.fetchone()

    conn.close()

    if row and row["d"]:
        return row["d"]

    return "2000-01-01"


def update_institutional():

    start_date = get_last_date("market_institutional")

    rows = request_dataset(
        "TaiwanStockTotalInstitutionalInvestors", "", start_date
    )

    print(f"三大法人買賣超：共 {len(rows)} 筆原始資料")

    # 依日期分組，同一天的各分類先收集起來，再一次算出這一天
    # 的彙整結果（外資/投信直接對應，自營商兩筆加總）。
    by_date = {}

    for row in rows:
        d = row.get("date")
        by_date.setdefault(d, {})[row.get("name")] = row

    conn = get_connection()
    cur = conn.cursor()

    saved = 0

    for d, items in by_date.items():

        def get(name, field):
            r = items.get(name)
            return r.get(field, 0) if r else 0

        foreign_buy = get("Foreign_Investor", "buy")
        foreign_sell = get("Foreign_Investor", "sell")

        trust_buy = get("Investment_Trust", "buy")
        trust_sell = get("Investment_Trust", "sell")

        # 自營商＝自行買賣＋避險
        dealer_buy = get("Dealer_self", "buy") + get("Dealer_Hedging", "buy")
        dealer_sell = get("Dealer_self", "sell") + get("Dealer_Hedging", "sell")

        total_buy = get("total", "buy")
        total_sell = get("total", "sell")

        cur.execute("""
            INSERT OR REPLACE INTO market_institutional(
                date, foreign_buy, foreign_sell,
                trust_buy, trust_sell,
                dealer_buy, dealer_sell,
                total_buy, total_sell
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            d, foreign_buy, foreign_sell,
            trust_buy, trust_sell,
            dealer_buy, dealer_sell,
            total_buy, total_sell,
        ))

        saved += 1

    conn.commit()
    conn.close()

    print(f"三大法人買賣超：存入 {saved} 天")


def update_margin():

    start_date = get_last_date("market_margin")

    rows = request_dataset(
        "TaiwanStockTotalMarginPurchaseShortSale", "", start_date
    )

    print(f"大盤資券：共 {len(rows)} 筆原始資料")

    by_date = {}

    for row in rows:
        d = row.get("date")
        by_date.setdefault(d, {})[row.get("name")] = row

    conn = get_connection()
    cur = conn.cursor()

    saved = 0

    for d, items in by_date.items():

        money = items.get("MarginPurchaseMoney", {})
        short = items.get("ShortSale", {})

        cur.execute("""
            INSERT OR REPLACE INTO market_margin(
                date,
                margin_money_buy, margin_money_sell,
                margin_money_today_balance, margin_money_yes_balance,
                short_shares_buy, short_shares_sell,
                short_shares_today_balance, short_shares_yes_balance
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            d,
            money.get("buy", 0), money.get("sell", 0),
            money.get("TodayBalance", 0), money.get("YesBalance", 0),
            short.get("buy", 0), short.get("sell", 0),
            short.get("TodayBalance", 0), short.get("YesBalance", 0),
        ))

        saved += 1

    conn.commit()
    conn.close()

    print(f"大盤資券：存入 {saved} 天")


def update_market_chips():

    ensure_tables()
    update_institutional()
    update_margin()


if __name__ == "__main__":
    update_market_chips()