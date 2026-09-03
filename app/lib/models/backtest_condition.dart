enum ConditionType {
  maCross, priceVsMa, priceAbove, priceBelow,
  volumeSpike, volumeNewHigh, volumeBreakout,
  liquidityTradingValueAbove, liquidityVolumeAbove,
  fundamentalAbove, fundamentalBelow, fundamentalNewHigh,
  fundamentalGrowth, fundamentalConsistent,
}

/// 基本面欄位選項，label 給畫面顯示，field 是後端 DB 欄位名稱
/// （已跟實際資料庫核對過，這些欄位真的存在）
class FundamentalField {
  const FundamentalField(this.field, this.label);
  final String field;
  final String label;

  static const options = [
    FundamentalField("pe", "本益比"),
    FundamentalField("eps", "EPS"),
    FundamentalField("roe", "ROE"),
    FundamentalField("roa", "ROA"),
    FundamentalField("gross_margin", "毛利率"),
    FundamentalField("operating_margin", "營業利益率"),
    FundamentalField("revenue", "營收"),
    FundamentalField("dividend_yield", "殖利率"),
    FundamentalField("debt_ratio", "負債比"),
    FundamentalField("free_cash_flow", "自由現金流"),
  ];

  static String labelOf(String field) {
    return options
        .firstWhere((o) => o.field == field, orElse: () => FundamentalField(field, field))
        .label;
  }
}

/// 比較符選項，給「高於/低於數值」模式用
class CompareOperator {
  const CompareOperator(this.op, this.label);
  final String op;
  final String label;

  static const options = [
    CompareOperator(">", "高於"),
    CompareOperator("<", "低於"),
    CompareOperator(">=", "大於等於"),
    CompareOperator("<=", "小於等於"),
    CompareOperator("==", "等於"),
  ];

  static String labelOf(String op) {
    return options
        .firstWhere((o) => o.op == op, orElse: () => CompareOperator(op, op))
        .label;
  }
}

class BacktestCondition {
  BacktestCondition.maCross({
    required this.fast,
    required this.slow,
    required this.direction,
  }) : type = ConditionType.maCross,
       period = null,
       operator = null,
       value = null,
       multiplier = null,
       minMultiplier = null,
       field = null,
       quartersBack = null,
       quarters = null;

  BacktestCondition.priceVsMa({
    required this.period,
    required this.direction,
  }) : type = ConditionType.priceVsMa,
       fast = null,
       slow = null,
       operator = null,
       value = null,
       multiplier = null,
       minMultiplier = null,
       field = null,
       quartersBack = null,
       quarters = null;

  BacktestCondition.priceAbove({required this.value})
      : type = ConditionType.priceAbove,
        fast = null,
        slow = null,
        period = null,
        direction = null,
        operator = null,
        multiplier = null,
        minMultiplier = null,
        field = null,
        quartersBack = null,
        quarters = null;

  BacktestCondition.priceBelow({required this.value})
      : type = ConditionType.priceBelow,
        fast = null,
        slow = null,
        period = null,
        direction = null,
        operator = null,
        multiplier = null,
        minMultiplier = null,
        field = null,
        quartersBack = null,
        quarters = null;

  BacktestCondition.volumeSpike({
    required this.period,
    required this.multiplier,
  }) : type = ConditionType.volumeSpike,
       fast = null,
       slow = null,
       direction = null,
       operator = null,
       value = null,
       minMultiplier = null,
       field = null,
       quartersBack = null,
       quarters = null;

  BacktestCondition.volumeNewHigh({required this.period})
      : type = ConditionType.volumeNewHigh,
        fast = null,
        slow = null,
        direction = null,
        operator = null,
        value = null,
        multiplier = null,
        minMultiplier = null,
        field = null,
        quartersBack = null,
        quarters = null;

  BacktestCondition.volumeBreakout({
    required this.period,
    required this.direction,
    this.minMultiplier = 1.5,
  }) : type = ConditionType.volumeBreakout,
       fast = null,
       slow = null,
       operator = null,
       value = null,
       multiplier = null,
       field = null,
       quartersBack = null,
       quarters = null;

  /// 流通性：近 windowDays 日平均成交額 > value（單位：億元）
  BacktestCondition.liquidityTradingValueAbove({
    required this.value,
    int windowDays = 20,
  }) : type = ConditionType.liquidityTradingValueAbove,
       period = windowDays,
       fast = null,
       slow = null,
       direction = null,
       operator = null,
       multiplier = null,
       minMultiplier = null,
       field = null,
       quartersBack = null,
       quarters = null;

  /// 流通性：近 windowDays 日平均成交量 > value（單位：張）
  BacktestCondition.liquidityVolumeAbove({
    required this.value,
    int windowDays = 20,
  }) : type = ConditionType.liquidityVolumeAbove,
       period = windowDays,
       fast = null,
       slow = null,
       direction = null,
       operator = null,
       multiplier = null,
       minMultiplier = null,
       field = null,
       quartersBack = null,
       quarters = null;

  /// 高於/低於數值，operator 預設 ">"，可指定 "<"/">="/"<="/"=="
  BacktestCondition.fundamentalAbove({
    required this.field,
    required this.value,
    this.operator = ">",
  }) : type = ConditionType.fundamentalAbove,
       fast = null,
       slow = null,
       period = null,
       direction = null,
       multiplier = null,
       minMultiplier = null,
       quartersBack = null,
       quarters = null;

  BacktestCondition.fundamentalBelow({
    required this.field,
    required this.value,
    this.operator = "<",
  }) : type = ConditionType.fundamentalBelow,
       fast = null,
       slow = null,
       period = null,
       direction = null,
       multiplier = null,
       minMultiplier = null,
       quartersBack = null,
       quarters = null;

