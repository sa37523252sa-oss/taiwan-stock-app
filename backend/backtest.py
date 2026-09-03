"""
回測引擎，第一版：單一股票 + MA 均線交叉策略。

架構刻意跟策略邏輯分開（Portfolio 記帳、Metrics 算指標、
run_ma_cross_backtest 是目前唯一的策略函式）——之後要加
RSI/MACD/動能策略，不用改這支檔案的記帳/指標邏輯，只要新增
一個新的策略函式，一樣回傳同樣格式的 asset_curve/trades，
Metrics 那段可以直接共用。

手續費／交易稅計算方式沿用 holdings.py 同一套規則（0.1425%
手續費、一般股票0.3%／ETF 0.1%交易稅，僅賣出課稅）。
"""

from datetime import datetime, date

from database import get_connection
from update_financial import get_publish_date

RAW_FEE_RATE = 0.001425
STOCK_TAX_RATE = 0.003
ETF_TAX_RATE = 0.001


def get_price_history(code, start_date, end_date, adjusted=None):
    """
    adjusted=None   原始價，顯示用、算成交金額用
    adjusted="price" 還原除權（股數變動），技術指標和策略回測用
    adjusted="total" 連現金股利一起還原，比較長期報酬用

    技術策略一定要用 price：除權當天原始價會斷崖式下跌，
    均線交叉、跌破停損、跌幅排序全部會被觸發假訊號。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT date, close, high, low, volume FROM prices
        WHERE code = ? AND date >= ? AND date <= ?
        ORDER BY date ASC
    """, (code, start_date, end_date))

    rows = cur.fetchall()
    conn.close()

    history = [
        {
            "date": r["date"],
            "close": r["close"],
            "high": r["high"],
            "low": r["low"],
            "volume": r["volume"] or 0,
        }
        for r in rows
    ]

    if not adjusted or not history:
        return history

    from corporate_actions import get_actions, adjust_history

    return adjust_history(
        history, get_actions(code, start_date, end_date), mode=adjusted
    )


def get_asset_type(code):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT asset_type FROM stocks WHERE code = ?", (code,))
    row = cur.fetchone()

    conn.close()

    return row["asset_type"] if row else "STOCK"


def get_dividend_events(code, start_date, end_date):
    """{除息日: 每股現金股利}。委派給 corporate_actions，事件來源只有一處。"""

    from corporate_actions import cash_events

    return cash_events(code, start_date, end_date)


def get_share_ratio_events(code, start_date, end_date):
    """
    {除權日: 股數乘數}。涵蓋股票股利、分割、減資——三者的股數
    效果都已經在寫入 corporate_actions 時正規化成同一個數字，
    這裡不需要再判斷事件類型。

    刻意不叫 split：台股的股票股利是盈餘轉增資，會計上跟美股的
    stock split 不同，只是股數效果可以用同一個乘數表達。
    """

    from corporate_actions import share_multiplier_events

    return share_multiplier_events(code, start_date, end_date)


def calculate_ma(closes, period):
    """回傳跟 closes 等長的 list，前 period-1 筆是 None（資料不足）"""

    result = []

    for i in range(len(closes)):
        if i < period - 1:
            result.append(None)
        else:
            window = closes[i - period + 1:i + 1]
            result.append(sum(window) / period)

    return result


def get_financial_history(code):
    """
    取得歷史每季財報數字，附上估算的公告日期（沿用
    update_financial.py 同一套 get_publish_date 邏輯），
    依公告日期由舊到新排序。

    支援的欄位：pe（本益比）、dividend_yield（殖利率）、eps、roe、
    roa、gross_margin（毛利率）、operating_margin（營業利益率）、
    revenue（營收）、debt_ratio（負債比）、free_cash_flow（自由
    現金流）——已跟實際資料庫欄位核對過，這些欄位真的存在，不是
    假設的。「營收成長率」「EPS成長率」不需要額外欄位，直接用
    fundamental_growth 這個機制對 revenue/eps 算成長率就是了。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT year, quarter, pe, dividend_yield, eps, roe, roa,
               gross_margin, operating_margin, revenue,
               debt_ratio, free_cash_flow
        FROM financials
        WHERE code = ?
        ORDER BY year ASC, quarter ASC
    """, (code,))

    rows = cur.fetchall()
    conn.close()

    result = []

    for r in rows:
        result.append({
            "publish_date": get_publish_date(r["year"], r["quarter"]),
            "pe": r["pe"],
            "dividend_yield": r["dividend_yield"],
            "eps": r["eps"],
            "roe": r["roe"],
            "roa": r["roa"],
            "gross_margin": r["gross_margin"],
            "operating_margin": r["operating_margin"],
            "revenue": r["revenue"],
            "debt_ratio": r["debt_ratio"],
            "free_cash_flow": r["free_cash_flow"],
        })

    result.sort(key=lambda x: x["publish_date"])

    return result


def build_fundamental_series(financial_history, dates, field):
    """
    對每個交易日，往前找出「當時已經公告」的最新一筆財報數值
    （point-in-time：某天的財報要等公告日過了才算數，不能用
    還沒公告的未來財報回測過去，避免「未來偷看」造成失真的
    回測績效）。

    financial_history 要先依 publish_date 由舊到新排序，
    dates 也要由舊到新——這是逐一往前推進的線性掃描，不是
    每天重新從頭找一次，資料量大也不會變慢。
    """

    result = []
    idx = 0
    current_value = None

    for d in dates:

        while (idx < len(financial_history) and
               financial_history[idx]["publish_date"] <= d):
            current_value = financial_history[idx][field]
            idx += 1

        result.append(current_value)

    return result


