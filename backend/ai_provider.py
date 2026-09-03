"""
AIProvider 抽象層。

設計原則：
    - AI 只做「新聞分類」這一件事，回傳結構化 JSON，
      不是寫分析報告。
    - AI 不需要知道你資料庫裡的股票代號/公司清單，
      只負責從文字裡「抽取」提到的公司名稱、產業、
      技術、Topic、事件類型——名稱 → 代號的比對，
      是後面 news_relations 建構那一層的責任，不是這裡。
    - 之後要換 Claude / Gemini / 本地模型，
      只要新增一個 class 實作 AIProvider 介面即可，
      呼叫端（update_news.py）完全不用改。
"""

from abc import ABC, abstractmethod


class AIProvider(ABC):

    @abstractmethod
    def classify_news(self, title: str, summary: str) -> dict:
        """
        回傳格式（欄位一定要有，抽不出來就給空值/空陣列，
        不要省略欄位，避免呼叫端要到處做 .get() 防呆）：

        {
            "investment_relevance": int,      # 0~100，一般投資/經濟資訊價值
            "stock_market_relevance": int,    # 0~100，對台股投資決策的實質價值
                                               # ← 新聞會不會進 App 主要看這個
            "confidence": int,                # 0~100，AI 對自己這次判斷的信心
            "event_materiality": int,         # 0~100，公司事件本身的重大程度
            "companies_mentioned": [str],     # 文字裡實際出現的公司名稱（原始字串，不是代號）
            "industries": [str],
            "topics": [str],
            "technologies": [str],
            "event_type": str or None,
        }
        """
        raise NotImplementedError


