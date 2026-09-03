import re
import time
from collections import defaultdict
from datetime import date, timedelta

from database import get_connection
from finmind import request_dataset
from finmind import get_historical_valuation

from fetch_cache import (
    ensure_fetch_log,
    financial_gaps,
    financial_queue,
    get_publish_date,
    block_quota,
    mark_fetch,
    needs_financials,
    needs_month_revenue,
    QuotaReached,
)

# 免費會員每小時 600 次；財報每檔要 6 次，所以一次只跑 90 檔
HOURLY_LIMIT = 90

DEBUG = False

KNOWN = {
    # ===== 損益表 =====
    "Revenue", "OperatingRevenue",

    "GrossProfit", "GrossProfitFromOperations", "OperatingGrossProfit",

    "OperatingIncome", "OperatingIncomeLoss", "ProfitFromOperations",

    "IncomeBeforeIncomeTax", "IncomeBeforeTax",
    "IncomeBeforeTaxFromContinuingOperations",
    "IncomeBeforeIncomeTaxFromContinuingOperations",

    "IncomeAfterTax", "IncomeAfterTaxes", "NetIncome",
    "IncomeAfterTaxFromContinuingOperations",

    "EPS",

    # ===== 獲利能力 =====
    "BookValue", "ROE", "ROA",

    # ===== 資產負債表 =====
    "Assets", "TotalAssets",

    "Liabilities", "TotalLiabilities",

    "Equity", "EquityAttributableToOwnersOfParent",

    "CurrentAssets", "CurrentLiabilities",

    "Inventories",

    # ===== 現金流 =====
    "CashFlowsFromOperatingActivities", "NetCashInflowFromOperatingActivities",

    "CashProvidedByInvestingActivities",

    "CashFlowsProvidedFromFinancingActivities",

    # ===== 資本支出 =====
    "PropertyPlantAndEquipment",

    # ===== 補算用 =====
    "CostOfGoodsSold",
    "OperatingExpenses",
}


def pick(row, *names):

    for name in names:

        value = row.get(name)

        if value is not None:
            return value

    return None


