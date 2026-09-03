class MarketMarginDay {
  const MarketMarginDay({
    required this.date,
    required this.marginMoneyTodayBalance,
    required this.marginMoneyYesBalance,
    required this.shortSharesTodayBalance,
    required this.shortSharesYesBalance,
  });

  final DateTime date;

  // 融資餘額，單位「元」
  final double marginMoneyTodayBalance;
  final double marginMoneyYesBalance;

  // 融券餘額，單位「股」（顯示時要自己除以1000換算成「張」）
  final double shortSharesTodayBalance;
  final double shortSharesYesBalance;

  // 增減額＝今天餘額 － 昨天餘額
  double get marginMoneyChange =>
      marginMoneyTodayBalance - marginMoneyYesBalance;

  double get shortSharesChange =>
      shortSharesTodayBalance - shortSharesYesBalance;

  factory MarketMarginDay.fromJson(Map<String, dynamic> json) {

    double asDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;

    return MarketMarginDay(
      date: DateTime.parse(json["date"]),
      marginMoneyTodayBalance:
          asDouble(json["margin_money_today_balance"]),
      marginMoneyYesBalance:
          asDouble(json["margin_money_yes_balance"]),
      shortSharesTodayBalance:
          asDouble(json["short_shares_today_balance"]),
      shortSharesYesBalance:
          asDouble(json["short_shares_yes_balance"]),
    );
  }
}