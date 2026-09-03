import 'package:flutter/material.dart';

import '../../models/backtest_result.dart';

class AssetCurveChart extends StatelessWidget {
  const AssetCurveChart({
    super.key,
    required this.points,
    required this.initialCapital,
  });

  final List<BacktestAssetPoint> points;
  final double initialCapital;

  @override
  Widget build(BuildContext context) {

    if (points.isEmpty) {
      return const Center(child: Text("沒有資料"));
    }

    return CustomPaint(
      painter: _Painter(points: points, initialCapital: initialCapital),
      size: Size.infinite,
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({required this.points, required this.initialCapital});

  final List<BacktestAssetPoint> points;
  final double initialCapital;

  @override
  void paint(Canvas canvas, Size size) {

    const leftPadding = 50.0;
    const rightPadding = 8.0;
    const topPadding = 10.0;
    const bottomPadding = 20.0;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightPadding,
      size.height - topPadding - bottomPadding,
    );

    final values = points.map((p) => p.value).toList();

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);

    final range = (maxV - minV) == 0 ? 1.0 : maxV - minV;
    final pad = range * 0.1;
    final chartMax = maxV + pad;
    final chartMin = minV - pad;
    final chartRange = chartMax - chartMin;

    double toY(double v) {
      return chartRect.top +
          (chartMax - v) / chartRange * chartRect.height;
    }

    final step = chartRect.width / points.length;

    // 格線 + 左軸文字
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    const gridCount = 4;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= gridCount; i++) {

      final v = chartMax - (chartRange / gridCount) * i;
      final y = toY(v);

      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );

      textPainter.text = TextSpan(
        text: "${(v / 10000).toStringAsFixed(0)}萬",
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y - textPainter.height / 2));
    }

    // 起始本金基準線（虛線示意用實線＋淡色代替）
    final initialY = toY(initialCapital);
    canvas.drawLine(
      Offset(chartRect.left, initialY),
      Offset(chartRect.right, initialY),
      Paint()
        ..color = Colors.grey.shade400
        ..strokeWidth = 1,
    );

    // 資產曲線
    final path = Path();
    bool started = false;

    for (int i = 0; i < points.length; i++) {
      final x = chartRect.left + i * step;
      final y = toY(points[i].value);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    final isProfit = points.last.value >= initialCapital;

    canvas.drawPath(
      path,
      Paint()
        ..color = isProfit ? Colors.red : Colors.green
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // X 軸頭尾日期
    void drawDateLabel(DateTime date, double x, bool alignRight) {
      textPainter.text = TextSpan(
        text: "${date.year}/${date.month}",
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
      );
      textPainter.layout();
      final dx = alignRight ? x - textPainter.width : x;
      textPainter.paint(canvas, Offset(dx, chartRect.bottom + 4));
    }

    drawDateLabel(points.first.date, chartRect.left, false);
    drawDateLabel(points.last.date, chartRect.right, true);
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) =>
      oldDelegate.points.length != points.length;
}