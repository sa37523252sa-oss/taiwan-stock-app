import 'dart:convert';
import '../services/api_config.dart';

import 'package:http/http.dart' as http;

import '../models/backtest_result.dart';
import '../models/backtest_condition.dart';
import '../models/portfolio_stock_input.dart';
import '../models/rank_field.dart';

class BacktestApi {
  static String get baseUrl => kBaseUrl;

  static Future<BacktestResult> runMaCross({
    required String code,
    required DateTime startDate,
    required DateTime endDate,
    required int buyFast,
    required int buySlow,
    required int sellFast,
    required int sellSlow,
    required double initialCapital,
    double? feeDiscount,
  }) async {

    String fmt(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final response = await http.post(
      Uri.parse("$baseUrl/backtest/ma_cross"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "code": code,
        "start_date": fmt(startDate),
        "end_date": fmt(endDate),
        "buy_fast": buyFast,
        "buy_slow": buySlow,
        "sell_fast": sellFast,
        "sell_slow": sellSlow,
        "initial_capital": initialCapital,
        "fee_discount": feeDiscount,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "回測失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    return BacktestResult.fromJson(json.decode(response.body));
  }

  /// 通用版本：群組結構（外層OR、內層AND），多種條件類型
  static Future<BacktestResult> runBacktest({
    required String code,
    required DateTime startDate,
    required DateTime endDate,
    required List<List<BacktestCondition>> buyConditionGroups,
    required List<List<BacktestCondition>> sellConditionGroups,
    required double initialCapital,
    double? feeDiscount,
  }) async {

    String fmt(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final response = await http.post(
      Uri.parse("$baseUrl/backtest/run"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "code": code,
        "start_date": fmt(startDate),
        "end_date": fmt(endDate),
        "buy_conditions": buyConditionGroups
            .map((group) => group.map((c) => c.toJson()).toList())
            .toList(),
        "sell_conditions": sellConditionGroups
            .map((group) => group.map((c) => c.toJson()).toList())
            .toList(),
        "initial_capital": initialCapital,
        "fee_discount": feeDiscount,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "回測失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    return BacktestResult.fromJson(json.decode(response.body));
  }

  static Future<BacktestResult> runPortfolioBacktest({
    required List<PortfolioStockInput> stocks,
    required DateTime startDate,
    required DateTime endDate,
    required double initialCapital,
    double? feeDiscount,
  }) async {

    String fmt(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final response = await http.post(
      Uri.parse("$baseUrl/backtest/portfolio"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "stocks": stocks.map((s) => s.toJson()).toList(),
        "start_date": fmt(startDate),
        "end_date": fmt(endDate),
        "initial_capital": initialCapital,
        "fee_discount": feeDiscount,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "回測失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    return BacktestResult.fromJson(json.decode(response.body));
  }

  static Future<BacktestResult> runScreenerBacktest({
    required List<List<BacktestCondition>> screeningConditionGroups,
    required DateTime startDate,
    required DateTime endDate,
    required int rebalanceMonths,
    int? maxStocks,
    List<RankField>? rankFields,
    required double initialCapital,
    double? feeDiscount,
  }) async {

    String fmt(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final response = await http.post(
      Uri.parse("$baseUrl/backtest/screener"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "screening_conditions": screeningConditionGroups
            .map((group) => group.map((c) => c.toJson()).toList())
            .toList(),
        "start_date": fmt(startDate),
        "end_date": fmt(endDate),
        "rebalance_months": rebalanceMonths,
        "max_stocks": maxStocks,
        "rank_fields": rankFields?.map((r) => r.toJson()).toList(),
        "initial_capital": initialCapital,
        "fee_discount": feeDiscount,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "回測失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    return BacktestResult.fromJson(json.decode(response.body));
  }

  static Future<BacktestResult> runDcaBacktest({
    required String code,
    required DateTime startDate,
    required DateTime endDate,
    required double amountPerPeriod,
    required int intervalMonths,
    double? feeDiscount,
  }) async {

    String fmt(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final response = await http.post(
      Uri.parse("$baseUrl/backtest/dca"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "code": code,
        "start_date": fmt(startDate),
        "end_date": fmt(endDate),
        "amount_per_period": amountPerPeriod,
        "interval_months": intervalMonths,
        "fee_discount": feeDiscount,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "回測失敗（狀態碼 ${response.statusCode}）：${response.body}",
      );
    }

    return BacktestResult.fromJson(json.decode(response.body));
  }
}