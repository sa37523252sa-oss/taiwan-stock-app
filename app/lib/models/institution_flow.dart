class InstitutionFlow {
  const InstitutionFlow({
    required this.date,
    required this.foreign,
    required this.trust,
    required this.dealer,
    required this.close,
  });

  final DateTime date;
  final double foreign;
  final double trust;
  final double dealer;
  final double? close;

  double get total => foreign + trust + dealer;

  factory InstitutionFlow.fromJson(Map<String, dynamic> json) {
    return InstitutionFlow(
      date: DateTime.parse(json["date"]),
      foreign: (json["foreign"] as num).toDouble(),
      trust: (json["trust"] as num).toDouble(),
      dealer: (json["dealer"] as num).toDouble(),
      close: (json["close"] as num?)?.toDouble(),
    );
  }
}