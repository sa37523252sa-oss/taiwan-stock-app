"""
新聞抓取 + AI 分類 + 公司比對，一次到位的批次流程。

流程：
    RSS（多個分類）
      -> 存進 news 表（不再要求一定要比對到公司名稱才存）
      -> 對還沒分析過的新聞（processed_at IS NULL）呼叫 AI 分類
      -> 把分類結果寫回 news 表
      -> companies_mentioned 的公司名稱比對回 stocks.code
      -> 寫進 news_relations

執行方式：
    python update_news.py

成本控制：
    - 同一則新聞（同一個 link）只會存一次
    - 只有 processed_at 是 NULL 的新聞才會呼叫 AI，
      已經分析過的新聞重跑這支程式不會重複花 token
"""

import time
from datetime import datetime

import feedparser

from database import get_connection
from news_prefilter import prefilter
from ai_provider import GeminiProvider


RSS_SOURCES = {
    "Yahoo股市-最新新聞": "https://tw.stock.yahoo.com/rss?category=news",
    "Yahoo股市-台股動態": "https://tw.stock.yahoo.com/rss?category=tw-market",
    "Yahoo股市-國際財經": "https://tw.stock.yahoo.com/rss?category=intl-markets",
    "Yahoo股市-研究報導": "https://tw.stock.yahoo.com/rss?category=research",
}


# =====================
# 資料庫欄位確認（沿用 migrate_news_ai.py 建的表，
# 這裡只是額外補上 stock_market_relevance /
# event_materiality / confidence 這三個新分數欄位）
# =====================

def ensure_extra_columns():
    """
    確保 news 表所有需要的欄位都存在，不依賴 migrate_news_ai.py
    有沒有先跑過——這支程式自己負責把 schema 補齊。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS news (
            link TEXT PRIMARY KEY,
            source TEXT,
            title TEXT,
            summary TEXT,
            pub_date TEXT,
            matched_codes TEXT,
            created_at TEXT
        )
    """)

    extra_columns = [
        ("investment_relevance", "INTEGER"),
        ("stock_market_relevance", "INTEGER"),
        ("confidence", "INTEGER"),
        ("event_materiality", "INTEGER"),
        ("industries", "TEXT"),
        ("topics", "TEXT"),
        ("technologies", "TEXT"),
        ("event_type", "TEXT"),
        ("processed_at", "TEXT"),
    ]

    for col_name, col_type in extra_columns:
        try:
            cur.execute(f"ALTER TABLE news ADD COLUMN {col_name} {col_type}")
            print(f"news.{col_name} 新增成功")
        except Exception as e:
            if "duplicate column name" in str(e):
                pass
            else:
                raise

    cur.execute("""
        CREATE TABLE IF NOT EXISTS news_relations (
            news_link TEXT NOT NULL,
            code TEXT NOT NULL,
            relevance_score INTEGER,
            confidence INTEGER,
            relation_type TEXT,
            reasons TEXT,
            created_at TEXT,
            PRIMARY KEY (news_link, code)
        )
    """)

    conn.commit()
    conn.close()


# =====================
# 抓取
# =====================

def parse_pub_date(entry):

    if entry.get("published_parsed"):
        t = entry["published_parsed"]
        return datetime(*t[:6]).isoformat()

    return entry.get("published", "") or datetime.now().isoformat()


def fetch_all_raw():

    all_items = []

    for source_name, url in RSS_SOURCES.items():

        print(f"抓取 {source_name} ...")

        try:
            feed = feedparser.parse(url)
        except Exception as e:
            print(f"{source_name} 失敗：{e}")
            continue

        entries = feed.entries or []

        print(f"  共 {len(entries)} 則")

        for entry in entries:

            title = entry.get("title", "").strip()
            link = entry.get("link", "").strip()
            summary = entry.get("summary", "") or entry.get("description", "")
            pub_date = parse_pub_date(entry)

            if not title or not link:
                continue

            all_items.append({
                "link": link,
                "source": source_name,
                "title": title,
                "summary": summary,
                "pub_date": pub_date,
            })

    return all_items


def get_all_stocks():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT code, name FROM stocks")

    rows = [(r["code"], r["name"]) for r in cur.fetchall()]

    conn.close()

    return rows


# =====================
# 存原始新聞（不再要求一定要比對到公司名稱才存，
# 讓後面的規則 prefilter + AI 決定要不要留）
# =====================

def save_raw_news(items):

    conn = get_connection()
    cur = conn.cursor()

    new_count = 0

    for item in items:

        cur.execute(
            "SELECT 1 FROM news WHERE link=?",
            (item["link"],),
        )

        if cur.fetchone():
            continue

        cur.execute("""
            INSERT INTO news(
                link, source, title, summary, pub_date,
                matched_codes, created_at
            )
            VALUES(?,?,?,?,?,?,datetime('now'))
        """, (
            item["link"],
            item["source"],
            item["title"],
            item["summary"],
            item["pub_date"],
            "",
        ))

        new_count += 1

    conn.commit()
    conn.close()

    return new_count


# =====================
# 規則 prefilter：只用來丟掉明顯垃圾/重複/太舊，
# 通過的新聞才會進到後面的 AI 分析佇列
# （沒有比對到公司也可能通過，因為 has_finance_signal
# 也會看財經關鍵字，不是只看公司名稱）
# =====================

