enum InvestorPeriod {
  day5,
  day10,
  day20,
  day30,
}

enum InvestorChartType {
  price,
  total,
}

extension InvestorPeriodX on InvestorPeriod {
  int get days {
    switch (this) {
      case InvestorPeriod.day5:
        return 5;
      case InvestorPeriod.day10:
        return 10;
      case InvestorPeriod.day20:
        return 20;
      case InvestorPeriod.day30:
        return 30;
    }
  }

  String get label => "$days日";
}