from fastapi import FastAPI
import os
from fastapi.middleware.cors import CORSMiddleware

# Demo / 正式環境用 READ_ONLY=1 啟動，所有端點只讀資料庫，不在
# 請求中打 FinMind。評審點開個股不用等好幾秒，也不會跟每日排程
# 搶額度。資料由 cron 的 daily_update.sh 負責更新。
READ_ONLY = os.getenv("READ_ONLY") == "1"
from database import get_connection
from update_price import update_one_stock
from update_financial import update_one_financial
from update_institution import update_one_institution
from update_holder import update_one_holder
from update_margin import update_one_margin
from datetime import datetime, timedelta
import json
from update_disclosures import ensure_table as ensure_disclosures_table, update_disclosures
import holdings as holdings_module
import watchlists as watchlists_module
from backfill_price_history import ensure_full_history
from backtest import run_ma_cross_backtest, run_backtest, run_portfolio_backtest, run_screener_backtest, run_dca_backtest
from update_market_chips import ensure_tables as ensure_market_chips_tables
from fetch_cache import safe_update, needs_price, quota_blocked

app = FastAPI(
    title="Stock AI API"
)



app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)



@app.get("/ping")
def ping():
    return {"status": "ok"}

@app.get("/")
def home():

    return {
        "message": "Stock AI API running"
    }





# ==========================
# 股票搜尋
# ==========================


def latest_available_quarter():
    today = datetime.today()

    if today.month < 5:
        return today.year - 1, 4
    elif today.month < 8:
        return today.year, 1
    elif today.month < 11:
        return today.year, 2
    else:
        return today.year, 3


def ensure_financial(code: str):

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT year, quarter, updated_at
        FROM financials
        WHERE code=?
        ORDER BY year DESC, quarter DESC
        LIMIT 1
    """, (code,))

    newest = cursor.fetchone()

    target_year, target_quarter = latest_available_quarter()

    need_update = False

    if newest is None:
        need_update = True
    else:
        if newest["year"] < target_year:
            need_update = True
        elif newest["year"] == target_year and newest["quarter"] < target_quarter:
            need_update = True

    conn.close()

    if need_update:
        print(f"{code} 更新財報...")
        if not READ_ONLY:
            safe_update(update_one_financial, code)



@app.get("/search")
def search_stock(q: str):

    conn = get_connection()

    cursor = conn.cursor()


    cursor.execute(
        """
        SELECT *
        FROM stocks

        WHERE code LIKE ?
           OR name LIKE ?

        ORDER BY

        CASE

            WHEN code = ? THEN 0

            WHEN code LIKE ? THEN 1

            WHEN name LIKE ? THEN 2

            ELSE 3

        END,

        code

        LIMIT 20

        """,
        (
            f"{q}%",
            f"%{q}%",

            q,

            f"{q}%",

            f"%{q}%"
        )
    )


    stocks = cursor.fetchall()


    conn.close()


    return [
        dict(stock)
        for stock in stocks
    ]







# ==========================
# 全部股票
# ==========================

@app.get("/stocks")
def get_stocks():

    conn = get_connection()

    cursor = conn.cursor()


    cursor.execute(
        """
        SELECT *
        FROM stocks
        LIMIT 100
        """
    )


    stocks = cursor.fetchall()


    conn.close()


    return [
        dict(stock)
        for stock in stocks
    ]







# ==========================
# 單一股票詳細資料
# ==========================

@app.get("/stock/{code}")
def get_stock(code: str):


    conn = get_connection()

    cursor = conn.cursor()
    # 股票基本資料
    cursor.execute("""
        SELECT *
        FROM stocks
        WHERE code=?
    """, (code,))

    stock = cursor.fetchone()

    if not stock:
        conn.close()
        return {"error": "stock not found"}

    result = dict(stock)

    asset_type = result.get("asset_type", "STOCK")

    result["financial_supported"] = (
        asset_type == "STOCK"
    )

    # =====================
    # 最新股價
    # =====================
   # 最新價格

    cursor.execute("""
    SELECT *
    FROM prices
    WHERE code=?
        ORDER BY date DESC
    LIMIT 2