def get_all_stocks():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT code
        FROM stocks
        ORDER BY code
    """)

    rows = [r["code"] for r in cur.fetchall()]

    conn.close()

    return rows


def get_month_revenue(code):
    try:
        return request_dataset(
            "TaiwanStockMonthRevenue",
            code,
        )
    except Exception:
        return []




def get_valuation(code):
    return request_dataset(
        "TaiwanStockPER",
        code,
    )


def get_dividend(code):
    return request_dataset(
        "TaiwanStockDividend",
        code,
    )


def _dividend_base_date(d):
    """
    這筆股利記錄的基準日期：優先用除息日（現金股利跟股票股利
    的除息日可能不同，現金殖利率算法用現金那個），沒有的話退
    而求其次用公告日/原始日期，避免整筆被跳過。
    """
    return (
        d.get("CashExDividendTradingDate")
        or d.get("StockExDividendTradingDate")
        or d.get("AnnouncementDate")
        or d.get("date")
    )


def trailing_12m_cash_dividend(dividend_rows, as_of_date):
    """
    殖利率不該用「單一次配息 ÷ 股價」算，因為每支股票配息次數
    不一樣（有些一年配1次、有些季配4次）。改用移動視窗：以
    as_of_date 為基準，往回 365 天內所有實際發生過的現金股利
    加總起來——不用事先知道這支股票是年配、半年配還是季配，
    看「過去一年實際配了幾次、配了多少」，自動就會算對。

    Parameters
    ----------
    dividend_rows : get_dividend() 回傳的原始股利清單
    as_of_date : "yyyy-mm-dd" 字串，基準日期

    Returns
    -------
    float：往回12個月的現金股利加總（沒有任何配息記錄則為 0）
    """

    try:
        as_of = date.fromisoformat(as_of_date[:10])
    except (ValueError, TypeError):
        return 0.0

    one_year_ago = as_of - timedelta(days=365)

    total = 0.0

    for d in dividend_rows:

        cash = d.get("CashEarningsDistribution")

        if not cash:
            continue

        base_date_str = _dividend_base_date(d)

        if not base_date_str:
            continue

        try:
            base_date = date.fromisoformat(base_date_str[:10])
        except (ValueError, TypeError):
            continue

        if one_year_ago < base_date <= as_of:
            total += cash

    return total


def get_price_on_or_before(code, as_of_date):
    """
    查某個日期「當天或之前最近一個交易日」的收盤價，用來跟
    trailing_12m_cash_dividend 的結果一起算殖利率。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT close FROM prices
        WHERE code = ? AND date <= ?
        ORDER BY date DESC
        LIMIT 1
    """, (code, as_of_date))

    row = cur.fetchone()

    conn.close()

    return row["close"] if row else None


def calculate_dividend_yield(code, dividend_rows, as_of_date):
    """
    殖利率 = 往回12個月現金股利加總 ÷ as_of_date 當時（或之前
    最近一個交易日）的股價 × 100。沒有股價或配息資料就回傳 None，
    不要硬算出一個誤導的數字。
    """

    price = get_price_on_or_before(code, as_of_date)

    if price is None or price == 0:
        return None

    trailing_dividend = trailing_12m_cash_dividend(
        dividend_rows, as_of_date
    )

    if trailing_dividend == 0:
        return None

    return trailing_dividend / price * 100


def get_financial_data(code):

    income = request_dataset(
        "TaiwanStockFinancialStatements",
        code,
    )

    try:
        balance = request_dataset(
            "TaiwanStockBalanceSheet",
            code,
        )
    except Exception:
        balance = []

    try:
        cash = request_dataset(
            "TaiwanStockCashFlowsStatement",
            code,
        )
    except Exception:
        cash = []

    return income + balance + cash


def quarter_from_date(d):

    month = int(d[5:7])

    if month <= 3:
        return 1
    elif month <= 6:
        return 2
    elif month <= 9:
        return 3
    else:
        return 4


def get_dividend_year_quarter(d):
    """
    這筆股利「屬於哪一季財報盈餘」的標籤。

    優先解析 FinMind 原始資料裡的 year 欄位（格式類似
    "114年第3季"）——這是 FinMind 自己標好的「這筆股利根據
    哪一季財報盈餘配發」，不是除息日期，兩者可能差好幾季
    （例如台積電季配息，通常隔 2~3 季才真正除息發放）。

    只有在這個欄位缺失或格式跟預期不同時，才退回用除息日
    當天的日曆季度去猜（舊邏輯，不夠準，只當保底）。
    """

    period = d.get("year")

    if period:

        m = re.match(r"(\d+)年第(\d)季", period)

        if m:
            roc_year = int(m.group(1))
            quarter = int(m.group(2))
            return roc_year + 1911, quarter

    # ---- 保底：舊邏輯，只有 year 欄位解析不出來才會走到這裡 ----

    if d.get("CashExDividendTradingDate"):
        dt = d["CashExDividendTradingDate"]
    elif d.get("StockExDividendTradingDate"):
        dt = d["StockExDividendTradingDate"]
    elif d.get("AnnouncementDate"):
        dt = d["AnnouncementDate"]
    else:
        dt = d["date"]

    year = int(dt[:4])
    quarter = quarter_from_date(dt)

    return year, quarter


def parse_financial_data(data):

    out = defaultdict(dict)

    unknown_types = set()

    # ===== 第一層：原始資料（Raw）=====
    for item in data:

        t = item["type"]

        if t not in KNOWN:
            unknown_types.add(t)

        year = int(item["date"][:4])
        quarter = quarter_from_date(item["date"])

        row = out[(year, quarter)]

        row[t] = item["value"]

    if DEBUG and unknown_types:
        print("\n===== Unknown TYPE =====")
        for x in sorted(unknown_types):
            print(x)
        print("========================\n")

    results = []

    for (year, quarter), row in out.items():

        # ===== 第二層：標準化（Normalize）=====

        revenue = pick(row, "Revenue", "OperatingRevenue")

        gross_profit = pick(
            row,
            "GrossProfit",
            "GrossProfitFromOperations",
            "OperatingGrossProfit",
        )

        operating_profit = pick(
            row,
            "OperatingIncome",
            "OperatingIncomeLoss",
            "ProfitFromOperations",
        )

        net_income = pick(
            row,
            "NetIncome",
            "IncomeAfterTax",
            "IncomeAfterTaxes",
            "IncomeAfterTaxFromContinuingOperations",
        )

        pretax_profit = pick(
            row,
            "IncomeBeforeIncomeTax",
            "IncomeBeforeTax",
            "IncomeBeforeTaxFromContinuingOperations",
            "IncomeBeforeIncomeTaxFromContinuingOperations",
        )

        eps = pick(row, "EPS")

        book_value = pick(row, "BookValue")

        roe = pick(row, "ROE")
        roa = pick(row, "ROA")

        assets = pick(row, "Assets", "TotalAssets")

        liabilities = pick(row, "Liabilities", "TotalLiabilities")

        equity = pick(row, "Equity", "EquityAttributableToOwnersOfParent")

        current_assets = pick(row, "CurrentAssets")
        current_liabilities = pick(row, "CurrentLiabilities")
        inventory = pick(row, "Inventories")

        ocf = pick(
            row,
            "CashFlowsFromOperatingActivities",
            "NetCashInflowFromOperatingActivities",
        )
        icf = pick(row, "CashProvidedByInvestingActivities")
        fcf_type = pick(row, "CashFlowsProvidedFromFinancingActivities")

        # ===== 第三層：補算（Calculate）=====

        if gross_profit is None:

            cost = pick(row, "CostOfGoodsSold")

            if revenue and cost:
                gross_profit = revenue - cost

        if operating_profit is None:

            operating_expense = pick(row, "OperatingExpenses")

            if gross_profit and operating_expense:
                operating_profit = gross_profit - operating_expense

        # ===== 存回標準化欄位 =====

        row["revenue"] = revenue
        row["gross_profit"] = gross_profit
        row["operating_profit"] = operating_profit
        row["pretax_profit"] = pretax_profit
        row["net_income"] = net_income
        row["eps"] = eps
        row["book_value"] = book_value

        row["_assets"] = assets
        row["_liabilities"] = liabilities

        row["_current_assets"] = current_assets
        row["_current_liabilities"] = current_liabilities
        row["_inventory"] = inventory

        if revenue:

            if gross_profit is not None:
                row["gross_margin"] = gross_profit / revenue * 100

            if operating_profit is not None:
                row["operating_margin"] = operating_profit / revenue * 100

            if net_income is not None:
                row["net_margin"] = net_income / revenue * 100

        if equity and net_income and not roe:
            roe = net_income / equity * 100

        row["roe"] = roe

        if assets and net_income and not roa:
            roa = net_income / assets * 100

        row["roa"] = roa

        # 負債比
        if assets and liabilities:
            row["debt_ratio"] = liabilities / assets * 100

        # 流動比
        if current_assets and current_liabilities:
            row["current_ratio"] = current_assets / current_liabilities

        # 速動比
        if current_assets and current_liabilities:
            quick_assets = current_assets - (inventory or 0)
            row["quick_ratio"] = quick_assets / current_liabilities

        if ocf is not None:
            row["operating_cash_flow"] = ocf

        if icf is not None:
            row["investing_cash_flow"] = icf

        if fcf_type is not None:
            row["financing_cash_flow"] = fcf_type

        capex = abs(icf) if icf is not None else None

        if ocf is not None and capex is not None:
            row["free_cash_flow"] = ocf - capex

        row["equity"] = equity
        row["year"] = year
        row["quarter"] = quarter

        results.append(row)

    return results




def calculate_ttm_eps(rows):
    rows=sorted(rows,key=lambda x:(x["year"],x["quarter"]))
    for i,row in enumerate(rows):
        if i < 3:
            row["ttm_eps"] = None
            continue

        eps = 0

        for j in range(i - 3, i + 1):
            eps += rows[j].get("eps") or 0

        row["ttm_eps"] = round(eps, 2)
    return rows


def calculate_historical_valuation(code, rows, valuation=None):

    if valuation is None:
        valuation = get_historical_valuation(code)

    if not valuation:
        return rows

    valuation.sort(key=lambda x: x["date"])

    for row in rows:

        publish_date = get_publish_date(
            row["year"],
            row["quarter"],
        )

        row["pe"] = None
        row["pb"] = None

        for v in valuation:

            if v["date"] >= publish_date:

                row["pe"] = v.get("PER")
                row["pb"] = v.get("PBR")

                break

    return rows

def save_financials(code, rows):

    conn = get_connection()
    cur = conn.cursor()

    sql = """
    INSERT INTO financials(
        code,
        year,
        quarter,
        revenue,
        gross_profit,
        operating_profit,
        pretax_profit,
        net_income,
        eps,
        roe,
        roa,
        gross_margin,
        operating_margin,
        net_margin,
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
        stock_dividend_date,

        updated_at
    )
    VALUES(
         ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now')
    )
    ON CONFLICT(code,year,quarter)
    DO UPDATE SET

    revenue=excluded.revenue,
    gross_profit=excluded.gross_profit,
    operating_profit=excluded.operating_profit,
    pretax_profit=excluded.pretax_profit,
    net_income=excluded.net_income,
    eps=excluded.eps,
    roe=excluded.roe,
    roa=excluded.roa,
    gross_margin=excluded.gross_margin,
    operating_margin=excluded.operating_margin,
    net_margin=excluded.net_margin,
    book_value=excluded.book_value,

    assets=excluded.assets,
    liabilities=excluded.liabilities,
    equity=excluded.equity,

    debt_ratio=excluded.debt_ratio,
    current_ratio=excluded.current_ratio,
    quick_ratio=excluded.quick_ratio,

    operating_cash_flow=excluded.operating_cash_flow,
    investing_cash_flow=excluded.investing_cash_flow,
    financing_cash_flow=excluded.financing_cash_flow,

    free_cash_flow=excluded.free_cash_flow,
    pe=excluded.pe,
    pb=excluded.pb,
    dividend_yield=excluded.dividend_yield,

    cash_dividend=excluded.cash_dividend,
    stock_dividend=excluded.stock_dividend,

    ex_dividend_date=excluded.ex_dividend_date,
    cash_dividend_date=excluded.cash_dividend_date,
    stock_dividend_date=excluded.stock_dividend_date,

    updated_at=datetime('now')
    """

    for row in rows:

        cur.execute(sql, (

            code,

            row["year"],

            row["quarter"],

            row.get("revenue"),

            row.get("gross_profit"),

            row.get("operating_profit"),

            row.get("pretax_profit"),

            row.get("net_income"),

            row.get("eps"),

            row.get("roe"),

            row.get("roa"),

            row.get("gross_margin"),

            row.get("operating_margin"),

            row.get("net_margin"),

            row.get("book_value"),

            row.get("_assets"),
            row.get("_liabilities"),
            row.get("equity"),

            row.get("debt_ratio"),
            row.get("current_ratio"),
            row.get("quick_ratio"),

            row.get("operating_cash_flow"),
            row.get("investing_cash_flow"),
            row.get("financing_cash_flow"),

            row.get("free_cash_flow"),
            row.get("pe"),
            row.get("pb"),
            row.get("dividend_yield"),

            row.get("cash_dividend"),
            row.get("stock_dividend"),

            row.get("ex_dividend_date"),
            row.get("cash_dividend_date"),
            row.get("stock_dividend_date"),

        ))

    conn.commit()
    conn.close()




def calculate_growth(rows):
    rows = sorted(rows, key=lambda x: x["date"])

    revenue_map = {
        (int(r["revenue_year"]), int(r["revenue_month"])): r["revenue"]
        for r in rows
    }

    for r in rows:
        year = int(r["revenue_year"])
        month = int(r["revenue_month"])
        revenue = r["revenue"]

        # 上月
        if month == 1:
            py, pm = year - 1, 12
        else:
            py, pm = year, month - 1

        prev = revenue_map.get((py, pm))
        if prev:
            r["mom"] = (revenue - prev) / prev * 100

        # 去年同月
        last_year = revenue_map.get((year - 1, month))
        if last_year:
            r["yoy"] = (revenue - last_year) / last_year * 100

    return rows

def save_month_revenue(code, rows):

    conn = get_connection()
    cur = conn.cursor()

    sql = """
    INSERT INTO monthly_revenue(
        code,
        year,
        month,
        revenue,
        mom,
        yoy,
        updated_at
    )
    VALUES(
        ?,?,?,?,?,?,datetime('now')
    )
    ON CONFLICT(code,year,month)
    DO UPDATE SET

    revenue=excluded.revenue,
    mom=excluded.mom,
    yoy=excluded.yoy,
    updated_at=datetime('now')
    """

    for row in rows:

        year = int(row["revenue_year"])
        month = int(row["revenue_month"])

        cur.execute(
            sql,
            (
                code,
                year,
                month,
                float(row["revenue"]),
                row.get("mom"),
                row.get("yoy"),
            ),
        )

    conn.commit()
    conn.close()


def _check_quota(e):
    """把 FinMind 的額度錯誤轉成 QuotaReached，其餘照原樣丟出"""

    msg = str(e)

    if "402" in msg or "upper limit" in msg or "額度用完" in msg:
        block_quota()
        raise QuotaReached() from None

    raise


def _build_dividend_map(dividend):

    dividend_map = {}

    for d in dividend:

        key = get_dividend_year_quarter(d)

        m = dividend_map.setdefault(key, {})

        cash = d.get("CashEarningsDistribution")
        if cash not in (None, 0):
            m["CashEarningsDistribution"] = cash
            m["CashExDividendTradingDate"] = d.get("CashExDividendTradingDate")
            m["CashDividendPaymentDate"] = d.get("CashDividendPaymentDate")

        stock = d.get("StockEarningsDistribution")
        if stock not in (None, 0):
            m["StockEarningsDistribution"] = stock
            m["StockExDividendTradingDate"] = d.get("StockExDividendTradingDate")

    return dividend_map


def save_corporate_actions(code, dividend):
    """
    把 FinMind 的股利資料轉成通用的公司行動事件。

    正規化成 (cash_per_share, share_ratio) 兩個欄位，讓回測不必
    知道「股票股利要除以面額 10」這種台股專屬規則。分割和減資
    FinMind 沒有現成資料集，之後可以用同一張表手動補，
    source 標成 manual。
    """

    if not dividend:
        return 0

    conn = get_connection()
    cur = conn.cursor()

    sql = """
        INSERT INTO corporate_actions(
            code, ex_date, action_type,
            cash_per_share, share_ratio, raw_value,
            pay_date, source, updated_at
        )
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(code, ex_date, action_type)
        DO UPDATE SET
            cash_per_share = excluded.cash_per_share,
            share_ratio    = excluded.share_ratio,
            raw_value      = excluded.raw_value,
            pay_date       = excluded.pay_date,
            updated_at     = excluded.updated_at
    """

    now = date.today().isoformat()
    count = 0

    for d in dividend:

        cash = d.get("CashEarningsDistribution")
        cash_ex = d.get("CashExDividendTradingDate")

        if cash and cash_ex:
            cur.execute(sql, (
                code, cash_ex, "CASH",
                cash, 1.0, cash,
                d.get("CashDividendPaymentDate"), "finmind", now,
            ))
            count += 1

        # 股票股利以面額 10 元計價：配 1 元 = 每股多 0.1 股。
        # 這個 /10 只在這裡出現一次，之後所有程式看到的都是
        # 已經算好的股數乘數。
        stock = d.get("StockEarningsDistribution")
        stock_ex = d.get("StockExDividendTradingDate")

        if stock and stock_ex:
            cur.execute(sql, (
                code, stock_ex, "STOCK_DIVIDEND",
                0.0, 1.0 + stock / 10.0, stock,
                None, "finmind", now,
            ))
            count += 1

    conn.commit()
    conn.close()

    return count


def _update_financials(code, dividend, valuation=None):
    """
    財報那一段。回傳 True 代表這次有實際寫入資料。
    網路類的例外往上丟，讓呼叫端知道「這是失敗，不是沒資料」。
    """

    data = get_financial_data(code)

    if not data:
        mark_fetch(code, "financials", False)
        print(code, "無財報資料")
        return False

    mark_fetch(code, "financials", True)

    save_corporate_actions(code, dividend)

    parsed = parse_financial_data(data)
    parsed = calculate_ttm_eps(parsed)
    parsed = calculate_historical_valuation(code, parsed, valuation)

    dividend_map = _build_dividend_map(dividend)

    for row in parsed:

        d = dividend_map.get((row["year"], row["quarter"]))

        if not d:
            continue

        row["cash_dividend"] = d.get("CashEarningsDistribution")
        row["stock_dividend"] = d.get("StockEarningsDistribution")

        row["ex_dividend_date"] = d.get("CashExDividendTradingDate")
        row["cash_dividend_date"] = d.get("CashDividendPaymentDate")
        row["stock_dividend_date"] = d.get("StockExDividendTradingDate")

    # 殖利率要算「每一季」，不是只有那一季剛好有配息才算——
    # 用移動視窗往回12個月加總配息，即使這一季本身沒有新的
    # 配息事件，只要過去12個月內有配過，殖利率就不會是 0。
    for row in parsed:

        publish_date = get_publish_date(row["year"], row["quarter"])

        row["dividend_yield"] = calculate_dividend_yield(
            code, dividend, publish_date
        )

    save_financials(code, parsed)

    print(code, "財報完成", len(parsed), "季")

    return True


def _update_month_revenue(code):

    month_data = get_month_revenue(code)

    if not month_data:
        mark_fetch(code, "month_revenue", False)
        print(code, "無月營收資料")
        return False

    mark_fetch(code, "month_revenue", True)

    month_data = calculate_growth(month_data)
    save_month_revenue(code, month_data)

    print(code, "月營收完成", len(month_data), "筆")

    return True


def _update_valuation(code, dividend, valuation):
    """本益比、股價淨值比、主頁殖利率。每次都要更新。"""

    if not valuation:
        print(code, "無估值資料")
        return False

    last = valuation[-1]

    # 主頁殖利率＝往回12個月配息加總 ÷ 最新股價，不直接抄
    # FinMind 的 dividend_yield 欄位（那個是單一次配息算的，
    # 配息次數多的股票會被低估）。
    today_str = date.today().isoformat()

    dividend_yield_value = calculate_dividend_yield(
        code, dividend, today_str
    )

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        UPDATE stocks
        SET pe=?, pb=?, dividend_yield=?
        WHERE code=?
    """, (last["PER"], last["PBR"], dividend_yield_value, code))

    conn.commit()
    conn.close()

    return True


