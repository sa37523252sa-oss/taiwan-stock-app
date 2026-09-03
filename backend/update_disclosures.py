"""
抓取證交所官方重大訊息（TWSE OpenAPI t187ap04_L），
依 S/A/B 分級規則分類，存進 disclosures 表。

不需要 AI——這份資料本身就有官方的「符合條款」分類代碼
（例如第12款＝法人說明會），比對官方原文關鍵字也比比對
新聞標題準確。

資料來源：https://openapi.twse.com.tw/v1/opendata/t187ap04_L
（免金鑰、免註冊的官方 OpenAPI，回傳當日全市場重大訊息）

注意：這個端點只回傳「當天」的重大訊息快照，不是歷史查詢，
所以建議排程「每天」跑一次，累積存進資料庫，才會有歷史資料。
"""

import re
import time
import requests

from database import get_connection

TWSE_URL = "https://openapi.twse.com.tw/v1/opendata/t187ap04_L"


# =====================
# 分類規則（依序比對，符合就停止，不重複分類）
# 每條規則： (category, tier, matcher(subject, clause, detail) -> bool)
# =====================

def _has(text, *keywords):
    return any(k in text for k in keywords)


def _rule_investor_day(subject, clause, detail):
    return clause == "第12款" and "Investor Day" in subject

def _rule_roadshow(subject, clause, detail):
    return clause == "第12款" and _has(subject, "Roadshow", "Tour", "Forum")

def _rule_investor_conference(subject, clause, detail):
    return clause == "第12款"

def _rule_agm(subject, clause, detail):
    return "股東常會" in subject

def _rule_egm(subject, clause, detail):
    return _has(subject, "股東臨時會", "臨時股東會")

def _rule_financial_report(subject, clause, detail):
    return clause == "第31款"

def _rule_earnings_preview(subject, clause, detail):
    return "自結" in subject

def _rule_dividend(subject, clause, detail):
    return clause == "第14款"

def _rule_investment(subject, clause, detail):
    # 第15/20款：資本支出、資產取得處分（投資/擴產/併購）
    # 第11款：增資、私募、發行公司債（公司自己對外募資）
    if clause in ("第11款", "第15款", "第20款"):
        return True
    # 條款代碼之外，主旨文字本身很明確的併購/收購案也接住
    # （例如公開收購最終結算結果，這種條款代碼不一定落在
    # 上面幾款裡，但重要性很高，不該被規則漏掉）
    return _has(subject, "公開收購") and _has(subject, "結算結果", "完成", "成功")

def _rule_corporate_change(subject, clause, detail):
    # 公司更名、股票面額變更：不是投資行為，是公司基本資料
    # 本身的變動，跟「增資/併購/投資」性質不同，獨立一個分類。
    if "更名" in subject:
        return True
    if _has(subject, "面額") and _has(subject, "變更", "由"):
        return True
    return False

def _rule_audit_committee(subject, clause, detail):
    return clause == "第6款" and "審計委員會" in (subject + detail)

def _rule_comp_committee(subject, clause, detail):
    return clause == "第6款" and "薪酬委員會" in (subject + detail)

def _rule_board_resolution(subject, clause, detail):
    return _has(subject, "董事會決議", "董事會通過")


CLASSIFICATION_RULES = [
    ("investor_day",        "A", _rule_investor_day),
    ("roadshow",             "A", _rule_roadshow),
    ("investor_conference",  "S", _rule_investor_conference),
    ("agm",                  "S", _rule_agm),
    ("egm",                  "S", _rule_egm),
    ("financial_report",     "S", _rule_financial_report),
    ("earnings_preview",     "S", _rule_earnings_preview),
    ("dividend",              "A", _rule_dividend),
    ("investment",            "A", _rule_investment),
    ("corporate_change",      "A", _rule_corporate_change),
    ("audit_committee",       "B", _rule_audit_committee),
    ("comp_committee",        "B", _rule_comp_committee),
    ("board_resolution",      "S", _rule_board_resolution),
]

