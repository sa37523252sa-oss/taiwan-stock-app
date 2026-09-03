import 'package:flutter/material.dart';

import '../../models/holder_point.dart';
import '../../utils/responsive.dart';

class HolderChart extends StatefulWidget {
  const HolderChart({
    super.key,
    required this.points,
  });

  final List<HolderPoint> points;

  @override
  State<HolderChart> createState() => _HolderChartState();
}

class _HolderChartState extends State<HolderChart> {

  int visibleCount = 40;

  /// -1 代表第一次開啟，自動顯示最新 visibleCount 筆
  int startIndex = -1;

  int? selectedIndex;

  double _lastScale = 1.0;
  double _dragDx = 0;
  double _lastFocalX = 0;

  @override
  Widget build(BuildContext context) {

    if (widget.points.isEmpty) {
      return const Center(
        child: Text("沒有大戶持股資料"),
      );
    }

    final effectiveVisibleCount =
        visibleCount.clamp(5, widget.points.length);

    return LayoutBuilder(
      builder: (context, constraints) {

        final scale = ResponsiveChart.scaleFor(constraints.maxWidth);
        final leftPadding = 45.0 * scale;
        final rightAxisWidth = 55.0 * scale;
        final rightPadding = 20.0 * scale;

        final chartWidth =
            constraints.maxWidth -
            leftPadding -
            rightAxisWidth -
            rightPadding;

        return GestureDetector(

          onTapDown: (details) =>
              _onTap(details, chartWidth, effectiveVisibleCount, leftPadding),

          onScaleStart: (details) {
            _lastScale = 1.0;
            _dragDx = 0;
            _lastFocalX = details.localFocalPoint.dx;
          },

          onScaleUpdate: (details) {

            if (details.pointerCount == 1) {

              _dragDx += details.focalPointDelta.dx;

              final candleWidth = chartWidth / effectiveVisibleCount;

              if (_dragDx.abs() > candleWidth) {

                setState(() {

                  if (startIndex < 0) {
                    startIndex =
                        (widget.points.length - effectiveVisibleCount)
                            .clamp(0, widget.points.length);
                  }

                  final move = (_dragDx / candleWidth).round();

                  startIndex -= move;

                  final maxStart =
                      (widget.points.length - effectiveVisibleCount)
                          .clamp(0, widget.points.length);

                  startIndex = startIndex.clamp(0, maxStart);

                });

                _dragDx = 0;
              }

              return;
            }

            final delta = details.scale - _lastScale;

            if (delta.abs() > 0.05) {

              setState(() {

                if (startIndex < 0) {
                  startIndex =
                      (widget.points.length - visibleCount)
                          .clamp(0, widget.points.length);
                }

                final ratio = _lastFocalX / constraints.maxWidth;

                final centerIndex =
                    startIndex + (visibleCount * ratio).round();

                if (delta > 0) {
                  visibleCount -= 4;
                } else {
                  visibleCount += 4;
                }

                visibleCount = visibleCount.clamp(
                  10,
                  widget.points.length,
                );

                startIndex = centerIndex - (visibleCount * ratio).round();

                startIndex = startIndex.clamp(
                  0,
                  (widget.points.length - visibleCount)
                      .clamp(0, widget.points.length),
                );

              });

              _lastScale = details.scale;
            }
          },

          child: CustomPaint(
            painter: _HolderPainter(
              widget.points,
              effectiveVisibleCount,
              startIndex,
              selectedIndex,
            ),
            size: Size.infinite,
          ),

        );
      },
    );
  }

  void _onTap(
    TapDownDetails details,
    double chartWidth,
    int effectiveVisibleCount,
    double leftPadding,
  ) {

    final begin = startIndex < 0
        ? (widget.points.length - effectiveVisibleCount)
            .clamp(0, widget.points.length)
        : startIndex;

    final end = (begin + effectiveVisibleCount)
        .clamp(0, widget.points.length);

    final visible = widget.points.sublist(begin, end);

    if (details.localPosition.dx < leftPadding ||
        details.localPosition.dx > leftPadding + chartWidth) {
      setState(() {
        selectedIndex = null;
      });
      return;
    }

    final step = chartWidth / visible.length;

    final index =
        ((details.localPosition.dx - leftPadding) / step)
            .floor()
            .clamp(0, visible.length - 1);

    setState(() {
      selectedIndex = selectedIndex == index ? null : index;
    });
  }
}