""", (code,))

    price_rows = cursor.fetchall()
    price = price_rows[0] if price_rows else None
    prev_close = (price_rows[1]["close"] if len(price_rows) > 1 else None)

    # 用「最近一個交易日」判斷，不是「今天」——原本的寫法在
    # 週末和國定假日永遠成立，每次開頁面都會白打一次 API。
    # READ_ONLY 時整段跳過，不然會印出「更新股價...」卻什麼都
    # 沒做，還多查一次資料庫。
    price_need_update = (not READ_ONLY) and needs_price(code)

    if price_need_update:

        conn.close()

        print(f"{code} 更新股價...")

        safe_update(update_one_stock, code)

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT *
            FROM prices
            WHERE code=?
            ORDER BY date DESC
            LIMIT 2
        """, (code,))

        price_rows = cursor.fetchall()
        price = price_rows[0] if price_rows else None
        prev_close = (price_rows[1]["close"] if len(price_rows) > 1 else None)

    if price:

        result.update({

            "date": price["date"],
            "open": price["open"],
            "high": price["high"],
            "low": price["low"],
            "close": price["close"],
            "price": price["close"],
            "volume": price["volume"],

            "prev_close": prev_close,
            "change": (
                price["close"] - prev_close
                if price["close"] is not None and prev_close else None
            ),
            "change_pct": (
                (price["close"] - prev_close) / prev_close * 100
                if price["close"] is not None and prev_close else None
            ),

        })

    # =====================
    # 近四季EPS
    # =====================
    cursor.execute("""
        SELECT year,
               quarter,
               eps,
               roe,
               revenue
        FROM financials
        WHERE code=?
        ORDER BY year DESC, quarter DESC
        LIMIT 4
    """, (code,))

    quarter_data = cursor.fetchall()

    ensure_financial(code)

    conn.close()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            year,
            quarter,
            eps,
            roe,
            revenue
        FROM financials
        WHERE code=?
        ORDER BY year DESC, quarter DESC
        LIMIT 4
    """, (code,))

    quarter_data = cursor.fetchall()

    eps_quarter = []

    if len(quarter_data) == 0:

        result["eps_ttm"] = None
        result["eps_quarter"] = []

    else:

        eps_ttm = 0

        for row in quarter_data:

            eps = row["eps"] or 0

            eps_ttm += eps

            eps_quarter.append({

                "year": row["year"],
                "quarter": row["quarter"],
                "eps": eps,
                "roe": row["roe"],
                "revenue": row["revenue"]

            })

        result["eps_ttm"] = round(eps_ttm, 2)
        result["eps_quarter"] = eps_quarter

    # =====================
    # 歷年EPS
    # =====================
    cursor.execute("""
        SELECT
            year,
            SUM(eps) AS eps
        FROM financials
        WHERE code=?
        GROUP BY year
        ORDER BY year DESC
    """, (code,))

    year_rows = cursor.fetchall()

    eps_year = []

    for row in year_rows:

        eps_year.append({

            "year": row["year"],
            "eps": round(row["eps"] or 0, 2)

        })

    result["eps_year"] = eps_year

    cursor.execute("""
        SELECT pb
        FROM financials
        WHERE code=?
          AND pb IS NOT NULL
        ORDER BY year DESC, quarter DESC
        LIMIT 1
    """, (code,))

    pb_row = cursor.fetchone()

    close = result.get("price")
    eps_ttm = result.get("eps_ttm")

    # 本益比（用算的）
    if close and eps_ttm and eps_ttm > 0:
        result["pe"] = round(close / eps_ttm, 2)
    else:
        result["pe"] = None

    # 股價淨值比（直接用 FinMind 資料）
    result["pb"] = pb_row["pb"] if pb_row else None

    # 殖利率：不要在這裡重新算，直接沿用 stocks.dividend_yield
    # 這個欄位（update_financial.py 用往回12個月配息加總算出來
    # 的，已經是正確的移動視窗算法）。這裡原本自己另外重算一次
    # 「抓最近一筆有配息的季度」，等於只看單一次配息，是舊的
    # bug，跟 update_financial.py 修好的邏輯不一致，導致兩邊
    # 數字對不上——這裡改成直接複用，避免同一件事有兩套邏輯。
    result["dividendYield"] = result.get("dividend_yield")

    conn.close()

    return result


# ==========================
# 歷史價格(K線)
# ==========================

@app.get("/prices/{code}")
def get_prices(code:str):


    conn = get_connection()

    cursor = conn.cursor()



    cursor.execute(
        """
        SELECT *

        FROM prices

        WHERE code=?

        ORDER BY date ASC

        """,
        (code,)
    )


    prices = cursor.fetchall()


    conn.close()



    return [
        dict(price)
        for price in prices
    ]

# ==========================
# K線資料
# ==========================

@app.get("/kline/{code}")
def get_kline(code: str, limit: int | None = None):

    # 台指期資料結構跟一般股價不一樣（合約月份、近月/遠月），
    # 存在獨立的 futures_prices 表，這裡另外處理，但回傳格式
    # 保持跟下面股票/指數完全一樣，前端不用另外寫邏輯。
    if code == "TX":

        conn = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT date, open, high, low, close, volume FROM (
                SELECT date, open, high, low, close, volume,
                       ROW_NUMBER() OVER (
                           PARTITION BY date ORDER BY contract_date ASC
                       ) as rn
                FROM futures_prices
                WHERE futures_id = 'TX'
                  AND close IS NOT NULL AND close != 0
            )
            WHERE rn = 1
            ORDER BY date DESC
        """

        params = []

        if limit is not None:
            query += " LIMIT ?"
            params.append(limit)

        cursor.execute(query, params)

        rows = cursor.fetchall()
        conn.close()

        data = []
        for row in reversed(rows):
            data.append({
                "date": row["date"],
                "open": row["open"],
                "high": row["high"],
                "low": row["low"],
                "close": row["close"],
                "volume": row["volume"],
            })

        return data

    # 歷史筆數太少（可能是之前用匿名身份抓資料時被 FinMind
    # 默默限制成只有一個月）就先補一次完整歷史，只在筆數不足
    # 時才會真的觸發抓取，不會每次查詢都重跑。
    if not READ_ONLY:
        safe_update(ensure_full_history, code)

    conn = get_connection()
    cursor = conn.cursor()

    query = """
        SELECT
            date,
            open,
            high,
            low,
            close,
            volume
        FROM prices
        WHERE code = ?
          AND open IS NOT NULL
          AND high IS NOT NULL
          AND low IS NOT NULL
          AND close IS NOT NULL
        ORDER BY date DESC
    """

    params = [code]

    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)

    cursor.execute(query, params)

    rows = cursor.fetchall()
    conn.close()

    data = []
    for row in reversed(rows):
        data.append({
            "date": row["date"],
            "open": row["open"],
            "high": row["high"],
            "low": row["low"],
            "close": row["close"],
            "volume": row["volume"],
        })

    return data


