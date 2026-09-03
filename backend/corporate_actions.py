"""
公司行動與還原股價。所有回測都應該經過這裡拿價格，不要直接讀 prices 表，
否則除權當天會看到斷崖式下跌，均線交叉、回撤、報酬率全部失真。

三種序列，用途不同，不要混用：

  RAW    未還原。顯示用（使用者看到的成交價、均價比對券商對帳單）
  PRICE  只還原股數變動（除權、分割、減資），不還原現金股利。
         技術指標、K 線、股數連續性用這條。
  TOTAL  連現金股利一起還原（等同股利再投入）。
         比較長期報酬率、跟大盤對照用這條。

統一的除權息參考價公式，四種公司行動都適用：

    參考價 = (前日收盤 − cash_per_share) / share_ratio

還原係數就是「參考價 / 前日收盤」，往前累乘。
"""

from database import get_connection

RAW = "raw"
PRICE = "price"
TOTAL = "total"


def get_actions(code, start_date=None, end_date=None):
    """回傳這支股票的公司行動，依除權息日排序"""

    sql = """
        SELECT ex_date, action_type, cash_per_share, share_ratio
        FROM corporate_actions
        WHERE code = ?
    """
    params = [code]

    if start_date:
        sql += " AND ex_date >= ?"
        params.append(start_date)

    if end_date:
        sql += " AND ex_date <= ?"
        params.append(end_date)

    sql += " ORDER BY ex_date ASC"

    conn = get_connection()
    cur = conn.cursor()
    cur.execute(sql, params)
    rows = cur.fetchall()
    conn.close()

    return [
        {
            "ex_date": r["ex_date"],
            "action_type": r["action_type"],
            "cash": r["cash_per_share"] or 0.0,
            "ratio": r["share_ratio"] if r["share_ratio"] else 1.0,
        }
        for r in rows
    ]


def merge_same_day(actions):
    """
    同一天可能同時除權又除息（台股很常見）。合併成單一事件：
    現金相加、股數乘數相乘。
    """

    merged = {}

    for a in actions:

        m = merged.setdefault(
            a["ex_date"],
            {"ex_date": a["ex_date"], "cash": 0.0, "ratio": 1.0, "types": []},
        )

        m["cash"] += a["cash"]
        m["ratio"] *= a["ratio"]
        m["types"].append(a["action_type"])

    return [merged[k] for k in sorted(merged)]


def build_factors(history, actions, mode=TOTAL):
    """
    算出每一天的還原係數（要乘在原始收盤價上）。

    history : 由舊到新的 [{date, close}, ...]
    回傳    : {date: factor}

    係數是「往回」累乘的：最新一天永遠是 1.0，愈早的價格被壓得
    愈低。這樣最新價維持等於真實市價，使用者看到的數字才對得上。
    """

    if mode == RAW or not actions:
        return {b["date"]: 1.0 for b in history}

    events = merge_same_day(actions)

    close_by_date = {b["date"]: b["close"] for b in history}
    dates = [b["date"] for b in history]

    # 每個事件的單次係數
    per_event = []

    for ev in events:

        # 找除權息日前一個交易日的收盤價
        prev_close = None

        for i, d in enumerate(dates):
            if d >= ev["ex_date"]:
                if i > 0:
                    prev_close = close_by_date[dates[i - 1]]
                break

        if prev_close is None or prev_close <= 0:
            continue

        cash = ev["cash"] if mode == TOTAL else 0.0
        ratio = ev["ratio"] if ev["ratio"] else 1.0

        ref = (prev_close - cash) / ratio

        if ref <= 0:
            continue

        per_event.append((ev["ex_date"], ref / prev_close))

    if not per_event:
        return {d: 1.0 for d in dates}

    # 由新到舊累乘：某一天的係數 = 它之後所有事件的係數乘積
    factors = {}
    running = 1.0
    idx = len(per_event) - 1

    for d in reversed(dates):

        while idx >= 0 and per_event[idx][0] > d:
            running *= per_event[idx][1]
            idx -= 1

        factors[d] = running

    return factors


def adjust_history(history, actions, mode=TOTAL):
    """
    把原始日線套上還原係數，回傳新的 list（不改原物件）。

    成交量也要一起調整，方向相反：1 股拆 4 股之後，當年成交的
    1000 股相當於今天的 4000 股。價格乘以 f，張數就要除以 f，
    這樣「價 × 量」才會維持等於真實成交金額，均量條件在除權日
    前後才不會出現假訊號。

    量的調整只看股數變動（PRICE 係數），現金股利不影響股數。
    """

    factors = build_factors(history, actions, mode)

    vol_factors = (
        factors if mode == PRICE
        else build_factors(history, actions, PRICE)
    )

    out = []

    for b in history:

        f = factors.get(b["date"], 1.0)
        vf = vol_factors.get(b["date"], 1.0)

        row = dict(b)
        row["raw_close"] = b["close"]
        row["factor"] = f

        for field in ("close", "high", "low", "open"):
            if row.get(field) is not None:
                row[field] = row[field] * f

        if row.get("volume") and vf > 0:
            row["volume"] = row["volume"] / vf

        out.append(row)

    return out


def get_adjusted_history(code, start_date, end_date, mode=TOTAL):
    """
    回測的統一入口。注意公司行動要抓「整段歷史」而不是只抓區間內
    ——區間外的事件不影響區間內的相對關係，但抓錯會讓係數對不上。
    """

    from backtest import get_price_history

    history = get_price_history(code, start_date, end_date)

    if not history:
        return []

    actions = get_actions(code, start_date, end_date)

    return adjust_history(history, actions, mode)


def share_multiplier_events(code, start_date, end_date):
    """
    給事件驅動的模擬用（例如定期定額）：只回傳會改變股數的事件。
    {除權日: 股數乘數}

    這條路徑跟還原股價是兩種等價的做法：
      A. 用還原價 + 固定股數
      B. 用原始價 + 事件當天調整股數
    兩者算出來的總報酬必須一致，detect_gaps.py 的 selftest 會驗證。
    """

    events = merge_same_day(get_actions(code, start_date, end_date))

    return {
        e["ex_date"]: e["ratio"]
        for e in events
        if e["ratio"] and abs(e["ratio"] - 1.0) > 1e-9
    }


def cash_events(code, start_date, end_date):
    """{除息日: 每股現金}"""

    events = merge_same_day(get_actions(code, start_date, end_date))

    return {e["ex_date"]: e["cash"] for e in events if e["cash"]}