CATEGORY_LABELS = {
    "investor_conference": "法說會",
    "investor_day": "Investor Day",
    "roadshow": "海外Roadshow",
    "agm": "股東常會",
    "egm": "臨時股東會",
    "financial_report": "財報發布",
    "earnings_preview": "盈餘預告",
    "dividend": "股利決議",
    "investment": "增資/併購/投資/擴產",
    "corporate_change": "公司名稱/股票面額變更",
    "other_major_event": "重大公告",
    "audit_committee": "審計委員會",
    "comp_committee": "薪酬委員會",
    "board_resolution": "董事會重大決議",
    # 從股東會決議內容解析出來的衍生重大事件
    "director_change": "董監事改選",
    "major_strategy_change": "重大經營策略變更",
    "merger": "併購/合併",
    "acquisition": "收購",
    "private_placement": "私募",
    "capital_increase": "增資",
    "capital_reduction": "減資",
}

# 屬於「會議」本身的分類 -> 進「法說／股東會」頁
# 其餘分類本身就是具體事件 -> 進「重大動態」頁
#
# 董事會決議也算在這裡：決議公告是「會議中做的決定」，性質上
# 跟股東常會/臨時會的決議一樣，該進法說/股東會頁；如果這個決議
# 本身具有重大投資意義（例如決議通過併購案），一樣可以像股東會
# 決議那樣，另外解析出衍生的重大動態（見下方 extract 相關函式）。
MEETING_CATEGORIES = {
    "agm", "egm", "investor_conference", "investor_day", "roadshow",
    "board_resolution",
}

# =====================
# 公告 vs 決議結果（情況 A/C 對照 情況 B/D）
# =====================

_ANNOUNCE_KEYWORDS = ["召開", "召集", "預定", "擬訂", "擬於"]
_COMPLETED_KEYWORDS = ["重要決議事項", "決議事項", "議事錄", "表決結果"]


def determine_content_status(subject, category):
    """
    只對「會議類」分類判斷是公告（announcement_only）還是
    結果／內容（completed）。非會議類分類（財報/股利/投資等
    本身就是具體事件）不適用，回傳 None。
    """

    if category not in MEETING_CATEGORIES:
        return None

    # 法說會/Investor Day/Roadshow 目前資料源只有「將參加」這種
    # 公告，沒有簡報/逐字稿內容，一律當公告。
    if category in ("investor_conference", "investor_day", "roadshow"):
        return "announcement_only"

    # 董事會決議公告本身就是「已經做成的決定」，不是「即將召開」
    # 的預告，固定當作 completed（決議內容），不用再判斷關鍵字。
    if category == "board_resolution":
        return "completed"

    if _has(subject, *_COMPLETED_KEYWORDS):
        return "completed"

    if _has(subject, *_ANNOUNCE_KEYWORDS):
        return "announcement_only"

    # 兩種關鍵字都沒有時，保守當公告，避免誤判成結果
    return "announcement_only"


# =====================
# 股東會決議內容解析（只有 content_status=='completed' 才會用到）
# 官方「說明」欄位是結構化的：
#   1.股東常會日期:...
#   2.重要決議事項一、盈餘分配或盈虧撥補:...
#   3.重要決議事項二、章程修訂:...
#   4.重要決議事項三、營業報告書及財務報表:...
#   5.重要決議事項四、董監事選舉:...
#   6.重要決議事項五、其他事項:...
#   7.其他應敘明事項:...
# 用標籤文字切段落，不依賴前面的數字（不同公司數字順序可能不同）。
# =====================

_SECTION_LABELS = [
    "盈餘分配或盈虧撥補",
    "章程修訂",
    "營業報告書及財務報表",
    "董監事選舉",
    "其他事項",
    "其他應敘明事項",
]

