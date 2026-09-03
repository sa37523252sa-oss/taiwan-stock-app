import 'package:flutter/material.dart';

import '../../models/market_margin_day.dart';

class MarginInteractiveChart extends StatefulWidget {
  const MarginInteractiveChart({
    super.key,
    required this.days,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  final List<MarketMarginDay> days;
  final int? selectedIndex;
  final ValueChanged<int?> onSelectIndex;

  static const marginColor = Color(0xFFEF4444);
  static const shortColor = Color(0xFF10B981);

  @override
  State<MarginInteractiveChart> createState() =>
      _MarginInteractiveChartState();
}

class _MarginInteractiveChartState extends State<MarginInteractiveChart> {

  int visibleCount = 30;
  int startIndex = -1;

  double _lastScale = 1.0;
  double _dragDx = 0;
  double _lastFocalX = 0;

  @override
  Widget build(BuildContext context) {

    if (widget.days.isEmpty) {
      return const Center(child: Text("沒有資料"));
    }

    final effectiveVisibleCount =
        visibleCount.clamp(5, widget.days.length);

    return LayoutBuilder(
      builder: (context, constraints) {

        const leftPadding = 46.0;
        const rightPadding = 46.0;

        final chartWidth =
            constraints.maxWidth - leftPadding - rightPadding;

        void handleTapX(double dx) {

          final begin = startIndex < 0
              ? (widget.days.length - effectiveVisibleCount)
                  .clamp(0, widget.days.length)
              : startIndex;

          final adjustedDx = dx - leftPadding;

          if (adjustedDx < 0) {
            widget.onSelectIndex(null);
            return;
          }

          final unit = chartWidth / effectiveVisibleCount;

          final index = (begin + (adjustedDx / unit).floor())
              .clamp(0, widget.days.length - 1);

          widget.onSelectIndex(
            widget.selectedIndex == index ? null : index,
          );
        }

        return GestureDetector(

          onTapDown: (details) => handleTapX(details.localPosition.dx),

          onScaleStart: (details) {
            _lastScale = 1.0;
            _dragDx = 0;
            _lastFocalX = details.localFocalPoint.dx;
          },

          onScaleUpdate: (details) {

            if (details.pointerCount == 1) {

              _dragDx += details.focalPointDelta.dx;

              final unit = chartWidth / effectiveVisibleCount;

              if (_dragDx.abs() > unit) {

                setState(() {

                  if (startIndex < 0) {
                    startIndex = (widget.days.length - effectiveVisibleCount)
                        .clamp(0, widget.days.length);
                  }

                  final move = (_dragDx / unit).round();
                  startIndex -= move;

                  final maxStart =
                      (widget.days.length - effectiveVisibleCount)
                          .clamp(0, widget.days.length);

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
                  startIndex = (widget.days.length - effectiveVisibleCount)
                      .clamp(0, widget.days.length);
                }

                final ratio = _lastFocalX / constraints.maxWidth;

                final centerIndex =
                    startIndex + (visibleCount * ratio).round();

                if (delta > 0) {
                  visibleCount -= 3;
                } else {
                  visibleCount += 3;
                }

                visibleCount =
                    visibleCount.clamp(10, widget.days.length);

                startIndex = centerIndex - (visibleCount * ratio).round();

                startIndex = startIndex.clamp(
                  0,
                  (widget.days.length - visibleCount)
                      .clamp(0, widget.days.length),
                );

              });

              _lastScale = details.scale;
            }
          },

          child: CustomPaint(
            painter: _Painter(
              days: widget.days,
              visibleCount: effectiveVisibleCount,
              startIndex: startIndex,
              selectedIndex: widget.selectedIndex,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({
    required this.days,
    required this.visibleCount,
    required this.startIndex,
    required this.selectedIndex,
  });

  final List<MarketMarginDay> days;
  final int visibleCount;
  final int startIndex;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {

    const leftPadding = 46.0;
    const rightPadding = 46.0;
    const topPadding = 10.0;
    const bottomAxisHeight = 20.0;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightPadding,
      size.height - topPadding - bottomAxisHeight,
    );

    final maxStart = (days.length - visibleCount).clamp(0, days.length);
    final begin = startIndex < 0 ? maxStart : startIndex.clamp(0, maxStart);
    final end = (begin + visibleCount).clamp(0, days.length);

    final visibleDays = days.sublist(begin, end);

    if (visibleDays.isEmpty) return;

    final marginValues = visibleDays
        .map((d) => d.marginMoneyTodayBalance / 100000000)
        .toList();
    final shortValues =
        visibleDays.map((d) => d.shortSharesTodayBalance / 1000).toList();

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

    final step = chartRect.width / visibleDays.length;

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    const gridCount = 5;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= gridCount; i++) {

      final y = chartRect.top + chartRect.height * i / gridCount;

      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );

      final marginV = marginChartMax - (marginChartRange / gridCount) * i;
      textPainter.text = TextSpan(
        text: marginV.toStringAsFixed(0),
        style: TextStyle(fontSize: 10, color: MarginInteractiveChart.marginColor),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y - textPainter.height / 2));

      final shortV = shortChartMax - (shortChartRange / gridCount) * i;
      textPainter.text = TextSpan(
        text: shortV.toStringAsFixed(0),
        style: TextStyle(fontSize: 10, color: MarginInteractiveChart.shortColor),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(chartRect.right + 4, y - textPainter.height / 2),
      );
    }

    void drawLine(
      List<double> values,
      double Function(double) toY,
      Color color,
    ) {

      final path = Path();
      bool started = false;
      final points = <Offset>[];

      for (int i = 0; i < values.length; i++) {
        final x = chartRect.left + i * step + step / 2;
        final y = toY(values[i]);
        points.add(Offset(x, y));
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

      for (final p in points) {
        canvas.drawCircle(p, 2.5, Paint()..color = color);
      }
    }

    drawLine(marginValues, marginToY, MarginInteractiveChart.marginColor);
    drawLine(shortValues, shortToY, MarginInteractiveChart.shortColor);

    if (selectedIndex != null &&
        selectedIndex! >= begin &&
        selectedIndex! < end) {

      final localIndex = selectedIndex! - begin;
      final x = chartRect.left + localIndex * step + step / 2;

      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        Paint()
          ..color = Colors.blueGrey
          ..strokeWidth = 1,
      );
    }

    void drawDateLabel(DateTime date, double x, bool alignRight) {
      textPainter.text = TextSpan(
        text: "${date.month}/${date.day}",
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
      );
      textPainter.layout();

      final dx = alignRight ? x - textPainter.width : x;

      textPainter.paint(canvas, Offset(dx, chartRect.bottom + 4));
    }

    drawDateLabel(visibleDays.first.date, chartRect.left, false);
    drawDateLabel(visibleDays.last.date, chartRect.right, true);
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) {
    return oldDelegate.days.length != days.length ||
        oldDelegate.visibleCount != visibleCount ||
        oldDelegate.startIndex != startIndex ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}