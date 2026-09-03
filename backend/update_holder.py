import time

from database import get_connection
from finmind import request_dataset

# ⚠️ 欄位名稱是用猜的（FinMind 官方文件常見寫法）。
# 如果實際回傳的 key 不一樣，用 dump_finmind.py 測一次
# TaiwanStockHoldingSharesPer 之後把結果貼給我對正確。


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


def get_holder_data(code):
    try:
        return request_dataset(
            "TaiwanStockHoldingSharesPer",
            code,
        )
    except Exception:
        return []


def parse_holder_data(data):

    results = []

    for item in data:

        level = (
            item.get("HoldingSharesLevel")
            or item.get("level")
        )

        if level is None:
            continue

        people = (
            item.get("people")
            or item.get("HoldingSharesLevelPeopleCount")
        )

        percent = (
            item.get("percent")
            or item.get("percentage")
        )

        results.append({
            "date": item["date"],
            "level": str(level),
            "people": people,
            "percent": percent,
        })

    return results


def save_holder(code, rows):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS holder_distribution (
            code TEXT NOT NULL,
            date TEXT NOT NULL,
            level TEXT NOT NULL,
            people INTEGER,
            percent REAL,
            updated_at TEXT,
            PRIMARY KEY (code, date, level)
        )
    """)

    sql = """
    INSERT INTO holder_distribution(
        code, date, level, people, percent, updated_at
    )
    VALUES(
        ?,?,?,?,?,datetime('now')
    )
    ON CONFLICT(code,date,level)
    DO UPDATE SET

    people=excluded.people,
    percent=excluded.percent,

    updated_at=datetime('now')
    """

    for row in rows:

        cur.execute(sql, (
            code,
            row["date"],
            row["level"],
            row["people"],
            row["percent"],
        ))

    conn.commit()
    conn.close()


def update_one_holder(code):

    try:

        data = get_holder_data(code)

        if not data:

            print(code, "沒有大戶持股資料")

            return False

        parsed = parse_holder_data(data)

        save_holder(code, parsed)

        print(code, "完成", len(parsed), "筆")

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

        if update_one_holder(code):

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

        update_one_holder(code)

    else:

        update_all()


if __name__ == "__main__":
    main()