class ConditionEvaluator:
    """
    通用條件判斷器，支援多種條件類型，每種類型各自算好需要的
    序列（MA、成交量均量等），評估「第 i 天」這個條件是否成立。

    目前支援：
    - ma_cross：均線交叉（黃金/死亡交叉，訊號只在交叉當天成立，
      不是「目前是否在上方」這種持續狀態）
    - price_above / price_below：股價高於/低於一個固定金額
    - volume_spike：成交量 > N日均量 × 倍數

    「基本面」條件目前沒有支援——回測要對齊「當天股價 vs 當時
    最新一季財報」，牽涉到時間對齊的複雜度，這版先不做，避免
    做一個不夠準確的東西。
    """

    def __init__(self, closes, volumes, highs=None, lows=None, dates=None, code=None):
        self.closes = closes
        self.volumes = volumes
        self.highs = highs
        self.lows = lows
        self.dates = dates
        self.code = code
        self._ma_cache = {}
        self._vol_avg_cache = {}
        self._fundamental_cache = {}

    def _get_ma(self, period):
        if period not in self._ma_cache:
            self._ma_cache[period] = calculate_ma(self.closes, period)
        return self._ma_cache[period]

    def _get_vol_avg(self, period):
        if period not in self._vol_avg_cache:
            result = []
            for i in range(len(self.volumes)):
                if i < period - 1:
                    result.append(None)
                else:
                    window = self.volumes[i - period + 1:i + 1]
                    result.append(sum(window) / period)
            self._vol_avg_cache[period] = result
        return self._vol_avg_cache[period]

    def _get_fundamental_series(self, field):

        if field not in self._fundamental_cache:

            history = get_financial_history(self.code)

            self._fundamental_cache[field] = build_fundamental_series(
                history, self.dates, field
            )

        return self._fundamental_cache[field]

    def _get_fundamental_running_max(self, field):
        """
        每一天「在這天之前（不含當天）」曾經出現過的最大值，
        預先算好整條序列，避免 fundamental_new_high 每次呼叫
        都重新掃描一次歷史（長天期回測會變慢）。
        """

        cache_key = f"_max_{field}"

        if cache_key not in self._fundamental_cache:

            series = self._get_fundamental_series(field)

            result = []
            running_max = None

            for v in series:
                result.append(running_max)
                if v is not None and (running_max is None or v > running_max):
                    running_max = v

            self._fundamental_cache[cache_key] = result

        return self._fundamental_cache[cache_key]

    def evaluate(self, condition, i):

        if i < 1:
            return False

        ctype = condition.get("type")

        if ctype == "ma_cross":

            fast_ma = self._get_ma(condition["fast"])
            slow_ma = self._get_ma(condition["slow"])

            if (fast_ma[i] is None or slow_ma[i] is None or
                    fast_ma[i - 1] is None or slow_ma[i - 1] is None):
                return False

            if condition["direction"] == "above":
                return (
                    fast_ma[i - 1] <= slow_ma[i - 1] and
                    fast_ma[i] > slow_ma[i]
                )
            else:
                return (
                    fast_ma[i - 1] >= slow_ma[i - 1] and
                    fast_ma[i] < slow_ma[i]
                )

        elif ctype == "price_vs_ma":

            # 跟 ma_cross 不一樣：這個是「目前價格相對均線的位置」
            # （持續狀態），不是「交叉的那一瞬間」。例如「站上5MA」
            # 只要今天收盤價 > 5MA 就算符合，不用等真正突破那一天。
            ma = self._get_ma(condition["period"])

            if ma[i] is None:
                return False

            if condition["direction"] == "above":
                return self.closes[i] > ma[i]
            else:
                return self.closes[i] < ma[i]

        elif ctype == "price_above":
            return self.closes[i] > condition["value"]

        elif ctype == "price_below":
            return self.closes[i] < condition["value"]

        elif ctype == "volume_spike":

            period = condition.get("period", 20)
            multiplier = condition.get("multiplier", 2.0)

            avg = self._get_vol_avg(period)

            if avg[i] is None or avg[i] == 0:
                return False

            return self.volumes[i] > avg[i] * multiplier

        elif ctype == "volume_new_high":

            # 成交量創「近N日新高」：今天的量比過去N天（不含今天）
            # 每一天都大，用來抓「久違的爆量」這種訊號。
            period = condition.get("period", 20)

            if i < period:
                return False

            window = self.volumes[i - period:i]

            if not window:
                return False

            return self.volumes[i] > max(window)

        elif ctype == "volume_breakout":

            # 先在「今天以前」的N天內，找出成交量最大的那一天
            # （通常代表當時有主力進出、法人表態），記下那天的
            # 最高價/最低價，之後如果股價突破那個價位，視為訊號
            # ——這是常見的「大量表態日」量價關係判斷法。
            #
            # 有個陷阱：如果這N天成交量根本沒有明顯突出（例如
            # 每天量都差不多），硬選一天當「大量日」意義不大，
            # 甚至會產生沒道理的假訊號。所以額外要求：候選的那
            # 一天，成交量至少要達到窗口平均量的 min_multiplier
            # 倍（預設1.5倍），才算數，不然就當作「這段期間沒有
            # 真正的大量表態日」，不觸發。
            if self.highs is None or self.lows is None:
                return False

            period = condition.get("period", 20)
            direction = condition.get("direction", "above")
            min_multiplier = condition.get("min_multiplier", 1.5)

            if i < period:
                return False

            window_start = i - period
            window_volumes = self.volumes[window_start:i]

            if not window_volumes:
                return False

            window_avg = sum(window_volumes) / len(window_volumes)
            peak_volume = max(window_volumes)

            if window_avg == 0 or peak_volume < window_avg * min_multiplier:
                return False

            peak_offset = window_volumes.index(peak_volume)
            peak_index = window_start + peak_offset

            if direction == "above":
                return self.closes[i] > self.highs[peak_index]
            else:
                return self.closes[i] < self.lows[peak_index]

        elif ctype in ("fundamental_above", "fundamental_below"):

            field = condition["field"]
            series = self._get_fundamental_series(field)

            if series[i] is None:
                return False

            if ctype == "fundamental_above":
                return series[i] > condition["value"]
            else:
                return series[i] < condition["value"]

        elif ctype == "fundamental_new_high":

            field = condition["field"]
            series = self._get_fundamental_series(field)
            running_max = self._get_fundamental_running_max(field)

            if series[i] is None or running_max[i] is None:
                return False

            return series[i] > running_max[i]

        return False

    def evaluate_all(self, conditions, i):
        """AND 組合：條件清單裡全部都成立，這天才算訊號觸發
        （舊版介面，保留給還沒改用群組結構的呼叫端用）"""

        if not conditions:
            return False

        return all(self.evaluate(c, i) for c in conditions)

    def evaluate_groups(self, condition_groups, i):
        """
        群組結構：外層是 OR，每個群組內部是 AND。
        例如 [[A, B], [C]] 代表 (A AND B) OR (C)，
        只要有任何一個群組全部條件都成立，這天就算訊號觸發。
        """

        if not condition_groups:
            return False

        for group in condition_groups:
            if group and all(self.evaluate(c, i) for c in group):
                return True

        return False

    def max_lookback(self, conditions):
        """算出這組條件裡，最長需要往回看幾天的資料才能開始判斷
        （舊版介面，接受扁平清單）"""

        periods = [0]

        for c in conditions:
            if c.get("type") == "ma_cross":
                periods.append(c.get("fast", 0))
                periods.append(c.get("slow", 0))
            elif c.get("type") == "price_vs_ma":
                periods.append(c.get("period", 0))
            elif c.get("type") in ("volume_spike", "volume_new_high", "volume_breakout"):
                periods.append(c.get("period", 20))

        return max(periods)

    def max_lookback_groups(self, condition_groups):
        """跟 max_lookback 一樣，但接受群組結構（list of list）"""

        flat = [c for group in condition_groups for c in group]

        return self.max_lookback(flat)


def _normalize_to_groups(conditions):
    """
    把輸入正規化成「群組結構」（list of list）：
    - 如果傳進來的已經是群組結構（每個元素本身是 list），原樣回傳
    - 如果傳進來的是舊版扁平清單（每個元素是 dict），包成單一群組
      （等同全部條件都用 AND，等同以前的行為，向下相容）
    - 空清單視為空群組清單
    """

    if not conditions:
        return []

    if isinstance(conditions[0], list):
        return conditions

    return [conditions]


def run_backtest(
    code,
    start_date,
    end_date,
    buy_conditions,
    sell_conditions,
    initial_capital=1000000,
    fee_discount=None,
):
    """
    通用回測引擎：buy_conditions/sell_conditions 是「群組結構」
    （list of list）：外層群組之間用 OR，群組內部條件用 AND。
    例如 [[A, B], [C]] 代表 (A AND B) OR (C)。

    也接受舊版扁平清單（單純 list of 條件），會自動當成單一
    AND 群組處理，向下相容。

    第一版只做「全押全出」，不做分批加減碼。
    """

    buy_groups = _normalize_to_groups(buy_conditions)
    sell_groups = _normalize_to_groups(sell_conditions)

    # 用還原除權的價格跑策略。原始價在除權當天會出現假跌停，
    # 停損條件會被觸發、均線會被拉出假交叉。
    prices = get_price_history(code, start_date, end_date, adjusted="price")

    closes = [p["close"] for p in prices]
    highs = [p["high"] for p in prices]
    lows = [p["low"] for p in prices]
    volumes = [p["volume"] for p in prices]
    dates = [p["date"] for p in prices]

    evaluator = ConditionEvaluator(
        closes, volumes, highs=highs, lows=lows, dates=dates, code=code
    )

    max_period = max(
        evaluator.max_lookback_groups(buy_groups),
        evaluator.max_lookback_groups(sell_groups),
    )

    if len(prices) < max_period + 2:
        return {
            "error": f"資料筆數不足（只有 {len(prices)} 筆），"
                     f"至少需要 {max_period + 2} 筆才能計算指標"
        }

    asset_type = get_asset_type(code)

    fee_rate = (
        RAW_FEE_RATE * (fee_discount / 10) if fee_discount else RAW_FEE_RATE
    )
    tax_rate = (
        ETF_TAX_RATE if (asset_type or "").upper() == "ETF" else STOCK_TAX_RATE
    )

    cash = initial_capital
    shares = 0
    holding = False
    entry_price = 0.0

    trades = []
    asset_curve = []

    dividend_events = get_dividend_events(code, start_date, end_date)
    total_dividend = 0.0

    for i in range(1, len(closes)):

        price = closes[i]

        # 持有期間如果剛好遇到除息日，把現金股利加進現金部位
        # （只算現金股利，理由跟庫存股頁面一致：股票股利資料
        # 完整度太低、邏輯也複雜很多）。
        if holding and dates[i] in dividend_events:
            dividend_income = shares * dividend_events[dates[i]]
            cash += dividend_income
            total_dividend += dividend_income

        if not holding and price > 0:

            if evaluator.evaluate_groups(buy_groups, i):

                approx_shares = int(cash / (price * (1 + fee_rate)))

                if approx_shares > 0:

                    cost = approx_shares * price
                    buy_fee = round(cost * fee_rate)

                    cash -= (cost + buy_fee)
                    shares = approx_shares
                    holding = True
                    entry_price = price

                    trades.append({
                        "date": dates[i],
                        "action": "buy",
                        "price": price,
                        "shares": shares,
                        "profit": None,
                    })

        elif holding:

            if evaluator.evaluate_groups(sell_groups, i):

                proceeds = shares * price
                sell_fee = round(proceeds * fee_rate)
                sell_tax = round(proceeds * tax_rate)
                net = proceeds - sell_fee - sell_tax

                profit = net - (entry_price * shares)

                cash += net

                trades.append({
                    "date": dates[i],
                    "action": "sell",
                    "price": price,
                    "shares": shares,
                    "profit": round(profit, 2),
                })

                shares = 0
                holding = False

        total_value = cash + shares * price
        asset_curve.append({"date": dates[i], "value": round(total_value, 2)})

    final_price = closes[-1] if closes else 0
    final_value = cash + shares * final_price

    metrics = calculate_metrics(
        asset_curve, initial_capital, final_value, trades
    )

    return {
        "asset_curve": asset_curve,
        "trades": trades,
        "metrics": metrics,
        "still_holding": holding,
        "total_dividend": round(total_dividend, 2),
    }


