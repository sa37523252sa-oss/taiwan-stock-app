import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/institution_flow.dart';

class InstitutionApi {
  static String get baseUrl => kBaseUrl;

  static Future<List<InstitutionFlow>> getInstitution(
    String code,
  ) async {
    final uri = Uri.parse(
      "$baseUrl/institution/$code",
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("取得三大法人資料失敗");
    }

    final List<dynamic> jsonData = json.decode(response.body);

    return jsonData
        .map((e) => InstitutionFlow.fromJson(e))
        .toList();
  }
}