  /// 創新高：跟最近 quarters 季比較（不是跟資料庫全部歷史比）
  BacktestCondition.fundamentalNewHigh({
    required this.field,
    this.quarters = 12,
  }) : type = ConditionType.fundamentalNewHigh,
        fast = null,
        slow = null,
        period = null,
        direction = null,
        operator = null,
        value = null,
        multiplier = null,
        minMultiplier = null,
        quartersBack = null;

  /// 成長幅度：跟 quartersBack 季前比較，成長率高於/低於 value(%)
  BacktestCondition.fundamentalGrowth({
    required this.field,
    required this.direction,
    required this.value,
    this.quartersBack = 4,
  }) : type = ConditionType.fundamentalGrowth,
       fast = null,
       slow = null,
       period = null,
       operator = null,
       multiplier = null,
       minMultiplier = null,
       quarters = null;

  /// 連續維持：最近 quarters 季，每一季都要高於/低於 value
  BacktestCondition.fundamentalConsistent({
    required this.field,
    required this.direction,
    required this.value,
    this.quarters = 4,
  }) : type = ConditionType.fundamentalConsistent,
       fast = null,
       slow = null,
       period = null,
       operator = null,
       multiplier = null,
       minMultiplier = null,
       quartersBack = null;

  final ConditionType type;

  final int? fast;
  final int? slow;

  // price_vs_ma/volume_new_high/volume_breakout 的天數；
  // liquidity_* 的平均天數視窗
  final int? period;
  final String? direction;

  // ">"|"<"|">="|"<="|"=="，給 fundamentalAbove/Below 用
  final String? operator;

  final double? value;

  final double? multiplier;

  final double? minMultiplier;

  final String? field;

  final int? quartersBack;

  // fundamentalConsistent：連續維持幾季；fundamentalNewHigh：比較範圍幾季
  final int? quarters;

  String get _typeString {
    switch (type) {
      case ConditionType.maCross:
        return "ma_cross";
      case ConditionType.priceVsMa:
        return "price_vs_ma";
      case ConditionType.priceAbove:
        return "price_above";
      case ConditionType.priceBelow:
        return "price_below";
      case ConditionType.volumeSpike:
        return "volume_spike";
      case ConditionType.volumeNewHigh:
        return "volume_new_high";
      case ConditionType.volumeBreakout:
        return "volume_breakout";
      case ConditionType.liquidityTradingValueAbove:
        return "liquidity_trading_value_above";
      case ConditionType.liquidityVolumeAbove:
        return "liquidity_volume_above";
      case ConditionType.fundamentalAbove:
        return "fundamental_above";
      case ConditionType.fundamentalBelow:
        return "fundamental_below";
      case ConditionType.fundamentalNewHigh:
        return "fundamental_new_high";
      case ConditionType.fundamentalGrowth:
        return "fundamental_growth";
      case ConditionType.fundamentalConsistent:
        return "fundamental_consistent";
    }
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{"type": _typeString};
    if (fast != null) map["fast"] = fast;
    if (slow != null) map["slow"] = slow;
    if (type == ConditionType.liquidityTradingValueAbove ||
        type == ConditionType.liquidityVolumeAbove) {
      if (period != null) map["window_days"] = period;
    } else if (period != null) {
      map["period"] = period;
    }
    if (direction != null) map["direction"] = direction;
    if (operator != null) map["operator"] = operator;
    if (value != null) map["value"] = value;
    if (multiplier != null) map["multiplier"] = multiplier;
    if (minMultiplier != null) map["min_multiplier"] = minMultiplier;
    if (field != null) map["field"] = field;
    if (quartersBack != null) map["quarters_back"] = quartersBack;
    if (quarters != null) map["quarters"] = quarters;
    return map;
  }

  /// 給畫面顯示用的簡短描述文字——不顯示內部 type/enum，只顯示
  /// 使用者看得懂的中文敘述，例如「ROE > 15」「EPS 跟4季前比
  /// 成長超過 20%」
  String get label {
    switch (type) {
      case ConditionType.maCross:
        final dirText = direction == "above" ? "向上突破" : "向下跌破";
        return "MA$fast $dirText MA$slow";
      case ConditionType.priceVsMa:
        final dirText = direction == "above" ? "站上" : "跌破";
        return "股價 $dirText MA$period";
      case ConditionType.priceAbove:
        return "股價 > $value";
      case ConditionType.priceBelow:
        return "股價 < $value";
      case ConditionType.volumeSpike:
        return "成交量 > $period日均量 × $multiplier倍";
      case ConditionType.volumeNewHigh:
        return "成交量創$period日新高";
      case ConditionType.volumeBreakout:
        final dirText = direction == "above" ? "高點" : "低點";
        return "突破近$period日大量日的$dirText";
      case ConditionType.liquidityTradingValueAbove:
        return "近$period日均成交額 > $value億";
      case ConditionType.liquidityVolumeAbove:
        return "近$period日均成交量 > $value張";
      case ConditionType.fundamentalAbove:
      case ConditionType.fundamentalBelow:
        final opText = CompareOperator.labelOf(operator ?? ">");
        return "${FundamentalField.labelOf(field!)} $opText $value";
      case ConditionType.fundamentalNewHigh:
        return "${FundamentalField.labelOf(field!)} 創近$quarters季新高";
      case ConditionType.fundamentalGrowth:
        final dirText = direction == "above" ? "成長超過" : "衰退超過";
        return "${FundamentalField.labelOf(field!)} 跟$quartersBack季前比$dirText $value%";
      case ConditionType.fundamentalConsistent:
        final dirText = direction == "above" ? ">" : "<";
        return "${FundamentalField.labelOf(field!)} 連續$quarters季都$dirText $value";
    }
  }
}