import 'package:flutter/material.dart';

import '../../models/candle.dart';
import '../../models/indicator_setting.dart';
import '../../utils/responsive.dart';

class KlinePainter extends CustomPainter {
  KlinePainter(
    this.candles, {
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

  void drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
  ) {
    const dash = 5.0;
    const gap = 5.0;
    final total = (p2 - p1).distance;
    final dx = (p2.dx - p1.dx) / total;
    final dy = (p2.dy - p1.dy) / total;
    double distance = 0;
    while (distance < total) {
      final start = Offset(p1.dx + dx * distance, p1.dy + dy * distance);
      distance += dash;
      final end = Offset(p1.dx + dx * distance, p1.dy + dy * distance);
      canvas.drawLine(start, end, paint);
      distance += gap;
    }
  }


  void drawMA(Canvas canvas,Rect chartRect,List<double?> values,int begin,int end,double step,double Function(double) priceToY,Color color,{double strokeWidth = 1.5}){final path=Path();bool started=false;final p=Paint()..color=color..strokeWidth=strokeWidth..style=PaintingStyle.stroke;for(int i=begin;i<end;i++){final v=values[i];if(v==null)continue;final x=chartRect.left+(i-begin)*step+step/2;final y=priceToY(v);if(!started){path.moveTo(x,y);started = true;}else{path.lineTo(x,y);}}canvas.drawPath(path,p);}

  @override
  void paint(Canvas canvas, Size size) {

    final maxStart =
        (candles.length - visibleCount).clamp(0, candles.length);

    final begin =
        startIndex < 0
            ? maxStart
            : startIndex.clamp(0, maxStart);

    final end =
        (begin + visibleCount).clamp(
          0,
          candles.length,
        );

    final visibleCandles =
        candles.sublist(begin, end);

    // 空清單的話，下面的 reduce 會丟 StateError，整張圖直接消失。
    // 寧可什麼都不畫也不要拋例外。
    if (visibleCandles.isEmpty) return;

    // 留白、蠟燭寬度、線寬都依實際畫布寬度換算，平板上（畫布
    // 較寬）比例才不會跑掉。
    final scale = ResponsiveChart.scaleFor(size.width);

    final rightAxisWidth = 55.0 * scale;
    final bottomAxisHeight = 24.0 * scale;
    final leftPadding = 30.0 * scale;
    final rightPadding = 20.0 * scale;
    final axisFontSize = 11.0 * scale;
    final dateFontSize = 10.0 * scale;
    final maStrokeWidth = 1.5 * scale;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      0,
      size.width - leftPadding - rightAxisWidth - rightPadding,
      size.height - bottomAxisHeight,
    );

    final rightAxisRect = Rect.fromLTWH(
      chartRect.right,
      0,
      rightAxisWidth,
      chartRect.height,
    );

    final bottomAxisRect = Rect.fromLTWH(
      chartRect.left,
      chartRect.bottom,
      chartRect.width,
      bottomAxisHeight,
    );

    final chartWidth = chartRect.width;
    final chartHeight = chartRect.height;

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.25)
      ..strokeWidth = 1;

    final maxPrice =
        visibleCandles.map((e) => e.high).reduce((a, b) => a > b ? a : b);

    final minPrice =
        visibleCandles.map((e) => e.low).reduce((a, b) => a < b ? a : b);

    final highest =
        visibleCandles.reduce((a, b) => a.high > b.high ? a : b);
    final lowest =
        visibleCandles.reduce((a, b) => a.low < b.low ? a : b);
    final highestIndex = visibleCandles.indexOf(highest);
    final lowestIndex = visibleCandles.indexOf(lowest);

    final rawRange = maxPrice - minPrice;

    // 只剩一根 K 棒、或這段期間完全沒波動時 rawRange 會是 0。
    // 原本直接 return 會讓畫面整片空白，改成給一個最小範圍，
    // 至少還看得到那根 K 棒和座標軸。
    final effectiveRange =
        rawRange > 0 ? rawRange : (maxPrice.abs() * 0.02 + 1);

    // 上下各留 5%
    final padding = effectiveRange * 0.05;

    final chartMax = maxPrice + padding + (rawRange > 0 ? 0 : effectiveRange / 2);
    final chartMin = minPrice - padding - (rawRange > 0 ? 0 : effectiveRange / 2);

    final priceRange = chartMax - chartMin;

    if (priceRange <= 0) return;

    const spacing = 2.0;

    final step = chartWidth / visibleCandles.length;

    final bodyWidth = (step - spacing).clamp(3.0 * scale, 12.0 * scale);