def update_one_financial(code, force=False):
    """
    三段資料各自判斷要不要下載：
      財報   一季一次    needs_financials()
      月營收 每月一次    needs_month_revenue()
      估值   每天       一定跑
    回傳 False 代表這檔中間出了錯（不是「沒資料」）。
    額度用完時丟 QuotaReached，讓外層停止整批執行。
    """

    ok = True

    # 股利：估值那段要用。失敗時保持 None，不要退化成空清單——
    # 空清單會讓殖利率算出 None，然後把 stocks 表裡原本正確的
    # 數字覆蓋掉。沒配過息的股票回傳的才是「真正的空清單」。
    dividend = None

    try:
        dividend = get_dividend(code)
    except Exception as e:
        _check_quota(e)
        print(code, "股利下載失敗:", e)
        ok = False

    # TaiwanStockPER 抓一次就好：歷史估值和主頁 PE/PB 用的是
    # 同一個資料集，分開抓等於每檔白花一次額度。
    valuation = None

    try:
        valuation = get_valuation(code)
    except Exception as e:
        _check_quota(e)
        print(code, "估值下載失敗:", e)
        ok = False

    # ---------- 財報 ----------
    if force or needs_financials(code):
        try:
            _update_financials(code, dividend or [], valuation)
        except QuotaReached:
            raise
        except Exception as e:
            _check_quota(e)
            print(code, "財報處理失敗:", e)
            ok = False
    else:
        print(code, "財報已是最新，跳過")

    # ---------- 月營收 ----------
    if force or needs_month_revenue(code):
        try:
            _update_month_revenue(code)
        except QuotaReached:
            raise
        except Exception as e:
            _check_quota(e)
            print(code, "月營收處理失敗:", e)
            ok = False
    else:
        print(code, "月營收已是最新，跳過")

    # ---------- 估值 ----------
    # 股利沒拿到就不要更新，否則會把 stocks 表的殖利率洗成 NULL
    if dividend is None or valuation is None:
        print(code, "股利或估值缺漏，略過 stocks 表更新")
    else:
        try:
            _update_valuation(code, dividend, valuation)
        except QuotaReached:
            raise
        except Exception as e:
            _check_quota(e)
            print(code, "估值處理失敗:", e)
            ok = False

    return ok


