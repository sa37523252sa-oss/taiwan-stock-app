"""
把資料庫結構補到「程式實際需要的樣子」。

跟 database.create_table() 不同的地方：這支會先看目前實際長怎樣，
再補差異。所以在舊資料庫上跑會補欄位、補索引，在空目錄跑會建出
完整的表，兩邊結果一致。

可以重複執行，不會壞事。執行前先備份 stocks.db。
"""

from database import get_connection


# ==========================================================
# 各表應該要有的欄位
# ==========================================================

PRICES_COLUMNS = {
    "code": "TEXT",
    "date": "TEXT",
    "open": "REAL",
    "high": "REAL",
    "low": "REAL",
    "close": "REAL",
    "volume": "INTEGER",
}

FINANCIALS_COLUMNS = {
    "code": "TEXT",
    "year": "INTEGER",
    "quarter": "INTEGER",

    "revenue": "REAL",
    "gross_profit": "REAL",
    "operating_profit": "REAL",
    "pretax_profit": "REAL",
    "net_income": "REAL",
    "eps": "REAL",

    "roe": "REAL",
    "roa": "REAL",

    "gross_margin": "REAL",
    "operating_margin": "REAL",
    "net_margin": "REAL",

    "book_value": "REAL",

    "assets": "REAL",
    "liabilities": "REAL",
    "equity": "REAL",

    "debt_ratio": "REAL",
    "current_ratio": "REAL",
    "quick_ratio": "REAL",

    "operating_cash_flow": "REAL",
    "investing_cash_flow": "REAL",
    "financing_cash_flow": "REAL",
    "free_cash_flow": "REAL",

    "pe": "REAL",
    "pb": "REAL",
    "dividend_yield": "REAL",

    "cash_dividend": "REAL",
    "stock_dividend": "REAL",

    "ex_dividend_date": "TEXT",
    "cash_dividend_date": "TEXT",
    "stock_dividend_date": "TEXT",

    "updated_at": "TEXT",
}

# 公司行動。刻意不叫 dividends 或 splits——台股的股票股利、
# 股票分割、減資在數學上是不同的東西，但都能用「每股配發現金」
# 加「股數乘數」兩個數字描述：
#
#     參考價 = (前日收盤 − cash_per_share) / share_ratio
#
# 下游回測只吃這兩欄，不必知道事件類型；action_type 保留給
# 顯示和稽核用。
CORPORATE_ACTIONS_COLUMNS = {
    "code": "TEXT",
    "ex_date": "TEXT",           # 除權息交易日
    "action_type": "TEXT",       # CASH / STOCK_DIVIDEND / SPLIT / REDUCTION
    "cash_per_share": "REAL",    # 每股發放或退還的現金
    "share_ratio": "REAL",       # 股數乘數：1=不變, 2=一股變兩股, 0.8=減資
    "raw_value": "REAL",         # 原始欄位值，方便回查
    "pay_date": "TEXT",
    "source": "TEXT",            # finmind / manual
    "updated_at": "TEXT",
}

MONTHLY_REVENUE_COLUMNS = {
    "code": "TEXT",
    "year": "INTEGER",
    "month": "INTEGER",
    "revenue": "REAL",
    "mom": "REAL",
    "yoy": "REAL",
    "updated_at": "TEXT",
}


# ==========================================================
# 工具
# ==========================================================

def table_exists(cur, table):

    cur.execute("""
        SELECT name FROM sqlite_master
        WHERE type='table' AND name=?
    """, (table,))

    return cur.fetchone() is not None


def existing_columns(cur, table):

    cur.execute(f"PRAGMA table_info({table})")

    return {r["name"] for r in cur.fetchall()}


def add_missing_columns(cur, table, wanted):

    have = existing_columns(cur, table)

    added = []

    for name, sql_type in wanted.items():

        if name in have:
            continue

        cur.execute(f"ALTER TABLE {table} ADD COLUMN {name} {sql_type}")

        added.append(name)

    return added


def has_duplicates(cur, table, cols):

    key = ", ".join(cols)

    cur.execute(f"""
        SELECT COUNT(*) AS n FROM (
            SELECT {key} FROM {table}
            GROUP BY {key} HAVING COUNT(*) > 1
        )
    """)

    return cur.fetchone()["n"]


def index_covers(cur, table, cols):
    """這張表已經有涵蓋同樣欄位組合的唯一索引了嗎"""

    cur.execute("""
        SELECT name FROM sqlite_master
        WHERE type='index' AND tbl_name=? AND sql LIKE '%UNIQUE%'
    """, (table,))

    for r in cur.fetchall():

        cur.execute(f"PRAGMA index_info({r['name']})")

        have = [c["name"] for c in cur.fetchall()]

        if have == list(cols):
            return r["name"]

    return None