# ==========================
# 三大法人買賣超
# ==========================

def ensure_institution(code: str):

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
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

    cursor.execute("""
        SELECT date
        FROM institution_flows
        WHERE code=?
        ORDER BY date DESC
        LIMIT 1
    """, (code,))

    newest = cursor.fetchone()

    conn.close()

    need_update = False

    if newest is None:
        need_update = True
    else:
        last_date = datetime.strptime(newest["date"], "%Y-%m-%d").date()
        today = datetime.today().date()

        if last_date < today:
            need_update = True

    if need_update:
        print(f"{code} 更新三大法人...")
        if not READ_ONLY:
            safe_update(update_one_institution, code)


@app.get("/institution/{code}")
def get_institution(code: str):

    ensure_institution(code)

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            i.date,
            i.foreign_net,
            i.trust_net,
            i.dealer_net,
            p.close
        FROM institution_flows i
        LEFT JOIN prices p
            ON p.code = i.code AND p.date = i.date
        WHERE i.code = ?
        ORDER BY i.date ASC
    """, (code,))

    rows = cursor.fetchall()
    conn.close()

    data = []
    for row in rows:
        data.append({
            "date": row["date"],
            "foreign": row["foreign_net"],
            "trust": row["trust_net"],
            "dealer": row["dealer_net"],
            "close": row["close"],
        })

    return data

@app.get("/financial/{code}")
def get_financial(code: str):

    conn = get_connection()
    cursor = conn.cursor()

    # ===== 季資料 =====
    cursor.execute("""
        SELECT
            year,
            quarter,

            revenue,

            gross_profit,
            operating_profit,
            pretax_profit,
            net_income,

            eps,

            gross_margin,
            operating_margin,
            net_margin,

            roe,
            roa,

            book_value,

            assets,
            liabilities,
            equity,

            debt_ratio,
            current_ratio,
            quick_ratio,

            operating_cash_flow,
            investing_cash_flow,
            financing_cash_flow,

            free_cash_flow,

            pe,
            pb,
            dividend_yield,

            cash_dividend,
            stock_dividend,

            ex_dividend_date,
            cash_dividend_date,
            stock_dividend_date

        FROM financials

        WHERE code=?

        ORDER BY year, quarter
    """, (code,))

    quarter_rows = cursor.fetchall()

    ensure_financial(code)

    conn.close()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            year,
            quarter,

            revenue,

            gross_profit,
            operating_profit,
            pretax_profit,
            net_income,

            eps,

            gross_margin,
            operating_margin,
            net_margin,

            roe,
            roa,

            book_value,

            assets,
            liabilities,
            equity,

            debt_ratio,
            current_ratio,
            quick_ratio,

            operating_cash_flow,
            investing_cash_flow,
            financing_cash_flow,

            free_cash_flow,

            pe,
            pb,
            dividend_yield,

            cash_dividend,
            stock_dividend,

            ex_dividend_date,
            cash_dividend_date,
            stock_dividend_date

        FROM financials
        WHERE code=?
        ORDER BY year, quarter
    """, (code,))

    quarter_rows = cursor.fetchall()

    quarter = [
        {
            "year": row["year"],
            "quarter": row["quarter"],

            "revenue": row["revenue"],

            "grossProfit": row["gross_profit"],
            "operatingProfit": row["operating_profit"],
            "pretaxProfit": row["pretax_profit"],
            "netIncome": row["net_income"],

            "eps": row["eps"],

            "grossMargin": row["gross_margin"],
            "operatingMargin": row["operating_margin"],
            "netMargin": row["net_margin"],

            "roe": row["roe"],
            "roa": row["roa"],

            "bookValue": row["book_value"],

            "assets": row["assets"],
            "liabilities": row["liabilities"],
            "equity": row["equity"],

            "debtRatio": row["debt_ratio"],
            "currentRatio": row["current_ratio"],
            "quickRatio": row["quick_ratio"],

            "operatingCashFlow": row["operating_cash_flow"],
            "investingCashFlow": row["investing_cash_flow"],
            "financingCashFlow": row["financing_cash_flow"],

            "freeCashFlow": row["free_cash_flow"],

            "pe": row["pe"],
            "pb": row["pb"],
            "dividendYield": row["dividend_yield"],

            "cashDividend": row["cash_dividend"],
            "stockDividend": row["stock_dividend"],

            "exDividendDate": row["ex_dividend_date"],
            "cashDividendDate": row["cash_dividend_date"],
            "stockDividendDate": row["stock_dividend_date"],
        }
        for row in quarter_rows
    ]

    # ===== 月營收 =====
    cursor.execute("""
        SELECT
            year,
            month,
            revenue,
            mom,
            yoy
        FROM monthly_revenue
        WHERE code=?
        ORDER BY year, month
    """, (code,))

    month_rows = cursor.fetchall()

    month = [
        {
            "year": row["year"],
            "month": row["month"],
            "revenue": row["revenue"],
            "mom": row["mom"],
            "yoy": row["yoy"],
        }
        for row in month_rows
    ]

    conn.close()

    return {
        "quarter": quarter,
        "month": month,
    }


