class MarketInstitutionalDay {
  const MarketInstitutionalDay({
    required this.date,
    required this.foreignNet,
    required this.trustNet,
    required this.dealerNet,
    required this.totalNet,
  });

  final DateTime date;
  final double foreignNet;
  final double trustNet;
  final double dealerNet;
  final double totalNet;

  factory MarketInstitutionalDay.fromJson(Map<String, dynamic> json) {

    double net(String prefix) {
      final buy = (json["${prefix}_buy"] as num?)?.toDouble() ?? 0;
      final sell = (json["${prefix}_sell"] as num?)?.toDouble() ?? 0;
      return buy - sell;
    }

    return MarketInstitutionalDay(
      date: DateTime.parse(json["date"]),
      foreignNet: net("foreign"),
      trustNet: net("trust"),
      dealerNet: net("dealer"),
      totalNet: net("total"),
    );
  }
}