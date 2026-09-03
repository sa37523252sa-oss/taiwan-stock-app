import sqlite3
import os


BASE_DIR = os.path.dirname(
    os.path.abspath(__file__)
)


DATABASE = os.getenv(
    "DB_PATH",
    os.path.join(BASE_DIR, "stocks.db")
)



def get_connection():

    conn = sqlite3.connect(DATABASE)

    conn.row_factory = sqlite3.Row

    return conn





def create_table():

    conn = get_connection()

    cursor = conn.cursor()



    # 股票基本資料
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS stocks (

        code TEXT PRIMARY KEY,

        name TEXT NOT NULL,

        industry TEXT

    )
    """)



    # 歷史股價資料
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS prices (

    id INTEGER PRIMARY KEY AUTOINCREMENT,

    code TEXT,

    date TEXT,

    open REAL,

    high REAL,

    low REAL,

    close REAL,

    volume INTEGER,


    FOREIGN KEY(code)
    REFERENCES stocks(code)

)
""") 



    # 財報資料
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS financials (

        id INTEGER PRIMARY KEY AUTOINCREMENT,

        code TEXT,

        year INTEGER,

        quarter INTEGER,

        revenue REAL,

        eps REAL,

        roe REAL,

        pe REAL,

        pb REAL,

        dividend_yield REAL,

        cash_dividend REAL,
        stock_dividend REAL,

        ex_dividend_date TEXT,
        cash_dividend_date TEXT,
        stock_dividend_date TEXT,

        FOREIGN KEY(code)
        REFERENCES stocks(code)

    )
    """)



    # 舊版資料庫升級
    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN pe REAL")
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN pb REAL")
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN dividend_yield REAL")
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN cash_dividend REAL")
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN stock_dividend REAL")
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN ex_dividend_date TEXT")
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN cash_dividend_date TEXT")
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE financials ADD COLUMN stock_dividend_date TEXT")
    except Exception:
        pass

    conn.commit()

    conn.close()






# 新增股票

def insert_stock(

    code,

    name,

    industry

):

    conn = get_connection()

    cursor = conn.cursor()



    cursor.execute(
        """
        INSERT OR REPLACE INTO stocks
        (
            code,
            name,
            industry
        )

        VALUES (?, ?, ?)
        """,

        (
            code,
            name,
            industry
        )

    )


    conn.commit()

    conn.close()







# 新增股價

def insert_price(

    code,

    date,

    open_price,

    high,

    low,

    close,

    volume

):

    conn = get_connection()

    cursor = conn.cursor()



    cursor.execute(
        """
        INSERT INTO prices
        (
            code,
            date,
            open,
            high,
            low,
            close,
            volume
        )

        VALUES (?, ?, ?, ?, ?, ?, ?)

        ON CONFLICT(code, date)

        DO UPDATE SET

            open = excluded.open,

            high = excluded.high,

            low = excluded.low,

            close = excluded.close,

            volume = excluded.volume

        """,
        (
            code,
            date,
            open_price,
            high,
            low,
            close,
            volume,
        )
    )


    conn.commit()

    conn.close()







# 新增財報

def insert_financial(

    code,

    year,

    quarter,

    revenue,

    eps,

    roe

):

    conn = get_connection()

    cursor = conn.cursor()



    cursor.execute(
        """
        INSERT INTO financials
        (
            code,
            year,
            quarter,
            revenue,
            eps,
            roe
        )

        VALUES (?, ?, ?, ?, ?, ?)

        """,

        (
            code,
            year,
            quarter,
            revenue,
            eps,
            roe
        )

    )


    conn.commit()

    conn.close()







# 查單一股票

def get_stock(code):

    conn = get_connection()

    cursor = conn.cursor()


    cursor.execute(
        """
        SELECT *
        FROM stocks
        WHERE code=?
        """,
        (code,)
    )


    stock = cursor.fetchone()

    conn.close()


    return stock







# 查歷史股價

def get_prices(code):

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


    data = cursor.fetchall()

    conn.close()


    return data
