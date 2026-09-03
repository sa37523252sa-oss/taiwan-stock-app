"""
用法: python context_builder.py 2330
v2 修正: 法人/信用單位、流動比倍數、新聞篩選與去重、新聞時效偵測
"""
import re
import sqlite3
import sys
from datetime import date, datetime

DB = "stocks.db"
SCALE = 1

FIN_DEADLINE = {1: (5, 15), 2: (8, 14), 3: (11, 14), 4: (3, 31)}

# 大盤盤中快訊特徵：命中即排除（這類新聞只是順帶提到個股）
NOISE_TITLE = re.compile(
    r"(台股|大盤|加權指數|櫃買|台指期|美股|道瓊|那斯達克|費半|日經|韓股)"
    r".{0,20}(開盤|早盤|盤中|收盤|終場|夜盤|漲|跌|震盪|點)"
    r"|盤前|盤後速報|盤中速報|三大法人買賣超|類股[漲跌]"
)

# 投資建議語言：命中即排除，避免模型複述
ADVICE_TITLE = re.compile(
    r"(買點|賣點|進場|布局|逢低|抄底|target|目標價|上看|下看|喊進|看好|看空"
    r"|分析師|老師|操作策略|存股|飆股|潛力股|該買|能買|可買|要買|該賣)"
)


def fin_pub_date(year, quarter):
    m, d = FIN_DEADLINE[quarter]
    return date(year + 1 if quarter == 4 else year, m, d)


def rev_pub_date(year, month):
    y, m = (year + 1, 1) if month == 12 else (year, month + 1)
    return date(y, m, 10)


def num(v, unit="", nd=2):
    if v is None:
        return "無資料"
    if unit == "$":
        v *= SCALE
        a = abs(v)
        if a >= 1e8:
            return f"{v/1e8:,.2f} 億"
        if a >= 1e4:
            return f"{v/1e4:,.1f} 萬"
        return f"{v:,.0f}"
    return f"{v:,.{nd}f}{unit}"


def ratio(v):
    """流動比/速動比：資料為倍數，同時給倍數與百分比避免誤讀。"""
    if v is None:
        return "無資料"
    return f"{v:,.2f} 倍（{v*100:,.0f}%）"


def days_ago(s, today):
    try:
        return (today - datetime.strptime(s[:10], "%Y-%m-%d").date()).days
    except Exception:
        return None


def q(conn, sql, args=()):
    return conn.execute(sql, args).fetchall()


def pick_news(rows, today, limit=8):
    """篩掉大盤快訊、投資建議、同日重複標題。"""
    seen, out = set(), []
    for r in rows:
        pub, src, title, summary = (r[0] or ""), r[1], (r[2] or ""), r[3]
        if NOISE_TITLE.search(title) or ADVICE_TITLE.search(title):
            continue
        key = (pub[:10], re.sub(r"[^\u4e00-\u9fff]", "", title)[:12])
        if key in seen:
            continue
        seen.add(key)
        out.append(r)
        if len(out) >= limit:
            break
    return out