def apply_prefilter():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT link, source, title, summary, pub_date
        FROM news
        WHERE processed_at IS NULL
    """)

    rows = [dict(r) for r in cur.fetchall()]

    stocks = get_all_stocks()
    stock_names = [name for _, name in stocks]

    kept, rejected = prefilter(rows, stock_names)

    # 被規則淘汰的新聞，直接標記 processed_at，
    # 但分數留 0，代表「規則淘汰，AI 沒有分析過」，
    # 避免這些新聞每次重跑都被拿去問 AI
    for row, reason in rejected:
        cur.execute("""
            UPDATE news SET
                stock_market_relevance = 0,
                investment_relevance = 0,
                processed_at = datetime('now')
            WHERE link = ?
        """, (row["link"],))

    conn.commit()
    conn.close()

    print(f"規則過濾：保留 {len(kept)} 則，淘汰 {len(rejected)} 則")

    return kept


# =====================
# 公司名稱 -> 代號比對
# =====================

def resolve_company_codes(names, stocks):

    codes = []

    name_to_code = {name: code for code, name in stocks if name}

    for n in names:

        if not n:
            continue

        if n in name_to_code:
            codes.append(name_to_code[n])
            continue

        # 精確比對不到，嘗試互相包含
        # （新聞可能寫簡稱或全名，跟資料庫存的名稱不完全一樣）
        for code, stock_name in stocks:
            if not stock_name:
                continue
            if stock_name in n or n in stock_name:
                codes.append(code)
                break

    return list(dict.fromkeys(codes))  # 去重，保留順序


# =====================
# AI 分類 + 寫回 news + 寫進 news_relations
# =====================

def classify_with_retry(provider, title, summary, max_retries=3):
    """
    包一層重試機制，遇到 429（免費層級 RPM 限制）就照 API
    建議的秒數等待後重試，而不是直接放棄那則新聞。
    """

    import re

    for attempt in range(max_retries):

        try:
            return provider.classify_news(title=title, summary=summary)

        except Exception as e:

            msg = str(e)

            if "429" in msg or "RESOURCE_EXHAUSTED" in msg:

                # 嘗試從錯誤訊息解析 API 建議的等待秒數，
                # 解析不到就保守等 45 秒
                match = re.search(r"retryDelay['\"]?:\s*['\"]?(\d+)", msg)
                wait_seconds = int(match.group(1)) + 3 if match else 45

                print(
                    f"  被限流（第 {attempt + 1} 次），"
                    f"等待 {wait_seconds} 秒後重試..."
                )
                time.sleep(wait_seconds)
                continue

            # 不是限流問題，直接往外拋，讓外層照原本邏輯處理
            raise

    raise Exception("重試次數用盡，仍然被限流")


def classify_and_link(provider, stocks, kept_rows):

    conn = get_connection()
    cur = conn.cursor()

    total = len(kept_rows)
    relation_count = 0

    for i, row in enumerate(kept_rows, 1):

        print(f"[{i}/{total}] {row['title'][:40]}")

        try:
            result = classify_with_retry(
                provider,
                title=row["title"],
                summary=row["summary"],
            )
        except Exception as e:
            print(f"  分類失敗（放棄，下次重跑會再嘗試）：{e}")
            continue

        import json

        cur.execute("""
            UPDATE news SET
                investment_relevance = ?,
                stock_market_relevance = ?,
                confidence = ?,
                event_materiality = ?,
                industries = ?,
                topics = ?,
                technologies = ?,
                event_type = ?,
                processed_at = datetime('now')
            WHERE link = ?
        """, (
            result["investment_relevance"],
            result["stock_market_relevance"],
            result["confidence"],
            result["event_materiality"],
            json.dumps(result["industries"], ensure_ascii=False),
            json.dumps(result["topics"], ensure_ascii=False),
            json.dumps(result["technologies"], ensure_ascii=False),
            result["event_type"],
            row["link"],
        ))

        codes = resolve_company_codes(
            result["companies_mentioned"], stocks
        )

        reasons = result["topics"][:]
        if result["event_type"]:
            reasons.append(result["event_type"])

        for code in codes:

            cur.execute("""
                INSERT INTO news_relations(
                    news_link, code, relevance_score, confidence,
                    relation_type, reasons, created_at
                )
                VALUES(?,?,?,?,?,?,datetime('now'))
                ON CONFLICT(news_link, code) DO UPDATE SET
                    relevance_score = excluded.relevance_score,
                    confidence = excluded.confidence,
                    reasons = excluded.reasons
            """, (
                row["link"],
                code,
                result["stock_market_relevance"],
                result["confidence"],
                "direct",
                json.dumps(reasons, ensure_ascii=False),
            ))

            relation_count += 1

        conn.commit()

        # 免費層級限制每分鐘 15 次請求，間隔 5 秒＝每分鐘 12 次，
        # 留一點安全餘裕
        time.sleep(5)

    conn.close()

    return relation_count


def main():

    ensure_extra_columns()

    print("\n===== 第一步：抓取 RSS =====")
    items = fetch_all_raw()
    print(f"共抓到 {len(items)} 則（含之前已存在的）")

    new_count = save_raw_news(items)
    print(f"新增 {new_count} 則到資料庫\n")

    print("===== 第二步：規則 prefilter =====")
    kept_rows = apply_prefilter()

    if not kept_rows:
        print("沒有新的新聞需要分析")
        return

    print(f"\n===== 第三步：AI 分類（共 {len(kept_rows)} 則）=====")

    provider = GeminiProvider()
    stocks = get_all_stocks()

    relation_count = classify_and_link(provider, stocks, kept_rows)

    print("\n======================")
    print(f"AI 分析完成：{len(kept_rows)} 則")
    print(f"建立公司關聯：{relation_count} 筆")
    print("======================")


if __name__ == "__main__":
    main()