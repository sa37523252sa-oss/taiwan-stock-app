import time
from collections import defaultdict

from database import get_connection
from finmind import request_dataset

# FinMind 的 name 分類：
# Foreign_Investor / Foreign_Dealer_Self  -> 外資（含外資自營）
# Investment_Trust                        -> 投信
# Dealer_self / Dealer_Hedging            -> 自營商（自行買賣 + 避險）

FOREIGN_NAMES = {"Foreign_Investor", "Foreign_Dealer_Self"}
TRUST_NAMES = {"Investment_Trust"}
DEALER_NAMES = {"Dealer_self", "Dealer_Hedging"}


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


def get_institution_data(code):
    try:
        return request_dataset(
            "TaiwanStockInstitutionalInvestorsBuySell",
            code,
        )
    except Exception:
        return []


def parse_institution_data(data):

    out = defaultdict(lambda: {"foreign": 0, "trust": 0, "dealer": 0})

    for item in data:

        d = item["date"]
        name = item["name"]

        net = (item.get("buy") or 0) - (item.get("sell") or 0)

        row = out[d]

        if name in FOREIGN_NAMES:
            row["foreign"] += net
        elif name in TRUST_NAMES:
            row["trust"] += net
        elif name in DEALER_NAMES:
            row["dealer"] += net

    results = []

    for d, row in out.items():

        results.append({
            "date": d,
            # FinMind 回傳單位是「股」，換成「張」
            "foreign": row["foreign"] / 1000,
            "trust": row["trust"] / 1000,
            "dealer": row["dealer"] / 1000,
        })

    return results


def save_institution(code, rows):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS institution_flows (
            code TEXT NOT NULL,
            date TEXT NOT NULL,
            foreign_net REAL,
            trust_net REAL,
            dealer_net REAL,
            updated_at TEXT,
            PRIMARY KEY (code, date)
        )
    """)

    sql = """
    INSERT INTO institution_flows(
        code,
        date,
        foreign_net,
        trust_net,
        dealer_net,
        updated_at
    )
    VALUES(
        ?,?,?,?,?,datetime('now')
    )
    ON CONFLICT(code,date)
    DO UPDATE SET

    foreign_net=excluded.foreign_net,
    trust_net=excluded.trust_net,
    dealer_net=excluded.dealer_net,

    updated_at=datetime('now')
    """

    for row in rows:

        cur.execute(sql, (
            code,
            row["date"],
            row["foreign"],
            row["trust"],
            row["dealer"],
        ))

    conn.commit()
    conn.close()


def update_one_institution(code):

    try:

        data = get_institution_data(code)

        if not data:

            print(code, "沒有三大法人資料")

            return False

        parsed = parse_institution_data(data)

        save_institution(code, parsed)

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

        if update_one_institution(code):

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

        update_one_institution(code)

    else:

        update_all()


if __name__ == "__main__":
    main()