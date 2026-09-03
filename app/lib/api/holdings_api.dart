import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/holding.dart';

class HoldingsApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<Holding>> getHoldings() async {

    final response = await http.get(Uri.parse("$baseUrl/holdings"));

    if (response.statusCode != 200) {
      throw Exception(
        "取得庫存股失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    final List<dynamic> data = json.decode(response.body);

    return data.map((e) => Holding.fromJson(e)).toList();
  }

  static Future<void> addHolding({
    required String code,
    required double avgPrice,
    required int shares,
  }) async {

    final response = await http.post(
      Uri.parse("$baseUrl/holdings"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "code": code,
        "avg_price": avgPrice,
        "shares": shares,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "新增庫存股失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }

  static Future<void> updateHolding({
    required int id,
    required double avgPrice,
    required int shares,
  }) async {

    final response = await http.put(
      Uri.parse("$baseUrl/holdings/$id"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "avg_price": avgPrice,
        "shares": shares,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "更新庫存股失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }

  static Future<void> deleteHolding(int id) async {

    final response = await http.delete(
      Uri.parse("$baseUrl/holdings/$id"),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "刪除庫存股失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }

  static Future<double?> getFeeDiscount() async {

    final response =
        await http.get(Uri.parse("$baseUrl/settings/fee_discount"));

    if (response.statusCode != 200) {
      throw Exception(
        "取得手續費折扣失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    final data = json.decode(response.body);
    final discount = data["discount"];

    return discount == null ? null : (discount as num).toDouble();
  }

  static Future<void> setFeeDiscount(double? discount) async {

    final response = await http.post(
      Uri.parse("$baseUrl/settings/fee_discount"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"discount": discount}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "設定手續費折扣失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }
}