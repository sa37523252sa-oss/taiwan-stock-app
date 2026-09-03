import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/financial.dart';

class FinancialApi {
  static String get baseUrl => kBaseUrl;

  static Future<FinancialData> getFinancial(String code) async {

    print("=== GET Financial ===");
    print("$baseUrl/financial/$code");

    final response =
        await http.get(Uri.parse("$baseUrl/financial/$code"));

    print("status = ${response.statusCode}");
    print(response.body);

    if (response.statusCode != 200) {
      throw Exception("取得財務資料失敗");
    }

    return FinancialData.fromJson(
      jsonDecode(response.body),
    );
  }
}