class MarketIndexInfo {
  const MarketIndexInfo({
    required this.code,
    required this.name,
    required this.price,
    required this.change,
    required this.changePct,
  });

  final String code;
  final String name;
  final double? price;
  final double? change;
  final double? changePct;

  factory MarketIndexInfo.fromJson(Map<String, dynamic> json) {

    double? asDouble(dynamic v) =>
        v == null ? null : (v as num).toDouble();

    return MarketIndexInfo(
      code: json["code"],
      name: json["name"],
      price: asDouble(json["price"]),
      change: asDouble(json["change"]),
      changePct: asDouble(json["change_pct"]),
    );
  }
}