class _HolderPainter extends CustomPainter {
  const _HolderPainter(
    this.points,
    this.visibleCount,
    this.startIndex,
    this.selectedIndex,
  );

  final List<HolderPoint> points;
  final int visibleCount;
  final int startIndex;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {

    if (points.isEmpty) return;

    final maxStart =
        (points.length - visibleCount).clamp(0, points.length);

    final begin = startIndex < 0
        ? maxStart
        : startIndex.clamp(0, maxStart);

    final end = (begin + visibleCount).clamp(0, points.length);

    final visible = points.sublist(begin, end);

    if (visible.isEmpty) return;

    final scale = ResponsiveChart.scaleFor(size.width);

    final leftPadding = 45.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;
    final bottomAxisHeight = 20.0 * scale;
    final topPadding = 10.0 * scale;
    final axisFontSize = 10.0 * scale;
    final lineStrokeWidth = 2.0 * scale;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightAxisWidth - rightPadding,
      size.height - topPadding - bottomAxisHeight,
    );

    final maxPct = visible
        .map((p) => p.bigHolderPercent)
        .reduce((a, b) => a > b ? a : b);
    final minPct = visible
        .map((p) => p.bigHolderPercent)
        .reduce((a, b) => a < b ? a : b);

    final rawRange = maxPct - minPct;
    final padding = rawRange == 0 ? 1.0 : rawRange * 0.15;

    final chartMax = maxPct + padding;
    final chartMin = (minPct - padding).clamp(0, 100).toDouble();
    final range = chartMax - chartMin;

    double toY(double v) {
      return chartRect.top +
          (chartMax - v) / range * chartRect.height;
    }

    final step = chartRect.width / visible.length;

    // 網格 + 左軸文字
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    const gridCount = 5;

    for (int i = 0; i <= gridCount; i++) {
      final v = chartMax - (range / gridCount) * i;
      final y = toY(v);

      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: "${v.toStringAsFixed(1)}%",
          style: TextStyle(fontSize: axisFontSize, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // 面積 + 折線
    final linePath = Path();
    final areaPath = Path();
    bool started = false;

    for (int i = 0; i < visible.length; i++) {
      final x = chartRect.left + i * step + step / 2;
      final y = toY(visible[i].bigHolderPercent);

      if (!started) {
        linePath.moveTo(x, y);
        areaPath.moveTo(x, chartRect.bottom);
        areaPath.lineTo(x, y);
        started = true;
      } else {
        linePath.lineTo(x, y);
        areaPath.lineTo(x, y);
      }
    }

    final lastX =
        chartRect.left + (visible.length - 1) * step + step / 2;
    areaPath.lineTo(lastX, chartRect.bottom);
    areaPath.close();

    canvas.drawPath(
      areaPath,
      Paint()..color = Colors.blue.withOpacity(0.12),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.blue
        ..strokeWidth = lineStrokeWidth
        ..style = PaintingStyle.stroke,
    );

    // X 軸日期
    final labelStep = (visible.length / 6).round().clamp(1, visible.length);

    for (int i = 0; i < visible.length; i += labelStep) {
      final x = chartRect.left + i * step + step / 2;
      final d = visible[i].date;

      final tp = TextPainter(
        text: TextSpan(
          text: "${d.month}/${d.day}",
          style: TextStyle(fontSize: axisFontSize, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, chartRect.bottom + 4));
    }

    // 十字線 + 選中值
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < visible.length) {

      final p = visible[selectedIndex!];
      final x = chartRect.left + selectedIndex! * step + step / 2;
      final y = toY(p.bigHolderPercent);

      final crossPaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 1;

      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        crossPaint,
      );

      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        crossPaint,
      );

      final labelTp = TextPainter(
        text: TextSpan(
          text:
              "${p.date.year}/${p.date.month}/${p.date.day}  "
              "大戶 ${p.bigHolderPercent.toStringAsFixed(2)}%",
          style: TextStyle(
            fontSize: 11.0 * scale,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        chartRect.left + 4,
        chartRect.top + 4,
        labelTp.width + 8,
        labelTp.height + 4,
      );

      canvas.drawRect(
        labelRect,
        Paint()..color = Colors.white.withOpacity(0.9),
      );

      labelTp.paint(
        canvas,
        Offset(labelRect.left + 4, labelRect.top + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}