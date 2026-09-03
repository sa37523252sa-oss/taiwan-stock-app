import 'package:flutter/material.dart';

import '../../models/market_margin_day.dart';

/// 融資融券餘額的迷你折線圖。融資是金額（元）、融券是股數，
/// 單位天差地遠，硬放同一軸會讓其中一條線變成一直線看不出
/// 變化，所以用雙軸：左軸融資（億元）、右軸融券（張）。
class MarginMiniChart extends StatelessWidget {
  const MarginMiniChart({
    super.key,
    required this.days,
  });

  final List<MarketMarginDay> days;

  static const marginColor = Color(0xFFEF4444); // 融資：紅
  static const shortColor = Color(0xFF10B981);  // 融券：綠

  @override
  Widget build(BuildContext context) {

    if (days.isEmpty) {
      return const Center(child: Text("沒有資料"));
    }

    return CustomPaint(
      painter: _Painter(days: days),
      size: Size.infinite,
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({required this.days});

  final List<MarketMarginDay> days;

  @override
  void paint(Canvas canvas, Size size) {

    const leftPadding = 42.0;
    const rightPadding = 42.0;
    const topPadding = 8.0;
    const bottomPadding = 20.0;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightPadding,
      size.height - topPadding - bottomPadding,
    );

    // 左軸：融資餘額，單位換算成億元
    final marginValues =
        days.map((d) => d.marginMoneyTodayBalance / 100000000).toList();

    // 右軸：融券餘額，單位換算成張
    final shortValues =
        days.map((d) => d.shortSharesTodayBalance / 1000).toList();

    final marginMax = marginValues.reduce((a, b) => a > b ? a : b);
    final marginMin = marginValues.reduce((a, b) => a < b ? a : b);
    final marginRange =
        (marginMax - marginMin) == 0 ? 1.0 : marginMax - marginMin;
    final marginPad = marginRange * 0.15;
    final marginChartMax = marginMax + marginPad;
    final marginChartMin = marginMin - marginPad;
    final marginChartRange = marginChartMax - marginChartMin;

    final shortMax = shortValues.reduce((a, b) => a > b ? a : b);
    final shortMin = shortValues.reduce((a, b) => a < b ? a : b);
    final shortRange =
        (shortMax - shortMin) == 0 ? 1.0 : shortMax - shortMin;
    final shortPad = shortRange * 0.15;
    final shortChartMax = shortMax + shortPad;
    final shortChartMin = shortMin - shortPad;
    final shortChartRange = shortChartMax - shortChartMin;

    double marginToY(double v) {
      return chartRect.top +
          (marginChartMax - v) / marginChartRange * chartRect.height;
    }

    double shortToY(double v) {
      return chartRect.top +
          (shortChartMax - v) / shortChartRange * chartRect.height;
    }

    final step = chartRect.width / days.length;

    void drawLine(
      List<double> values,
      double Function(double) toY,
      Color color,
    ) {

      final path = Path();
      bool started = false;

      for (int i = 0; i < values.length; i++) {
        final x = chartRect.left + i * step + step / 2;
        final y = toY(values[i]);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    drawLine(marginValues, marginToY, MarginMiniChart.marginColor);
    drawLine(shortValues, shortToY, MarginMiniChart.shortColor);

    // 左軸文字（融資，億元）
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(
      text: "${marginValues.last.toStringAsFixed(0)}億",
      style: TextStyle(fontSize: 10, color: MarginMiniChart.marginColor),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(2, marginToY(marginValues.last) - textPainter.height / 2),
    );

    // 右軸文字（融券，張）
    textPainter.text = TextSpan(
      text: "${shortValues.last.toStringAsFixed(0)}張",
      style: TextStyle(fontSize: 10, color: MarginMiniChart.shortColor),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        chartRect.right + 4,
        shortToY(shortValues.last) - textPainter.height / 2,
      ),
    );

    // X 軸頭尾日期
    void drawDateLabel(DateTime date, double x, TextAlign align) {
      textPainter.text = TextSpan(
        text: "${date.month}/${date.day}",
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
      );
      textPainter.layout();

      double dx = x;
      if (align == TextAlign.right) {
        dx = x - textPainter.width;
      } else if (align == TextAlign.center) {
        dx = x - textPainter.width / 2;
      }

      textPainter.paint(canvas, Offset(dx, chartRect.bottom + 4));
    }

    drawDateLabel(days.first.date, chartRect.left, TextAlign.left);
    drawDateLabel(days.last.date, chartRect.right, TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) =>
      oldDelegate.days.length != days.length;
}