def build(code, conn, today=None):
    today = today or date.today()
    out, gaps = [], []
    R = {"P": 0, "F": 0, "R": 0, "C": 0, "M": 0, "N": 0, "E": 0}

    def tag(k):
        R[k] += 1
        return f"[{k}{R[k]}]"

    s = q(conn, "SELECT name, industry, asset_type FROM stocks WHERE code=?", (code,))
    if not s:
        raise SystemExit(f"查無股票代號 {code}")
    name, industry, atype = s[0]
    out += [f"=== {name} ({code}) ===",
            f"產業: {industry or '未分類'} | 類型: {atype or 'STOCK'}",
            f"context 產生日期: {today}", ""]

    # ---------- 股價 ----------
    px = q(conn, "SELECT date,open,high,low,close,volume FROM prices WHERE code=? ORDER BY date DESC LIMIT 61", (code,))
    out.append("--- 股價（未還原權值）---")
    if not px:
        gaps.append("無股價資料")
    else:
        d0, c0, v0 = px[0][0], px[0][4], px[0][5]
        chg = f"（{(c0/px[1][4]-1)*100:+.2f}%）" if len(px) > 1 and px[1][4] else ""
        out.append(f"{tag('P')} 最新交易日 {d0} 收盤 {num(c0)}{chg}，成交量 {num(v0/1000,' 張',0) if v0 else '無資料'}")
        for n in (5, 20, 60):
            if len(px) > n and px[n][4]:
                hi = max(r[2] for r in px[:n] if r[2] is not None)
                lo = min(r[3] for r in px[:n] if r[3] is not None)
                out.append(f"{tag('P')} 近 {n} 交易日 {(c0/px[n][4]-1)*100:+.2f}%（{px[n][0]} {num(px[n][4])} → {num(c0)}），區間 {num(lo)}~{num(hi)}")
        lag = days_ago(d0, today)
        if lag and lag > 5:
            gaps.append(f"股價資料已 {lag} 天未更新（最新 {d0}）")
    out.append("")

    # ---------- 財報 ----------
    fin = q(conn, """SELECT year,quarter,revenue,gross_margin,operating_margin,net_margin,eps,roe,roa,
                     debt_ratio,current_ratio,operating_cash_flow,free_cash_flow,net_income
                     FROM financials WHERE code=? ORDER BY year DESC, quarter DESC LIMIT 5""", (code,))
    out.append("--- 財報（單季數字，非年化；附推估公布日）---")
    if not fin:
        gaps.append("無財報資料")
    for r in fin:
        pub = fin_pub_date(r[0], r[1])
        st = "推估公布日" if pub <= today else "尚未到公布期限"
        out += [f"{tag('F')} {r[0]} Q{r[1]}（{st} {pub}）",
                f"     營收 {num(r[2],'$')} | 毛利率 {num(r[3],'%')} | 營益率 {num(r[4],'%')} | 淨利率 {num(r[5],'%')} | 單季 EPS {num(r[6])}",
                f"     單季 ROE {num(r[7],'%')} | 單季 ROA {num(r[8],'%')} | 負債比 {num(r[9],'%')} | 流動比 {ratio(r[10])}",
                f"     營業現金流 {num(r[11],'$')} | 自由現金流 {num(r[12],'$')} | 稅後淨利 {num(r[13],'$')}"]
    if fin:
        yy, qq = fin[0][0], fin[0][1]
        nxt = (yy + 1, 1) if qq == 4 else (yy, qq + 1)
        if fin_pub_date(*nxt) <= today:
            gaps.append(f"{nxt[0]} Q{nxt[1]} 財報依法定期限應已於 {fin_pub_date(*nxt)} 前公布，資料庫尚無")
    out.append("")

    # ---------- 月營收 ----------
    rev = q(conn, "SELECT year,month,revenue,mom,yoy FROM monthly_revenue WHERE code=? ORDER BY year DESC, month DESC LIMIT 13", (code,))
    out.append("--- 月營收（附推估公布日）---")
    if not rev:
        gaps.append("無月營收資料")
    for r in rev[:6]:
        pub = rev_pub_date(r[0], r[1])
        st = "推估公布日" if pub <= today else "尚未到公布期限"
        out.append(f"{tag('R')} {r[0]}/{r[1]:02d}（{st} {pub}）營收 {num(r[2],'$')} | MoM {num(r[3],'%')} | YoY {num(r[4],'%')}")
    if len(rev) >= 12:
        out.append(f"{tag('R')} 近 12 個月累計營收 {num(sum(x[2] for x in rev[:12] if x[2] is not None),'$')}")
    if rev:
        yy, mm = rev[0][0], rev[0][1]
        nxt = (yy + 1, 1) if mm == 12 else (yy, mm + 1)
        if rev_pub_date(*nxt) <= today:
            gaps.append(f"{nxt[0]}/{nxt[1]:02d} 月營收應已於 {rev_pub_date(*nxt)} 前公布，資料庫尚無")
    out.append("")

    # ---------- 籌碼（原始資料單位為「張」，不再換算）----------
    ins = q(conn, "SELECT date,foreign_net,trust_net,dealer_net FROM institution_flows WHERE code=? ORDER BY date DESC LIMIT 20", (code,))
    out.append("--- 法人買賣超（張）---")
    if not ins:
        gaps.append("無法人買賣超資料")
    else:
        for label, n in (("近 5 日", 5), ("近 20 日", 20)):
            sub = ins[:n]
            if len(sub) >= 3:
                f_, t_, d_ = (sum(x[i] or 0 for x in sub) for i in (1, 2, 3))
                out.append(f"{tag('C')} {label}累計（{sub[-1][0]}~{sub[0][0]}）外資 {f_:+,.0f}、投信 {t_:+,.0f}、自營商 {d_:+,.0f}")
        out.append(f"{tag('C')} 最近交易日 {ins[0][0]}：外資 {ins[0][1] or 0:+,.0f}、投信 {ins[0][2] or 0:+,.0f}、自營商 {ins[0][3] or 0:+,.0f}")

    mg = q(conn, "SELECT date,margin_today_balance,short_today_balance FROM margin_flows WHERE code=? ORDER BY date DESC LIMIT 20", (code,))
    if mg:
        out.append("--- 信用交易（張）---")
        out.append(f"{tag('M')} {mg[0][0]} 融資餘額 {mg[0][1] or 0:,.0f}、融券餘額 {mg[0][2] or 0:,.0f}")
        if len(mg) >= 20 and mg[19][1]:
            out.append(f"{tag('M')} 近 20 日融資餘額變化 {(mg[0][1] or 0)-(mg[19][1] or 0):+,.0f}（{mg[19][0]} → {mg[0][0]}）")
    out.append("")

    # ---------- 公告 ----------
    dis = q(conn, """SELECT COALESCE(speak_date,fact_date),category,subject,detail,major_event_type
                     FROM disclosures WHERE code=?
                     ORDER BY COALESCE(speak_date,fact_date) DESC LIMIT 6""", (code,))
    out.append("--- 公司公告／重大訊息 ---")
    if not dis:
        out.append("（無公告資料）")
        gaps.append("資料庫中無此公司公告資料")
    for r in dis:
        out.append(f"{tag('E')} {r[0]}｜{r[1] or ''}{('／'+r[4]) if r[4] else ''}｜{r[2] or ''}")
        if r[3]:
            out.append(f"     {r[3][:300].strip()}")
    out.append("")

    # ---------- 新聞 ----------
    raw = q(conn, """SELECT n.pub_date,n.source,n.title,n.summary,n.event_type,r.relevance_score,r.relation_type
                     FROM news n JOIN news_relations r ON n.link=r.news_link
                     WHERE r.code=?
                     ORDER BY COALESCE(r.relevance_score,0) DESC, n.pub_date DESC LIMIT 60""", (code,))
    if not raw:
        raw = q(conn, """SELECT pub_date,source,title,summary,event_type,NULL,NULL FROM news
                         WHERE matched_codes LIKE ? ORDER BY pub_date DESC LIMIT 60""", (f"%{code}%",))
    news = pick_news(sorted(raw, key=lambda r: r[0] or "", reverse=True), today)
    out.append("--- 近期公司相關新聞（已排除大盤快訊與評論性內容）---")
    if not news:
        out.append("（無符合條件的公司相關新聞）")
        gaps.append("近期無公司層級新聞，數字變化的外部原因無資料可佐證")
    for r in news:
        out.append(f"{tag('N')} {(r[0] or '')[:10]}｜{r[1] or ''}{('｜'+r[4]) if r[4] else ''}")
        out.append(f"     標題：{r[2] or ''}")
        if r[3]:
            out.append(f"     摘要：{r[3][:250].strip()}")
    if news:
        lag = days_ago(news[0][0] or "", today)
        if lag and lag > 7:
            gaps.append(f"最新一則公司新聞距今 {lag} 天（{news[0][0][:10]}）")
    out.append("")

    out.append("--- 資料缺漏（已知）---")
    out.extend(f"- {g}" for g in gaps) if gaps else out.append("（無）")
    return "\n".join(out)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("用法: python context_builder.py <股票代號>")
    print(build(sys.argv[1], sqlite3.connect(DB)))