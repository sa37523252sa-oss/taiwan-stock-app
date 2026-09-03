import 'package:flutter/material.dart';

import '../../models/institution_flow.dart';
import '../../models/investor_setting.dart';
import '../../utils/responsive.dart';

class InstitutionChart extends StatelessWidget {
  const InstitutionChart({
    super.key,
    required this.flows,
    required this.chartType,
    this.selectedDate,
  });

  final List<InstitutionFlow> flows;
  final InvestorChartType chartType;
  final DateTime? selectedDate;

  @override
  Widget build(BuildContext context) {
    if (flows.isEmpty) {
      return const Center(
        child: Text("沒有三大法人資料"),
      );
    }

    return CustomPaint(
      painter: _InstitutionChartPainter(flows, chartType, selectedDate),
      size: Size.infinite,
    );
  }
}

class _InstitutionChartPainter extends CustomPainter {
  const _InstitutionChartPainter(
    this.flows,
    this.chartType,
    this.selectedDate,
  );

  final List<InstitutionFlow> flows;
  final InvestorChartType chartType;
  final DateTime? selectedDate;

  static const Color foreignColor = Color(0xFF3B82F6);
  static const Color trustColor = Color(0xFFEF4444);
  static const Color dealerColor = Color(0xFF8B5CF6);
  static const Color lineColor = Color(0xFFF59E0B);

  String _formatVolume(double v) {
    final abs = v.abs();
    final sign = v < 0 ? "-" : "";

    if (abs >= 10000) {
      return "$sign${(abs / 10000).toStringAsFixed(1)}萬";
    }

    return v.toStringAsFixed(0);
  }

  double? _lineValue(InstitutionFlow f) {
    return chartType == InvestorChartType.price
        ? f.close
        : f.total;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (flows.isEmpty) return;

    final scale = ResponsiveChart.scaleFor(size.width);

    final leftPadding = 44.0 * scale;
    final rightAxisWidth = 60.0 * scale;
    final rightPadding = 8.0 * scale;
    final bottomAxisHeight = 20.0 * scale;
    final topPadding = 8.0 * scale;
    final axisFontSize = 10.0 * scale;
    final dotRadius = 2.5 * scale;
    final lineStrokeWidth = 2.0 * scale;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightAxisWidth - rightPadding,
      size.height - topPadding - bottomAxisHeight,
    );

    //-------------------------
    // 買賣超（長條）Y 軸範圍
    //-------------------------

    double maxPos = 0;
    double maxNeg = 0;

    for (final f in flows) {
      double pos = 0;
      double neg = 0;

      for (final v in [f.foreign, f.trust, f.dealer]) {
        if (v >= 0) {
          pos += v;
        } else {
          neg += v;
        }
      }

      if (pos > maxPos) maxPos = pos;
      if (neg < maxNeg) maxNeg = neg;
    }

    final rawVolRange = maxPos - maxNeg;
    final volRange = rawVolRange == 0 ? 1.0 : rawVolRange;
    final volPadding = volRange * 0.15;

    final volMax = maxPos + volPadding;
    final volMin = maxNeg - volPadding;
    final volSpan = volMax - volMin;

    double volToY(double v) {
      return chartRect.top +
          (volMax - v) / volSpan * chartRect.height;
    }

    //-------------------------
    // 折線（股價／合計）Y 軸範圍
    //-------------------------

    final lineValues = flows
        .map(_lineValue)
        .whereType<double>()
        .toList();

    if (lineValues.isEmpty) return;

    final lineMax = lineValues.reduce((a, b) => a > b ? a : b);
    final lineMin = lineValues.reduce((a, b) => a < b ? a : b);
    final rawLineRange = lineMax - lineMin;
    final linePadding =
        rawLineRange == 0 ? 1.0 : rawLineRange * 0.1;

    final lineChartMax = lineMax + linePadding;
    final lineChartMin = lineMin - linePadding;
    final lineSpan = lineChartMax - lineChartMin;

    double lineToY(double v) {
      return chartRect.top +
          (lineChartMax - v) / lineSpan * chartRect.height;
    }

    final step = chartRect.width / flows.length;
    const spacing = 6.0;
    final barWidth = (step - spacing).clamp(4.0 * scale, 24.0 * scale);

    //-------------------------
    // 網格線 + 買賣超 Y 軸文字
    //-------------------------

    const gridCount = 6;

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;

