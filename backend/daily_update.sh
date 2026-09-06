#!/bin/bash
cd /home/ubuntu/taiwan-stock-app/backend
source venv/bin/activate
echo "########## $(date '+%Y-%m-%d %H:%M') 開始 ##########"
echo "--- 大盤指數（優先）---"
python -u -c "
from update_price import update_one_stock
for c in ['TAIEX','TPEx']:
    try:
        update_one_stock(c, force=True)
    except Exception as e:
        print(c, e)
"
timeout 300 python -u update_index_money.py
echo "--- 股價/股利/財報 ---"
python -u sync_all.py --budget=400 --skip-detect
echo "--- 三大法人 ---"
echo "" | timeout 900 python -u update_institution.py
echo "--- 融資融券 ---"
echo "" | timeout 900 python -u update_margin.py
echo "--- 大盤籌碼 ---"
timeout 600 python -u update_market_chips.py
echo "--- 新聞 ---"
timeout 900 python -u update_news.py
echo "--- 重大動態 ---"
timeout 900 python -u update_disclosures.py

echo "--- 期貨 ---"
timeout 600 python -u update_futures.py
echo "########## $(date '+%Y-%m-%d %H:%M') 結束 ##########"
