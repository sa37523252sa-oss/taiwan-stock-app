import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/candle.dart';

class KlineApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<Candle>> getKline(
    String code, {
    int? limit,
  }) async {
    final uri = Uri.parse(
      limit == null
          ? "$baseUrl/kline/$code"
          : "$baseUrl/kline/$code?limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得K線失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => Candle.fromJson(e))
        .toList();
  }

  /// 大盤指數/期貨專用，volume 欄位是成交金額（不是股數/口數）
  static Future<List<Candle>> getMarketKline(
    String code, {
    int? limit,
  }) async {
    final uri = Uri.parse(
      limit == null
          ? "$baseUrl/market/kline/$code"
          : "$baseUrl/market/kline/$code?limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得大盤K線失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => Candle.fromJson(e))
        .toList();
  }
}