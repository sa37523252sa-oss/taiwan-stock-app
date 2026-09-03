import time

from database import get_connection
from finmind import request_dataset


def get_all_stocks():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT code
        FROM stocks
        ORDER BY code
    """)

    rows = [r["code"] for r in cur.fetchall()]

    conn.close()

    return rows


def get_margin_data(code):
    try:
        return request_dataset(
            "TaiwanStockMarginPurchaseShortSale",
            code,
        )
    except Exception:
        return []


def parse_margin_data(data):

    results = []

    for item in data:

        results.append({
            "date": item["date"],

            "margin_buy": item.get("MarginPurchaseBuy"),
            "margin_sell": item.get("MarginPurchaseSell"),
            "margin_cash_repayment": item.get("MarginPurchaseCashRepayment"),
            "margin_today_balance": item.get("MarginPurchaseTodayBalance"),
            "margin_yesterday_balance": item.get("MarginPurchaseYesterdayBalance"),
            "margin_limit": item.get("MarginPurchaseLimit"),

            "short_buy": item.get("ShortSaleBuy"),
            "short_sell": item.get("ShortSaleSell"),
            "short_cash_repayment": item.get("ShortSaleCashRepayment"),
            "short_today_balance": item.get("ShortSaleTodayBalance"),
            "short_yesterday_balance": item.get("ShortSaleYesterdayBalance"),
            "short_limit": item.get("ShortSaleLimit"),

            "offset_loan_and_short": item.get("OffsetLoanAndShort"),
        })

    return results


def save_margin(code, rows):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS margin_flows (
            code TEXT NOT NULL,
            date TEXT NOT NULL,

            margin_buy INTEGER,
            margin_sell INTEGER,
            margin_cash_repayment INTEGER,
            margin_today_balance INTEGER,
            margin_yesterday_balance INTEGER,
            margin_limit INTEGER,

            short_buy INTEGER,
            short_sell INTEGER,
            short_cash_repayment INTEGER,
            short_today_balance INTEGER,
            short_yesterday_balance INTEGER,
            short_limit INTEGER,

            offset_loan_and_short INTEGER,

            updated_at TEXT,
            PRIMARY KEY (code, date)
        )
    """)

    sql = """
    INSERT INTO margin_flows(
        code, date,
        margin_buy, margin_sell, margin_cash_repayment,
        margin_today_balance, margin_yesterday_balance, margin_limit,
        short_buy, short_sell, short_cash_repayment,
        short_today_balance, short_yesterday_balance, short_limit,
        offset_loan_and_short,
        updated_at
    )
    VALUES(
        ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now')
    )
    ON CONFLICT(code,date)
    DO UPDATE SET

    margin_buy=excluded.margin_buy,
    margin_sell=excluded.margin_sell,
    margin_cash_repayment=excluded.margin_cash_repayment,
    margin_today_balance=excluded.margin_today_balance,
    margin_yesterday_balance=excluded.margin_yesterday_balance,
    margin_limit=excluded.margin_limit,

    short_buy=excluded.short_buy,
    short_sell=excluded.short_sell,
    short_cash_repayment=excluded.short_cash_repayment,
    short_today_balance=excluded.short_today_balance,
    short_yesterday_balance=excluded.short_yesterday_balance,
    short_limit=excluded.short_limit,

    offset_loan_and_short=excluded.offset_loan_and_short,

    updated_at=datetime('now')
    """

    for row in rows:

        cur.execute(sql, (
            code,
            row["date"],
            row["margin_buy"],
            row["margin_sell"],
            row["margin_cash_repayment"],
            row["margin_today_balance"],
            row["margin_yesterday_balance"],
            row["margin_limit"],
            row["short_buy"],
            row["short_sell"],
            row["short_cash_repayment"],
            row["short_today_balance"],
            row["short_yesterday_balance"],
            row["short_limit"],
            row["offset_loan_and_short"],
        ))

    conn.commit()
    conn.close()


def update_one_margin(code):

    try:

        data = get_margin_data(code)

        if not data:

            print(code, "沒有資券資料")

            return False

        parsed = parse_margin_data(data)

        save_margin(code, parsed)

        print(code, "完成", len(parsed), "天")

        return True

    except Exception as e:

        print(code, "失敗", e)

        return False


def update_all():

    stocks = get_all_stocks()

    print("共", len(stocks), "檔")

    success = 0
    failed = []

    total = len(stocks)

    for i, code in enumerate(stocks, 1):

        print(f"[{i}/{total}] 更新 {code}")

        if update_one_margin(code):

            success += 1

        else:

            failed.append(code)

        time.sleep(0.3)

    print("\n======================")

    print("成功：", success)

    print("失敗：", len(failed))

    if failed:

        print("\n失敗股票：")

        for stock in failed:

            print(stock)

    print("======================")


def main():

    code = input("股票代號(Enter=全部)：").strip()

    if code:

        update_one_margin(code)

    else:

        update_all()


if __name__ == "__main__":
    main()