def run_ma_cross_backtest(
    code,
    start_date,
    end_date,
    buy_fast,
    buy_slow,
    sell_fast,
    sell_slow,
    initial_capital=1000000,
    fee_discount=None,
):
    """
    舊版單一MA交叉介面，內部改呼叫通用的 run_backtest，維持向下
    相容（Flutter 端如果還沒更新，呼叫這支不會壞掉）。
    """

    return run_backtest(
        code,
        start_date,
        end_date,
        buy_conditions=[{
            "type": "ma_cross", "fast": buy_fast, "slow": buy_slow,
            "direction": "above",
        }],
        sell_conditions=[{
            "type": "ma_cross", "fast": sell_fast, "slow": sell_slow,
            "direction": "below",
        }],
        initial_capital=initial_capital,
        fee_discount=fee_discount,
    )



def calculate_metrics(asset_curve, initial_capital, final_value, trades):

    if not asset_curve:
        return {}

    total_return = (
        (final_value - initial_capital) / initial_capital * 100
        if initial_capital else 0
    )

    start_date = datetime.strptime(asset_curve[0]["date"], "%Y-%m-%d")
    end_date = datetime.strptime(asset_curve[-1]["date"], "%Y-%m-%d")
    days = (end_date - start_date).days

    if days > 0 and final_value > 0 and initial_capital > 0:
        cagr = ((final_value / initial_capital) ** (365 / days) - 1) * 100
    else:
        cagr = 0

    # 最大回撤：追蹤歷史最高點，記錄每天相對高點的跌幅，取最深的一次
    peak = asset_curve[0]["value"]
    max_dd = 0.0

    for point in asset_curve:
        v = point["value"]
        if v > peak:
            peak = v
        dd = (v - peak) / peak * 100 if peak > 0 else 0
        if dd < max_dd:
            max_dd = dd

    # Sharpe：用資產曲線的日報酬率年化，無風險利率簡化為0
    daily_returns = []

    for i in range(1, len(asset_curve)):
        prev = asset_curve[i - 1]["value"]
        curr = asset_curve[i]["value"]
        if prev > 0:
            daily_returns.append((curr - prev) / prev)

    if len(daily_returns) > 1:

        mean_r = sum(daily_returns) / len(daily_returns)
        variance = sum(
            (r - mean_r) ** 2 for r in daily_returns
        ) / len(daily_returns)
        std_r = variance ** 0.5

        sharpe = (mean_r / std_r * (252 ** 0.5)) if std_r > 0 else 0

    else:
        sharpe = 0

    sell_trades = [t for t in trades if t["action"] == "sell"]
    win_trades = [
        t for t in sell_trades if t["profit"] is not None and t["profit"] > 0
    ]

    win_rate = (
        len(win_trades) / len(sell_trades) * 100 if sell_trades else 0
    )

    return {
        "total_return": round(total_return, 2),
        "cagr": round(cagr, 2),
        "max_drawdown": round(max_dd, 2),
        "sharpe": round(sharpe, 2),
        "win_rate": round(win_rate, 2),
        "trade_count": len(sell_trades),
    }


def resolve_weights(stocks):
    """
    stocks: [{"code": ..., "weight": 0~100 之間的數字 或 None}, ...]

    規則：
    - 有手動設定權重的股票，直接用設定的比例
    - 沒設定的股票，平分「剩餘額度」（不是平分全部100%）
    - 如果手動設定的權重加總超過100%，視為輸入錯誤
    - 如果手動設定的權重加總不到100%、又沒有任何股票留給系統
      自動分配，剩下的百分比就當作保留現金、不投入（不強迫湊滿
      100%，使用者可能就是刻意不想滿倉）

    回傳：{code: 0~1之間的比例}，加總不一定是1（可能小於1，
    代表有保留現金）
    """

    explicit = [s for s in stocks if s.get("weight") is not None]
    implicit = [s for s in stocks if s.get("weight") is None]

    explicit_sum = sum(s["weight"] for s in explicit)

    if explicit_sum > 100 + 1e-9:
        raise ValueError(
            f"手動設定的權重加總是 {explicit_sum}%，超過100%，"
            f"請調整後再試一次"
        )

    remaining = max(0, 100 - explicit_sum)

    result = {}

    for s in explicit:
        result[s["code"]] = s["weight"] / 100

    if implicit:
        per_stock = (remaining / len(implicit)) / 100
        for s in implicit:
            result[s["code"]] = per_stock

    return result


def run_portfolio_backtest(
    stocks,
    start_date,
    end_date,
    initial_capital=1000000,
    fee_discount=None,
):
    """
    多股票組合回測（第一版）：

    - 每支股票各自分配固定資金（依權重），各自獨立套用自己的
      買賣條件（可以每支股票都不同，也可以全部傳同一組達到
      「統一策略」的效果——這個判斷交給呼叫端，這支函式不區分）
    - 賣掉某支股票空出來的錢，留在該股票自己的現金部位裡，
      不會拿去買其他股票（不做再平衡、不做動態調整）
    - 最後把每支股票各自的資產曲線相加，合併成一條組合曲線

    stocks: [
        {
            "code": "2330",
            "weight": 50 或 None,
            "buy_conditions": [[...]],   # 群組結構
            "sell_conditions": [[...]],
        },
        ...
    ]
    """

    if not stocks:
        return {"error": "至少要選一支股票"}

    try:
        weights = resolve_weights(stocks)
    except ValueError as e:
        return {"error": str(e)}

    per_stock_results = {}

    for s in stocks:

        code = s["code"]
        allocated_capital = initial_capital * weights[code]

        if allocated_capital <= 0:
            continue

        result = run_backtest(
            code,
            start_date,
            end_date,
            buy_conditions=s.get("buy_conditions", []),
            sell_conditions=s.get("sell_conditions", []),
            initial_capital=allocated_capital,
            fee_discount=fee_discount,
        )

        if "error" in result:
            return {"error": f"{code}：{result['error']}"}

        per_stock_results[code] = result

    if not per_stock_results:
        return {"error": "沒有任何股票實際投入資金（權重都是0）"}

    # 把每支股票的資產曲線合併成一條組合曲線。用「日期聯集」
    # 對齊，缺值的股票用前一筆已知數值往前補（同一天不一定
    # 每支股票都有交易資料，例如個別股票停牌），確保加總時
    # 不會漏掉某支股票那天的價值。
    all_dates = sorted({
        point["date"]
        for result in per_stock_results.values()
        for point in result["asset_curve"]
    })

    # 每支股票各自先建立「日期 -> 資產值」的查表，避免等一下
    # 合併曲線時要用巢狀迴圈逐一比對日期（資料量大會很慢）。
    value_lookup = {
        code: {p["date"]: p["value"] for p in result["asset_curve"]}
        for code, result in per_stock_results.items()
    }

    combined_curve = []

    last_known = {code: initial_capital * weights[code] for code in per_stock_results}

    for d in all_dates:

        for code in per_stock_results:
            if d in value_lookup[code]:
                last_known[code] = value_lookup[code][d]

        total = sum(last_known.values())

        combined_curve.append({"date": d, "value": round(total, 2)})

    all_trades = []

    for code, result in per_stock_results.items():
        for t in result["trades"]:
            all_trades.append({**t, "code": code})

    all_trades.sort(key=lambda t: t["date"])

    final_value = combined_curve[-1]["value"] if combined_curve else initial_capital

    metrics = calculate_metrics(
        combined_curve, initial_capital, final_value, all_trades
    )

    total_dividend = sum(
        result.get("total_dividend", 0) for result in per_stock_results.values()
    )

    return {
        "asset_curve": combined_curve,
        "trades": all_trades,
        "metrics": metrics,
        "weights": {code: round(w * 100, 2) for code, w in weights.items()},
        "per_stock": {
            code: result["metrics"] for code, result in per_stock_results.items()
        },
        "total_dividend": round(total_dividend, 2),
    }