# ==========================
# 大戶持股 / 籌碼分布
# ==========================

def ensure_holder(code: str):

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
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

    cursor.execute("""
        SELECT date
        FROM holder_distribution
        WHERE code=?
        ORDER BY date DESC
        LIMIT 1
    """, (code,))

    newest = cursor.fetchone()

    conn.close()

    need_update = False

    if newest is None:
        need_update = True
    else:
        last_date = datetime.strptime(newest["date"], "%Y-%m-%d").date()
        today = datetime.today().date()

        # 持股分級通常一週才更新一次，超過 7 天沒資料才觸發
        if (today - last_date).days > 7:
            need_update = True

    if need_update:
        print(f"{code} 更新大戶持股...")
        if not READ_ONLY:
            safe_update(update_one_holder, code)


@app.get("/holder/{code}")
def get_holder(code: str):

    ensure_holder(code)

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT date, level, people, percent
        FROM holder_distribution
        WHERE code = ?
        ORDER BY date ASC, level ASC
    """, (code,))

    rows = cursor.fetchall()
    conn.close()

    data = []
    for row in rows:
        data.append({
            "date": row["date"],
            "level": row["level"],
            "people": row["people"],
            "percent": row["percent"],
        })

    return data


# ==========================
# 資券當沖
# ==========================

def ensure_margin(code: str):

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
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

    cursor.execute("""
        SELECT date
        FROM margin_flows
        WHERE code=?
        ORDER BY date DESC
        LIMIT 1
    """, (code,))

    newest = cursor.fetchone()

    conn.close()

    need_update = False

    if newest is None:
        need_update = True
    else:
        last_date = datetime.strptime(newest["date"], "%Y-%m-%d").date()
        today = datetime.today().date()

        if last_date < today:
            need_update = True

    if need_update:
        print(f"{code} 更新資券...")
        if not READ_ONLY:
            safe_update(update_one_margin, code)


@app.get("/margin/{code}")
def get_margin(code: str):

    ensure_margin(code)

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT *
        FROM margin_flows
        WHERE code = ?
        ORDER BY date ASC
    """, (code,))

    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in rows]


# ==========================
# 新聞（改用 news_relations，依 AI 判斷的相關性排序）
# ==========================

def ensure_news_table():

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS news (
            link TEXT PRIMARY KEY,
            source TEXT,
            title TEXT,
            summary TEXT,
            pub_date TEXT,
            matched_codes TEXT,
            created_at TEXT,
            investment_relevance INTEGER,
            stock_market_relevance INTEGER,
            confidence INTEGER,
            event_materiality INTEGER,
            industries TEXT,
            topics TEXT,
            technologies TEXT,
            event_type TEXT,
            processed_at TEXT
        )
    """)

    cursor.execute("""
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


@app.get("/news/{code}")
def get_news(code: str, min_score: int = 40, limit: int = 30):

    ensure_news_table()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            n.link,
            n.source,
            n.title,
            n.summary,
            n.pub_date,
            n.topics,
            n.event_type,
            r.relevance_score,
            r.confidence,
            r.relation_type,
            r.reasons
        FROM news_relations r
        JOIN news n ON n.link = r.news_link
        WHERE r.code = ?
          AND r.relevance_score >= ?
        ORDER BY n.pub_date DESC
        LIMIT ?
    """, (code, min_score, limit))

    rows = cursor.fetchall()
    conn.close()

    def parse_json_field(v):
        if not v:
            return []
        try:
            return json.loads(v)
        except (json.JSONDecodeError, TypeError):
            return []

    data = []
    for row in rows:
        data.append({
            "link": row["link"],
            "source": row["source"],
            "title": row["title"],
            "summary": row["summary"],
            "pub_date": row["pub_date"],
            "topics": parse_json_field(row["topics"]),
            "event_type": row["event_type"],
            "relevance_score": row["relevance_score"],
            "confidence": row["confidence"],
            "relation_type": row["relation_type"],
            "reasons": parse_json_field(row["reasons"]),
        })

    return data


@app.get("/news/portfolio/all")
def get_portfolio_news(min_score: int = 40, limit: int = 50):
    """
    首頁新聞頁用：庫存股 + 自選股（合併去重）的股票代號，各自的
    相關新聞合併成一條時間軸。同一則新聞如果跟多支股票都有關，
    只會出現一次，但會列出全部相關的股票代號，不會重複顯示。
    """

    ensure_news_table()
    holdings_module.ensure_tables()
    watchlists_module.ensure_tables()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT DISTINCT code FROM holdings")
    holding_codes = {row["code"] for row in cursor.fetchall()}

    cursor.execute("SELECT DISTINCT code FROM watchlist_stocks")
    watchlist_codes = {row["code"] for row in cursor.fetchall()}

    all_codes = holding_codes | watchlist_codes

    if not all_codes:
        conn.close()
        return []

    placeholders = ",".join("?" for _ in all_codes)

    cursor.execute(f"""
        SELECT
            n.link, n.source, n.title, n.summary, n.pub_date,
            n.topics, n.event_type,
            MAX(r.relevance_score) as relevance_score,
            MAX(r.confidence) as confidence,
            GROUP_CONCAT(DISTINCT r.code) as related_codes
        FROM news_relations r
        JOIN news n ON n.link = r.news_link
        WHERE r.code IN ({placeholders})
          AND r.relevance_score >= ?
        GROUP BY n.link
        ORDER BY n.pub_date DESC
        LIMIT ?
    """, (*all_codes, min_score, limit))

    rows = cursor.fetchall()
    conn.close()

    def parse_json_field(v):
        if not v:
            return []
        try:
            return json.loads(v)
        except (json.JSONDecodeError, TypeError):
            return []

    data = []
    for row in rows:
        data.append({
            "link": row["link"],
            "source": row["source"],
            "title": row["title"],
            "summary": row["summary"],
            "pub_date": row["pub_date"],
            "topics": parse_json_field(row["topics"]),
            "event_type": row["event_type"],
            "relevance_score": row["relevance_score"],
            "confidence": row["confidence"],
            "related_codes": (row["related_codes"] or "").split(","),
        })

    return data


@app.get("/news/market/all")
def get_market_news(min_score: int = 40, limit: int = 50):
    """
    首頁新聞頁用：大盤（跟整體股市相關，不綁定特定公司）+
    國際財經新聞（來源是 Yahoo股市-國際財經，確保是財金相關的
    國際新聞，不是隨便的國際新聞）合併成一條時間軸。
    """

    ensure_news_table()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT link, source, title, summary, pub_date, topics,
               event_type, stock_market_relevance
        FROM news
        WHERE (
            stock_market_relevance >= ?
            OR source = 'Yahoo股市-國際財經'
        )
        AND processed_at IS NOT NULL
        ORDER BY pub_date DESC
        LIMIT ?
    """, (min_score, limit))

    rows = cursor.fetchall()
    conn.close()

    def parse_json_field(v):
        if not v:
            return []
        try:
            return json.loads(v)
        except (json.JSONDecodeError, TypeError):
            return []

    data = []
    for row in rows:
        data.append({
            "link": row["link"],
            "source": row["source"],
            "title": row["title"],
            "summary": row["summary"],
            "pub_date": row["pub_date"],
            "topics": parse_json_field(row["topics"]),
            "event_type": row["event_type"],
            "relevance_score": row["stock_market_relevance"],
            "confidence": None,
            "related_codes": [],
        })

    return data


