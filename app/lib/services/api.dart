import 'dart:convert';
import 'api_config.dart';
import 'package:http/http.dart' as http;
import '../models/stock.dart';


class ApiService {


  static String get baseUrl => kBaseUrl;




  // =========================
  // 取得熱門股票
  // =========================

  static Future<List<Stock>> getStocks() async {


    final response = await http.get(

      Uri.parse(
        "$baseUrl/stocks",
      ),

    );



    if(response.statusCode == 200){


      final List data =
          jsonDecode(response.body);



      return data.map(

        (e) => Stock.fromJson(e)

      ).toList();


    }



    throw Exception(
      "取得股票失敗"
    );


  }







  // =========================
  // 搜尋股票
  // =========================

  static Future<List<Stock>> searchStock(

      String keyword

  ) async {



    final response = await http.get(


      Uri.parse(

        "$baseUrl/search?q=$keyword",

      ),


    );




    if(response.statusCode == 200){


      final List data =
          jsonDecode(response.body);




      return data.map(

        (e) => Stock.fromJson(e)

      ).toList();



    }



    throw Exception(

      "搜尋股票失敗"

    );


  }







  // =========================
  // 取得單一股票
  // =========================

  static Future<Stock> getStock(

      String code

  ) async {



    final response = await http.get(


      Uri.parse(

        "$baseUrl/stock/$code",

      ),


    );



    if(response.statusCode == 200){



      final data =
          jsonDecode(response.body);



      if(data["error"] != null){


        throw Exception(

          "找不到股票"

        );


      }




      return Stock.fromJson(

        data,

      );



    }




    throw Exception(

      "股票資料取得失敗"

    );


  }





}