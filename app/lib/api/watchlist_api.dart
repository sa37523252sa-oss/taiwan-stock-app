import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/watchlist.dart';

class WatchlistApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<WatchlistInfo>> getWatchlists() async {

    final response = await http.get(Uri.parse("$baseUrl/watchlists"));

    if (response.statusCode != 200) {
      throw Exception(
        "取得自選股清單失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    final List<dynamic> data = json.decode(response.body);

    return data.map((e) => WatchlistInfo.fromJson(e)).toList();
  }

  static Future<void> renameWatchlist(int id, String name) async {

    final response = await http.put(
      Uri.parse("$baseUrl/watchlists/$id"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"name": name}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "重新命名失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }

  static Future<List<WatchlistStock>> getWatchlistStocks(int id) async {

    final response =
        await http.get(Uri.parse("$baseUrl/watchlists/$id/stocks"));

    if (response.statusCode != 200) {
      throw Exception(
        "取得自選股內容失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    final List<dynamic> data = json.decode(response.body);

    return data.map((e) => WatchlistStock.fromJson(e)).toList();
  }

  static Future<void> addStock(int watchlistId, String code) async {

    final response = await http.post(
      Uri.parse("$baseUrl/watchlists/$watchlistId/stocks"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"code": code}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "加入自選股失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }

  static Future<void> removeStock(int watchlistId, String code) async {

    final response = await http.delete(
      Uri.parse("$baseUrl/watchlists/$watchlistId/stocks/$code"),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "移除自選股失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }

  static Future<void> reorderStocks(
    int watchlistId,
    List<String> orderedCodes,
  ) async {

    final response = await http.put(
      Uri.parse("$baseUrl/watchlists/$watchlistId/reorder"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"codes": orderedCodes}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "排序失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }
  }
}