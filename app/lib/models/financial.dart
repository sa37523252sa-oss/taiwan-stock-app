class FinancialQuarter {
  const FinancialQuarter({
    required this.year,
    required this.quarter,
    required this.eps,
    required this.roe,
    required this.revenue,
    this.grossProfit,
    this.operatingProfit,
    this.pretaxProfit,
    this.netIncome,
    this.grossMargin,
    this.operatingMargin,
    this.netMargin,
    this.roa,
    this.bookValue,
    this.assets,
    this.liabilities,
    this.equity,
    this.operatingCashFlow,
    this.investingCashFlow,
    this.financingCashFlow,
    this.debtRatio,
    this.currentRatio,
    this.quickRatio,
    this.freeCashFlow,
    this.pe,
    this.pb,
    this.dividendYield,
    this.cashDividend,
    this.stockDividend,
    this.exDividendDate,
    this.cashDividendDate,
    this.stockDividendDate,
  });

  final int year;
  final int quarter;
  final double? eps;
  final double? roe;
  final double? revenue;

  final double? grossProfit;
  final double? operatingProfit;
  final double? pretaxProfit;
  final double? netIncome;

  final double? grossMargin;
  final double? operatingMargin;
  final double? netMargin;

  final double? roa;
  final double? bookValue;

  final double? assets;
  final double? liabilities;
  final double? equity;

  final double? operatingCashFlow;
  final double? investingCashFlow;
  final double? financingCashFlow;

  final double? debtRatio;
  final double? currentRatio;
  final double? quickRatio;

  final double? freeCashFlow;
  final double? pe;
  final double? pb;
  final double? dividendYield;
  final double? cashDividend;
  final double? stockDividend;

  final String? exDividendDate;
  final String? cashDividendDate;
  final String? stockDividendDate;

  factory FinancialQuarter.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic value) {
      if (value == null) return null;
      return (value as num).toDouble();
    }

    return FinancialQuarter(
      year: json["year"],
      quarter: json["quarter"],
      eps: toDouble(json["eps"]),
      roe: toDouble(json["roe"]),
      revenue: toDouble(json["revenue"]),
      grossProfit: toDouble(json["grossProfit"]),
      operatingProfit: toDouble(json["operatingProfit"]),
      pretaxProfit: toDouble(json["pretaxProfit"]),
      netIncome: toDouble(json["netIncome"]),
      grossMargin: toDouble(json["grossMargin"]),
      operatingMargin: toDouble(json["operatingMargin"]),
      netMargin: toDouble(json["netMargin"]),
      roa: toDouble(json["roa"]),
      bookValue: toDouble(json["bookValue"]),
      assets: toDouble(json["assets"]),
      liabilities: toDouble(json["liabilities"]),
      equity: toDouble(json["equity"]),
      operatingCashFlow: toDouble(json["operatingCashFlow"]),
      investingCashFlow: toDouble(json["investingCashFlow"]),
      financingCashFlow: toDouble(json["financingCashFlow"]),
      debtRatio: toDouble(json["debtRatio"]),
      currentRatio: toDouble(json["currentRatio"]),
      quickRatio: toDouble(json["quickRatio"]),
      freeCashFlow: toDouble(json["freeCashFlow"]),
      pe: toDouble(json["pe"]),
      pb: toDouble(json["pb"]),
      dividendYield: toDouble(json["dividendYield"]),
      cashDividend: toDouble(json["cashDividend"]),
      stockDividend: toDouble(json["stockDividend"]),

      exDividendDate: json["exDividendDate"],
      cashDividendDate: json["cashDividendDate"],
      stockDividendDate: json["stockDividendDate"],
    );
  }
}

class FinancialMonth {
  const FinancialMonth({
    required this.year,
    required this.month,
    this.revenue,
    this.mom,
    this.yoy,
  });

  final int year;
  final int month;
  final double? revenue;
  final double? mom;
  final double? yoy;

  factory FinancialMonth.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic value) {
      if (value == null) return null;
      return (value as num).toDouble();
    }

    return FinancialMonth(
      year: json["year"],
      month: json["month"],
      revenue: toDouble(json["revenue"]),
      mom: toDouble(json["mom"]),
      yoy: toDouble(json["yoy"]),
    );
  }
}

class FinancialData {
  const FinancialData({
    required this.quarter,
    required this.month,
  });

  final List<FinancialQuarter> quarter;
  final List<FinancialMonth> month;

  factory FinancialData.fromJson(Map<String, dynamic> json) {
    return FinancialData(
      quarter: (json["quarter"] as List)
          .map((e) => FinancialQuarter.fromJson(e))
          .toList(),
      month: (json["month"] as List)
          .map((e) => FinancialMonth.fromJson(e))
          .toList(),
    );
  }
}