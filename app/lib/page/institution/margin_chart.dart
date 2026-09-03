import 'package:flutter/material.dart';

import '../../models/margin_flow.dart';
import '../../utils/responsive.dart';

class MarginChart extends StatefulWidget {
  const MarginChart({
    super.key,
    required this.flows,
  });

  final List<MarginFlow> flows;

  @override
  State<MarginChart> createState() => _MarginChartState();
}

class _MarginChartState extends State<MarginChart> {

  int visibleCount = 40;
  int startIndex = -1;
  int? selectedIndex;

  double _lastScale = 1.0;
  double _dragDx = 0;
  double _lastFocalX = 0;

  @override
  Widget build(BuildContext context) {

    if (widget.flows.isEmpty) {
      return const Center(
        child: Text("沒有資券資料"),
      );
    }

    final effectiveVisibleCount =
        visibleCount.clamp(5, widget.flows.length);

    return LayoutBuilder(
      builder: (context, constraints) {

        // 留白要依實際畫布寬度換算，並且跟下面 CustomPaint 用
        // 同一個寬度算出來的 scale 保持一致，手勢判斷的座標
        // 才會跟畫面對得上。
        final scale = ResponsiveChart.scaleFor(constraints.maxWidth);
        final leftPadding = 50.0 * scale;
        final rightAxisWidth = 20.0 * scale;
        final rightPadding = 12.0 * scale;

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
                        (widget.flows.length - effectiveVisibleCount)
                            .clamp(0, widget.flows.length);
                  }

                  final move = (_dragDx / candleWidth).round();

                  startIndex -= move;

                  final maxStart =
                      (widget.flows.length - effectiveVisibleCount)
                          .clamp(0, widget.flows.length);

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
                      (widget.flows.length - visibleCount)
                          .clamp(0, widget.flows.length);
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
                  widget.flows.length,
                );

                startIndex = centerIndex - (visibleCount * ratio).round();

                startIndex = startIndex.clamp(
                  0,
                  (widget.flows.length - visibleCount)
                      .clamp(0, widget.flows.length),
                );

              });

              _lastScale = details.scale;
            }
          },

          child: CustomPaint(
            painter: _MarginPainter(
              widget.flows,
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
        ? (widget.flows.length - effectiveVisibleCount)
            .clamp(0, widget.flows.length)
        : startIndex;

    final end = (begin + effectiveVisibleCount)
        .clamp(0, widget.flows.length);

    final visible = widget.flows.sublist(begin, end);

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

class _MarginPainter extends CustomPainter {
  const _MarginPainter(
    this.flows,
    this.visibleCount,
    this.startIndex,
    this.selectedIndex,
  );

  final List<MarginFlow> flows;
  final int visibleCount;
  final int startIndex;
  final int? selectedIndex;

  static const Color marginColor = Color(0xFFEF4444); // 融資：紅
  static const Color shortColor = Color(0xFF10B981); // 融券：綠
  static const Color offsetColor = Color(0xFF8B5CF6); // 資券互抵：紫

  @override
  void paint(Canvas canvas, Size size) {

    if (flows.isEmpty) return;

    final maxStart =
        (flows.length - visibleCount).clamp(0, flows.length);

    final begin = startIndex < 0
        ? maxStart
        : startIndex.clamp(0, maxStart);

    final end = (begin + visibleCount).clamp(0, flows.length);

    final visible = flows.sublist(begin, end);

    if (visible.isEmpty) return;

    const leftPadding = 50.0;
    const rightAxisWidth = 20.0;
    const rightPadding = 12.0;
    const bottomAxisHeight = 20.0;
    const topPadding = 10.0;
    const offsetAreaHeight = 40.0;

    // 跟 Widget 層（手勢判斷）用同一個公式，size.width 就是
    // LayoutBuilder 給的 constraints.maxWidth，兩邊縮放係數
    // 保持一致，畫面才會跟點擊座標對得上。
    final scale = ResponsiveChart.scaleFor(size.width);
    final scaledLeftPadding = leftPadding * scale;
    final scaledRightAxisWidth = rightAxisWidth * scale;
    final scaledRightPadding = rightPadding * scale;
    final scaledBottomAxisHeight = bottomAxisHeight * scale;
    final scaledTopPadding = topPadding * scale;
    final scaledOffsetAreaHeight = offsetAreaHeight * scale;
    final axisFontSize = 10.0 * scale;
    final lineStrokeWidth = 2.0 * scale;

    final lineRect = Rect.fromLTWH(
      scaledLeftPadding,
      scaledTopPadding,
      size.width - scaledLeftPadding - scaledRightAxisWidth - scaledRightPadding,
      size.height - scaledTopPadding - scaledBottomAxisHeight - scaledOffsetAreaHeight,
    );

    final offsetRect = Rect.fromLTWH(
      scaledLeftPadding,
      lineRect.bottom + 4,
      lineRect.width,
      scaledOffsetAreaHeight - 4,
    );

    final maxBalance = visible
        .map((f) =>
            f.marginTodayBalance > f.shortTodayBalance
                ? f.marginTodayBalance
                : f.shortTodayBalance)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    final chartMax = maxBalance == 0 ? 1.0 : maxBalance * 1.1;

    double toY(double v) {
      return lineRect.top + (chartMax - v) / chartMax * lineRect.height;
    }

    final step = lineRect.width / visible.length;

    // 網格 + 左軸
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    const gridCount = 4;

    for (int i = 0; i <= gridCount; i++) {
      final v = chartMax - (chartMax / gridCount) * i;
      final y = toY(v);

      canvas.drawLine(
        Offset(lineRect.left, y),
        Offset(lineRect.right, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: v >= 10000
              ? "${(v / 10000).toStringAsFixed(1)}萬"
              : v.toStringAsFixed(0),
          style: TextStyle(fontSize: axisFontSize, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // 融資 / 融券 折線
    void drawLine(
      int Function(MarginFlow) selector,
      Color color,
    ) {
      final path = Path();
      bool started = false;

      for (int i = 0; i < visible.length; i++) {
        final v = selector(visible[i]).toDouble();
        final x = lineRect.left + i * step + step / 2;
        final y = toY(v);

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
          ..strokeWidth = lineStrokeWidth
          ..style = PaintingStyle.stroke,
      );
    }

    drawLine((f) => f.marginTodayBalance, marginColor);
    drawLine((f) => f.shortTodayBalance, shortColor);

    // 資券互抵 長條（當沖指標）
    final maxOffset = visible
        .map((f) => f.offsetLoanAndShort)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    final offsetMax = maxOffset == 0 ? 1.0 : maxOffset * 1.2;

    const spacing = 2.0;
    final barWidth = (step - spacing).clamp(1.0 * scale, 12.0 * scale);

    for (int i = 0; i < visible.length; i++) {
      final v = visible[i].offsetLoanAndShort.toDouble();
      final x = lineRect.left + i * step + step / 2;
      final h = v / offsetMax * offsetRect.height;

      canvas.drawRect(
        Rect.fromLTWH(
          x - barWidth / 2,
          offsetRect.bottom - h,
          barWidth,
          h,
        ),
        Paint()..color = offsetColor,
      );
    }

    final offsetLabelTp = TextPainter(
      text: TextSpan(
        text: "資券互抵",
        style: TextStyle(fontSize: axisFontSize, color: offsetColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    offsetLabelTp.paint(
      canvas,
      Offset(2, offsetRect.top),
    );

    // X 軸日期
    final labelStep = (visible.length / 6).round().clamp(1, visible.length);

    for (int i = 0; i < visible.length; i += labelStep) {
      final x = lineRect.left + i * step + step / 2;
      final d = visible[i].date;

      final tp = TextPainter(
        text: TextSpan(
          text: "${d.month}/${d.day}",
          style: TextStyle(fontSize: axisFontSize, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(x - tp.width / 2, size.height - scaledBottomAxisHeight + 4),
      );
    }

    // 十字線 + 選中資訊
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < visible.length) {

      final f = visible[selectedIndex!];
      final x = lineRect.left + selectedIndex! * step + step / 2;

      final crossPaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 1;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height - scaledBottomAxisHeight),
        crossPaint,
      );

      final labelTp = TextPainter(
        text: TextSpan(
          text:
              "${f.date.year}/${f.date.month}/${f.date.day}  "
              "融資 ${f.marginTodayBalance}(${f.marginChange >= 0 ? '+' : ''}${f.marginChange})  "
              "融券 ${f.shortTodayBalance}(${f.shortChange >= 0 ? '+' : ''}${f.shortChange})",
          style: TextStyle(
            fontSize: 11.0 * scale,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        lineRect.left + 4,
        lineRect.top + 4,
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