def create_unique_index(cur, name, table, cols):
    """
    有重複資料的話 CREATE UNIQUE INDEX 會失敗，先檢查並回報，
    不要讓它直接炸掉整支 migration。
    已經有等價索引就不重複建，避免白白拖慢寫入。
    """

    existing = index_covers(cur, table, cols)

    if existing:
        print(f"  {table} 已有等價唯一索引 {existing}，略過")
        return True

    dup = has_duplicates(cur, table, cols)

    if dup:
        print(f"  !! {table} 有 {dup} 組重複的 {cols}，無法建立唯一索引")
        print(f"     先清理：DELETE FROM {table} WHERE id NOT IN ("
              f"SELECT MIN(id) FROM {table} GROUP BY {', '.join(cols)});")
        return False

    cur.execute(f"""
        CREATE UNIQUE INDEX IF NOT EXISTS {name}
        ON {table}({', '.join(cols)})
    """)

    return True


# ==========================================================
# 主流程
# ==========================================================

def ensure_schema():

    conn = get_connection()
    cur = conn.cursor()

    print("===== 檢查資料庫結構 =====")

    # ---------- stocks ----------
    cur.execute("""
        CREATE TABLE IF NOT EXISTS stocks (
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            industry TEXT
        )
    """)

    added = add_missing_columns(cur, "stocks", {
        "pe": "REAL",
        "pb": "REAL",
        "dividend_yield": "REAL",
        "track_financials": "INTEGER DEFAULT 1",
    })

    if added:
        print("stocks 補欄位:", added)

    # ---------- prices ----------
    if not table_exists(cur, "prices"):
        cur.execute("""
            CREATE TABLE prices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT,
                date TEXT,
                open REAL,
                high REAL,
                low REAL,
                close REAL,
                volume INTEGER,
                FOREIGN KEY(code) REFERENCES stocks(code)
            )
        """)
        print("prices 建立")

    added = add_missing_columns(cur, "prices", PRICES_COLUMNS)
    if added:
        print("prices 補欄位:", added)

    create_unique_index(cur, "idx_prices_code_date", "prices", ["code", "date"])

    cur.execute("""
        CREATE INDEX IF NOT EXISTS idx_prices_date ON prices(date)
    """)

    # ---------- financials ----------
    if not table_exists(cur, "financials"):
        cur.execute("""
            CREATE TABLE financials (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT,
                year INTEGER,
                quarter INTEGER,
                FOREIGN KEY(code) REFERENCES stocks(code)
            )
        """)
        print("financials 建立")

    added = add_missing_columns(cur, "financials", FINANCIALS_COLUMNS)
    if added:
        print("financials 補欄位:", added)

    create_unique_index(
        cur, "idx_financials_code_yq",
        "financials", ["code", "year", "quarter"],
    )

    # ---------- monthly_revenue ----------
    if not table_exists(cur, "monthly_revenue"):
        cur.execute("""
            CREATE TABLE monthly_revenue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT,
                year INTEGER,
                month INTEGER,
                FOREIGN KEY(code) REFERENCES stocks(code)
            )
        """)
        print("monthly_revenue 建立")

    added = add_missing_columns(
        cur, "monthly_revenue", MONTHLY_REVENUE_COLUMNS
    )
    if added:
        print("monthly_revenue 補欄位:", added)

    create_unique_index(
        cur, "idx_monthly_revenue_code_ym",
        "monthly_revenue", ["code", "year", "month"],
    )

    # ---------- corporate_actions ----------
    if not table_exists(cur, "corporate_actions"):
        cur.execute("""
            CREATE TABLE corporate_actions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT,
                ex_date TEXT,
                action_type TEXT,
                FOREIGN KEY(code) REFERENCES stocks(code)
            )
        """)
        print("corporate_actions 建立")

    added = add_missing_columns(
        cur, "corporate_actions", CORPORATE_ACTIONS_COLUMNS
    )
    if added:
        print("corporate_actions 補欄位:", added)

    create_unique_index(
        cur, "idx_ca_code_date_type",
        "corporate_actions", ["code", "ex_date", "action_type"],
    )

    # ---------- fetch_log ----------
    cur.execute("""
        CREATE TABLE IF NOT EXISTS fetch_log (
            code     TEXT,
            dataset  TEXT,
            last_try TEXT,
            has_data INTEGER,
            PRIMARY KEY (code, dataset)
        )
    """)

    conn.commit()
    conn.close()

    print("===== 完成 =====")


def report():
    """跑完看一下每張表的現況"""

    conn = get_connection()
    cur = conn.cursor()

    for table in ("stocks", "prices", "financials",
                  "monthly_revenue", "corporate_actions", "fetch_log"):

        if not table_exists(cur, table):
            print(f"{table:18} 不存在")
            continue

        cur.execute(f"SELECT COUNT(*) AS n FROM {table}")
        n = cur.fetchone()["n"]

        cols = len(existing_columns(cur, table))

        print(f"{table:18} {n:>10} 列  {cols:>3} 欄")

    print()

    cur.execute("""
        SELECT name, tbl_name FROM sqlite_master
        WHERE type='index' AND name NOT LIKE 'sqlite_%'
        ORDER BY tbl_name, name
    """)

    for r in cur.fetchall():
        print(f"index  {r['tbl_name']:18} {r['name']}")

    conn.close()


if __name__ == "__main__":
    ensure_schema()
    print()
    report()