"""
庫存股功能後端邏輯。

計算規則：
- 手續費率：預設 0.1425%，如果有設定折扣（例如 6 折），
  用 0.1425% × (折扣/10)
- 交易稅率：一般股票 0.3%，ETF 0.1%（依 stocks.asset_type 判斷）
- 成本（買入時）= 股數 × 均價 + 買入手續費（不含交易稅，稅只在賣出時課）
- 市值（現在）= 股數 × 現價 − 賣出手續費 − 賣出交易稅
  （持有中就先扣掉「如果現在賣出」會產生的費用跟稅，市值才是
  真正能拿到手的淨值）
- 損益 = 市值 − 成本
"""

from database import get_connection

RAW_FEE_RATE = 0.001425  # 0.1425%
STOCK_TAX_RATE = 0.003   # 0.3%
ETF_TAX_RATE = 0.001     # 0.1%


def ensure_tables():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS holdings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            avg_price REAL NOT NULL,
            shares INTEGER NOT NULL,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        )
    """)

    # 手續費折扣是全域設定（不是每檔股票各自設定），用簡單的
    # key-value 表存，之後如果有其他全域設定也可以放這裡。
    cur.execute("""
        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)

    conn.commit()
    conn.close()


def get_fee_discount():
    """
    回傳目前設定的手續費折扣（例如 6 代表 6 折），
    沒設定就回傳 None（代表用原價 0.1425%）。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "SELECT value FROM app_settings WHERE key = 'fee_discount'"
    )
    row = cur.fetchone()

    conn.close()

    if row is None or row["value"] in (None, ""):
        return None

    return float(row["value"])


def set_fee_discount(discount):
    """
    設定手續費折扣，discount 傳 None 或空字串代表恢復原價。
    """

    conn = get_connection()
    cur = conn.cursor()

    if discount in (None, ""):
        cur.execute(
            "DELETE FROM app_settings WHERE key = 'fee_discount'"
        )
    else:
        cur.execute("""
            INSERT INTO app_settings(key, value) VALUES('fee_discount', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """, (str(discount),))

    conn.commit()
    conn.close()


def _fee_rate():

    discount = get_fee_discount()

    if discount is None:
        return RAW_FEE_RATE

    return RAW_FEE_RATE * (discount / 10)


def _tax_rate(asset_type):

    if (asset_type or "").upper() == "ETF":
        return ETF_TAX_RATE

    return STOCK_TAX_RATE


def get_dividends_received(code, since_date, shares):
    """
    這支股票從 since_date（持有起始時間）到現在，領到的現金股利
    總額——只算現金股利，不算股票股利（資料完整度太低、邏輯
    也複雜很多，這次先不做）。

    限制：股數用「現在的股數」概算，不是「當時實際持有的股數」，
    如果持有期間股數有變動，這個數字會有誤差。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT cash_dividend, ex_dividend_date FROM financials
        WHERE code = ? AND cash_dividend IS NOT NULL
          AND ex_dividend_date IS NOT NULL
          AND ex_dividend_date >= ?
          AND ex_dividend_date <= date('now')
    """, (code, since_date))

    rows = cur.fetchall()
    conn.close()

    total = 0.0
    count = 0

    for row in rows:
        total += row["cash_dividend"] * shares
        count += 1

    return {"dividend_total": round(total, 2), "dividend_count": count}


def calc_holding(shares, avg_price, current_price, asset_type,
                  code=None, since_date=None):
    """
    依照目前的手續費折扣設定，算出單一庫存的成本／市值／損益。
    有給 code/since_date 的話，額外算出這段期間領到的現金股利，
    併入「含息總報酬」。
    """

    fee_rate = _fee_rate()
    tax_rate = _tax_rate(asset_type)

    buy_fee = round(shares * avg_price * fee_rate)
    cost = shares * avg_price + buy_fee

    dividend_info = None
    if code and since_date:
        dividend_info = get_dividends_received(code, since_date, shares)

    if current_price is None:
        return {
            "cost": cost,
            "buy_fee": buy_fee,
            "market_value": None,
            "profit_loss": None,
            "profit_loss_pct": None,
            "sell_fee": None,
            "sell_tax": None,
            "dividend_total": dividend_info["dividend_total"] if dividend_info else None,
            "dividend_count": dividend_info["dividend_count"] if dividend_info else None,
            "total_return": None,
            "total_return_pct": None,
        }

    sell_fee = round(shares * current_price * fee_rate)
    sell_tax = round(shares * current_price * tax_rate)
    market_value = shares * current_price - sell_fee - sell_tax

    profit_loss = market_value - cost
    profit_loss_pct = (profit_loss / cost * 100) if cost else 0

    result = {
        "cost": cost,
        "buy_fee": buy_fee,
        "market_value": market_value,
        "profit_loss": profit_loss,
        "profit_loss_pct": profit_loss_pct,
        "sell_fee": sell_fee,
        "sell_tax": sell_tax,
    }

    if dividend_info:
        dividend_total = dividend_info["dividend_total"]
        total_return = profit_loss + dividend_total
        total_return_pct = (total_return / cost * 100) if cost else 0

        result["dividend_total"] = dividend_total
        result["dividend_count"] = dividend_info["dividend_count"]
        result["total_return"] = total_return
        result["total_return_pct"] = total_return_pct
    else:
        result["dividend_total"] = None
        result["dividend_count"] = None
        result["total_return"] = None
        result["total_return_pct"] = None

    return result


def list_holdings():
    """
    回傳所有庫存股，每筆都附上即時算好的成本／市值／損益。
    """

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT
            h.id, h.code, h.avg_price, h.shares, h.created_at,
            s.name AS company_name,
            s.asset_type,
            (
                SELECT p.close FROM prices p
                WHERE p.code = h.code
                ORDER BY p.date DESC
                LIMIT 1
            ) AS current_price
        FROM holdings h
        LEFT JOIN stocks s ON s.code = h.code
        ORDER BY h.created_at DESC
    """)

    rows = cur.fetchall()
    conn.close()

    result = []

    for row in rows:

        calc = calc_holding(
            row["shares"],
            row["avg_price"],
            row["current_price"],
            row["asset_type"],
            code=row["code"],
            since_date=row["created_at"],
        )

        result.append({
            "id": row["id"],
            "code": row["code"],
            "company_name": row["company_name"],
            "avg_price": row["avg_price"],
            "shares": row["shares"],
            "current_price": row["current_price"],
            **calc,
        })

    return result


def add_holding(code, avg_price, shares):

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        INSERT INTO holdings(code, avg_price, shares)
        VALUES(?, ?, ?)
    """, (code, avg_price, shares))

    conn.commit()
    new_id = cur.lastrowid
    conn.close()

    return new_id


def update_holding(holding_id, avg_price, shares):

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        UPDATE holdings
        SET avg_price = ?, shares = ?, updated_at = datetime('now')
        WHERE id = ?
    """, (avg_price, shares, holding_id))

    conn.commit()
    conn.close()


def delete_holding(holding_id):

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("DELETE FROM holdings WHERE id = ?", (holding_id,))

    conn.commit()
    conn.close()