"""
強制重新抓取完整歷史股價，繞過 update_price.py 的增量更新邏輯
（那個邏輯只會往前抓 7 天，沒辦法補回真正缺失的歷史）。

背景：資料庫裡目前的股價可能是在 FinMind token bug 修好之前
抓的，當時用匿名身份呼叫，被 FinMind 默默限制成只給最近一個月
資料（不像股東持股分級表那樣會回傳明確的付費限定錯誤，這次
是安靜地少給資料，不容易發現）。

用法：
    python backfill_price_history.py           # 全部股票
    python backfill_price_history.py 2330       # 只補單一股票
"""

import sys
import time

from finmind import request_dataset
from database import get_connection, insert_price


def get_all_stocks():

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT code FROM stocks ORDER BY code")
    stocks = [row["code"] for row in cursor.fetchall()]

    conn.close()

    return stocks


def backfill_one_stock(code):
    """
    強制從 2000-01-01 開始重新抓，不管資料庫裡已經有什麼。
    insert_price 假設是用 code+date 當主鍵（之前檢查過 prices
    表沒有重複日期），重複抓到同一天會被覆蓋掉，不會產生
    重複資料，可以放心整批重跑。
    """

    rows = request_dataset(
        "TaiwanStockPrice",
        code,
        "2000-01-01",
    )

    if not rows:
        print(f"{code}：沒有抓到資料")
        return False

    print(
        f"{code}：抓到 {len(rows)} 筆"
        f"（{rows[0]['date']} ~ {rows[-1]['date']}）"
    )

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

    return True


# 判斷「歷史夠不夠」的門檻：少於這個天數，就當作歷史不完整，
# 需要補。250 個交易日大約等於 1 年，正常股票的完整歷史
# 應該遠超過這個數字（除非是剛上市不久的新股，那種情況重新
# 抓一次也不會抓出更多資料，backfill_one_stock 本身很快，
# 不會造成明顯負擔）。
MIN_EXPECTED_ROWS = 250


def ensure_full_history(code):
    """
    給 API endpoint 呼叫用：只在「這檔股票歷史看起來太短」時，
    才觸發一次完整補歷史，不是每次查詢都重抓。
    補完之後同一檔股票之後都不會再觸發（因為筆數已經夠了），
    效果等同於「使用者第一次打開這支股票時，順便把歷史補齊」，
    不用一次處理全部 3000+ 檔。
    """

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(
        "SELECT COUNT(*) as cnt FROM prices WHERE code = ?",
        (code,),
    )
    row = cursor.fetchone()
    conn.close()

    count = row["cnt"] if row else 0

    if count >= MIN_EXPECTED_ROWS:
        return  # 歷史夠長，不用補

    print(f"{code} 歷史只有 {count} 筆，觸發補歷史 ...")

    try:
        backfill_one_stock(code)
    except Exception as e:
        # 補歷史失敗不該讓原本查詢股價的功能跟著壞掉，
        # 只記錄錯誤，讓 API 照樣回傳現有的資料。
        print(f"{code} 補歷史失敗：{e}")


def backfill_price_history():

    code = sys.argv[1] if len(sys.argv) > 1 else None

    stocks = [code] if code else get_all_stocks()

    print(f"共 {len(stocks)} 檔股票要重新補歷史")

    success = 0
    failed = []

    for i, c in enumerate(stocks, 1):

        print(f"\n[{i}/{len(stocks)}] {c}")

        try:

            if backfill_one_stock(c):
                success += 1
            else:
                failed.append(c)

        except Exception as e:
            failed.append(c)
            print(f"錯誤：{e}")

        # 避免打太快撞到 FinMind 的請求限制
        time.sleep(0.5)

    print("\n========================")
    print(f"成功：{success}")
    print(f"失敗：{len(failed)}")

    if failed:
        print("失敗股票：", failed)


if __name__ == "__main__":
    backfill_price_history()