_AMOUNT_PATTERN = re.compile(r"\d+(\.\d+)?\s*元")

_STRATEGY_KEYWORDS = [
    "股權", "資本額", "實收資本", "私募", "增資", "減資",
    "更名", "名稱變更", "公司名稱",
]

_OTHER_ITEM_KEYWORDS = {
    "merger": ["合併"],
    "acquisition": ["收購"],
    "private_placement": ["私募"],
    "capital_increase": ["現金增資", "增資發行", "增資案"],
    "capital_reduction": ["減資"],
}

_EMPTY_VALUES = {"無", "不適用", "無。", "不適用。"}


_TRAILING_NOISE = re.compile(r"\d+\.(重要決議事項)?[一二三四五六七八九十]*、?\s*$")


def _parse_sections(detail):

    pattern = "|".join(re.escape(l) for l in _SECTION_LABELS)
    matches = list(re.finditer(pattern, detail))

    sections = {}

    for i, m in enumerate(matches):

        label = m.group()
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(detail)

        text = detail[start:end]
        text = re.sub(r"^[:：]\s*", "", text).strip()
        text = re.sub(r"^\d+\.", "", text).strip()

        # 這段文字結尾常常會夾帶「下一段」開頭的編號/標籤文字
        # （例如「無。4.重要決議事項三、」），要切掉才能正確
        # 判斷這段本身是不是「無」。
        text = _TRAILING_NOISE.sub("", text).strip()

        # 同一個標籤（例如「其他事項」跟「其他應敘明事項」都含「其他」
        # 開頭字樣）只保留第一次出現的乾淨版本
        if label not in sections:
            sections[label] = text

    return sections


def _clean_for_title(text, length=60):
    text = re.sub(r"\s+", "", text)
    return text[:length]


def _extract_from_freeform_text(detail):
    """
    給非標準格式（例如股東臨時會的自由格式議程，沒有固定的
    「盈餘分配/章程修訂/董監事選舉」等標籤）用的 fallback：
    直接對整段文字做關鍵字掃描，不依賴段落結構。
    """

    majors = []

    if _AMOUNT_PATTERN.search(detail) and _has(detail, "股利", "盈餘分派", "盈餘分配"):
        majors.append((
            "dividend",
            f"股東會通過股利分配：{_clean_for_title(detail)}",
        ))

    if any(k in detail for k in _STRATEGY_KEYWORDS):
        majors.append((
            "major_strategy_change",
            f"股東會通過重大變更：{_clean_for_title(detail)}",
        ))

    if _has(detail, "改選", "當選"):
        majors.append((
            "director_change",
            "股東會完成董監事改選",
        ))

    for event_type, keywords in _OTHER_ITEM_KEYWORDS.items():
        if any(k in detail for k in keywords):
            majors.append((
                event_type,
                f"股東會通過：{_clean_for_title(detail)}",
            ))

    return majors


