enum MAType {
  ma5,
  ma10,
  ma20,
  ma60,
  ma120,
  ma240,
}

enum MainIndicator {
  ma,
  boll,
}

class IndicatorSetting {
  bool ma5 = true;
  bool ma10 = true;
  bool ma20 = true;

  bool ma60 = false;
  bool ma120 = false;
  bool ma240 = false;

  MainIndicator mainIndicator = MainIndicator.ma;

  int bollPeriod = 20;
  double bollStd = 2.0;
}