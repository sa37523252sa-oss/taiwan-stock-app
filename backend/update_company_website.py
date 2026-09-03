"""
抓取每家上市公司的官方網址，存進 stocks 表。

資料源：證交所官方 OpenAPI（t187ap03_L，公司基本資料），
跟 update_disclosures.py 用的 t187ap04_L 是同一系列、完全合規，
不是爬蟲。

注意：用 UPDATE 只更新 website 這一欄，不影響 code/name/industry
（那些是 sync_stocks.py 負責的），也不會被 sync_stocks.py 下次執行
時的 INSERT OR REPLACE 洗掉（因為那邊的 INSERT OR REPLACE 沒有動
website 欄位以外的東西，兩支腳本互不干擾）。

執行方式：
    python update_company_website.py

建議跟 sync_stocks.py 一樣，久久跑一次就好（公司網址不常變），
不用像新聞/重大訊息那樣每天跑。
"""

import requests

from database import get_connection

# 上市（證交所）
TWSE_URL = "https://openapi.twse.com.tw/v1/opendata/t187ap03_L"

# 上櫃（櫃買中心）——同一份邏輯資料的另一半，網域、欄位命名
# 都跟上市那份不一樣（上市用中文欄名，上櫃用英文欄名）
TPEX_URL = "https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O"

# 上櫃那份的正確英文欄位名稱沒有 100% 把握，這裡列幾個常見
# 候選名稱依序嘗試，抓不到就印出原始資料方便人工比對調整
TPEX_CODE_KEYS = ["SecuritiesCompanyCode", "CompanyCode", "Code"]
TPEX_WEBSITE_KEYS = ["Website", "WebAddress", "CompanyWebsite", "URL"]


def ensure_column():

    conn = get_connection()
    cur = conn.cursor()

    try:
        cur.execute("ALTER TABLE stocks ADD COLUMN website TEXT")
        print("stocks.website 新增成功")
    except Exception as e:
        if "duplicate column name" not in str(e):
            raise

    conn.commit()
    conn.close()


def _first_present(row, keys):
    for k in keys:
        if k in row and row[k]:
            return row[k]
    return None


def _normalize_url(website):

    website = (website or "").strip()

    if not website or website in ("－", "-", "N/A"):
        return None

    if not website.lower().startswith(("http://", "https://")):
        website = f"http://{website}"

    return website


def _apply_updates(conn, pairs):

    cur = conn.cursor()

    updated = 0

    for code, website in pairs:
        cur.execute(
            "UPDATE stocks SET website = ? WHERE code = ?",
            (website, code),
        )
        updated += 1

    conn.commit()

    return updated


def update_listed():
    """上市公司（證交所 t187ap03_L，中文欄名，已驗證過欄位名稱）"""

    print("抓取上市公司基本資料 ...")

    resp = requests.get(TWSE_URL, timeout=30)
    resp.raise_for_status()

    rows = resp.json()

    print(f"共 {len(rows)} 家上市公司")

    pairs = []
    skipped = 0

    for row in rows:

        code = row.get("公司代號", "")
        website = _normalize_url(row.get("網址"))

        if not code or not website:
            skipped += 1
            continue

        pairs.append((code, website))

    conn = get_connection()
    updated = _apply_updates(conn, pairs)
    conn.close()

    print(f"上市：更新 {updated} 家，略過 {skipped} 家")


def update_otc():
    """上櫃公司（櫃買中心 mopsfin_t187ap03_O，英文欄名，
    欄位名稱沒有 100% 確認，用候選清單嘗試，抓不到就跳過並提示。"""

    print("抓取上櫃公司基本資料 ...")

    try:
        # tpex.org.tw 自己的 SSL 憑證缺少 Subject Key Identifier
        # 欄位，是對方憑證設定本身的瑕疵（不是我們的問題，也不是
        # 中間人攻擊那種真正的安全疑慮），這裡關閉這次請求的憑證
        # 驗證才連得上去。如果之後櫃買中心把憑證修好了，這段可以
        # 拿掉、改回正常驗證。
        import urllib3
        urllib3.disable_warnings(
            urllib3.exceptions.InsecureRequestWarning
        )

        resp = requests.get(TPEX_URL, timeout=30, verify=False)
        resp.raise_for_status()
        rows = resp.json()
    except Exception as e:
        print(f"上櫃資料抓取失敗（可能是網址或格式有變）：{e}")
        return

    if not rows:
        print("上櫃資料是空的，略過")
        return

    print(f"共 {len(rows)} 家上櫃公司")

    # 印出第一筆原始資料，方便人工核對欄位名稱對不對
    print("--- 上櫃資料第一筆原始內容（核對欄位名稱用）---")
    print(rows[0])
    print("---")

    pairs = []
    skipped = 0

    for row in rows:

        code = _first_present(row, TPEX_CODE_KEYS)
        website = _normalize_url(_first_present(row, TPEX_WEBSITE_KEYS))

        if not code or not website:
            skipped += 1
            continue

        pairs.append((code, website))

    if not pairs:
        print(
            "上櫃公司一筆都沒配到欄位，代表候選欄位名稱猜錯了，"
            "請對照上面印出的原始資料，把正確欄位名稱加進 "
            "TPEX_CODE_KEYS / TPEX_WEBSITE_KEYS 再重跑一次。"
        )
        return

    conn = get_connection()
    updated = _apply_updates(conn, pairs)
    conn.close()

    print(f"上櫃：更新 {updated} 家，略過 {skipped} 家")


def update_company_website():

    ensure_column()
    update_listed()
    update_otc()


if __name__ == "__main__":
    update_company_website()