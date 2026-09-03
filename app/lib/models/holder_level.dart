class HolderLevel {
  const HolderLevel({
    required this.date,
    required this.level,
    required this.people,
    required this.percent,
  });

  final DateTime date;
  final String level;
  final int? people;
  final double? percent;

  factory HolderLevel.fromJson(Map<String, dynamic> json) {
    return HolderLevel(
      date: DateTime.parse(json["date"]),
      level: json["level"].toString(),
      people: (json["people"] as num?)?.toInt(),
      percent: (json["percent"] as num?)?.toDouble(),
    );
  }
}