def update_all(force=False, limit=HOURLY_LIMIT):

    ensure_fetch_log()

    stocks = financial_queue(limit=limit)

    pending = len(financial_queue())

    print(f"待處理 {pending} 檔，本次跑 {len(stocks)} 檔")

    if pending > limit:
        print(f"約需再執行 {-(-pending // limit)} 次")

    success = 0
    failed = []
    quota_hit = False

    total = len(stocks)

    for i, code in enumerate(stocks, 1):

        print(f"[{i}/{total}] 更新 {code}")

        try:

            if update_one_financial(code, force=force):
                success += 1
            else:
                failed.append(code)

        except QuotaReached:

            quota_hit = True

            print("\n!!! FinMind 額度用完，停止本次執行")
            print(f"已完成 {i-1}/{total}，下次執行會自動接續")

            break

        time.sleep(0.3)

    print("\n======================")
    print("成功：", success)
    print("失敗：", len(failed))

    if failed:
        print("\n失敗股票：")
        for stock in failed:
            print(stock)

    if quota_hit:
        print("\n額度已滿，等一小時後再執行")
    else:
        print(f"\n剩餘待處理：{len(financial_queue())} 檔")

    print("======================")


def report_gaps(stocks):
    """
    列出中間缺季的股票。這只是報告，不會自動去補——
    要補的話針對這些代號跑 force=True。
    """

    holes = []

    for code in stocks:

        gaps = financial_gaps(code)

        if gaps:
            holes.append((code, gaps))

    if not holes:
        return

    print("\n===== 中間缺季（需要時用 force 重抓）=====")

    for code, gaps in holes:
        print(code, gaps)

    print("==========================================")


def main():

    ensure_fetch_log()

    code = input("股票代號(Enter=全部)：").strip()

    force = input("強制重抓？(y/Enter=否)：").strip().lower() == "y"

    if code:
        update_one_financial(code, force=force)
    else:
        raw = input(f"本次上限 (Enter={HOURLY_LIMIT})：").strip()
        update_all(force=force, limit=int(raw) if raw else HOURLY_LIMIT)


if __name__ == "__main__":
    main()