    for (int i = 0; i <= gridCount; i++) {
      final v = volMax - (volSpan / gridCount) * i;
      final y = volToY(v);

      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: _formatVolume(v),
          style: TextStyle(fontSize: axisFontSize, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // 0 軸
    canvas.drawLine(
      Offset(chartRect.left, volToY(0)),
      Offset(chartRect.right, volToY(0)),
      Paint()
        ..color = Colors.grey.withOpacity(0.5)
        ..strokeWidth = 1,
    );

    //-------------------------
    // 疊加長條圖
    //-------------------------

    for (int i = 0; i < flows.length; i++) {
      final f = flows[i];
      final x = chartRect.left + i * step + step / 2;

      double posTop = 0;
      double negBottom = 0;

      for (final entry in [
        MapEntry(f.foreign, foreignColor),
        MapEntry(f.trust, trustColor),
        MapEntry(f.dealer, dealerColor),
      ]) {
        final v = entry.key;
        final color = entry.value;

        if (v == 0) continue;

        double top;
        double bottom;

        if (v > 0) {
          top = posTop + v;
          bottom = posTop;
          posTop = top;
        } else {
          top = negBottom;
          bottom = negBottom + v;
          negBottom = bottom;
        }

        canvas.drawRect(
          Rect.fromLTRB(
            x - barWidth / 2,
            volToY(top),
            x + barWidth / 2,
            volToY(bottom),
          ),
          Paint()..color = color,
        );
      }
    }

    //-------------------------
    // 折線（股價／合計）
    //-------------------------

    final path = Path();
    bool started = false;

    for (int i = 0; i < flows.length; i++) {
      final v = _lineValue(flows[i]);
      if (v == null) continue;

      final x = chartRect.left + i * step + step / 2;
      final y = lineToY(v);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(
        Offset(x, y),
        dotRadius,
        Paint()..color = lineColor,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = lineStrokeWidth
        ..style = PaintingStyle.stroke,
    );

    //-------------------------
    // 右軸文字
    //-------------------------

    const rightGridCount = 5;

    for (int i = 0; i <= rightGridCount; i++) {
      final v = lineChartMax - (lineSpan / rightGridCount) * i;
      final y = lineToY(v);

      final tp = TextPainter(
        text: TextSpan(
          text: chartType == InvestorChartType.price
              ? v.toStringAsFixed(0)
              : _formatVolume(v),
          style: TextStyle(fontSize: axisFontSize, color: Colors.orange),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(chartRect.right + 6, y - tp.height / 2));
    }

    // 軸標籤（股價／合計）
    final axisLabelTp = TextPainter(
      text: TextSpan(
        text: chartType == InvestorChartType.price ? "股價" : "合計",
        style: TextStyle(
          fontSize: axisFontSize,
          color: Colors.orange,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    axisLabelTp.paint(
      canvas,
      Offset(chartRect.right + 6, chartRect.bottom + 2),
    );

    //-------------------------
    // 最新值 highlight
    //-------------------------

    final lastV = lineValues.isEmpty ? null : lineValues.last;

    if (lastV != null) {

      final lastY = lineToY(lastV);

      final labelText = chartType == InvestorChartType.price
          ? lastV.toStringAsFixed(2)
          : _formatVolume(lastV);

      final labelTp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            fontSize: axisFontSize,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        chartRect.right + 4,
        lastY - labelTp.height / 2 - 2,
        labelTp.width + 8,
        labelTp.height + 4,
      );

      canvas.drawRect(labelRect, Paint()..color = lineColor);

      labelTp.paint(
        canvas,
        Offset(labelRect.left + 4, labelRect.top + 2),
      );

    }

    //-------------------------
    // 選中日期的長線
    //-------------------------

    if (selectedDate != null) {

      final index = flows.indexWhere((f) =>
          f.date.year == selectedDate!.year &&
          f.date.month == selectedDate!.month &&
          f.date.day == selectedDate!.day);

      if (index != -1) {

        final x = chartRect.left + index * step + step / 2;

        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = Colors.grey
            ..strokeWidth = 1,
        );
      }
    }

    //-------------------------
    // X 軸日期
    //-------------------------

    final labelStep =
        (flows.length / 8).round().clamp(1, flows.length);

    for (int i = 0; i < flows.length; i += labelStep) {
      final x = chartRect.left + i * step + step / 2;

      final tp = TextPainter(
        text: TextSpan(
          text: "${flows[i].date.day}",
          style: TextStyle(fontSize: axisFontSize, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(x - tp.width / 2, chartRect.bottom + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}