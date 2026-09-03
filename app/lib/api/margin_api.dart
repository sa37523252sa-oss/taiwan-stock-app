import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/margin_flow.dart';

class MarginApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<MarginFlow>> getMargin(
    String code,
  ) async {
    final uri = Uri.parse(
      "$baseUrl/margin/$code",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得資券資料失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => MarginFlow.fromJson(e))
        .toList();
  }
}