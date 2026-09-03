class Holding {
  const Holding({
    required this.id,
    required this.code,
    required this.companyName,
    required this.avgPrice,
    required this.shares,
    required this.currentPrice,
    required this.cost,
    required this.buyFee,
    required this.marketValue,
    required this.profitLoss,
    required this.profitLossPct,
    required this.sellFee,
    required this.sellTax,
    this.dividendTotal,
    this.dividendCount,
    this.totalReturn,
    this.totalReturnPct,
  });

  final int id;
  final String code;
  final String? companyName;
  final double avgPrice;
  final int shares;
  final double? currentPrice;

  final double cost;
  final double buyFee;
  final double? marketValue;
  final double? profitLoss;
  final double? profitLossPct;
  final double? sellFee;
  final double? sellTax;

  // 這段持有期間領到的現金股利（只算現金股利，不算股票股利）、
  // 領了幾次、含息總報酬（價差損益+股利）
  final double? dividendTotal;
  final int? dividendCount;
  final double? totalReturn;
  final double? totalReturnPct;

  factory Holding.fromJson(Map<String, dynamic> json) {

    double? asDouble(dynamic v) =>
        v == null ? null : (v as num).toDouble();

    return Holding(
      id: json["id"],
      code: json["code"],
      companyName: json["company_name"],
      avgPrice: (json["avg_price"] as num).toDouble(),
      shares: json["shares"],
      currentPrice: asDouble(json["current_price"]),
      cost: (json["cost"] as num).toDouble(),
      buyFee: (json["buy_fee"] as num).toDouble(),
      marketValue: asDouble(json["market_value"]),
      profitLoss: asDouble(json["profit_loss"]),
      profitLossPct: asDouble(json["profit_loss_pct"]),
      sellFee: asDouble(json["sell_fee"]),
      sellTax: asDouble(json["sell_tax"]),
      dividendTotal: asDouble(json["dividend_total"]),
      dividendCount: json["dividend_count"],
      totalReturn: asDouble(json["total_return"]),
      totalReturnPct: asDouble(json["total_return_pct"]),
    );
  }
}