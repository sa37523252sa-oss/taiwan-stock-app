import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/market_index.dart';
import '../models/market_institutional_day.dart';
import '../models/market_margin_day.dart';

class MarketApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<MarketIndexInfo>> getOverview() async {

    final response = await http.get(Uri.parse("$baseUrl/market/overview"));

    if (response.statusCode != 200) {
      throw Exception(
        "取得大盤總覽失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    final List<dynamic> data = json.decode(response.body);

    return data.map((e) => MarketIndexInfo.fromJson(e)).toList();
  }

  static Future<List<MarketInstitutionalDay>> getInstitutionalHistory({
    int limit = 30,
  }) async {

    final response = await http.get(
      Uri.parse("$baseUrl/market/institutional/history?limit=$limit"),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "取得大盤三大法人歷史失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    final List<dynamic> data = json.decode(response.body);

    return data.map((e) => MarketInstitutionalDay.fromJson(e)).toList();
  }

  static Future<List<MarketMarginDay>> getMarginHistory({
    int limit = 30,
  }) async {

    final response = await http.get(
      Uri.parse("$baseUrl/market/margin/history?limit=$limit"),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "取得大盤資券歷史失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    final List<dynamic> data = json.decode(response.body);

    return data.map((e) => MarketMarginDay.fromJson(e)).toList();
  }
}