def extract_major_events_from_agm_detail(detail):
    """
    解析股東會決議結果的說明內容，回傳
    [(major_event_type, title_zh), ...]，判斷不出重大事件則回傳 []。

    判斷原則（對照使用者給的案例 1~5）：
    - 盈餘分配：內容裡有具體金額（含「元」）才算重大，
      單純「通過承認...盈餘分配案」沒有金額不算
      （案例1 財報案不重大；有寫金額的算股利決議）
    - 章程修訂：內容含股權/資本/私募/增資/減資/更名等關鍵字才算重大，
      單純文字修訂不算（案例5）
    - 董監事選舉：只要有實際內容（不是「無」）就算重大
      （代表這次公告是「已完成改選」的結果，不是預告）（案例3）
    - 其他事項：含合併/收購/私募/增資/減資關鍵字才算重大（案例4）
    - 財報承認案、單純章程文字修訂：不算重大（案例1、5）

    股東常會（AGM）用固定標籤格式，股東臨時會（EGM）常常是
    自由格式議程（例如「一、通過...」沒有固定標籤），這種
    情況段落解析會完全找不到任何段落，改用整段關鍵字掃描。
    """

    sections = _parse_sections(detail)

    # 「其他應敘明事項」幾乎每則公告結尾都會出現，不能單靠它
    # 判斷這是標準格式股東常會，要看有沒有真正的主要標籤。
    _primary_labels = {
        "盈餘分配或盈虧撥補", "章程修訂",
        "營業報告書及財務報表", "董監事選舉", "其他事項",
    }

    if not any(label in sections for label in _primary_labels):
        return _extract_from_freeform_text(detail)

    majors = []

    dividend_text = sections.get("盈餘分配或盈虧撥補", "")
    if dividend_text and dividend_text not in _EMPTY_VALUES:
        if _AMOUNT_PATTERN.search(dividend_text):
            majors.append((
                "dividend",
                f"股東會通過股利分配：{dividend_text[:60]}",
            ))

    charter_text = sections.get("章程修訂", "")
    if charter_text and charter_text not in _EMPTY_VALUES:
        if any(k in charter_text for k in _STRATEGY_KEYWORDS):
            majors.append((
                "major_strategy_change",
                f"股東會通過章程修訂：{charter_text[:60]}",
            ))

    director_text = sections.get("董監事選舉", "")
    if director_text and director_text not in _EMPTY_VALUES:
        majors.append((
            "director_change",
            "股東會完成董監事改選",
        ))

    other_text = sections.get("其他事項", "")
    if other_text and other_text not in _EMPTY_VALUES:
        for event_type, keywords in _OTHER_ITEM_KEYWORDS.items():
            if any(k in other_text for k in keywords):
                majors.append((
                    event_type,
                    f"股東會通過：{other_text[:60]}",
                ))

    return majors


def classify(subject, clause, detail):

    for category, tier, matcher in CLASSIFICATION_RULES:
        if matcher(subject, clause, detail):
            return category, tier

    # 不再直接丟掉比對不到規則的公告——不管分類規則寫得準不準，
    # 都不該讓公告憑空消失。比對不到就歸進通用的「重大公告」，
    # tier 給 B（沒辦法判斷重要程度，保守處理，不佔用 S/A 優先
    # 排序的位置，但至少會出現在重大動態頁，使用者自己判斷）。
    return "other_major_event", "B"


def roc_to_iso(roc_date: str) -> str:
    """民國年 1150813 -> 2026-08-13"""

    if not roc_date or len(roc_date) < 7:
        return ""

    year = int(roc_date[:-4]) + 1911
    month = roc_date[-4:-2]
    day = roc_date[-2:]

    return f"{year}-{month}-{day}"


