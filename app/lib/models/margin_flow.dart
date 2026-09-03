class MarginFlow {
  const MarginFlow({
    required this.date,
    required this.marginBuy,
    required this.marginSell,
    required this.marginCashRepayment,
    required this.marginTodayBalance,
    required this.marginYesterdayBalance,
    required this.marginLimit,
    required this.shortBuy,
    required this.shortSell,
    required this.shortCashRepayment,
    required this.shortTodayBalance,
    required this.shortYesterdayBalance,
    required this.shortLimit,
    required this.offsetLoanAndShort,
  });

  final DateTime date;

  final int marginBuy;
  final int marginSell;
  final int marginCashRepayment;
  final int marginTodayBalance;
  final int marginYesterdayBalance;
  final int marginLimit;

  final int shortBuy;
  final int shortSell;
  final int shortCashRepayment;
  final int shortTodayBalance;
  final int shortYesterdayBalance;
  final int shortLimit;

  // 資券互抵（資券當沖）
  final int offsetLoanAndShort;

  int get marginChange => marginTodayBalance - marginYesterdayBalance;
  int get shortChange => shortTodayBalance - shortYesterdayBalance;

  factory MarginFlow.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => (v as num?)?.toInt() ?? 0;

    return MarginFlow(
      date: DateTime.parse(json["date"]),
      marginBuy: toInt(json["margin_buy"]),
      marginSell: toInt(json["margin_sell"]),
      marginCashRepayment: toInt(json["margin_cash_repayment"]),
      marginTodayBalance: toInt(json["margin_today_balance"]),
      marginYesterdayBalance: toInt(json["margin_yesterday_balance"]),
      marginLimit: toInt(json["margin_limit"]),
      shortBuy: toInt(json["short_buy"]),
      shortSell: toInt(json["short_sell"]),
      shortCashRepayment: toInt(json["short_cash_repayment"]),
      shortTodayBalance: toInt(json["short_today_balance"]),
      shortYesterdayBalance: toInt(json["short_yesterday_balance"]),
      shortLimit: toInt(json["short_limit"]),
      offsetLoanAndShort: toInt(json["offset_loan_and_short"]),
    );
  }
}