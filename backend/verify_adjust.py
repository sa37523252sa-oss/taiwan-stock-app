"""
驗算還原股價的結果。

偵測器只能告訴你「這裡有跳空」，不能告訴你「補上去之後對不對」。
這支程式從結果反推：還原後的長期報酬率合不合理、事件當天的
價格連不連續。

用法：
    python verify_adjust.py               # 檢查有自動套用紀錄的股票
    python verify_adjust.py 2330 2382     # 指定幾檔
"""

import sys

from database import get_connection
from corporate_actions import get_actions, adjust_history, PRICE, TOTAL
from backtest import get_price_history


def auto_applied_codes():

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT DISTINCT code FROM corporate_actions
        WHERE source IN ('auto', 'manual') OR action_type = 'AUTO_ADJUST'
        ORDER BY code
    """)

    codes = [r["code"] for r in cur.fetchall()]

    conn.close()

    return codes


def applied_events(code):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT ex_date, action_type, share_ratio FROM corporate_actions
        WHERE code = ? AND action_type IN ('AUTO_ADJUST', 'SPLIT', 'REDUCTION')
        ORDER BY ex_date
    """, (code,))

    rows = [(r["ex_date"], r["action_type"], r["share_ratio"])
            for r in cur.fetchall()]

    conn.close()

    return rows


def annualized(first, last, years):

    if first <= 0 or years <= 0:
        return None

    return ((last / first) ** (1 / years) - 1) * 100


def is_exempt(code):
    """無漲跌幅限制的標的，殘留大波動是正常的，不要誤報"""

    conn = get_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            "SELECT price_limit_exempt FROM stocks WHERE code=?", (code,)
        )
        row = cur.fetchone()
        out = bool(row and row["price_limit_exempt"])
    except Exception:
        out = False

    conn.close()

    return out


def check(code):

    history = get_price_history(code, "1990-01-01", "2100-01-01")

    if len(history) < 250:
        print(f"{code}: 資料太少，跳過")
        return

    actions = get_actions(code)

    adj_p = adjust_history(history, actions, mode=PRICE)
    adj_t = adjust_history(history, actions, mode=TOTAL)

    first_date = history[0]["date"]
    last_date = history[-1]["date"]

    years = (int(last_date[:4]) - int(first_date[:4])
             + (int(last_date[5:7]) - int(first_date[5:7])) / 12)

    raw_cagr = annualized(history[0]["close"], history[-1]["close"], years)
    price_cagr = annualized(adj_p[0]["close"], adj_p[-1]["close"], years)
    total_cagr = annualized(adj_t[0]["close"], adj_t[-1]["close"], years)

    print(f"\n===== {code}  {first_date} ~ {last_date}  ({years:.1f} 年) =====")
    print(f"  未還原   {history[0]['close']:>9.2f} → {history[-1]['close']:>9.2f}"
          f"   年化 {raw_cagr:>7.2f}%")
    print(f"  還原除權 {adj_p[0]['close']:>9.2f} → {adj_p[-1]['close']:>9.2f}"
          f"   年化 {price_cagr:>7.2f}%")
    print(f"  含息還原 {adj_t[0]['close']:>9.2f} → {adj_t[-1]['close']:>9.2f}"
          f"   年化 {total_cagr:>7.2f}%")

    ev = applied_events(code)

    if ev:
        print(f"  人工/自動補的事件 {len(ev)} 筆：")
        for d, t, r in ev:
            print(f"    {d}  {t:<14} 乘數 {r}")

    # 還原後還有沒有殘留的跳空
    worst = None

    for i in range(1, len(adj_p)):

        a, b = adj_p[i - 1]["close"], adj_p[i]["close"]

        if a <= 0:
            continue

        dev = b / a - 1

        if worst is None or abs(dev) > abs(worst[1]):
            worst = (adj_p[i]["date"], dev)

    if worst:
        print(f"  還原後最大單日變動：{worst[0]}  {worst[1]*100:+.1f}%")

        if abs(worst[1]) > 0.11 and not is_exempt(code):
            print("    ↑ 仍超過漲跌幅限制，這檔可能還有沒補到的事件")

    # 年化報酬率離譜的話多半是還原過頭或不足
    if price_cagr is not None and (price_cagr > 40 or price_cagr < -40):
        print(f"    ↑ 年化 {price_cagr:.1f}% 不合理，檢查是否有重複套用的事件")


def main():

    codes = sys.argv[1:] or auto_applied_codes()

    if not codes:
        print("沒有找到人工或自動補過事件的股票")
        return

    print(f"驗算 {len(codes)} 檔")

    for code in codes:
        check(code)


if __name__ == "__main__":
    main()