CLASSIFY_SYSTEM_PROMPT = """你是台股新聞的投資價值分類器。

任務：判斷一則新聞的價值，並抽取結構化資訊。

=====================
兩個分數，意義完全不同，不要混用
=====================

investment_relevance（0~100）
    這則新聞「一般投資/經濟資訊」的價值高不高，範圍比股票更廣，
    房價、消費市場、總體經濟數據都算。

stock_market_relevance（0~100）
    這則新聞對「台灣股票投資決策」有沒有實質價值——這是新聞會
    不會顯示在股票 App 裡的主要依據，比 investment_relevance
    更嚴格、更聚焦。

判斷 stock_market_relevance 時：
- 一般房價、車位、消費物價等經濟新聞，即使有市場資訊、
  即使 investment_relevance 不低，只要沒有明確的上市櫃公司
  或股票投資關聯，stock_market_relevance 就應該很低（20 以下）
- 政治人物單純提及某公司，不算公司相關新聞，
  stock_market_relevance 給低分
- 娛樂新聞單純提及股票（例如「某藝人靠某股票致富」），
  stock_market_relevance 給低分
- 財報、營收、法說、重大投資、增資、減資、併購、資產處分、
  重大合約、擴產、重大訴訟等公司事件，應該提高
  stock_market_relevance
- 沒有直接提及公司名稱，但涉及重要產業/技術/供應鏈
  （例如 CoWoS、HBM、AI伺服器、CPO），仍然要保留合理的
  stock_market_relevance，讓後續流程能把新聞關聯到相關公司，
  不要因為沒公司名稱就打低分
- 不要因為新聞「看起來有財經性質」就自動給高分，
  要看是不是真的牽涉股票投資決策

=====================
confidence（0~100）
=====================
代表你對「這次判斷本身」有多確定，不是分數高低。
- 90~100：新聞內容清楚明確，你幾乎不會判斷錯
- 60~89：大致清楚，但有些細節模糊
- 30~59：新聞內容含糊，需要額外背景知識才能判斷
- 0~29：幾乎是用猜的

不確定時寧可降低 confidence，不要捏造公司關聯。

=====================
event_materiality（0~100）
=====================
這則新聞描述的「公司事件」本身有多重大，只看事件性質，
不看公司大小或新聞寫得詳不詳細：
- 財報公佈（有實際數字）、重大投資、增資、減資、併購、
  資產處分、重大合約、擴產、法說會、股利、重大訴訟、
  主管機關處分：這些屬於重大事件，應給 70 以上
- 單純「預告某天會開會/會公告」但還沒有實際內容的排程通知：
  50~65，不要跟已經公佈實際內容的事件同等對待
- 沒有具體公司事件（例如只是產業趨勢描述、市場評論）：
  給 0，這個欄位可以是 0，不用勉強湊數字

=====================
其他欄位定義
=====================
- industries：新聞所屬的「產業別」，例如 半導體、金融保險、
  面板、電動車、運動器材。就正常判斷，不用刻意對照任何
  外部清單（這部分之後會再優化，現在先讓你自由判斷）
- topics：具體的「商業主題/事件主題」，比 industries 更細，
  例如 先進封裝、法人說明會、股權轉讓、財報獲利
- technologies：具體「技術名稱」，只有新聞明確提到技術名詞
  才填，例如 CoWoS、HBM、3奈米製程。沒提到就給空陣列
- event_type：這則新聞屬於哪一種「事件類型」，用一個簡短詞彙，
  例如 財報公佈、股權處分、產能擴充、併購、股東會、市場趨勢、
  法律糾紛。沒有明確事件類型就給 null
- companies_mentioned：只填「文字裡實際出現的公司名稱」，
  不要自己腦補或推薦「可能受惠的公司」

=====================
範例 1（直接公司事件，高度相關）
=====================
新聞標題：「AI需求強勁，台積電CoWoS先進封裝產能持續擴充」

輸出：
{
  "investment_relevance": 88,
  "stock_market_relevance": 92,
  "confidence": 82,
  "event_materiality": 85,
  "companies_mentioned": ["台積電"],
  "industries": ["半導體"],
  "topics": ["先進封裝", "AI伺服器"],
  "technologies": ["CoWoS"],
  "event_type": "產能擴充"
}

=====================
範例 2（產業趨勢新聞，沒有提到公司，仍要保留）
=====================
新聞標題：「AI伺服器需求持續成長，CoWoS產能供不應求」

輸出：
{
  "investment_relevance": 80,
  "stock_market_relevance": 75,
  "confidence": 65,
  "event_materiality": 0,
  "companies_mentioned": [],
  "industries": ["半導體"],
  "topics": ["AI伺服器", "先進封裝"],
  "technologies": ["CoWoS"],
  "event_type": "市場趨勢"
}

=====================
範例 3（有市場資訊，但跟股票投資無關）
=====================
新聞標題：「比房價還瘋！六都車位「台南狂漲84%」稱霸」

輸出：
{
  "investment_relevance": 55,
  "stock_market_relevance": 15,
  "confidence": 85,
  "event_materiality": 0,
  "companies_mentioned": [],
  "industries": ["營建房地產"],
  "topics": ["不動產市場", "車位價格"],
  "technologies": [],
  "event_type": "市場趨勢"
}

=====================
範例 4（公司只是背景/巧合提及，不是新聞主體）
=====================
新聞標題：「某藝人靠早年買進的台積電股票致富，如今身價翻倍」

輸出：
{
  "investment_relevance": 20,
  "stock_market_relevance": 8,
  "confidence": 85,
  "event_materiality": 0,
  "companies_mentioned": [],
  "industries": [],
  "topics": ["個人理財", "名人話題"],
  "technologies": [],
  "event_type": null
}

=====================
範例 5（政治人物提及公司，沒有實質政策/營運內容）
=====================
新聞標題：「某政治人物受訪時批評台積電海外設廠政策」

輸出：
{
  "investment_relevance": 30,
  "stock_market_relevance": 10,
  "confidence": 70,
  "event_materiality": 0,
  "companies_mentioned": [],
  "industries": [],
  "topics": ["政治評論"],
  "technologies": [],
  "event_type": null
}

=====================
輸出規則
=====================
不確定的欄位就填空值，不要瞎猜。寧可少判斷，不要亂關聯。
請只回傳一個 JSON 物件，不要有其他文字說明，格式跟上面範例完全一致，
七個欄位都要有：investment_relevance, stock_market_relevance,
confidence, event_materiality, companies_mentioned, industries,
topics, technologies, event_type。"""


