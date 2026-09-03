class WatchlistInfo {
  const WatchlistInfo({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.stockCount,
  });

  final int id;
  final String name;
  final int sortOrder;
  final int stockCount;

  factory WatchlistInfo.fromJson(Map<String, dynamic> json) {
    return WatchlistInfo(
      id: json["id"],
      name: json["name"],
      sortOrder: json["sort_order"],
      stockCount: json["stock_count"] ?? 0,
    );
  }
}

class WatchlistStock {
  const WatchlistStock({
    required this.code,
    required this.companyName,
    required this.currentPrice,
    required this.change,
    required this.changePct,
    required this.volume,
    required this.pe,
    required this.dividendYield,
  });

  final String code;
  final String? companyName;
  final double? currentPrice;
  final double? change;
  final double? changePct;
  final int? volume;
  final double? pe;
  final double? dividendYield;

  factory WatchlistStock.fromJson(Map<String, dynamic> json) {

    double? asDouble(dynamic v) =>
        v == null ? null : (v as num).toDouble();

    return WatchlistStock(
      code: json["code"],
      companyName: json["company_name"],
      currentPrice: asDouble(json["current_price"]),
      change: asDouble(json["change"]),
      changePct: asDouble(json["change_pct"]),
      volume: json["volume"],
      pe: asDouble(json["pe"]),
      dividendYield: asDouble(json["dividend_yield"]),
    );
  }
}