# ==========================
# 法說會 / 股東會 / 董事會 等重大訊息
#
# 拆成兩組：
#   /disclosures/{code}/events   -> 重大動態（is_major_event=1）
#   /disclosures/{code}/meetings -> 法說／股東會（會議類分類，含公告與結果）
# ==========================

TIER_ORDER = {"S": 0, "A": 1, "B": 2}

MEETING_CATEGORIES_SQL = (
    "agm", "egm", "investor_conference", "investor_day", "roadshow",
)


def _row_to_dict(row):
    return dict(row)


@app.get("/disclosures/{code}/events")
def get_major_events(code: str, limit: int = 50):
    """重大動態：is_major_event=1 的所有紀錄（含官方分類本身就是
    事件的財報/股利/投資，以及從股東會決議內容解析出的衍生事件）。"""

    ensure_disclosures_table()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, code, company_name, category, tier,
               subject, detail, fact_date, speak_date,
               major_event_type, related_id
        FROM disclosures
        WHERE code = ? AND is_major_event = 1
        ORDER BY COALESCE(fact_date, speak_date) DESC
        LIMIT ?
    """, (code, limit))

    rows = cursor.fetchall()
    conn.close()

    data = [_row_to_dict(r) for r in rows]
    data.sort(key=lambda r: TIER_ORDER.get(r["tier"], 9))

    return data


@app.get("/disclosures/{code}/meetings")
def get_meetings(code: str, limit: int = 50):
    """法說／股東會：會議類分類，公告與結果都顯示（保留完整會議脈絡），
    不含從中衍生出來的重大動態子項目。"""

    ensure_disclosures_table()

    conn = get_connection()
    cursor = conn.cursor()

    placeholders = ",".join("?" for _ in MEETING_CATEGORIES_SQL)

    cursor.execute(f"""
        SELECT id, code, company_name, category, tier,
               subject, detail, fact_date, speak_date, content_status
        FROM disclosures
        WHERE code = ? AND category IN ({placeholders})
        ORDER BY COALESCE(fact_date, speak_date) DESC
        LIMIT ?
    """, (code, *MEETING_CATEGORIES_SQL, limit))

    rows = cursor.fetchall()
    conn.close()

    return [_row_to_dict(r) for r in rows]


@app.get("/disclosures/{code}")
def get_disclosures(code: str, limit: int = 50):
    """舊版扁平端點，暫時保留給還沒切換的呼叫端使用。"""

    ensure_disclosures_table()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, code, company_name, category, tier,
               subject, detail, fact_date, speak_date
        FROM disclosures
        WHERE code = ?
        ORDER BY speak_date DESC
        LIMIT ?
    """, (code, limit))

    rows = cursor.fetchall()
    conn.close()

    data = [dict(row) for row in rows]

    data.sort(key=lambda r: TIER_ORDER.get(r["tier"], 9))

    return data
"""
把這段加進 main.py（建議放在檔案最後面）。

同時要在 main.py 最上面加這行 import：
    import holdings as holdings_module
"""

import holdings as holdings_module
from pydantic import BaseModel
from typing import Optional


class HoldingCreate(BaseModel):
    code: str
    avg_price: float
    shares: int


class HoldingUpdate(BaseModel):
    avg_price: float
    shares: int