# =====================
# 選股策略（第一版）：定期審核成分股 + 換股
# =====================
#
# 跟單一股票/多股票組合不一樣：不是逐日判斷買賣訊號，而是像
# 被動式 ETF 那樣，每隔固定期間（例如每季、每半年）重新審核
# 一次全市場的股票，篩出符合條件的，組成一個等權重投資組合，
# 持有到下次審核日再重新篩選、換股。


def get_all_stock_codes():
    """全市場所有股票代號，排除加權/櫃買指數這種不是真正股票的項目"""

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT code FROM stocks WHERE asset_type IS NULL OR asset_type != 'INDEX'")

    rows = cur.fetchall()
    conn.close()

    return [r["code"] for r in rows]


def get_fundamental_value_asof(history, field, target_date, quarters_back=0):
    """
    history 已依 publish_date 由舊到新排序。找出「target_date
    當時已經公告」的最新一季數值；quarters_back > 0 則額外往回
    多找幾季前的數值（用來算成長率）。point-in-time，不會用到
    target_date 當時還沒公告的未來財報。
    """

    available = [h for h in history if h["publish_date"] <= target_date]

    if not available:
        return None

    idx = len(available) - 1 - quarters_back

    if idx < 0:
        return None

    return available[idx][field]


def check_fundamental_consistency(history, field, target_date, quarters, direction, value):
    """檢查「最近N季（以target_date當時已公告的為準）」是否每一季
    都符合門檻，用來判斷「能不能維持良好基本面」，不是只看單一
    時間點。"""

    available = [h for h in history if h["publish_date"] <= target_date]

    if len(available) < quarters:
        return False

    recent = available[-quarters:]

    for r in recent:

        v = r[field]

        if v is None:
            return False

        if direction == "above" and not (v > value):
            return False

        if direction == "below" and not (v < value):
            return False

    return True


def get_liquidity_value_asof(price_history, field, target_date, window_days=20):
    """
    price_history：已依日期排序的股價紀錄（含 close/volume/
    trading_money），取「target_date 當天或之前」最近 window_days
    個交易日的平均值，用來衡量流通性（不用單一天，避免被單一天
    的異常值誤導）。
    """

    available = [p for p in price_history if p["date"] <= target_date]

    if not available:
        return None

    window = available[-window_days:] if window_days else available

    values = [p[field] for p in window if p.get(field) is not None]

    if not values:
        return None

    return sum(values) / len(values)


def evaluate_screening_condition(condition, history, target_date, price_history=None):
    """
    選股用的條件判斷，跟逐日回測的 ConditionEvaluator 不同——
    這裡只需要判斷「某支股票在某個審核時間點」符不符合，不用算
    整條時間序列。

    支援：
    - fundamental_above / fundamental_below：單一時間點的門檻
      判斷，支援 operator 參數細分成 >、<、>=、<=、==（不給的話
      預設 fundamental_above=>、fundamental_below=<，向下相容）
    - fundamental_new_high：跟「最近N季」比較（不是跟資料庫裡
      全部歷史比），最新一季要高於這個範圍內其餘各季
    - fundamental_growth：成長幅度，跟N季前比較，成長率高於/
      低於門檻
    - fundamental_consistent：維持水準，最近N季每一季都要符合
      門檻（不是只有最新一季符合就算數）
    - liquidity_trading_value_above：近N日平均成交金額門檻
      （單位：億元），衡量流通性/規模是否足夠
    - liquidity_volume_above：近N日平均成交量門檻（單位：張）
    """

    ctype = condition["type"]

    if ctype in ("fundamental_above", "fundamental_below"):

        field = condition["field"]
        val = get_fundamental_value_asof(history, field, target_date)

        if val is None:
            return False

        operator = condition.get(
            "operator", ">" if ctype == "fundamental_above" else "<"
        )
        threshold = condition["value"]

        if operator == ">":
            return val > threshold
        elif operator == "<":
            return val < threshold
        elif operator == ">=":
            return val >= threshold
        elif operator == "<=":
            return val <= threshold
        elif operator == "==":
            return val == threshold

        return False

    elif ctype == "fundamental_new_high":

        field = condition["field"]
        # 比較範圍：最近幾季（不給就預設12季），不是跟資料庫裡
        # 全部歷史比較。
        quarters = condition.get("quarters", 12)

        available = [h for h in history if h["publish_date"] <= target_date]

        if len(available) < 2:
            return False

        window = available[-quarters:] if quarters else available

        latest = window[-1][field]
        previous = [h[field] for h in window[:-1] if h[field] is not None]

        if latest is None or not previous:
            return False

        return latest > max(previous)

    elif ctype == "fundamental_growth":

        field = condition["field"]
        quarters_back = condition.get("quarters_back", 4)
        direction = condition.get("direction", "above")
        threshold = condition["value"]

        current = get_fundamental_value_asof(history, field, target_date, 0)
        past = get_fundamental_value_asof(history, field, target_date, quarters_back)

        if current is None or past is None or past == 0:
            return False

        growth_pct = (current - past) / abs(past) * 100

        return growth_pct > threshold if direction == "above" else growth_pct < threshold

    elif ctype == "fundamental_consistent":

        field = condition["field"]
        quarters = condition.get("quarters", 4)
        direction = condition.get("direction", "above")
        threshold = condition["value"]

        return check_fundamental_consistency(
            history, field, target_date, quarters, direction, threshold
        )

    elif ctype == "liquidity_trading_value_above":

        if price_history is None:
            return False

        window_days = condition.get("window_days", 20)
        # 門檻單位是「億元」，price_history 裡的 trading_money 是「元」
        threshold_yi = condition["value"]

        avg_money = get_liquidity_value_asof(
            price_history, "trading_money", target_date, window_days
        )

        if avg_money is None:
            return False

        return (avg_money / 100000000) > threshold_yi

    elif ctype == "liquidity_volume_above":

        if price_history is None:
            return False

        window_days = condition.get("window_days", 20)
        # 門檻單位是「張」，price_history 裡的 volume 是「股」
        threshold_lots = condition["value"]

        avg_volume = get_liquidity_value_asof(
            price_history, "volume", target_date, window_days
        )

        if avg_volume is None:
            return False

        return (avg_volume / 1000) > threshold_lots

    elif ctype in ("price_above", "price_below"):

        if price_history is None:
            return False

        available = [p for p in price_history if p["date"] <= target_date]

        if not available:
            return False

        latest_close = available[-1]["close"]

        if latest_close is None:
            return False

        threshold = condition["value"]

        return latest_close > threshold if ctype == "price_above" else latest_close < threshold

    elif ctype == "price_vs_ma":

        if price_history is None:
            return False

        period = condition.get("period", 20)
        direction = condition.get("direction", "above")

        available = [p for p in price_history if p["date"] <= target_date]

        if len(available) < period:
            return False

        window = available[-period:]
        closes = [p["close"] for p in window if p["close"] is not None]

        if len(closes) < period:
            return False

        ma = sum(closes) / len(closes)
        latest_close = available[-1]["close"]

        if latest_close is None:
            return False

        return latest_close > ma if direction == "above" else latest_close < ma

    elif ctype == "volume_breakout":

        # 先在「target_date以前」的N天內，找出成交量最大的那一天
        # （代表當時有主力進出、法人表態），記下那天的最高價/
        # 最低價，判斷target_date當時的收盤價有沒有突破那個價位。
        # 邏輯跟逐日回測那邊的 volume_breakout 一致，只是這裡是
        # 對「單一時間點」判斷，不是對整條時間序列跑一次。
        if price_history is None:
            return False

        period = condition.get("period", 20)
        direction = condition.get("direction", "above")
        min_multiplier = condition.get("min_multiplier", 1.5)

        available = [p for p in price_history if p["date"] <= target_date]

        if len(available) < period + 1:
            return False

        latest = available[-1]
        window = available[-(period + 1):-1]  # 不含target_date當天

        window_volumes = [p["volume"] for p in window if p["volume"] is not None]

        if not window_volumes:
            return False

        window_avg = sum(window_volumes) / len(window_volumes)
        peak_volume = max(window_volumes)

        if window_avg == 0 or peak_volume < window_avg * min_multiplier:
            return False

        peak_day = next(p for p in window if p["volume"] == peak_volume)

        latest_close = latest["close"]

        if latest_close is None:
            return False

        if direction == "above":
            return peak_day["high"] is not None and latest_close > peak_day["high"]
        else:
            return peak_day["low"] is not None and latest_close < peak_day["low"]

    return False


