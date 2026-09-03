import 'backtest_condition.dart';

class PortfolioStockInput {
  PortfolioStockInput({
    required this.code,
    required this.name,
    this.weight,
    required this.buyConditionGroups,
    required this.sellConditionGroups,
  });

  final String code;
  final String name;

  // 0~100，null 代表沒手動設定，平分剩餘額度
  double? weight;

  List<List<BacktestCondition>> buyConditionGroups;
  List<List<BacktestCondition>> sellConditionGroups;

  Map<String, dynamic> toJson() {
    return {
      "code": code,
      "weight": weight,
      "buy_conditions": buyConditionGroups
          .map((group) => group.map((c) => c.toJson()).toList())
          .toList(),
      "sell_conditions": sellConditionGroups
          .map((group) => group.map((c) => c.toJson()).toList())
          .toList(),
    };
  }
}