class FeeDiscountUpdate(BaseModel):
    discount: Optional[float] = None  # 例如 6 代表 6 折，傳 null 恢復原價


@app.get("/holdings")
def get_holdings():
    return holdings_module.list_holdings()


@app.post("/holdings")
def create_holding(payload: HoldingCreate):
    new_id = holdings_module.add_holding(
        payload.code, payload.avg_price, payload.shares
    )
    return {"id": new_id}


@app.put("/holdings/{holding_id}")
def edit_holding(holding_id: int, payload: HoldingUpdate):
    holdings_module.update_holding(
        holding_id, payload.avg_price, payload.shares
    )
    return {"ok": True}


@app.delete("/holdings/{holding_id}")
def remove_holding(holding_id: int):
    holdings_module.delete_holding(holding_id)
    return {"ok": True}


@app.get("/settings/fee_discount")
def get_fee_discount():
    return {"discount": holdings_module.get_fee_discount()}


@app.post("/settings/fee_discount")
def set_fee_discount(payload: FeeDiscountUpdate):
    holdings_module.set_fee_discount(payload.discount)
    return {"ok": True}
"""
把這段加進 main.py（建議放在檔案最後面）。

同時要在 main.py 最上面加這行 import：
    import watchlists as watchlists_module

（如果之前已經有 from pydantic import BaseModel 就不用重複加）
"""

import watchlists as watchlists_module
from pydantic import BaseModel


class WatchlistRename(BaseModel):
    name: str


class WatchlistAddStock(BaseModel):
    code: str


@app.get("/watchlists")
def get_watchlists():
    return watchlists_module.list_watchlists()


@app.put("/watchlists/{watchlist_id}")
def rename_watchlist_endpoint(watchlist_id: int, payload: WatchlistRename):
    watchlists_module.rename_watchlist(watchlist_id, payload.name)
    return {"ok": True}


@app.get("/watchlists/{watchlist_id}/stocks")
def get_watchlist_stocks_endpoint(watchlist_id: int):
    return watchlists_module.get_watchlist_stocks(watchlist_id)


@app.post("/watchlists/{watchlist_id}/stocks")
def add_watchlist_stock(watchlist_id: int, payload: WatchlistAddStock):
    watchlists_module.add_stock(watchlist_id, payload.code)
    return {"ok": True}


@app.delete("/watchlists/{watchlist_id}/stocks/{code}")
def remove_watchlist_stock(watchlist_id: int, code: str):
    watchlists_module.remove_stock(watchlist_id, code)
    return {"ok": True}

class WatchlistReorder(BaseModel):
    codes: list[str]  # 拖曳後的新順序


@app.put("/watchlists/{watchlist_id}/reorder")
def reorder_watchlist_stocks(watchlist_id: int, payload: WatchlistReorder):
    watchlists_module.reorder_stocks(watchlist_id, payload.codes)
    return {"ok": True}
"""
這段是新端點，可以先加進 main.py（不需要看你現有的內容，
純新增），/kline/{code} 支援 TX 的部分我拿到你目前的
main.py 之後再幫你改到正確位置。

最上面加 import：
    from update_futures import ensure_table as ensure_futures_table
"""

from update_futures import ensure_table as ensure_futures_table
from update_index_money import ensure_table as ensure_index_money_table
from database import get_connection


def _get_index_overview(code, name):
    """加權指數／櫃買指數：沿用 prices 表，跟一般股票查現價的
    邏輯完全一樣。"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT close FROM prices
        WHERE code = ?
        ORDER BY date DESC
        LIMIT 2
    """, (code,))

    rows = cur.fetchall()
    conn.close()

    if not rows:
        return {"code": code, "name": name, "price": None,
                "change": None, "change_pct": None}

    current = rows[0]["close"]
    prev = rows[1]["close"] if len(rows) > 1 else None

    change = None
    change_pct = None

    if current is not None and prev is not None and prev != 0:
        change = current - prev
        change_pct = change / prev * 100

    return {
        "code": code, "name": name,
        "price": current, "change": change, "change_pct": change_pct,
    }