def evaluate_screening_groups(groups, history, target_date, price_history=None):
    """OR 群組（跟逐日回測的邏輯一致）：只要有一個群組全部條件
    都成立，這支股票就算通過篩選"""

    if not groups:
        return False

    for group in groups:
        if group and all(
            evaluate_screening_condition(c, history, target_date, price_history)
            for c in group
        ):
            return True

    return False


_FIELD_LABELS = {
    "pe": "本益比", "eps": "EPS", "roe": "ROE", "roa": "ROA",
    "gross_margin": "毛利率", "operating_margin": "營業利益率",
    "revenue": "營收", "dividend_yield": "殖利率",
    "debt_ratio": "負債比", "free_cash_flow": "自由現金流",
}

_OPERATOR_LABELS = {">": ">", "<": "<", ">=": ">=", "<=": "<=", "==": "="}


def describe_matched_condition(condition, history, target_date, price_history=None):
    """
    把一個已經判定為「符合」的條件，轉成含實際數值的說明文字，
    例如「ROE 32.5 > 15」，不是只顯示條件本身的設定值，讓使用者
    知道「當時實際數字是多少、為什麼會通過」。
    """

    ctype = condition["type"]
    field = condition.get("field", "")
    label = _FIELD_LABELS.get(field, field)

    if ctype in ("fundamental_above", "fundamental_below"):

        val = get_fundamental_value_asof(history, field, target_date)
        op = _OPERATOR_LABELS.get(
            condition.get("operator", ">" if ctype == "fundamental_above" else "<"),
            ">"
        )
        val_text = f"{val:.2f}" if val is not None else "N/A"
        return f"{label} {val_text} {op} {condition['value']}"

    elif ctype == "fundamental_new_high":

        quarters = condition.get("quarters", 12)
        val = get_fundamental_value_asof(history, field, target_date)
        val_text = f"{val:.2f}" if val is not None else "N/A"
        return f"{label} {val_text}（近{quarters}季新高）"

    elif ctype == "fundamental_growth":

        quarters_back = condition.get("quarters_back", 4)
        current = get_fundamental_value_asof(history, field, target_date, 0)
        past = get_fundamental_value_asof(history, field, target_date, quarters_back)

        if current is not None and past is not None and past != 0:
            growth_pct = (current - past) / abs(past) * 100
            return f"{label} 跟{quarters_back}季前比成長 {growth_pct:.1f}%"

        return f"{label} 成長幅度符合條件"

    elif ctype == "fundamental_consistent":

        quarters = condition.get("quarters", 4)
        direction = condition.get("direction", "above")
        op = ">" if direction == "above" else "<"
        return f"{label} 連續{quarters}季都 {op} {condition['value']}"

    elif ctype == "liquidity_trading_value_above":

        window_days = condition.get("window_days", 20)

        if price_history is not None:
            avg = get_liquidity_value_asof(
                price_history, "trading_money", target_date, window_days
            )
            val_text = f"{avg/100000000:.1f}億" if avg is not None else "N/A"
            return f"近{window_days}日均成交額 {val_text} > {condition['value']}億"

        return f"近{window_days}日均成交額 > {condition['value']}億"

    elif ctype == "liquidity_volume_above":

        window_days = condition.get("window_days", 20)

        if price_history is not None:
            avg = get_liquidity_value_asof(
                price_history, "volume", target_date, window_days
            )
            val_text = f"{avg/1000:.0f}張" if avg is not None else "N/A"
            return f"近{window_days}日均成交量 {val_text} > {condition['value']}張"

        return f"近{window_days}日均成交量 > {condition['value']}張"

    elif ctype in ("price_above", "price_below"):

        op = ">" if ctype == "price_above" else "<"

        if price_history is not None:
            available = [p for p in price_history if p["date"] <= target_date]
            latest = available[-1]["close"] if available else None
            val_text = f"{latest:.1f}" if latest is not None else "N/A"
            return f"股價 {val_text} {op} {condition['value']}"

        return f"股價 {op} {condition['value']}"

    elif ctype == "price_vs_ma":

        period = condition.get("period", 20)
        direction = condition.get("direction", "above")
        op = "站上" if direction == "above" else "跌破"

        if price_history is not None:
            available = [p for p in price_history if p["date"] <= target_date]
            if len(available) >= period:
                closes = [p["close"] for p in available[-period:] if p["close"] is not None]
                ma = sum(closes) / len(closes) if closes else None
                latest = available[-1]["close"]
                if ma is not None and latest is not None:
                    return f"股價 {latest:.1f} {op} MA{period}({ma:.1f})"

        return f"股價 {op} MA{period}"

    elif ctype == "volume_breakout":

        period = condition.get("period", 20)
        direction = condition.get("direction", "above")
        op = "高點" if direction == "above" else "低點"
        return f"突破近{period}日大量日的{op}"

    return label


def evaluate_screening_groups_detailed(groups, history, target_date, price_history=None):
    """
    跟 evaluate_screening_groups 邏輯一樣（第一個全部條件都成立
    的群組就算通過），但額外回傳「是哪些條件讓它通過的」說明
    文字清單，給前端顯示用（例如「為什麼這次選了台積電」）。
    """

    if not groups:
        return False, []

    for group in groups:
        if group and all(
            evaluate_screening_condition(c, history, target_date, price_history)
            for c in group
        ):
            descriptions = [
                describe_matched_condition(c, history, target_date, price_history)
                for c in group
            ]
            return True, descriptions

    return False, []


def _add_months(d, months):
    """幫日期加上N個月，處理跨年、月底日期溢位（例如1/31加1個月
    要變成2/28，不是不存在的2/31）"""

    month_index = d.month - 1 + months
    year = d.year + month_index // 12
    month = month_index % 12 + 1

    days_in_month = [
        31, 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28,
        31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
    ]

    day = min(d.day, days_in_month[month - 1])

    return date(year, month, day)


def compute_rebalance_dates(start_date, end_date, rebalance_months):

    start = datetime.strptime(start_date, "%Y-%m-%d").date()
    end = datetime.strptime(end_date, "%Y-%m-%d").date()

    dates = []
    current = start

    while current <= end:
        dates.append(current.isoformat())
        current = _add_months(current, rebalance_months)

    return dates


def get_price_series_for_liquidity(code):
    """
    取得一支股票完整的股價歷史序列（date/close/high/low/volume/
    trading_money），給選股策略的「流通性」跟「價格條件」共用
    ——原本只抓量跟金額，現在也把 close/high/low 一起抓進來，
    這樣「股價>X」「站上均線」「突破大量日高低點」這幾種價格
    相關條件在選股模式下才有資料可以判斷。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT date, close, high, low, volume, trading_money FROM prices
        WHERE code = ?
        ORDER BY date ASC
    """, (code,))

    rows = cur.fetchall()
    conn.close()

    return [
        {
            "date": r["date"], "close": r["close"], "high": r["high"],
            "low": r["low"], "volume": r["volume"],
            "trading_money": r["trading_money"],
        }
        for r in rows
    ]


    """direction="after"：找 target_date 當天或之後最近的一個交易日
    direction="before"：找 target_date 當天或之前最近的一個交易日"""

    conn = get_connection()
    cur = conn.cursor()

    if direction == "after":
        cur.execute("""
            SELECT date, close FROM prices
            WHERE code = ? AND date >= ?
            ORDER BY date ASC LIMIT 1
        """, (code, target_date))
    else:
        cur.execute("""
            SELECT date, close FROM prices
            WHERE code = ? AND date <= ?
            ORDER BY date DESC LIMIT 1
        """, (code, target_date))

    row = cur.fetchone()
    conn.close()

    if not row:
        return None

    return {"date": row["date"], "close": row["close"]}


