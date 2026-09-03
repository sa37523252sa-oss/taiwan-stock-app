class ScreenerSelection {
  const ScreenerSelection({
    required this.date,
    required this.codes,
  });

  final DateTime date;
  final List<String> codes;

  factory ScreenerSelection.fromJson(Map<String, dynamic> json) {
    return ScreenerSelection(
      date: DateTime.parse(json["date"]),
      codes: List<String>.from(json["codes"]),
    );
  }
}