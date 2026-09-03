"""
下載前的判斷邏輯：決定「這檔股票這次到底要不要打 API」。

核心想法是用日曆推算「現在應該已經公告到哪一期」，跟 DB 裡
已經存到哪一期比對。相等就不用下載。

另外用 fetch_log 記錄「查過但確實沒有資料」的標的（ETF、沒有
財報的公司），避免每次跑全市場都對它們白打一次 API。
"""

from datetime import date, datetime, timedelta

from database import get_connection


class QuotaReached(Exception):
    """FinMind 回 402，本小時額度用完"""
    pass


# ==========================================================
# 額度熔斷
# ==========================================================
# 撞到 402 之後，接下來一段時間內所有請求直接走 DB，不再戳
# FinMind。否則額度滿的期間每個網頁請求都會再打一次，把下一
# 小時的配額也預支掉。

_blocked_until = None


def quota_blocked():
    return _blocked_until is not None and datetime.now() < _blocked_until


def block_quota(minutes=60):
    global _blocked_until
    _blocked_until = datetime.now() + timedelta(minutes=minutes)
    print(f"[quota] 額度用完，{minutes} 分鐘內不再嘗試")


def clear_quota_block():
    global _blocked_until
    _blocked_until = None


def safe_update(fn, *args, **kwargs):
    """
    在網頁請求裡呼叫更新函式時用這個包起來。
    更新失敗不該讓整個端點回 500——資料庫裡本來就有資料，
    先把舊的顯示出來比整頁掛掉好。

    回傳 True 表示更新成功，False 表示這次沒更新到。
    """

    if quota_blocked():
        return False

    try:
        fn(*args, **kwargs)
        return True

    except QuotaReached:
        return False

    except Exception as e:

        msg = str(e)

        if "402" in msg or "upper limit" in msg:
            block_quota()
        else:
            print(f"[update] {fn.__name__} 失敗:", msg[:200])

        return False


# ==========================================================
# 期別推算
# ==========================================================

def get_publish_date(year, quarter):
    """推估上市公司財報公告日，回傳 yyyy-mm-dd"""

    if quarter == 1:
        return date(year, 5, 15).isoformat()
    elif quarter == 2:
        return date(year, 8, 14).isoformat()
    elif quarter == 3:
        return date(year, 11, 14).isoformat()
    else:
        return date(year + 1, 3, 15).isoformat()


def latest_published_quarter(today=None):
    """今天為止，最新一季「應該」已經公告的財報是哪一季"""

    today = (today or date.today()).isoformat()
    y = int(today[:4])

    for cy, cq in ((y, 3), (y, 2), (y, 1), (y - 1, 4), (y - 1, 3)):
        if get_publish_date(cy, cq) <= today:
            return (cy, cq)

    return (y - 1, 3)


def latest_published_month(today=None):
    """
    月營收每月 10 號公告上個月。10 號前跑就只能拿到上上個月。
    回傳 (year, month)
    """

    today = today or date.today()

    y, m = today.year, today.month
    back = 1 if today.day >= 10 else 2

    for _ in range(back):
        m -= 1
        if m == 0:
            y, m = y - 1, 12

    return (y, m)


def last_trading_day(now=None):
    """
    最近一個「收盤價應該已經產出」的日子。
    下午 3 點前執行的話當天還沒收盤，往回退一天。
    國定假日抓不到，但那天本來就沒有新資料。
    """

    now = now or datetime.now()

    d = now.date()

    if now.hour < 15:
        d -= timedelta(days=1)

    while d.weekday() >= 5:
        d -= timedelta(days=1)

    return d.isoformat()


# ==========================================================
# fetch_log：記錄「查過但沒資料」
# ==========================================================

def ensure_fetch_log():

    conn = get_connection()
    cur = conn.cursor()

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


def mark_fetch(code, dataset, has_data):
    """
    只在「API 正常回應」之後才呼叫。網路失敗、逾時不要寫，
    否則會把一檔正常的股票錯誤冷凍住。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        INSERT INTO fetch_log(code, dataset, last_try, has_data)
        VALUES(?, ?, ?, ?)
        ON CONFLICT(code, dataset)
        DO UPDATE SET
            last_try = excluded.last_try,
            has_data = excluded.has_data
    """, (code, dataset, date.today().isoformat(), 1 if has_data else 0))

    conn.commit()
    conn.close()


def recently_empty(code, dataset, days=30):
    """最近 days 天內查過、而且確定沒資料 → True"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT last_try FROM fetch_log
        WHERE code=? AND dataset=? AND has_data=0
    """, (code, dataset))

    row = cur.fetchone()

    conn.close()

    if not row or not row["last_try"]:
        return False

    cutoff = (date.today() - timedelta(days=days)).isoformat()

    return row["last_try"] > cutoff


# ==========================================================
# DB 現況查詢
# ==========================================================

def latest_quarter_in_db(code):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT year, quarter FROM financials
        WHERE code=?
          AND (eps IS NOT NULL
               OR revenue IS NOT NULL
               OR net_income IS NOT NULL)
        ORDER BY year DESC, quarter DESC
        LIMIT 1
    """, (code,))

    row = cur.fetchone()

    conn.close()

    return (row["year"], row["quarter"]) if row else None


def latest_month_in_db(code):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT year, month FROM monthly_revenue
        WHERE code=? AND revenue IS NOT NULL
        ORDER BY year DESC, month DESC
        LIMIT 1
    """, (code,))

    row = cur.fetchone()

    conn.close()

    return (row["year"], row["month"]) if row else None