def get_price_near_date(code, target_date, direction="after"):
    """direction="after"：找 target_date 當天或之後最近的一個交易日
    direction="before"：找 target_date 當天或之前最近的一個交易日
    （回測結束時的最終估值用這個，不用 T+1 那個版本，因為結束時
    沒有「下一個交易日」的概念，只需要「最後能看到的價格」）"""

    conn = get_connection()
    cur = conn.cursor()

    if direction == "after":
        cur.execute("""
            SELECT date, close FROM prices
            WHERE code = ? AND date >= ?
            ORDER BY date ASC LIMIT 1
        """, (code, target_date))
    else:
        cur.execute("""
            SELECT date, close FROM prices
            WHERE code = ? AND date <= ?
            ORDER BY date DESC LIMIT 1
        """, (code, target_date))

    row = cur.fetchone()
    conn.close()

    if not row:
        return None

    return {"date": row["date"], "close": row["close"]}


def get_next_trading_day_price(code, audit_date):
    """
    找「嚴格晚於 audit_date」的下一個交易日價格（不是audit_date
    當天）。用來實作「審核日收盤後選股，下一個有效交易日才真正
    買賣」——不能用審核當天的收盤價直接成交，那樣等於用了審核
    當下還沒實際發生的成交資訊。
    """

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT date, close FROM prices
        WHERE code = ? AND date > ?
        ORDER BY date ASC LIMIT 1
    """, (code, audit_date))

    row = cur.fetchone()
    conn.close()

    if not row:
        return None

    return {"date": row["date"], "close": row["close"]}


def run_screener_backtest(
    screening_groups,
    start_date,
    end_date,
    rebalance_months=6,
    max_stocks=None,
    rank_by=None,
    rank_direction="desc",
    initial_capital=1000000,
    fee_discount=None,
):
    """
    選股策略回測（第一版）：

    - 每隔 rebalance_months 個月審核一次：用「審核日當天收盤前
      已公開」的財報資料篩選（避免未來偷看），但**實際買賣執行
      在審核日之後的下一個交易日**，不是審核當天收盤價直接成交
      ——因為審核當下不可能知道自己「當天收盤價」會是多少就先
      決定要不要交易，這樣會有未來資訊問題。
    - 如果符合條件的股票數量超過 max_stocks，用 rank_by 欄位排序
      （rank_direction 決定高到低還是低到高），只留前 max_stocks 名；
      max_stocks 是 None 代表不限制數量，全部納入
    - 每次換股是「全部清倉、重新等權重買入」，不是只調整增減碼的
      部位（第一版簡化，之後可以再做成只調整有變動的部位，即使
      某支股票連續兩次都符合條件，也會先賣出再買回，多付一次
      手續費/交易稅，這是真實成本，不是bug）
    - 手續費／交易稅比照 App 其他回測模式同一套規則
    """

    rebalance_dates = compute_rebalance_dates(start_date, end_date, rebalance_months)

    if len(rebalance_dates) < 2:
        return {"error": "回測期間太短，至少要涵蓋兩次審核區間"}

    all_codes = get_all_stock_codes()

    # 每支股票的財報歷史、股價歷史都只抓一次、快取起來，不要每個
    # 審核時間點都重查一次資料庫（全市場股票數量很多，這樣會
    # 非常慢）。
    history_cache = {code: get_financial_history(code) for code in all_codes}
    price_history_cache = {
        code: get_price_series_for_liquidity(code) for code in all_codes
    }

    asset_type_cache = {code: get_asset_type(code) for code in all_codes}

    fee_rate = (
        RAW_FEE_RATE * (fee_discount / 10) if fee_discount else RAW_FEE_RATE
    )

    # rank_by 支援兩種格式：
    # - 舊版：單一字串（例如 "roe"），向下相容
    # - 新版：多欄位清單 [{"field": "roe", "direction": "desc"}, ...]
    #   用來做「多條件排名」，第一個欄位優先，後面的欄位當同分時
    #   的排序依據（tie-breaker）
    if rank_by is None:
        rank_fields = []
    elif isinstance(rank_by, str):
        rank_fields = [{"field": rank_by, "direction": rank_direction}]
    else:
        rank_fields = rank_by

    _LIQUIDITY_RANK_FIELDS = {
        "liquidity_trading_value": "trading_money",
        "liquidity_volume": "volume",
    }

    def get_rank_value(code, field, target_date):

        if field in _LIQUIDITY_RANK_FIELDS:
            ph = price_history_cache.get(code, [])
            return get_liquidity_value_asof(
                ph, _LIQUIDITY_RANK_FIELDS[field], target_date, 20
            )

        return get_fundamental_value_asof(history_cache.get(code, []), field, target_date)

    def apply_multi_key_ranking(codes, target_date):
        """
        依 rank_fields 做多欄位排名：第一個欄位優先排序，後面的
        欄位在前面欄位同分時當 tie-breaker。用「從最後一個欄位
        排到第一個欄位」、每次都用穩定排序（stable sort）的方式
        實作——Python 的 sort 是穩定的，這樣疊代下來，最後結果會
        正確反映「第一個欄位優先」的排序。
        """

        result = list(codes)

        for rf in reversed(rank_fields):

            field = rf["field"]
            direction = rf.get("direction", "desc")

            def key_fn(code, field=field, direction=direction):
                v = get_rank_value(code, field, target_date)
                if v is not None:
                    return v
                return float("-inf") if direction == "desc" else float("inf")

            result.sort(key=key_fn, reverse=(direction == "desc"))

        return result

    combined_curve = []
    all_trades = []
    all_selections = []  # 每次審核選出的成分股清單，回傳給前端顯示

    total_fee = 0.0
    total_tax = 0.0

    # 跨審核期間持續追蹤的持股狀態：code -> {"shares": 股數, "total_cost": 目前持股的總成本}
    # 用加權平均成本法，買進時把新成本併入、賣出時依比例扣減，
    # 這樣才能正確算出「部分加減碼」下每一筆交易的損益，不是
    # 只能算「整批買進、整批賣出」這種簡單配對。
    holdings_state = {}
    cash = initial_capital

    # 加減碼的門檻：目標金額跟目前部位差距太小（例如小於總資產的
    # 0.5%）就不動作，避免因為股價正常波動就一直做微幅調整、
    # 白白付手續費。
    REBALANCE_THRESHOLD_PCT = 0.005

    # 股利只算現金股利（跟庫存股頁面/其他回測引擎同一個決定），
    # last_dividend_check_date 記錄「上次已經結算過股利到哪一天」，
    # 避免同一筆股利被重複算兩次。
    total_dividend = 0.0
    last_dividend_check_date = start_date

    def get_tax_rate(code):
        return (
            ETF_TAX_RATE if (asset_type_cache.get(code) or "").upper() == "ETF"
            else STOCK_TAX_RATE
        )

    for period_i in range(len(rebalance_dates) - 1):

        period_start = rebalance_dates[period_i]
        period_end = rebalance_dates[period_i + 1]

        # 用「這個審核時間點以前已公告」的財報篩選，避免未來偷看
        qualified = []
        matched_reasons = {}  # code -> 觸發的條件說明清單

        for code in all_codes:

            history = history_cache.get(code, [])

            if not history:
                continue

            price_history = price_history_cache.get(code, [])

            matched, reasons = evaluate_screening_groups_detailed(
                screening_groups, history, period_start, price_history
            )

            if matched:
                qualified.append(code)
                matched_reasons[code] = reasons

        if max_stocks is not None and len(qualified) > max_stocks and rank_fields:

            qualified = apply_multi_key_ranking(qualified, period_start)
            qualified = qualified[:max_stocks]

        all_selections.append({
            "date": period_start,
            "codes": qualified,
            "reasons": {code: matched_reasons.get(code, []) for code in qualified},
        })

        # 審核日收盤後選股，實際換股在下一個交易日（T+1）成交，
        # 不是審核當天就用收盤價直接買賣。這裡先把「這次會用到的
        # 股票（目前持有的+新篩選出來的）」的成交價都查好。
        codes_involved = set(holdings_state.keys()) | set(qualified)
        exec_prices = {}

        for code in codes_involved:
            p = get_next_trading_day_price(code, period_start)
            if p:
                exec_prices[code] = p

        # 在做任何這次的買賣調整之前，先把「上次審核到這次審核
        # 之間」持續持有的股票，領到的現金股利結算進現金部位，
        # 避免因為改成部分調整之後，股票可能從頭到尾都沒被賣過、
        # 導致股利完全沒被算進去。
        for code, state in list(holdings_state.items()):

            events = get_dividend_events(code, last_dividend_check_date, period_start)

            for ex_date, div_per_share in events.items():
                dividend_income = state["shares"] * div_per_share
                cash += dividend_income
                total_dividend += dividend_income

            # 除權：這段期間如果配股、分割或減資，持股數要跟著變。
            # 沒有這一段的話，除權後股價腰斬但股數不變，帳面市值
            # 會憑空蒸發一半，整個投組配置就跟著錯掉。
            #
            # 順序跟股利一致：現金按調整前的股數算，再改股數。
            ratios = get_share_ratio_events(
                code, last_dividend_check_date, period_start
            )

            for ex_date, ratio in ratios.items():
                state["shares"] *= ratio

        last_dividend_check_date = period_start

        # 用這次的成交價，把目前持股（含現金）的總市值算出來，
        # 當作這次分配的基準。
        portfolio_value = cash

        for code, state in holdings_state.items():
            if code in exec_prices:
                portfolio_value += state["shares"] * exec_prices[code]["close"]
            else:
                # 這支股票這次沒查到成交價（可能下市/停牌），
                # 用上次記錄的成本當作它現在的價值，不要憑空消失。
                portfolio_value += state["total_cost"]

        target_value_per_stock = (
            portfolio_value / len(qualified) if qualified else 0
        )

        # 第一步：不再符合條件的股票，全部賣出
        for code in list(holdings_state.keys()):

            if code in qualified:
                continue

            state = holdings_state[code]
            shares = state["shares"]

            if shares <= 0 or code not in exec_prices:
                del holdings_state[code]
                continue

            price = exec_prices[code]["close"]
            proceeds = shares * price
            sell_fee = round(proceeds * fee_rate)
            sell_tax = round(proceeds * get_tax_rate(code))
            net_proceeds = proceeds - sell_fee - sell_tax

            profit = net_proceeds - state["total_cost"]

            cash += net_proceeds
            total_fee += sell_fee
            total_tax += sell_tax

            all_trades.append({
                "date": exec_prices[code]["date"], "action": "sell",
                "price": price, "shares": shares,
                "profit": round(profit, 2), "code": code,
            })

            del holdings_state[code]

        # 第二步：符合條件的股票，依目標金額做加碼或減碼
        # （不是整批賣掉重買，同樣在名單裡的股票只調整差額）
        for code in qualified:

            if code not in exec_prices:
                # 沒有成交價可用，這次沒辦法調整，維持原狀
                continue

            price = exec_prices[code]["close"]
            state = holdings_state.get(code, {"shares": 0, "total_cost": 0.0})
            current_shares = state["shares"]
            current_value = current_shares * price

            diff_value = target_value_per_stock - current_value
            threshold = portfolio_value * REBALANCE_THRESHOLD_PCT

            if diff_value > threshold:

                # 加碼：買進差額部分。如果目標金額因為賣出其他
                # 股票的摩擦成本（手續費/交易稅）導致現金差一點
                # 不夠，不要整筆放棄不買，改成「現金夠買多少就買
                # 多少」。
                buy_shares = int(diff_value / (price * (1 + fee_rate)))
                max_affordable_shares = int(cash / (price * (1 + fee_rate)))
                buy_shares = min(buy_shares, max_affordable_shares)

                if buy_shares > 0:

                    buy_cost = buy_shares * price
                    buy_fee = round(buy_cost * fee_rate)
                    total_spend = buy_cost + buy_fee

                    if total_spend <= cash:

                        cash -= total_spend
                        total_fee += buy_fee

                        state["shares"] = current_shares + buy_shares
                        state["total_cost"] = state["total_cost"] + buy_cost + buy_fee
                        holdings_state[code] = state

                        all_trades.append({
                            "date": exec_prices[code]["date"], "action": "buy",
                            "price": price, "shares": buy_shares,
                            "profit": None, "code": code,
                        })

            elif diff_value < -threshold and current_shares > 0:

                # 減碼：賣出多餘部分
                sell_shares = min(current_shares, int(-diff_value / price))

                if sell_shares > 0:

                    proceeds = sell_shares * price
                    sell_fee = round(proceeds * fee_rate)
                    sell_tax = round(proceeds * get_tax_rate(code))
                    net_proceeds = proceeds - sell_fee - sell_tax

                    # 賣掉的這部分，依加權平均成本比例扣減
                    avg_cost_per_share = state["total_cost"] / current_shares
                    realized_cost = avg_cost_per_share * sell_shares
                    profit = net_proceeds - realized_cost

                    cash += net_proceeds
                    total_fee += sell_fee
                    total_tax += sell_tax

                    state["shares"] = current_shares - sell_shares
                    state["total_cost"] = state["total_cost"] - realized_cost
                    holdings_state[code] = state

                    all_trades.append({
                        "date": exec_prices[code]["date"], "action": "sell",
                        "price": price, "shares": sell_shares,
                        "profit": round(profit, 2), "code": code,
                    })

            # 差距在門檻內：不動作，維持原持股

        # 這次調整完之後，用調整當下的成交價重新估一次總資產，
        # 記錄到資產曲線上。
        period_value = cash
        for code, state in holdings_state.items():
            if code in exec_prices:
                period_value += state["shares"] * exec_prices[code]["close"]
            else:
                period_value += state["total_cost"]

        combined_curve.append({
            "date": period_start, "value": round(period_value, 2)
        })

    # 回測結束：用最後一個交易日的股價，把目前持股估值，當作
    # 最終資產（不強制真的賣掉，跟庫存股頁面的「未實現市值」
    # 概念一致）。

    # 最後一次審核到回測結束這段期間，還在持有的股票如果有除息，
    # 這裡結算，不然這段最後的股利會漏掉。
    for code, state in list(holdings_state.items()):

        events = get_dividend_events(code, last_dividend_check_date, end_date)

        for ex_date, div_per_share in events.items():
            dividend_income = state["shares"] * div_per_share
            cash += dividend_income
            total_dividend += dividend_income

    final_value = cash
    unrealized_entries = []  # 只給統計指標用，不會出現在交易紀錄清單裡

    for code, state in holdings_state.items():

        last_price = get_price_near_date(code, end_date, direction="before")

        if last_price:

            market_value = state["shares"] * last_price["close"]
            final_value += market_value

            # 回測結束時還在持有、沒有真的賣掉的部位，如果完全不
            # 計入交易次數/勝率統計，會導致「明明賺錢的策略，
            # 勝率/交易次數卻顯示0」這種誤導人的結果——因為這次
            # 改成部分調整之後，表現好的股票很可能從頭到尾都沒被
            # 賣過。這裡用「未實現損益」補進統計用的清單，但不會
            # 出現在使用者看到的交易紀錄裡（那個要保持只顯示真正
            # 發生過的交易）。
            unrealized_profit = market_value - state["total_cost"]

            unrealized_entries.append({
                "date": end_date, "action": "sell",
                "price": last_price["close"], "shares": state["shares"],
                "profit": round(unrealized_profit, 2), "code": code,
            })

        else:
            final_value += state["total_cost"]

    combined_curve.append({"date": end_date, "value": round(final_value, 2)})

    if not combined_curve:
        return {"error": "沒有產生任何資產曲線資料"}

    trades_for_metrics = all_trades + unrealized_entries

    metrics = calculate_metrics(combined_curve, initial_capital, final_value, trades_for_metrics)

    return {
        "asset_curve": combined_curve,
        "trades": all_trades,
        "metrics": metrics,
        "selections": all_selections,
        "initial_capital": initial_capital,
        "final_value": round(final_value, 2),
        "total_fee": round(total_fee, 2),
        "total_tax": round(total_tax, 2),
        "total_dividend": round(total_dividend, 2),
        "open_positions_count": len(holdings_state),
    }


# =====================
# 定期定額（第一版）
# =====================
#
# 跟其他回測模式不一樣：資金不是一開始就全部到位，是每隔固定
# 期間投入固定金額。這代表「年化報酬率」不能直接套用其他模式
# 的CAGR公式（那個公式假設全部資金從第一天就開始成長，如果拿
# 來算定期定額會嚴重高估報酬率，因為大部分錢其實是後來才投入
# 的）。這裡改用「年化內部報酬率（XIRR）」，會把每一筆投入
# 「當下的時間點」也算進去，才是正確反映定期定額真實報酬率的
# 算法。


def xirr(cash_flows):
    """
    cash_flows: [(date, amount), ...]，amount 負數代表投入的錢
    （現金流出），正數代表最後拿回的錢（現金流入）。用二分搜尋
    找出讓「現金流折現後總和=0」的年化報酬率。

    這個算法假設現金流只有一次正負號轉換（先持續投入、最後一次
    拿回全部），這是定期定額的標準情境，符合的話二分搜尋是穩定
    可靠的；如果現金流正負號變化更複雜，二分搜尋可能找不到正確
    的根，但這裡的使用情境不會有這種狀況。
    """

    if not cash_flows:
        return 0.0

    d0 = cash_flows[0][0]

    def npv(rate):
        total = 0.0
        for date, amount in cash_flows:
            days = (date - d0).days
            total += amount / ((1 + rate) ** (days / 365))
        return total

    low, high = -0.99, 10.0

    npv_low = npv(low)
    npv_high = npv(high)

    # 現金流全部同號（例如從頭到尾都虧損到歸零以下這種極端狀況），
    # 二分搜尋的前提不成立，直接回傳0，不要硬跑出一個沒意義的數字
    if npv_low * npv_high > 0:
        return 0.0

    mid = 0.0

    for _ in range(100):

        mid = (low + high) / 2
        val = npv(mid)

        if abs(val) < 1e-6:
            break

        if (val > 0) == (npv_low > 0):
            low = mid
        else:
            high = mid

    return mid * 100


def run_dca_backtest(
    code,
    start_date,
    end_date,
    amount_per_period,
    interval_months=1,
    fee_discount=None,
    reinvest_dividends=False,
):
    """
    定期定額回測。改成逐日推進（原本一個月才記一個點），這樣
    回撤和 Sharpe 才有意義，除權除息也才能落在正確的日子上。

    允許買零股，跟券商的定期定額服務一致。

    reinvest_dividends：現金股利要不要在除息日換算成股數投入。
      False（預設）＝ 股利存現金，貼近實際體驗
      True         ＝ 股利再投入，才會等同 corporate_actions.TOTAL 的
                      還原股價報酬率。兩種算法本身都對，但不能
                      混用——比較不同標的時要用同一種。
    """

    invest_dates = compute_rebalance_dates(start_date, end_date, interval_months)

    if len(invest_dates) < 2:
        return {"error": "回測期間太短，至少要涵蓋兩次扣款區間"}

    history = get_price_history(code, start_date, end_date)

    if not history:
        return {"error": "這段期間沒有股價資料"}

    asset_type = get_asset_type(code)
    fee_rate = RAW_FEE_RATE * (fee_discount / 10) if fee_discount else RAW_FEE_RATE

    cash_events = get_dividend_events(code, start_date, end_date)
    ratio_events = get_share_ratio_events(code, start_date, end_date)

    pending = sorted(invest_dates)

    total_shares = 0.0
    total_invested = 0.0
    total_fee = 0.0
    total_dividend = 0.0

    trades = []
    asset_curve = []
    cash_flows = []

    # 單位淨值：把每次扣款當成「用當時淨值申購單位」，算出來的
    # 曲線不受現金流影響。回撤和 Sharpe 要用這條，不能用市值曲線
    # ——市值每次扣款都會跳升，會被誤判成暴賺。
    nav = 100.0
    units = 0.0
    nav_curve = []

    for bar in history:

        d = bar["date"]
        price = bar["close"]

        if price is None or price <= 0:
            continue

        # 1) 除息：現金股利按「調整前」的股數計算。台股除權息通常
        #    同一天，配息和配股都是以除權息基準日的持股數為準，
        #    所以要先算現金、再補股數，順序顛倒會多算一倍。
        if d in cash_events:

            income = total_shares * cash_events[d]

            if reinvest_dividends:
                # 用除息後的參考價買回，跟 TOTAL 還原價的定義一致
                total_shares += income / price
            else:
                total_dividend += income

        # 2) 除權：補進配股，之後就用當天（已扣抵）的股價計價
        if d in ratio_events:
            total_shares *= ratio_events[d]

        # 3) 先用「扣款前」的市值更新單位淨值，再處理今天的扣款。
        #    順序不能顛倒，否則新投入的錢會被算成當日報酬。
        value_before = total_shares * price + total_dividend

        if units > 0:
            nav = value_before / units

        bought = 0.0

        while pending and pending[0] <= d:

            pending.pop(0)

            buy_fee = round(amount_per_period * fee_rate)
            net_amount = amount_per_period - buy_fee

            if net_amount <= 0:
                continue

            shares_bought = net_amount / price

            total_shares += shares_bought
            total_invested += amount_per_period
            total_fee += buy_fee
            bought += amount_per_period

            units += amount_per_period / nav

            cash_flows.append((datetime.strptime(d, "%Y-%m-%d"), -amount_per_period))

            trades.append({
                "date": d, "action": "buy",
                "price": price, "shares": round(shares_bought, 4),
                "profit": None, "code": code,
            })

        # 4) 收盤時的市值與淨值
        value = total_shares * price + total_dividend

        if units > 0:
            nav = value / units
            nav_curve.append({"date": d, "nav": round(nav, 6)})

        asset_curve.append({
            "date": d,
            "value": round(value, 2),
            "invested": round(total_invested, 2),
        })

    if not trades:
        return {"error": "回測期間內沒有成功執行任何一次扣款，請確認股票代號或期間是否正確"}

    last = asset_curve[-1]
    final_price = history[-1]["close"]
    final_value = last["value"]

    cash_flows.append((datetime.strptime(last["date"], "%Y-%m-%d"), final_value))

    annualized_return_pct = xirr(cash_flows)

    total_return_pct = (
        (final_value - total_invested) / total_invested * 100
        if total_invested else 0
    )

    avg_cost = total_invested / total_shares if total_shares else 0
    market_value = total_shares * final_price
    unrealized = market_value - total_invested

    # ---- 回撤：用單位淨值，不是市值 ----
    max_dd = 0.0
    peak = nav_curve[0]["nav"] if nav_curve else 0

    for p in nav_curve:
        if p["nav"] > peak:
            peak = p["nav"]
        dd = (p["nav"] - peak) / peak * 100 if peak > 0 else 0
        max_dd = min(max_dd, dd)

    # ---- 帳面虧損：定期定額使用者更在意這個 ----
    max_loss = 0.0

    for p in asset_curve:
        if p["invested"] > 0:
            loss = (p["value"] - p["invested"]) / p["invested"] * 100
            max_loss = min(max_loss, loss)

    # ---- Sharpe：用淨值的日報酬，年化係數 252 ----
    rets = []

    for i in range(1, len(nav_curve)):
        a, b = nav_curve[i - 1]["nav"], nav_curve[i]["nav"]
        if a > 0:
            rets.append((b - a) / a)

    if len(rets) > 1:
        mean_r = sum(rets) / len(rets)
        var = sum((r - mean_r) ** 2 for r in rets) / len(rets)
        std_r = var ** 0.5
        sharpe = (mean_r / std_r * (252 ** 0.5)) if std_r > 0 else 0
    else:
        sharpe = 0

    metrics = {
        "total_return": round(total_return_pct, 2),
        "cagr": round(annualized_return_pct, 2),
        "max_drawdown": round(max_dd, 2),
        "max_paper_loss": round(max_loss, 2),
        "sharpe": round(sharpe, 2),
        "win_rate": 100.0 if final_value > total_invested else 0.0,
        "trade_count": len(trades),
    }

    return {
        "asset_curve": asset_curve,
        "nav_curve": nav_curve,
        "trades": trades,
        "metrics": metrics,
        "total_invested": round(total_invested, 2),
        "final_value": round(final_value, 2),
        "total_fee": round(total_fee, 2),
        "total_dividend": round(total_dividend, 2),
        "total_shares": round(total_shares, 4),
        "avg_cost": round(avg_cost, 2),
        "current_price": round(final_price, 2),
        "market_value": round(market_value, 2),
        "unrealized_profit": round(unrealized, 2),
        "share_ratio_events": len(ratio_events),
        "reinvest_dividends": reinvest_dividends,
        "dividend_events": len(cash_events),
    }