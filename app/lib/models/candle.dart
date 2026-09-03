class Candle {
  final DateTime date;

  final double open;
  final double high;
  final double low;
  final double close;

  final double volume;

  Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return Candle(
      date: DateTime.parse(json["date"]),
      open: toDouble(json["open"]),
      high: toDouble(json["high"]),
      low: toDouble(json["low"]),
      close: toDouble(json["close"]),
      volume: toDouble(json["volume"]),
    );
  }
}