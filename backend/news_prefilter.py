"""
規則式 prefilter（不碰 AI）。

目的：砍掉「明顯垃圾」，不做語意判斷。
    - 重複新聞（標題正規化後比對）
    - 太舊的新聞
    - 標題/連結缺失的髒資料
    - 完全沒有任何財經訊號的新聞
      （沒有提到任何股票名稱，也沒有任何財經/產業關鍵字）

注意：
    - 這裡「有提到股票名稱」用的是跟 update_news.py 一樣的
      子字串比對，寬鬆、低精準度是刻意的——這一步的目標是
      「盡量不要漏掉真正有價值的新聞」，不是精準分類。
      像「台南（1473）」這種假陽性，會留到 AI 那一關，
      靠 AI 判斷跟 company_profile 的 topic 有沒有對上來剔除，
      不是這裡的責任。
    - 不會因為新聞提到「政治」「政策」「出口管制」就砍掉，
      因為這類新聞常常才是真正重要的產業訊號
      （例如「美國限制中國AI晶片出口」）。

這一版是 dry-run：只讀取、只印出統計，不寫回資料庫、
不刪除任何新聞，方便你先確認過濾比例合理再往下接 AI。
"""

import re
from datetime import datetime, timedelta

from database import get_connection

# 太舊的新聞：超過幾天直接丟
STALE_DAYS = 7

# 財經/產業關鍵字（寬鬆列表，只要沾到一點邊就留著給 AI 判斷）
FINANCE_KEYWORDS = [
    # 公司財務
    "營收", "財報", "獲利", "虧損", "毛利", "淨利", "EPS", "股利", "配息",
    "除權", "除息", "股東會", "董事會", "法說", "財測", "增資", "減資",
    "庫藏股", "私募", "現增",

    # 股市/籌碼
    "股價", "股市", "台股", "大盤", "指數", "法人", "外資", "投信", "自營商",
    "融資", "融券", "當沖", "漲停", "跌停", "成交量", "成交值", "MSCI",
    "上市", "上櫃", "興櫃", "IPO",

    # 產業/事件
    "併購", "收購", "合資", "轉投資", "擴產", "擴廠", "投資", "產能", "訂單",
    "出貨", "接單", "新品", "量產", "認證", "供應鏈", "供應商", "客戶",

    # 科技/半導體常見詞（因為台股新聞很多是這類）
    "半導體", "晶圓", "封裝", "測試", "AI", "晶片", "伺服器", "記憶體",
    "面板", "光電", "電動車", "新能源", "5G", "雲端",

    # 總經
    "升息", "降息", "通膨", "GDP", "關稅", "出口", "進口", "貿易",
]


def normalize_title(title: str) -> str:
    """去標點、去空白，方便比對「不同媒體報同一件事」。"""

    text = re.sub(r"[\s\W_]+", "", title)

    return text.lower()


def has_finance_signal(title: str, summary: str, stock_names: list) -> bool:

    text = title + summary

    for name in stock_names:
        if name and name in text:
            return True

    for kw in FINANCE_KEYWORDS:
        if kw in text:
            return True

    return False


def get_all_stock_names():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT name FROM stocks")

    names = [r["name"] for r in cur.fetchall()]

    conn.close()

    return names


def get_all_news():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT link, source, title, summary, pub_date
        FROM news
    """)

    rows = [dict(r) for r in cur.fetchall()]

    conn.close()

    return rows


def prefilter(news_rows: list, stock_names: list):

    kept = []
    rejected = []

    seen_titles = set()
    seen_links = set()

    stale_cutoff = datetime.now() - timedelta(days=STALE_DAYS)

    for row in news_rows:

        link = row.get("link") or ""
        title = row.get("title") or ""
        summary = row.get("summary") or ""
        pub_date = row.get("pub_date") or ""

        # 髒資料
        if not link or not title:
            rejected.append((row, "invalid"))
            continue

        # 連結重複
        if link in seen_links:
            rejected.append((row, "duplicate_link"))
            continue

        # 標題重複（不同媒體報同一件事）
        norm_title = normalize_title(title)

        if norm_title in seen_titles:
            rejected.append((row, "duplicate_title"))
            continue

        # 太舊
        try:
            pub_dt = datetime.fromisoformat(pub_date)
            if pub_dt < stale_cutoff:
                rejected.append((row, "stale"))
                continue
        except ValueError:
            pass  # 日期格式怪異的話不擋，交給後面判斷

        # 完全沒有財經訊號
        if not has_finance_signal(title, summary, stock_names):
            rejected.append((row, "no_signal"))
            continue

        seen_links.add(link)
        seen_titles.add(norm_title)
        kept.append(row)

    return kept, rejected


def main():

    stock_names = get_all_stock_names()
    news_rows = get_all_news()

    print(f"讀取到 {len(news_rows)} 則新聞")
    print(f"比對用的股票名稱共 {len(stock_names)} 檔\n")

    kept, rejected = prefilter(news_rows, stock_names)

    print("======================")
    print(f"原始：{len(news_rows)} 則")
    print(f"保留：{len(kept)} 則")
    print(f"淘汰：{len(rejected)} 則")
    print("======================\n")

    # 依淘汰原因統計
    reason_count = {}
    for _, reason in rejected:
        reason_count[reason] = reason_count.get(reason, 0) + 1

    print("淘汰原因分布：")
    for reason, count in sorted(
        reason_count.items(), key=lambda x: -x[1]
    ):
        print(f"  {reason}: {count}")

    print("\n===== 被淘汰的新聞範例（每種原因最多 5 則）=====")

    shown_per_reason = {}

    for row, reason in rejected:

        shown_per_reason.setdefault(reason, 0)

        if shown_per_reason[reason] >= 5:
            continue

        shown_per_reason[reason] += 1

        print(f"[{reason}] {row['title']}")

    print("\n===== 保留的新聞範例（前 10 則）=====")

    for row in kept[:10]:
        print(f"- {row['title']}")


if __name__ == "__main__":
    main()