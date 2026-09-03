import requests
from database import get_connection


TOKEN = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoic2EzNzUyMzI1MnNhQGdtYWlsLmNvbSIsImVtYWlsIjoic2EzNzUyMzI1MnNhQGdtYWlsLmNvbSIsInRva2VuX3ZlcnNpb24iOjB9.o-DEF8eMhhml3WZLjgIyO-nhfD1C0FoSkuT6IhHYc-A"

URL = "https://api.finmindtrade.com/api/v4/data"



def sync_stocks():

    params = {

        "dataset": "TaiwanStockInfo",

        "token": TOKEN

    }



    response = requests.get(

        URL,

        params=params

    )



    data = response.json()



    # API錯誤檢查

    if data.get("status") != 200:

        print("FinMind API 錯誤：")

        print(data)

        return



    stocks = data["data"]



    print(
        f"取得股票數量：{len(stocks)}"
    )



    conn = get_connection()

    cursor = conn.cursor()



    count = 0



    for stock in stocks:


        cursor.execute(

            """
            INSERT OR REPLACE INTO stocks
            (
                code,
                name,
                industry
            )

            VALUES (?, ?, ?)

            """,

            (

                stock["stock_id"],

                stock["stock_name"],

                stock.get(
                    "industry_category",
                    ""
                )

            )

        )


        count += 1



    conn.commit()

    conn.close()



    print(
        f"股票同步完成，共 {count} 檔"
    )



if __name__ == "__main__":

    sync_stocks()