    double priceToY(double price) {
      const topPadding = 15.0;
      const bottomPadding = 10.0;
      return topPadding +
          (chartMax - price) /
              priceRange *
              (chartHeight - topPadding - bottomPadding);
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final lineCount = (chartHeight / 80).floor().clamp(3, 10);
    final labelCount =
        (chartWidth / 120).floor().clamp(2, 8);



    final borderPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(chartRect, borderPaint);

    canvas.save();
    canvas.clipRect(chartRect);

    for (int i = 0; i < lineCount; i++) {
      final y = chartHeight * i / (lineCount - 1);

      drawDashedLine(
        canvas,
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final columnCount = labelCount;

    for (int i = 0; i <= columnCount; i++) {
      final x = chartRect.left + chartRect.width * i / columnCount;

      drawDashedLine(
        canvas,
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        gridPaint,
      );
    }

    for (int i = 0; i < visibleCandles.length; i++) {

      final c = visibleCandles[i];

      final x =
          chartRect.left +
          step * i +
          step / 2;

      final openY = priceToY(c.open);
      final closeY = priceToY(c.close);
      final highY = priceToY(c.high);
      final lowY = priceToY(c.low);

      final isUp = c.close >= c.open;

      final candlePaint = Paint()
        ..color = isUp ? Colors.red : Colors.green;

      canvas.drawLine(
        Offset(x, highY),
        Offset(x, lowY),
        candlePaint,
      );

      final bodyTop = openY < closeY ? openY : closeY;
      final bodyBottom = openY > closeY ? openY : closeY;

      canvas.drawRect(
        Rect.fromLTRB(
          x - bodyWidth / 2,
          bodyTop,
          x + bodyWidth / 2,
          bodyBottom,
        ),
        candlePaint,
      );
    }

    if (indicator.mainIndicator == MainIndicator.ma) {
      if (indicator.ma5) { drawMA(canvas, chartRect, ma5, begin, end, step, priceToY, Colors.amber, strokeWidth: maStrokeWidth); }
      if (indicator.ma10) { drawMA(canvas, chartRect, ma10, begin, end, step, priceToY, Colors.blue, strokeWidth: maStrokeWidth); }
      if (indicator.ma20) { drawMA(canvas, chartRect, ma20, begin, end, step, priceToY, Colors.purple, strokeWidth: maStrokeWidth); }
      if (indicator.ma60) { drawMA(canvas, chartRect, ma60, begin, end, step, priceToY, Colors.green, strokeWidth: maStrokeWidth); }
      if (indicator.ma120) { drawMA(canvas, chartRect, ma120, begin, end, step, priceToY, Colors.orange, strokeWidth: maStrokeWidth); }
      if (indicator.ma240) { drawMA(canvas, chartRect, ma240, begin, end, step, priceToY, Colors.red, strokeWidth: maStrokeWidth); }
    } else {
      drawMA(canvas, chartRect, bollUpper, begin, end, step, priceToY, Colors.orange, strokeWidth: maStrokeWidth);
      drawMA(canvas, chartRect, bollMiddle, begin, end, step, priceToY, Colors.purple, strokeWidth: maStrokeWidth);
      drawMA(canvas, chartRect, bollLower, begin, end, step, priceToY, Colors.orange, strokeWidth: maStrokeWidth);
    }

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < visibleCandles.length) {

      final c = visibleCandles[selectedIndex!];

      final x =
          chartRect.left +
          step * selectedIndex! +
          step / 2;

      final y = priceToY(c.close);

      final crossPaint = Paint()
        ..color = Colors.blue
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
    }

    void drawPriceLabel(Canvas canvas,String text,double x,double y){
      final tp=TextPainter(text:TextSpan(text:text,style:TextStyle(fontSize:axisFontSize,color:Colors.black)),textDirection:TextDirection.ltr);
      tp.layout();
      canvas.drawLine(Offset(x,y),Offset(x+20*scale,y),Paint()..color=Colors.black..strokeWidth=1*scale);
      tp.paint(canvas,Offset(x+24*scale,y-tp.height/2));
    }

    final highestX=chartRect.left+highestIndex*step+step/2;
    drawPriceLabel(canvas,highest.high.toStringAsFixed(0),highestX,priceToY(highest.high));
    final lowestX=chartRect.left+lowestIndex*step+step/2;
    drawPriceLabel(canvas,lowest.low.toStringAsFixed(0),lowestX,priceToY(lowest.low));

    canvas.restore();

    for (int i = 0; i < lineCount; i++) {
      final y = chartHeight * i / (lineCount - 1);
      final price =
          chartMax - (priceRange / (lineCount - 1)) * i;

      textPainter.text = TextSpan(
        text: price.toStringAsFixed(0),
        style: TextStyle(
          color: Colors.grey,
          fontSize: axisFontSize,
        ),
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(
          rightAxisRect.left + 12,
          y - textPainter.height / 2,
        ),
      );
    }
    final labelStep =
        (visibleCandles.length / labelCount).round().clamp(1, visibleCandles.length);

    double lastRight = -100;

    for (int i = 0; i < visibleCandles.length; i += labelStep) {
      final candle = visibleCandles[i];

      final x =
          chartRect.left +
          step * i +
          step / 2;

      final date = candle.date;

      final text = "${date.month}/${date.day}";

      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.grey,
          fontSize: dateFontSize,
        ),
      );

      textPainter.layout();

      final left = x - textPainter.width / 2;

      if (left > lastRight + 12) {
        textPainter.paint(
          canvas,
          Offset(left, bottomAxisRect.top + 8),
        );

        lastRight = left + textPainter.width;
      }
    }
    final last = visibleCandles.last;

    final lastX =
        chartRect.left +
        step * (visibleCandles.length - 1) +
        step / 2;

    final lastText = "${last.date.month}/${last.date.day}";

    textPainter.text = TextSpan(
      text: lastText,
      style: TextStyle(
        color: Colors.grey,
        fontSize: dateFontSize,
      ),
    );

    textPainter.layout();

    final lastLeft = lastX - textPainter.width / 2;

    final drawX = lastLeft.clamp(
      chartRect.left,
      chartRect.right - textPainter.width,
    );

    textPainter.paint(
      canvas,
      Offset(drawX, bottomAxisRect.top + 8),
    );

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}