def ensure_table():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS disclosures (
            id TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            company_name TEXT,
            category TEXT,
            tier TEXT,
            subject TEXT,
            detail TEXT,
            fact_date TEXT,
            speak_date TEXT,
            created_at TEXT
        )
    """)

    # 這次新增的欄位，用 ALTER TABLE 補上，不重建表、不動舊資料
    extra_columns = [
        ("content_status", "TEXT"),   # announcement_only / completed，只有會議類分類會用到
        ("is_major_event", "INTEGER"),  # 0/1，是否要出現在「重大動態」頁
        ("major_event_type", "TEXT"),   # 重大事件細分類型
        ("related_id", "TEXT"),         # 指向來源會議那筆 disclosures.id
    ]

    for col_name, col_type in extra_columns:
        try:
            cur.execute(f"ALTER TABLE disclosures ADD COLUMN {col_name} {col_type}")
        except Exception as e:
            if "duplicate column name" not in str(e):
                raise

    conn.commit()
    conn.close()


def fetch_disclosures():

    resp = requests.get(TWSE_URL, timeout=30)
    resp.raise_for_status()

    return resp.json()


def save_disclosures(rows):

    conn = get_connection()
    cur = conn.cursor()

    saved = 0
    skipped = 0
    derived = 0

    for row in rows:

        code = row.get("公司代號", "")
        name = row.get("公司名稱", "")
        subject = (row.get("主旨 ") or row.get("主旨") or "").strip()
        detail = row.get("說明", "") or ""
        clause = row.get("符合條款", "")
        fact_date = roc_to_iso(row.get("事實發生日", ""))
        speak_date = roc_to_iso(row.get("發言日期", ""))
        speak_time = row.get("發言時間", "")

        category, tier = classify(subject, clause, detail)

        content_status = determine_content_status(subject, category)

        # 非會議類分類（財報/股利/投資/董事會決議等）本身就是
        # 公司突然公布的具體事件，直接算重大動態。
        #
        # 會議類分類（法說會/股東常會/臨時股東會）依 content_status
        # 再拆一次：
        #   - announcement_only（公告即將舉辦）：投資人需要知道
        #     公司「即將」有事發生，也算重大動態
        #   - completed（會議實際決議內容）：只留在法說/股東會頁，
        #     不算重大動態，除非從決議內容解析出真正重大的子項目
        #     （見下方衍生邏輯）
        if category not in MEETING_CATEGORIES:
            is_major_event = 1
        elif content_status == "announcement_only":
            is_major_event = 1
        else:
            is_major_event = 0

        # id 用 公司代號+發言日期+發言時間 組合，避免重複寫入
        disclosure_id = f"{code}-{speak_date}-{speak_time}"

        cur.execute("""
            INSERT INTO disclosures(
                id, code, company_name, category, tier,
                subject, detail, fact_date, speak_date, created_at,
                content_status, is_major_event, major_event_type, related_id
            )
            VALUES(?,?,?,?,?,?,?,?,?,datetime('now'),?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                category=excluded.category,
                tier=excluded.tier,
                subject=excluded.subject,
                content_status=excluded.content_status,
                is_major_event=excluded.is_major_event
        """, (
            disclosure_id, code, name, category, tier,
            subject, detail, fact_date, speak_date,
            content_status, is_major_event, None, None,
        ))

        saved += 1

        # 決議「結果」內容才解析，公告類（announcement_only）
        # 不用解析，因為還沒有實際決議內容。董事會決議也適用
        # 同一套邏輯——如果決議內容本身具重大投資意義（金額、
        # 併購、更名等關鍵字），一樣要衍生出重大動態，不能因為
        # 董事會決議整批搬去法說頁，就漏掉裡面真正重要的內容。
        if category in ("agm", "egm", "board_resolution") \
                and content_status == "completed":

            majors = extract_major_events_from_agm_detail(detail)

            for major_event_type, title in majors:

                major_id = f"{disclosure_id}-major-{major_event_type}"

                cur.execute("""
                    INSERT INTO disclosures(
                        id, code, company_name, category, tier,
                        subject, detail, fact_date, speak_date, created_at,
                        content_status, is_major_event, major_event_type,
                        related_id
                    )
                    VALUES(?,?,?,?,?,?,?,?,?,datetime('now'),?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET
                        subject=excluded.subject,
                        is_major_event=excluded.is_major_event
                """, (
                    major_id, code, name, major_event_type, tier,
                    title, "", fact_date, speak_date,
                    None, 1, major_event_type, disclosure_id,
                ))

                derived += 1

    conn.commit()
    conn.close()

    return saved, skipped, derived


def update_disclosures():

    ensure_table()

    print("抓取 TWSE 重大訊息 ...")

    rows = fetch_disclosures()

    print(f"共 {len(rows)} 則原始重大訊息")

    saved, skipped, derived = save_disclosures(rows)

    print(f"分類並存入：{saved} 則")
    print(f"未命中分類規則（略過）：{skipped} 則")
    print(f"從股東會決議內容解析出的衍生重大事件：{derived} 則")


if __name__ == "__main__":
    update_disclosures()