def latest_price_in_db(code):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT MAX(date) AS d FROM prices WHERE code=?
    """, (code,))

    row = cur.fetchone()

    conn.close()

    return row["d"] if row and row["d"] else None


# ==========================================================
# 對外的三個判斷
# ==========================================================

def needs_financials(code):

    if recently_empty(code, "financials"):
        return False

    latest = latest_quarter_in_db(code)

    if latest is None:
        return True

    return latest < latest_published_quarter()


def needs_month_revenue(code):

    if recently_empty(code, "month_revenue"):
        return False

    latest = latest_month_in_db(code)

    if latest is None:
        return True

    return latest < latest_published_month()


def needs_price(code):

    latest = latest_price_in_db(code)

    if latest is None:
        return True

    return latest < last_trading_day()


# ==========================================================
# 診斷用：找出中間缺掉的期別
# ==========================================================

def quarter_range(start, end):

    y, q = start

    while (y, q) <= end:
        yield (y, q)
        y, q = (y + 1, 1) if q == 4 else (y, q + 1)


def financial_gaps(code):
    """
    回傳「最早一季到最新已公告一季之間」缺掉的季別。
    這是給你事後檢查用的，不拿來當下載的判斷條件——
    有些公司中間本來就真的沒資料，拿它當條件會永遠判定要下載。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT year, quarter FROM financials
        WHERE code=?
          AND (eps IS NOT NULL
               OR revenue IS NOT NULL
               OR net_income IS NOT NULL)
    """, (code,))

    have = {(r["year"], r["quarter"]) for r in cur.fetchall()}

    conn.close()

    if not have:
        return []

    want = set(quarter_range(min(have), latest_published_quarter()))

    return sorted(want - have)


# ==========================================================
# 工作佇列：決定「這次要跑哪些股票、依什麼順序」
# ==========================================================

def price_queue(limit=None, cooldown_days=30, as_of=None):
    """
    回傳這次該更新股價的股票代號。

    三件事一次做完：
      1. 已經更新到最近交易日的 → 排除
      2. 近期查過確定沒資料的 → 排除（cooldown_days 內）
      3. 剩下的按「最久沒被嘗試過」排序，沒試過的排最前面

    第 3 點是重點：不再用 ORDER BY code，否則額度永遠被
    前面幾百檔吃光，後面的輪不到。
    """

    cutoff = (date.today() - timedelta(days=cooldown_days)).isoformat()

    sql = """
        SELECT s.code
        FROM stocks s
        LEFT JOIN (
            SELECT code, MAX(date) AS d FROM prices GROUP BY code
        ) p ON p.code = s.code
        LEFT JOIN fetch_log f
            ON f.code = s.code AND f.dataset = 'price'
        WHERE (p.d IS NULL OR p.d < ?)
          AND (f.has_data IS NULL OR f.has_data = 1 OR f.last_try <= ?)
        ORDER BY
            (p.d IS NOT NULL),        -- 完全沒有資料的排最前面（回補優先）
            (f.last_try IS NOT NULL), -- 再來是從沒嘗試過的
            f.last_try,               -- 再來是最久沒嘗試的
            p.d,                      -- 再來是資料最舊的
            s.code
    """

    params = [as_of or last_trading_day(), cutoff]

    if limit:
        sql += " LIMIT ?"
        params.append(limit)

    conn = get_connection()
    cur = conn.cursor()
    cur.execute(sql, params)

    codes = [r["code"] for r in cur.fetchall()]

    conn.close()

    return codes


def financial_queue(limit=None, cooldown_days=30):
    """
    財報版本。判斷條件是「DB 最新一季 < 現在應該公告到的那一季」，
    排序邏輯跟 price_queue 一樣。
    """

    y, q = latest_published_quarter()

    cutoff = (date.today() - timedelta(days=cooldown_days)).isoformat()

    sql = """
        SELECT s.code
        FROM stocks s
        LEFT JOIN (
            SELECT code, MAX(year * 10 + quarter) AS yq
            FROM financials
            WHERE eps IS NOT NULL
               OR revenue IS NOT NULL
               OR net_income IS NOT NULL
            GROUP BY code
        ) fin ON fin.code = s.code
        LEFT JOIN fetch_log f
            ON f.code = s.code AND f.dataset = 'financials'
        WHERE COALESCE(s.track_financials, 1) = 1
          AND (fin.yq IS NULL OR fin.yq < ?)
          AND (f.has_data IS NULL OR f.has_data = 1 OR f.last_try <= ?)
        ORDER BY
            (fin.yq IS NOT NULL),
            (f.last_try IS NOT NULL),
            f.last_try,
            fin.yq,
            s.code
    """

    params = [y * 10 + q, cutoff]

    if limit:
        sql += " LIMIT ?"
        params.append(limit)

    conn = get_connection()
    cur = conn.cursor()
    cur.execute(sql, params)

    codes = [r["code"] for r in cur.fetchall()]

    conn.close()

    return codes


def queue_summary(dataset):
    """跑之前先看還剩多少檔沒處理完"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) AS n FROM stocks")
    total = cur.fetchone()["n"]

    cur.execute("""
        SELECT COUNT(*) AS n FROM fetch_log
        WHERE dataset=? AND has_data=0
    """, (dataset,))
    empty = cur.fetchone()["n"]

    conn.close()

    return total, empty