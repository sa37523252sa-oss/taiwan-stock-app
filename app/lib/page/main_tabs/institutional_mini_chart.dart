import 'package:flutter/material.dart';

import '../../models/market_institutional_day.dart';

/// 大盤三大法人買賣超的迷你預覽圖，樣式跟個股的三大法人頁一致
/// （外資藍、投信紅、自營商紫），單一軸即可（三者單位一致，
/// 都是新台幣買賣超金額）。純靜態顯示，不支援拖曳/縮放——
/// 這是首頁的預覽用途，完整互動請點「查看更多」進歷史頁。
class InstitutionalMiniChart extends StatelessWidget {
  const InstitutionalMiniChart({
    super.key,
    required this.days,
  });

  final List<MarketInstitutionalDay> days;

  static const foreignColor = Color(0xFF3B82F6);
  static const trustColor = Color(0xFFEF4444);
  static const dealerColor = Color(0xFF8B5CF6);

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

  final List<MarketInstitutionalDay> days;

  @override
  void paint(Canvas canvas, Size size) {

    const leftPadding = 8.0;
    const rightPadding = 8.0;
    const topPadding = 8.0;
    const bottomPadding = 20.0;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightPadding,
      size.height - topPadding - bottomPadding,
    );

    final allValues = [
      ...days.map((d) => d.foreignNet),
      ...days.map((d) => d.trustNet),
      ...days.map((d) => d.dealerNet),
    ];

    final maxV = allValues.reduce((a, b) => a > b ? a : b);
    final minV = allValues.reduce((a, b) => a < b ? a : b);

    final range = (maxV - minV) == 0 ? 1.0 : maxV - minV;
    final pad = range * 0.15;
    final chartMax = maxV + pad;
    final chartMin = minV - pad;
    final chartRange = chartMax - chartMin;

    double toY(double v) {
      return chartRect.top +
          (chartMax - v) / chartRange * chartRect.height;
    }

    final step = chartRect.width / days.length;

    // 零軸參考線
    final zeroY = toY(0);
    canvas.drawLine(
      Offset(chartRect.left, zeroY),
      Offset(chartRect.right, zeroY),
      Paint()
        ..color = Colors.grey.shade300
        ..strokeWidth = 1,
    );

    void drawLine(List<double> values, Color color) {

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

    drawLine(days.map((d) => d.foreignNet).toList(), InstitutionalMiniChart.foreignColor);
    drawLine(days.map((d) => d.trustNet).toList(), InstitutionalMiniChart.trustColor);
    drawLine(days.map((d) => d.dealerNet).toList(), InstitutionalMiniChart.dealerColor);

    // X 軸只標頭尾兩個日期，預覽圖不用太密集
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

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