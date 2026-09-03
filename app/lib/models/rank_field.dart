class RankFieldOption {
  const RankFieldOption(this.field, this.label);
  final String field;
  final String label;

  static const options = [
    RankFieldOption("liquidity_trading_value", "成交額（流通性）"),
    RankFieldOption("liquidity_volume", "成交量（流通性）"),
    RankFieldOption("pe", "本益比"),
    RankFieldOption("eps", "EPS"),
    RankFieldOption("roe", "ROE"),
    RankFieldOption("roa", "ROA"),
    RankFieldOption("gross_margin", "毛利率"),
    RankFieldOption("operating_margin", "營業利益率"),
    RankFieldOption("revenue", "營收"),
    RankFieldOption("dividend_yield", "殖利率"),
    RankFieldOption("debt_ratio", "負債比"),
    RankFieldOption("free_cash_flow", "自由現金流"),
  ];

  static String labelOf(String field) {
    return options
        .firstWhere((o) => o.field == field,
            orElse: () => RankFieldOption(field, field))
        .label;
  }
}

class RankField {
  RankField({required this.field, this.direction = "desc"});

  String field;
  String direction; // "desc" | "asc"

  Map<String, dynamic> toJson() => {"field": field, "direction": direction};
}