def _get_futures_overview():
    """台指期：查 futures_prices 表，只看近月合約、跳過還沒
    結算的全 0 列（用 SQLite window function 每天挑近月那筆）。"""

    ensure_futures_table()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT date, close FROM (
            SELECT date, close,
                   ROW_NUMBER() OVER (
                       PARTITION BY date ORDER BY contract_date ASC
                   ) as rn
            FROM futures_prices
            WHERE futures_id = 'TX' AND close IS NOT NULL AND close != 0
        )
        WHERE rn = 1
        ORDER BY date DESC
        LIMIT 2
    """)

    rows = cur.fetchall()
    conn.close()

    if not rows:
        return {"code": "TX", "name": "台指期", "price": None,
                "change": None, "change_pct": None}

    current = rows[0]["close"]
    prev = rows[1]["close"] if len(rows) > 1 else None

    change = None
    change_pct = None

    if current is not None and prev is not None and prev != 0:
        change = current - prev
        change_pct = change / prev * 100

    return {
        "code": "TX", "name": "台指期",
        "price": current, "change": change, "change_pct": change_pct,
    }


@app.get("/market/overview")
def get_market_overview():
    return [
        _get_index_overview("TAIEX", "加權指數"),
        _get_index_overview("TPEx", "櫃買指數"),
        _get_futures_overview(),
    ]


@app.get("/market/kline/{code}")
def get_market_kline(code: str, limit: int | None = None):
    """
    大盤頁專用的K線端點，回傳格式比照 /kline/{code}，但
    volume 欄位是「成交金額」，不是股數/口數：
    - TAIEX / TPEx：真正的成交金額（index_trading_money 表）
    - TX（台指期）：台指期沒有現成的金額欄位，用「口數 × 收盤價
      × 200元/點」估算（200元/點是台指期公開的合約規格，不是
      隨便設的數字），估算值會在回傳資料裡標註 is_estimated。
    """

    ensure_index_money_table()

    conn = get_connection()
    cursor = conn.cursor()

    if code == "TX":

        cursor.execute("""
            SELECT date, open, high, low, close, volume FROM (
                SELECT date, open, high, low, close, volume,
                       ROW_NUMBER() OVER (
                           PARTITION BY date ORDER BY contract_date ASC
                       ) as rn
                FROM futures_prices
                WHERE futures_id = 'TX'
                  AND close IS NOT NULL AND close != 0
            )
            WHERE rn = 1
            ORDER BY date DESC
        """)

        rows = cursor.fetchall()
        conn.close()

        data = []
        for row in reversed(rows):
            money = None
            if row["volume"] is not None and row["close"] is not None:
                money = row["volume"] * row["close"] * 200
            data.append({
                "date": row["date"],
                "open": row["open"],
                "high": row["high"],
                "low": row["low"],
                "close": row["close"],
                "volume": money,
                "is_estimated": True,
            })

        if limit is not None:
            data = data[-limit:]

        return data

    cursor.execute("""
        SELECT p.date, p.open, p.high, p.low, p.close,
               m.trading_money
        FROM prices p
        LEFT JOIN index_trading_money m
          ON m.code = p.code AND m.date = p.date
        WHERE p.code = ?
          AND p.open IS NOT NULL AND p.high IS NOT NULL
          AND p.low IS NOT NULL AND p.close IS NOT NULL
        ORDER BY p.date DESC
    """, (code,))

    rows = cursor.fetchall()
    conn.close()

    data = []
    for row in reversed(rows):
        data.append({
            "date": row["date"],
            "open": row["open"],
            "high": row["high"],
            "low": row["low"],
            "close": row["close"],
            "volume": row["trading_money"],
            "is_estimated": False,
        })

    if limit is not None:
        data = data[-limit:]

    return data

@app.get("/market/chips")
def get_market_chips():
    """
    大盤三大法人買賣超 + 資券，回傳最新一天的資料。

    注意單位不一樣：
    - institutional（三大法人）：買賣金額，單位「元」
    - margin_money（融資）：金額，單位「元」
    - short_shares（融券）：股數，單位「股」（前端顯示時自己
      除以1000換算成「張」，這裡故意不換算，保留原始股數，
      避免格式跟精確度混在後端邏輯裡）
    """

    ensure_market_chips_tables()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT * FROM market_institutional
        ORDER BY date DESC LIMIT 1
    """)
    institutional = cursor.fetchone()

    cursor.execute("""
        SELECT * FROM market_margin
        ORDER BY date DESC LIMIT 1
    """)
    margin = cursor.fetchone()

    conn.close()

    return {
        "institutional": dict(institutional) if institutional else None,
        "margin": dict(margin) if margin else None,
    }

@app.get("/market/institutional/history")
def get_market_institutional_history(limit: int = 30):

    ensure_market_chips_tables()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT * FROM market_institutional
        ORDER BY date DESC
        LIMIT ?
    """, (limit,))

    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in reversed(rows)]


@app.get("/market/margin/history")
def get_market_margin_history(limit: int = 30):

    ensure_market_chips_tables()

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT * FROM market_margin
        ORDER BY date DESC
        LIMIT ?
    """, (limit,))

    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in reversed(rows)]

class BacktestRequest(BaseModel):
    code: str
    start_date: str
    end_date: str
    buy_fast: int
    buy_slow: int
    sell_fast: int
    sell_slow: int
    initial_capital: float = 1000000
    fee_discount: float | None = None


@app.post("/backtest/ma_cross")
def run_backtest_endpoint(payload: BacktestRequest):
    return run_ma_cross_backtest(
        payload.code,
        payload.start_date,
        payload.end_date,
        payload.buy_fast,
        payload.buy_slow,
        payload.sell_fast,
        payload.sell_slow,
        payload.initial_capital,
        payload.fee_discount,
    )


class BacktestCondition(BaseModel):
    type: str
    # "ma_cross" | "price_vs_ma" | "price_above" | "price_below"
    # | "volume_spike" | "volume_new_high" | "volume_breakout"
    # | "liquidity_trading_value_above" | "liquidity_volume_above"（選股策略專用）
    # | "fundamental_above" | "fundamental_below" | "fundamental_new_high"
    # | "fundamental_growth" | "fundamental_consistent"（選股策略專用）
    fast: int | None = None
    slow: int | None = None
    period: int | None = None  # 給 price_vs_ma / volume_* 用
    window_days: int | None = None  # 給 liquidity_* 用：近幾日平均
    direction: str | None = None  # "above" | "below"
    operator: str | None = None  # ">"|"<"|">="|"<="|"=="，給 fundamental_above/below 用，不給則沿用 direction 的預設行為
    value: float | None = None  # 給 price/fundamental/liquidity 條件用
    multiplier: float | None = None  # 給 volume_spike 用
    min_multiplier: float | None = None  # 給 volume_breakout 用（大量日最低倍數門檻）
    field: str | None = None  # 給 fundamental 條件用："pe"/"dividend_yield"/"eps"/"roe"/"roa"/"gross_margin"/"operating_margin"/"revenue"/"debt_ratio"/"free_cash_flow"
    quarters_back: int | None = None  # 給 fundamental_growth 用：跟幾季前比較
    quarters: int | None = None  # 給 fundamental_consistent 用：連續維持幾季；給 fundamental_new_high 用：比較範圍幾季


