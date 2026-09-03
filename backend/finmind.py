import os
import time
import requests
from dotenv import load_dotenv

load_dotenv()

# 修正：os.getenv() 的參數要是「環境變數的名字」，不是 token 本身。
# 原本寫法等於在找一個名字剛好叫做那串 JWT 的環境變數（幾乎不可能
# 存在），永遠回傳 None，代表 TOKEN 一直都沒有真正生效。
#
# 這裡改成：從 .env 檔案讀取名為 FINMIND_TOKEN 的環境變數；如果
# 你的 .env 裡還沒有這個變數，請新增一行：
#   FINMIND_TOKEN=你的token
TOKEN = os.getenv("FINMIND_TOKEN")

if not TOKEN:
    print(
        "⚠️ 警告：找不到環境變數 FINMIND_TOKEN，目前會用匿名（未登入）"
        "身份呼叫 FinMind API，額度限制會更嚴格，付費方案的權限也不會生效。"
        "請在 .env 檔案加上一行 FINMIND_TOKEN=你的token"
    )

BASE_URL = "https://api.finmindtrade.com/api/v4/data"


class QuotaError(Exception):
    """FinMind 每小時額度用完（HTTP 402）"""
    pass


def request_dataset(
    dataset: str,
    stock_id: str,
    start_date: str = "2000-01-01",
    retry: int = 3,
):
    """
    共用 FinMind API

    Parameters
    ----------
    dataset : TaiwanStockPrice、TaiwanStockFinancialStatements...
    stock_id : 股票代號
    start_date : 起始日期 yyyy-mm-dd
    retry : 重試次數

    Returns
    -------
    list
    """

    params = {
        "dataset": dataset,
        "data_id": stock_id,
        "start_date": start_date,
        "token": TOKEN,
    }

    last_error = None

    for i in range(retry):

        try:

            response = requests.get(
                BASE_URL,
                params=params,
                timeout=30,
            )

            # 402 = 額度用完。重試沒有意義，而且每重試一次就
            # 再消耗一次額度，等於把失敗成本乘以 retry 次數。
            # 這裡直接中斷，並且不要把原始例外接上去——
            # requests 的 HTTPError 訊息含完整 URL，token 會外洩。
            if response.status_code == 402:
                raise QuotaError(
                    f"FinMind 額度用完 ({dataset} {stock_id})"
                ) from None

            response.raise_for_status()

            data = response.json()

            if data.get("status") != 200:
                # 把 FinMind 實際回傳的錯誤訊息完整拋出，
                # 不要吞掉——如果是「此資料集需要付費方案」
                # 這類訊息，呼叫端才看得到。
                raise Exception(
                    f"FinMind Error (status={data.get('status')}): "
                    f"{data.get('msg', '未知錯誤')}"
                )

            return data.get("data", [])

        except QuotaError:
            raise

        except requests.HTTPError as e:

            # 同樣避免 token 出現在錯誤訊息裡
            code = e.response.status_code if e.response is not None else "?"
            last_error = RuntimeError(
                f"FinMind HTTP {code} ({dataset} {stock_id})"
            )

            if i < retry - 1:
                time.sleep(1)

        except Exception as e:

            last_error = e

            if i < retry - 1:
                time.sleep(1)

    raise last_error


def get_stock_price(
    stock_id: str,
    start_date: str = "2000-01-01",
):
    """
    抓股價
    """

    return request_dataset(
        "TaiwanStockPrice",
        stock_id,
        start_date,
    )


def get_income_statement(stock_id: str):
    """
    損益表
    """

    return request_dataset(
        "TaiwanStockFinancialStatements",
        stock_id,
    )


def get_balance_sheet(stock_id: str):
    """
    資產負債表
    """

    return request_dataset(
        "TaiwanStockBalanceSheet",
        stock_id,
    )


def get_cash_flow(stock_id: str):
    """
    現金流量表
    """

    return request_dataset(
        "TaiwanStockCashFlowsStatement",
        stock_id,
    )


def get_historical_valuation(stock_id: str):
    """
    歷史 PE / PB / 殖利率
    """

    return request_dataset(
        "TaiwanStockPER",
        stock_id,
    )