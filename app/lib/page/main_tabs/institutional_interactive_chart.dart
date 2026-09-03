import 'package:flutter/material.dart';

import '../../models/market_institutional_day.dart';

/// 三大法人買賣超的完整互動圖表：左軸金額座標、下方日期座標、
/// 單指拖曳橫移、雙指縮放、點擊選點（會跟外部傳入的
/// selectedIndex 同步，讓表格點擊也能反過來標記圖表上的點）。
class InstitutionalInteractiveChart extends StatefulWidget {
  const InstitutionalInteractiveChart({
    super.key,
    required this.days,
    required this.selectedIndex,
    required this.onSelectIndex,
  });

  final List<MarketInstitutionalDay> days;
  final int? selectedIndex;
  final ValueChanged<int?> onSelectIndex;

  static const foreignColor = Color(0xFF3B82F6);
  static const trustColor = Color(0xFFEF4444);
  static const dealerColor = Color(0xFF8B5CF6);

  @override
  State<InstitutionalInteractiveChart> createState() =>
      _InstitutionalInteractiveChartState();
}

class _InstitutionalInteractiveChartState
    extends State<InstitutionalInteractiveChart> {

  int visibleCount = 30;

  /// -1 代表尚未手動移動過，畫最新 visibleCount 筆
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
        const rightPadding = 8.0;

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

  final List<MarketInstitutionalDay> days;
  final int visibleCount;
  final int startIndex;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {

    const leftPadding = 46.0;
    const rightPadding = 8.0;
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

    final allValues = [
      ...visibleDays.map((d) => d.foreignNet),
      ...visibleDays.map((d) => d.trustNet),
      ...visibleDays.map((d) => d.dealerNet),
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

    final step = chartRect.width / visibleDays.length;

    // 格線 + 左軸文字
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    const gridCount = 5;

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
        text: "${(v / 100000000).toStringAsFixed(0)}億",
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(2, y - textPainter.height / 2),
      );
    }

    // 零軸加粗
    final zeroY = toY(0);
    canvas.drawLine(
      Offset(chartRect.left, zeroY),
      Offset(chartRect.right, zeroY),
      Paint()
        ..color = Colors.grey.shade400
        ..strokeWidth = 1.2,
    );

    void drawLine(List<double> values, Color color) {

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

    drawLine(
      visibleDays.map((d) => d.foreignNet).toList(),
      InstitutionalInteractiveChart.foreignColor,
    );
    drawLine(
      visibleDays.map((d) => d.trustNet).toList(),
      InstitutionalInteractiveChart.trustColor,
    );
    drawLine(
      visibleDays.map((d) => d.dealerNet).toList(),
      InstitutionalInteractiveChart.dealerColor,
    );

    // 十字線（選中點）
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

    // X 軸日期（頭尾）
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