class BacktestRunRequest(BaseModel):
    code: str
    start_date: str
    end_date: str
    # 群組結構：外層 list 是 OR，內層 list 是 AND
    # 例如 [[A, B], [C]] 代表 (A AND B) OR (C)
    buy_conditions: list[list[BacktestCondition]]
    sell_conditions: list[list[BacktestCondition]]
    initial_capital: float = 1000000
    fee_discount: float | None = None


def _condition_to_dict(c: BacktestCondition):

    d = {"type": c.type}

    if c.fast is not None:
        d["fast"] = c.fast
    if c.slow is not None:
        d["slow"] = c.slow
    if c.direction is not None:
        d["direction"] = c.direction
    if c.operator is not None:
        d["operator"] = c.operator
    if c.value is not None:
        d["value"] = c.value
    if c.period is not None:
        d["period"] = c.period
    if c.window_days is not None:
        d["window_days"] = c.window_days
    if c.multiplier is not None:
        d["multiplier"] = c.multiplier
    if c.min_multiplier is not None:
        d["min_multiplier"] = c.min_multiplier
    if c.field is not None:
        d["field"] = c.field
    if c.quarters_back is not None:
        d["quarters_back"] = c.quarters_back
    if c.quarters is not None:
        d["quarters"] = c.quarters

    return d


@app.post("/backtest/run")
def run_backtest_generic_endpoint(payload: BacktestRunRequest):
    return run_backtest(
        payload.code,
        payload.start_date,
        payload.end_date,
        buy_conditions=[
            [_condition_to_dict(c) for c in group]
            for group in payload.buy_conditions
        ],
        sell_conditions=[
            [_condition_to_dict(c) for c in group]
            for group in payload.sell_conditions
        ],
        initial_capital=payload.initial_capital,
        fee_discount=payload.fee_discount,
    )



class PortfolioStockInput(BaseModel):
    code: str
    weight: float | None = None  # 0~100 之間，不填代表平分剩餘額度
    buy_conditions: list[list[BacktestCondition]]
    sell_conditions: list[list[BacktestCondition]]


class PortfolioBacktestRequest(BaseModel):
    stocks: list[PortfolioStockInput]
    start_date: str
    end_date: str
    initial_capital: float = 1000000
    fee_discount: float | None = None


@app.post("/backtest/portfolio")
def run_portfolio_backtest_endpoint(payload: PortfolioBacktestRequest):
    return run_portfolio_backtest(
        stocks=[
            {
                "code": s.code,
                "weight": s.weight,
                "buy_conditions": [
                    [_condition_to_dict(c) for c in group]
                    for group in s.buy_conditions
                ],
                "sell_conditions": [
                    [_condition_to_dict(c) for c in group]
                    for group in s.sell_conditions
                ],
            }
            for s in payload.stocks
        ],
        start_date=payload.start_date,
        end_date=payload.end_date,
        initial_capital=payload.initial_capital,
        fee_discount=payload.fee_discount,
    )


class ScreenerRankField(BaseModel):
    field: str  # 基本面欄位 或 "liquidity_trading_value"/"liquidity_volume"
    direction: str = "desc"


class ScreenerBacktestRequest(BaseModel):
    # 群組結構：外層 list 是 OR，內層 list 是 AND
    screening_conditions: list[list[BacktestCondition]]
    start_date: str
    end_date: str
    rebalance_months: int = 6
    max_stocks: int | None = None
    # 多欄位排名：第一個欄位優先，後面的當同分時的 tie-breaker
    rank_fields: list[ScreenerRankField] | None = None
    initial_capital: float = 1000000
    fee_discount: float | None = None


@app.post("/backtest/screener")
def run_screener_backtest_endpoint(payload: ScreenerBacktestRequest):
    return run_screener_backtest(
        screening_groups=[
            [_condition_to_dict(c) for c in group]
            for group in payload.screening_conditions
        ],
        start_date=payload.start_date,
        end_date=payload.end_date,
        rebalance_months=payload.rebalance_months,
        max_stocks=payload.max_stocks,
        rank_by=(
            [{"field": r.field, "direction": r.direction} for r in payload.rank_fields]
            if payload.rank_fields else None
        ),
        initial_capital=payload.initial_capital,
        fee_discount=payload.fee_discount,
    )


class DcaBacktestRequest(BaseModel):
    code: str
    start_date: str
    end_date: str
    amount_per_period: float
    interval_months: int = 1
    fee_discount: float | None = None


@app.post("/backtest/dca")
def run_dca_backtest_endpoint(payload: DcaBacktestRequest):
    return run_dca_backtest(
        code=payload.code,
        start_date=payload.start_date,
        end_date=payload.end_date,
        amount_per_period=payload.amount_per_period,
        interval_months=payload.interval_months,
        fee_discount=payload.fee_discount,
    )