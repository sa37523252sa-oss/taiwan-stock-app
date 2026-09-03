"""
自選股功能後端邏輯。

固定建立 5 個清單（自選股清單1~5），使用者可以各自改名，
一檔股票可以同時存在於多個清單裡。
"""

from database import get_connection

DEFAULT_LIST_COUNT = 5


def ensure_tables():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS watchlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS watchlist_stocks (
            watchlist_id INTEGER NOT NULL,
            code TEXT NOT NULL,
            added_at TEXT DEFAULT (datetime('now')),
            sort_order INTEGER,
            PRIMARY KEY (watchlist_id, code)
        )
    """)

    # 舊版沒有 sort_order 欄位，用 ALTER TABLE 補上（新資料庫
    # 因為上面 CREATE TABLE 已經有這欄，這裡會是 duplicate
    # column，直接忽略即可）
    try:
        cur.execute(
            "ALTER TABLE watchlist_stocks ADD COLUMN sort_order INTEGER"
        )
    except Exception as e:
        if "duplicate column name" not in str(e):
            raise

    # 第一次使用時，自動建立預設的 5 個清單
    cur.execute("SELECT COUNT(*) as cnt FROM watchlists")
    count = cur.fetchone()["cnt"]

    if count == 0:
        for i in range(1, DEFAULT_LIST_COUNT + 1):
            cur.execute(
                "INSERT INTO watchlists(name, sort_order) VALUES(?, ?)",
                (f"自選股清單{i}", i),
            )

    conn.commit()
    conn.close()


def list_watchlists():

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT w.id, w.name, w.sort_order,
               COUNT(ws.code) as stock_count
        FROM watchlists w
        LEFT JOIN watchlist_stocks ws ON ws.watchlist_id = w.id
        GROUP BY w.id
        ORDER BY w.sort_order
    """)

    rows = cur.fetchall()
    conn.close()

    return [dict(row) for row in rows]


def rename_watchlist(watchlist_id, name):

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "UPDATE watchlists SET name = ? WHERE id = ?",
        (name, watchlist_id),
    )

    conn.commit()
    conn.close()


def get_watchlist_stocks(watchlist_id):
    """
    回傳某個清單裡的股票，附上現價、漲跌、漲跌幅、總量
    （用 prices 表最新兩筆算出來，不是存在 stocks 表的固定欄位）。
    """

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT
            ws.code,
            ws.sort_order,
            s.name AS company_name,
            s.dividend_yield,
            (
                SELECT p.close FROM prices p
                WHERE p.code = ws.code
                ORDER BY p.date DESC
                LIMIT 1
            ) AS current_price,
            (
                SELECT p.close FROM prices p
                WHERE p.code = ws.code
                ORDER BY p.date DESC
                LIMIT 1 OFFSET 1
            ) AS prev_price,
            (
                SELECT p.volume FROM prices p
                WHERE p.code = ws.code
                ORDER BY p.date DESC
                LIMIT 1
            ) AS volume,
            (
                -- 本益比要跟股票主頁同一套算法：最近4季EPS加總，
                -- 不是讀 stocks.pe（那個是 FinMind 的舊資料，
                -- 跟主頁即時算出來的數字會對不上）。
                SELECT SUM(eps) FROM (
                    SELECT eps FROM financials
                    WHERE code = ws.code
                    ORDER BY year DESC, quarter DESC
                    LIMIT 4
                )
            ) AS eps_ttm
        FROM watchlist_stocks ws
        LEFT JOIN stocks s ON s.code = ws.code
        WHERE ws.watchlist_id = ?
        ORDER BY
            CASE WHEN ws.sort_order IS NULL THEN 1 ELSE 0 END,
            ws.sort_order ASC,
            ws.added_at DESC
    """, (watchlist_id,))

    rows = cur.fetchall()
    conn.close()

    result = []

    for row in rows:

        current = row["current_price"]
        prev = row["prev_price"]
        eps_ttm = row["eps_ttm"]

        change = None
        change_pct = None

        if current is not None and prev is not None and prev != 0:
            change = current - prev
            change_pct = change / prev * 100

        pe = None
        if current is not None and eps_ttm and eps_ttm > 0:
            pe = current / eps_ttm

        result.append({
            "code": row["code"],
            "company_name": row["company_name"],
            "current_price": current,
            "change": change,
            "change_pct": change_pct,
            "volume": row["volume"],
            "pe": pe,
            "dividend_yield": row["dividend_yield"],
        })

    return result


def add_stock(watchlist_id, code):

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order "
        "FROM watchlist_stocks WHERE watchlist_id = ?",
        (watchlist_id,),
    )
    next_order = cur.fetchone()["next_order"]

    cur.execute("""
        INSERT OR IGNORE INTO watchlist_stocks(watchlist_id, code, sort_order)
        VALUES(?, ?, ?)
    """, (watchlist_id, code, next_order))

    conn.commit()
    conn.close()


def reorder_stocks(watchlist_id, ordered_codes):
    """
    使用者在編輯模式拖曳排序後，依照新的順序（一個代號清單）
    整批更新 sort_order。
    """

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    for index, code in enumerate(ordered_codes):
        cur.execute("""
            UPDATE watchlist_stocks
            SET sort_order = ?
            WHERE watchlist_id = ? AND code = ?
        """, (index, watchlist_id, code))

    conn.commit()
    conn.close()


def remove_stock(watchlist_id, code):

    ensure_tables()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        DELETE FROM watchlist_stocks
        WHERE watchlist_id = ? AND code = ?
    """, (watchlist_id, code))

    conn.commit()
    conn.close()