class CloudAIProvider(AIProvider):
    """
    用 OpenAI API 做分類。

    需要：
        pip install openai --break-system-packages
        環境變數 OPENAI_API_KEY

    模型選擇：
        預設 gpt-5.6-luna——OpenAI 目前官方建議給新的
        「速度/成本敏感型」用例的首選模型，適合這種
        分類/抽取任務。如果之後想更省，可以換成
        gpt-5-nano（更便宜，但只建議在你實測品質可接受
        後再換，不要一開始就用最便宜的）。

        模型名稱這塊變動很快，實際跑之前建議先去
        OpenAI 後台的 Models 頁面確認目前可用的正確
        model id 字串，如果跟這裡預設的不一樣，
        改 model 參數即可，不用動其他程式碼。
    """

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "gpt-5.6-luna",
    ):
        from openai import OpenAI

        # api_key=None 時，OpenAI SDK 會自動去讀
        # 環境變數 OPENAI_API_KEY
        self.client = OpenAI(api_key=api_key)
        self.model = model

    def classify_news(self, title: str, summary: str) -> dict:

        import json

        user_content = f"標題：{title}\n摘要：{summary}"

        response = self.client.chat.completions.create(
            model=self.model,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": CLASSIFY_SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
        )

        raw = response.choices[0].message.content

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            # AI 沒有照格式回傳，保守處理成「不確定，不判斷」
            return self._empty_result()

        return {
            "investment_relevance": data.get("investment_relevance", 0),
            "stock_market_relevance": data.get("stock_market_relevance", 0),
            "confidence": data.get("confidence", 0),
            "event_materiality": data.get("event_materiality", 0),
            "companies_mentioned": data.get("companies_mentioned", []),
            "industries": data.get("industries", []),
            "topics": data.get("topics", []),
            "technologies": data.get("technologies", []),
            "event_type": data.get("event_type"),
        }

    def _empty_result(self) -> dict:
        return {
            "investment_relevance": 0,
            "stock_market_relevance": 0,
            "confidence": 0,
            "event_materiality": 0,
            "companies_mentioned": [],
            "industries": [],
            "topics": [],
            "technologies": [],
            "event_type": None,
        }


class GeminiProvider(AIProvider):
    """
    用 Google Gemini API 做分類。

    需要：
        pip install google-genai --break-system-packages
        環境變數 GEMINI_API_KEY
        （去 https://aistudio.google.com/apikey 申請，
        不用信用卡，Flash / Flash-Lite 系列有免費額度）

    模型選擇：
        預設 gemini-3.5-flash-lite——目前（2026/08）Gemini 官方
        正式版（GA，不是 preview）裡明確定位為「高流量、低成本
        自動化」的模型，跟我們這種大量分類任務的需求吻合。

        Gemini 的模型代號變動非常快（幾乎每個月都有舊模型
        對新帳號下架），如果這裡預設的名稱之後又失效，
        跑一次同目錄的 list_gemini_models.py 查詢你的 key
        目前實際能用哪些模型，把 model 參數換成查到的名稱即可，
        不用改其他程式碼。
    """

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "gemini-3.5-flash-lite",
    ):
        from google import genai

        # api_key=None 時，SDK 會自動去讀環境變數 GEMINI_API_KEY
        self.client = genai.Client(api_key=api_key)
        self.model = model

    def classify_news(self, title: str, summary: str) -> dict:

        import json

        user_content = f"標題：{title}\n摘要：{summary}"

        response = self.client.models.generate_content(
            model=self.model,
            contents=f"{CLASSIFY_SYSTEM_PROMPT}\n\n{user_content}",
            config={
                "response_mime_type": "application/json",
            },
        )

        raw = response.text

        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            # AI 沒有照格式回傳，保守處理成「不確定，不判斷」
            return self._empty_result()

        return {
            "investment_relevance": data.get("investment_relevance", 0),
            "stock_market_relevance": data.get("stock_market_relevance", 0),
            "confidence": data.get("confidence", 0),
            "event_materiality": data.get("event_materiality", 0),
            "companies_mentioned": data.get("companies_mentioned", []),
            "industries": data.get("industries", []),
            "topics": data.get("topics", []),
            "technologies": data.get("technologies", []),
            "event_type": data.get("event_type"),
        }

    def _empty_result(self) -> dict:
        return {
            "investment_relevance": 0,
            "stock_market_relevance": 0,
            "confidence": 0,
            "event_materiality": 0,
            "companies_mentioned": [],
            "industries": [],
            "topics": [],
            "technologies": [],
            "event_type": None,
        }