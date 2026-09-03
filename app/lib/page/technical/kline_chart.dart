import 'package:flutter/material.dart';

import '../../models/candle.dart';
import 'kline_painter.dart';
import '../../models/indicator_setting.dart';

class KlineChart extends StatelessWidget {
  const KlineChart({
    super.key,
    required this.candles,
    required this.visibleCount,
    required this.startIndex,
    this.selectedIndex,
    required this.ma5,
    required this.ma10,
    required this.ma20,
    required this.ma60,
    required this.ma120,
    required this.ma240,
    required this.bollUpper,
    required this.bollMiddle,
    required this.bollLower,
    required this.indicator,
  });

  final List<Candle> candles;
  final int visibleCount;
  final int startIndex;
  final int? selectedIndex;
  final List<double?> ma5;
  final List<double?> ma10;
  final List<double?> ma20;
  final List<double?> ma60;
  final List<double?> ma120;
  final List<double?> ma240;
  final List<double?> bollUpper;
  final List<double?> bollMiddle;
  final List<double?> bollLower;
  final IndicatorSetting indicator;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) {
      return const Center(
        child: Text("沒有K線資料"),
      );
    }

    return CustomPaint(
      painter: KlinePainter(
        candles,
        visibleCount: visibleCount,
        startIndex: startIndex,
        selectedIndex: selectedIndex,
        ma5: ma5,
        ma10: ma10,
        ma20: ma20,
        ma60: ma60,
        ma120: ma120,
        ma240: ma240,
        bollUpper: bollUpper,
        bollMiddle: bollMiddle,
        bollLower: bollLower,
        indicator: indicator,
      ),
      size: Size.infinite,
    );
  }
}