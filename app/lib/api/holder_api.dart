import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/holder_level.dart';

class HolderApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<HolderLevel>> getHolder(
    String code,
  ) async {
    final uri = Uri.parse(
      "$baseUrl/holder/$code",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得大戶持股資料失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => HolderLevel.fromJson(e))
        .toList();
  }
}