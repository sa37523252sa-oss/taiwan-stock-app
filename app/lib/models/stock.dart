class Stock {
  final String code;
  final String name;
  final String industry;

  final double price;
  final double open;
  final double high;
  final double low;
  final double close;

  final int volume;

  final double? epsTtm;
  final double? pe;
  final double? pb;
  final double? dividendYield;

  final bool financialSupported;

  final String? website;

  Stock({
    required this.code,
    required this.name,
    required this.industry,
    required this.price,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.epsTtm,

    this.pe,
    this.pb,
    this.dividendYield,

    required this.financialSupported,
    this.website,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    print(json);
    double toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    int toInt(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? 0;
    }

    return Stock(
      code: json["code"] ?? "",
      name: json["name"] ?? "",
      industry: json["industry"] ?? "",

      price: toDouble(json["price"] ?? json["close"]),
      open: toDouble(json["open"]),
      high: toDouble(json["high"]),
      low: toDouble(json["low"]),
      close: toDouble(json["close"]),
      volume: toInt(json["volume"]),

      epsTtm: json["eps_ttm"] == null
          ? null
          : toDouble(json["eps_ttm"]),

      pe: json["pe"] == null
          ? null
          : toDouble(json["pe"]),

      pb: json["pb"] == null
          ? null
          : toDouble(json["pb"]),

      dividendYield: json["dividendYield"] == null
          ? (json["dividend_yield"] == null
              ? null
              : toDouble(json["dividend_yield"]))
          : toDouble(json["dividendYield"]),

      financialSupported:
          json["financial_supported"] ?? true,

      website: (json["website"] as String?)?.isNotEmpty == true
          ? json["website"]
          : null,
    );
  }
}