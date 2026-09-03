import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/disclosure.dart';

class DisclosureApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<Disclosure>> getDisclosures(
    String code, {
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/disclosures/$code?limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得公司會議資訊失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => Disclosure.fromJson(e))
        .toList();
  }

  /// 重大動態
  static Future<List<Disclosure>> getMajorEvents(
    String code, {
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/disclosures/$code/events?limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得重大動態失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => Disclosure.fromJson(e))
        .toList();
  }

  /// 法說／股東會
  static Future<List<Disclosure>> getMeetings(
    String code, {
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/disclosures/$code/meetings?limit=$limit",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得法說/股東會資訊失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => Disclosure.fromJson(e))
        .toList();
  }
}