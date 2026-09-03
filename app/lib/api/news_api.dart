import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/news_item.dart';

class NewsApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<NewsItem>> getNews(
    String code, {
    int limit = 30,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/news/$code?limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得新聞失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => NewsItem.fromJson(e))
        .toList();
  }

  /// 首頁新聞頁用：庫存股+自選股合併新聞
  static Future<List<NewsItem>> getPortfolioNews({
    int minScore = 40,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/news/portfolio/all?min_score=$minScore&limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得庫存股/自選股新聞失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => NewsItem.fromJson(e))
        .toList();
  }

  /// 首頁新聞頁用：大盤+國際財經合併新聞
  static Future<List<NewsItem>> getMarketNews({
    int minScore = 40,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/news/market/all?min_score=$minScore&limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得大盤/國際新聞失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => NewsItem.fromJson(e))
        .toList();
  }
}