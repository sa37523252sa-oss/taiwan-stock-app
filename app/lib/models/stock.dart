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

  /// 這筆價格的交易日。畫面標「9/3 收盤」比「今日股價」誠實——
  /// 資料是每天排程更新的，不是即時報價。
  final String? date;

  /// 昨收與漲跌。判斷紅綠一定要用這個，不能拿 close 跟 open 比
  /// ——收盤高於開盤是「紅K」，跟「上漲」是兩回事：今天開高走低
  /// 但仍高於昨收，是綠K卻上漲。
  final double? prevClose;
  final double? change;
  final double? changePct;

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
    this.date,
    this.prevClose,
    this.change,
    this.changePct,
    this.epsTtm,
    this.pe,
    this.pb,
    this.dividendYield,
    required this.financialSupported,
    this.website,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    double? toDoubleOrNull(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
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
      date: json["date"] as String?,

      prevClose: toDoubleOrNull(json["prev_close"]),
      change: toDoubleOrNull(json["change"]),
      changePct: toDoubleOrNull(json["change_pct"]),

      epsTtm: toDoubleOrNull(json["eps_ttm"]),
      pe: toDoubleOrNull(json["pe"]),
      pb: toDoubleOrNull(json["pb"]),

      dividendYield: toDoubleOrNull(
        json["dividendYield"] ?? json["dividend_yield"],
      ),

      financialSupported:
          json["financial_supported"] ?? true,

      website: (json["website"] as String?)?.isNotEmpty == true
          ? json["website"]
          : null,
    );
  }
}