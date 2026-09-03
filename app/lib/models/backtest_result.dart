import 'screener_selection.dart';

class BacktestAssetPoint {
  const BacktestAssetPoint({
    required this.date,
    required this.value,
  });

  final DateTime date;
  final double value;

  factory BacktestAssetPoint.fromJson(Map<String, dynamic> json) {
    return BacktestAssetPoint(
      date: DateTime.parse(json["date"]),
      value: (json["value"] as num).toDouble(),
    );
  }
}

class BacktestTrade {
  const BacktestTrade({
    required this.date,
    required this.action,
    required this.price,
    required this.shares,
    required this.profit,
    this.code,
  });

  final DateTime date;
  final String action; // "buy" / "sell"
  final double price;
  // double 不是 int：定期定額模式允許買零股，股數可能是小數
  // （例如 81.6349 股），其他模式股數雖然一定是整數，但共用同一個
  // 型別，顯示時再依模式決定要不要四捨五入成整數。
  final double shares;
  final double? profit;
  final String? code; // 多股票組合模式才有，標示這筆交易屬於哪支股票

  factory BacktestTrade.fromJson(Map<String, dynamic> json) {
    return BacktestTrade(
      date: DateTime.parse(json["date"]),
      action: json["action"],
      price: (json["price"] as num).toDouble(),
      shares: (json["shares"] as num).toDouble(),
      profit: json["profit"] == null
          ? null
          : (json["profit"] as num).toDouble(),
      code: json["code"],
    );
  }
}

class BacktestMetrics {
  const BacktestMetrics({
    required this.totalReturn,
    required this.cagr,
    required this.maxDrawdown,
    required this.sharpe,
    required this.winRate,
    required this.tradeCount,
  });

  final double totalReturn;
  final double cagr;
  final double maxDrawdown;
  final double sharpe;
  final double winRate;
  final int tradeCount;

  factory BacktestMetrics.fromJson(Map<String, dynamic> json) {
    return BacktestMetrics(
      totalReturn: (json["total_return"] as num?)?.toDouble() ?? 0,
      cagr: (json["cagr"] as num?)?.toDouble() ?? 0,
      maxDrawdown: (json["max_drawdown"] as num?)?.toDouble() ?? 0,
      sharpe: (json["sharpe"] as num?)?.toDouble() ?? 0,
      winRate: (json["win_rate"] as num?)?.toDouble() ?? 0,
      tradeCount: json["trade_count"] ?? 0,
    );
  }
}

class BacktestResult {
  const BacktestResult({
    required this.assetCurve,
    required this.trades,
    required this.metrics,
    this.error,
    this.weights,
    this.perStock,
    this.selections,
    this.totalFee,
    this.totalTax,
    this.totalDividend,
    this.finalValue,
    this.totalInvested,
    this.totalShares,
  });

  final List<BacktestAssetPoint> assetCurve;
  final List<BacktestTrade> trades;
  final BacktestMetrics? metrics;
  final String? error;

  // 多股票組合模式才有：每支股票實際分配到的權重(%)、
  // 各自獨立算出來的績效指標
  final Map<String, double>? weights;
  final Map<String, BacktestMetrics>? perStock;

  // 選股策略模式才有：每次審核時間點選出的成分股清單
  final List<ScreenerSelection>? selections;

  // 選股策略模式才有：整段回測累計的手續費/交易稅、最終資產
  final double? totalFee;
  final double? totalTax;
  final double? finalValue;

  // 三種模式都有：整段回測期間持有股票領到的現金股利總額
  // （只算現金股利，不算股票股利）
  final double? totalDividend;

  // 定期定額模式才有：總共投入的本金、累積到的股數（可能含零股）
  final double? totalInvested;
  final double? totalShares;

  factory BacktestResult.fromJson(Map<String, dynamic> json) {

    if (json["error"] != null) {
      return BacktestResult(
        assetCurve: const [],
        trades: const [],
        metrics: null,
        error: json["error"],
      );
    }

    return BacktestResult(
      assetCurve: (json["asset_curve"] as List)
          .map((e) => BacktestAssetPoint.fromJson(e))
          .toList(),
      trades: (json["trades"] as List)
          .map((e) => BacktestTrade.fromJson(e))
          .toList(),
      metrics: BacktestMetrics.fromJson(json["metrics"]),
      weights: json["weights"] == null
          ? null
          : (json["weights"] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
      perStock: json["per_stock"] == null
          ? null
          : (json["per_stock"] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, BacktestMetrics.fromJson(v))),
      selections: json["selections"] == null
          ? null
          : (json["selections"] as List)
              .map((e) => ScreenerSelection.fromJson(e))
              .toList(),
      totalFee: (json["total_fee"] as num?)?.toDouble(),
      totalTax: (json["total_tax"] as num?)?.toDouble(),
      totalDividend: (json["total_dividend"] as num?)?.toDouble(),
      finalValue: (json["final_value"] as num?)?.toDouble(),
      totalInvested: (json["total_invested"] as num?)?.toDouble(),
      totalShares: (json["total_shares"] as num?)?.toDouble(),
    );
  }
}