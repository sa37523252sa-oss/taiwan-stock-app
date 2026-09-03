import 'package:flutter/material.dart';

import '../../models/candle.dart';
import '../../utils/responsive.dart';

enum LowerIndicator {
  volume,
  kd,
  macd,
  rsi,
  obv,
}

class VolumeChart extends StatelessWidget {
  const VolumeChart({
    super.key,
    required this.candles,
    required this.visibleCount,
    required this.startIndex,
    required this.selectedIndex,
    required this.type,
    required this.k,
    required this.d,
    required this.dif,
    required this.dea,
    required this.osc,
    required this.rsi5,
    required this.rsi10,
    required this.obv,
  });

  final List<Candle> candles;
  final int visibleCount;
  final int startIndex;
  final int? selectedIndex;
  final LowerIndicator type;
  final List<double?> k;
  final List<double?> d;
  final List<double?> dif;
  final List<double?> dea;
  final List<double?> osc;
  final List<double?> rsi5;
  final List<double?> rsi10;
  final List<double?> obv;

  @override
  Widget build(BuildContext context) {
    final begin = startIndex < 0
        ? (candles.length - visibleCount).clamp(0, candles.length)
        : startIndex;

    final end =
        (begin + visibleCount).clamp(0, candles.length);

    final visible = candles.sublist(begin, end);
    final visibleK = k.sublist(begin, end);
    final visibleD = d.sublist(begin, end);
    final visibleDif = dif.sublist(begin, end);
    final visibleDea = dea.sublist(begin, end);
    final visibleOsc = osc.sublist(begin, end);
    final visibleRsi5 = rsi5.sublist(begin, end);
    final visibleRsi10 = rsi10.sublist(begin, end);
    final visibleObv = obv.sublist(begin, end);

    return CustomPaint(
      painter: _VolumePainter(
        visible,
        selectedIndex,
        type,
        visibleK,
        visibleD,
        visibleDif,
        visibleDea,
        visibleOsc,
        visibleRsi5,
        visibleRsi10,
        visibleObv,
      ),
      size: Size.infinite,
    );
  }
}

class _VolumePainter extends CustomPainter {
  const _VolumePainter(
    this.candles,
    this.selectedIndex,
    this.type,
    this.k,
    this.d,
    this.dif,
    this.dea,
    this.osc,
    this.rsi5,
    this.rsi10,
    this.obv,
  );

  final List<Candle> candles;
  final int? selectedIndex;
  final LowerIndicator type;
  final List<double?> k;
  final List<double?> d;
  final List<double?> dif;
  final List<double?> dea;
  final List<double?> osc;
  final List<double?> rsi5;
  final List<double?> rsi10;
  final List<double?> obv;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    switch (type) {
      case LowerIndicator.volume:
        _drawVolume(canvas, size);
        break;
      case LowerIndicator.kd:
        _drawKD(canvas, size);
        break;
      case LowerIndicator.macd:
        _drawMACD(canvas, size);
        break;
      case LowerIndicator.rsi:
        _drawRSI(canvas, size);
        break;
      case LowerIndicator.obv:
        _drawOBV(canvas, size);
        break;
    }
  }

  void _drawTopLeftLabel(Canvas canvas, List<TextSpan> spans) {
    final tp = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, const Offset(6, 4));
  }

  void _drawOneLine(
    Canvas canvas,
    List<double?> values,
    double step,
    double leftPadding,
    double Function(double) toY,
    Color color, {
    double strokeWidth = 2,
  }) {
    final path = Path();
    bool started = false;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = leftPadding + i * step + step / 2;
      final py = toY(v);
      if (!started) {
        path.moveTo(x, py);
        started = true;
      } else {
        path.lineTo(x, py);
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
  ) {
    const dash = 4.0;
    const gap = 4.0;
    final total = (p2 - p1).distance;
    if (total == 0) return;
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

  void _drawVolume(
    Canvas canvas,
    Size size,
  ) {
    final scale = ResponsiveChart.scaleFor(size.width);
    final leftPadding = 30.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;
    final labelFontSize = 11.0 * scale;
    final hairlineWidth = 1.0 * scale;
    final dataLineWidth = 2.0 * scale;
    final thinLineWidth = 1.5 * scale;

    final chartWidth =
        size.width -
        leftPadding -
        rightAxisWidth -
        rightPadding;

    final maxVolume = candles
        .map((e) => e.volume)
        .reduce((a, b) => a > b ? a : b);

    const spacing = 2.0;
    final barWidth =
        (chartWidth - spacing * candles.length) /
        candles.length;

    for (int i = 0; i < candles.length; i++) {
      final candle = candles[i];

      final h =
          candle.volume / maxVolume * size.height;

      final left =
          leftPadding +
          i * (barWidth + spacing);

      final rect = Rect.fromLTWH(
        left,
        size.height - h,
        barWidth,
        h,
      );

      final color =
          candle.close >= candle.open
              ? Colors.red
              : Colors.green;

      canvas.drawRect(
        rect,
        Paint()..color = color,
      );
    }

    if (selectedIndex != null) {

      final x =
          leftPadding +
          selectedIndex! * (barWidth + spacing) +
          barWidth / 2;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = hairlineWidth,
      );
    }

    _drawTopLeftLabel(canvas, [
      TextSpan(
        text: "成交量",
        style: TextStyle(fontSize: labelFontSize, color: Colors.grey),
      ),
    ]);
  }

  void _drawKD(
    Canvas canvas,
    Size size,
  ) {
    final scale = ResponsiveChart.scaleFor(size.width);
    final leftPadding = 30.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;
    final labelFontSize = 11.0 * scale;
    final hairlineWidth = 1.0 * scale;
    final dataLineWidth = 2.0 * scale;
    final thinLineWidth = 1.5 * scale;

    final chartWidth =
        size.width -
        leftPadding -
        rightAxisWidth -
        rightPadding;

    final step = chartWidth / candles.length;

    double y(double value) {
      return size.height - value / 100 * size.height;
    }

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.25)
      ..strokeWidth = hairlineWidth;

    const levels = [0.0, 20.0, 50.0, 80.0, 100.0];

    for (final level in levels) {
      final ly = y(level);
      canvas.drawLine(
        Offset(leftPadding, ly),
        Offset(leftPadding + chartWidth, ly),
        gridPaint,
      );
    }

    _drawDashedLine(
      canvas,
      Offset(leftPadding, y(80)),
      Offset(leftPadding + chartWidth, y(80)),
      Paint()
        ..color = Colors.red.withOpacity(0.6)
        ..strokeWidth = hairlineWidth,
    );

    _drawDashedLine(
      canvas,
      Offset(leftPadding, y(20)),
      Offset(leftPadding + chartWidth, y(20)),
      Paint()
        ..color = Colors.green.withOpacity(0.6)
        ..strokeWidth = hairlineWidth,
    );

    void drawLine(List<double?> values, Color color) {
      final path = Path();
      bool started = false;
      final paint = Paint()
        ..color = color
        ..strokeWidth = dataLineWidth
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < values.length; i++) {
        final v = values[i];
        if (v == null) continue;
        final x = leftPadding + i * step + step / 2;
        final py = y(v);
        if (!started) {
          path.moveTo(x, py);
          started = true;
        } else {
          path.lineTo(x, py);
        }
      }

      canvas.drawPath(path, paint);
    }

    drawLine(k, Colors.amber);
    drawLine(d, Colors.blue);

    if (selectedIndex != null) {
      final x =
          leftPadding +
          selectedIndex! * step +
          step / 2;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = hairlineWidth,
      );
    }

    final idx = selectedIndex ?? (candles.length - 1);
    final kVal = idx >= 0 && idx < k.length ? k[idx] : null;
    final dVal = idx >= 0 && idx < d.length ? d[idx] : null;

    _drawTopLeftLabel(canvas, [
      TextSpan(
        text: "KD  ",
        style: TextStyle(fontSize: labelFontSize, color: Colors.grey),
      ),
      TextSpan(
        text: "K ${kVal?.toStringAsFixed(2) ?? '--'}  ",
        style: TextStyle(
          fontSize: labelFontSize,
          color: Colors.amber,
          fontWeight: FontWeight.bold,
        ),
      ),
      TextSpan(
        text: "D ${dVal?.toStringAsFixed(2) ?? '--'}",
        style: TextStyle(
          fontSize: labelFontSize,
          color: Colors.blue,
          fontWeight: FontWeight.bold,
        ),
      ),
    ]);
  }

  void _drawMACD(
    Canvas canvas,
    Size size,
  ) {
    final scale = ResponsiveChart.scaleFor(size.width);
    final leftPadding = 30.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;
    final labelFontSize = 11.0 * scale;
    final hairlineWidth = 1.0 * scale;
    final dataLineWidth = 2.0 * scale;
    final thinLineWidth = 1.5 * scale;

    final chartWidth =
        size.width -
        leftPadding -
        rightAxisWidth -
        rightPadding;

    final step = chartWidth / candles.length;

    final values = <double>[
      for (final v in dif) if (v != null) v.abs(),
      for (final v in dea) if (v != null) v.abs(),
      for (final v in osc) if (v != null) v.abs(),
    ];

    final maxAbs = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);

    final range = maxAbs == 0 ? 1.0 : maxAbs * 1.1;

    double y(double value) {
      return size.height / 2 - value / range * (size.height / 2);
    }

    final zeroPaint = Paint()
      ..color = Colors.grey.withOpacity(0.4)
      ..strokeWidth = hairlineWidth;

    canvas.drawLine(
      Offset(leftPadding, y(0)),
      Offset(leftPadding + chartWidth, y(0)),
      zeroPaint,
    );

    const spacing = 2.0;
    final barWidth = (step - spacing).clamp(1.0 * scale, 12.0 * scale);

    for (int i = 0; i < osc.length; i++) {
      final v = osc[i];
      if (v == null) continue;

      final x = leftPadding + i * step + step / 2;

      final top = v >= 0 ? y(v) : y(0);
      final bottom = v >= 0 ? y(0) : y(v);

      canvas.drawRect(
        Rect.fromLTRB(
          x - barWidth / 2,
          top,
          x + barWidth / 2,
          bottom,
        ),
        Paint()
          ..color = v >= 0 ? Colors.red : Colors.green,
      );
    }

    void drawLine(List<double?> values, Color color) {
      final path = Path();
      bool started = false;
      final paint = Paint()
        ..color = color
        ..strokeWidth = thinLineWidth
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < values.length; i++) {
        final v = values[i];
        if (v == null) continue;
        final x = leftPadding + i * step + step / 2;
        final py = y(v);
        if (!started) {
          path.moveTo(x, py);
          started = true;
        } else {
          path.lineTo(x, py);
        }
      }

      canvas.drawPath(path, paint);
    }

    drawLine(dif, Colors.orange);
    drawLine(dea, Colors.purple);

    if (selectedIndex != null) {
      final x =
          leftPadding +
          selectedIndex! * step +
          step / 2;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = hairlineWidth,
      );
    }

    final idx = selectedIndex ?? (candles.length - 1);
    final difVal = idx >= 0 && idx < dif.length ? dif[idx] : null;
    final deaVal = idx >= 0 && idx < dea.length ? dea[idx] : null;
    final oscVal = idx >= 0 && idx < osc.length ? osc[idx] : null;

    _drawTopLeftLabel(canvas, [
      TextSpan(
        text: "MACD  ",
        style: TextStyle(fontSize: labelFontSize, color: Colors.grey),
      ),
      TextSpan(
        text: "DIF ${difVal?.toStringAsFixed(2) ?? '--'}  ",
        style: TextStyle(
          fontSize: labelFontSize,
          color: Colors.orange,
          fontWeight: FontWeight.bold,
        ),
      ),
      TextSpan(
        text: "DEA ${deaVal?.toStringAsFixed(2) ?? '--'}  ",
        style: TextStyle(
          fontSize: labelFontSize,
          color: Colors.purple,
          fontWeight: FontWeight.bold,
        ),
      ),
      TextSpan(
        text: "OSC ${oscVal?.toStringAsFixed(2) ?? '--'}",
        style: TextStyle(
          fontSize: labelFontSize,
          color: (oscVal ?? 0) >= 0 ? Colors.red : Colors.green,
          fontWeight: FontWeight.bold,
        ),
      ),
    ]);
  }

  void _drawRSI(
    Canvas canvas,
    Size size,
  ) {
    final scale = ResponsiveChart.scaleFor(size.width);
    final leftPadding = 30.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;
    final labelFontSize = 11.0 * scale;
    final hairlineWidth = 1.0 * scale;
    final dataLineWidth = 2.0 * scale;
    final thinLineWidth = 1.5 * scale;

    final chartWidth =
        size.width -
        leftPadding -
        rightAxisWidth -
        rightPadding;

    final step = chartWidth / candles.length;

    double y(double value) {
      return size.height - value / 100 * size.height;
    }

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.25)
      ..strokeWidth = hairlineWidth;

    const levels = [0.0, 30.0, 50.0, 70.0, 100.0];

    for (final level in levels) {
      final ly = y(level);
      canvas.drawLine(
        Offset(leftPadding, ly),
        Offset(leftPadding + chartWidth, ly),
        gridPaint,
      );
    }

    _drawDashedLine(
      canvas,
      Offset(leftPadding, y(70)),
      Offset(leftPadding + chartWidth, y(70)),
      Paint()
        ..color = Colors.red.withOpacity(0.6)
        ..strokeWidth = hairlineWidth,
    );

    _drawDashedLine(
      canvas,
      Offset(leftPadding, y(30)),
      Offset(leftPadding + chartWidth, y(30)),
      Paint()
        ..color = Colors.green.withOpacity(0.6)
        ..strokeWidth = hairlineWidth,
    );

    _drawOneLine(canvas, rsi5, step, leftPadding, y, Colors.yellow, strokeWidth: dataLineWidth);
    _drawOneLine(canvas, rsi10, step, leftPadding, y, Colors.lightBlue, strokeWidth: dataLineWidth);

    if (selectedIndex != null) {
      final x =
          leftPadding +
          selectedIndex! * step +
          step / 2;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = hairlineWidth,
      );
    }

    final idx = selectedIndex ?? (candles.length - 1);
    final rsi5Val = idx >= 0 && idx < rsi5.length ? rsi5[idx] : null;
    final rsi10Val = idx >= 0 && idx < rsi10.length ? rsi10[idx] : null;

    _drawTopLeftLabel(canvas, [
      TextSpan(
        text: "RSI  ",
        style: TextStyle(fontSize: labelFontSize, color: Colors.grey),
      ),
      TextSpan(
        text: "5T ${rsi5Val?.toStringAsFixed(2) ?? '--'}  ",
        style: TextStyle(
          fontSize: labelFontSize,
          color: Colors.yellow,
          fontWeight: FontWeight.bold,
        ),
      ),
      TextSpan(
        text: "10T ${rsi10Val?.toStringAsFixed(2) ?? '--'}",
        style: TextStyle(
          fontSize: labelFontSize,
          color: Colors.lightBlue,
          fontWeight: FontWeight.bold,
        ),
      ),
    ]);
  }

  String _formatObv(double value) {
    final abs = value.abs();
    final sign = value < 0 ? "-" : "";

    if (abs >= 1e9) {
      return "$sign${(abs / 1e9).toStringAsFixed(2)}B";
    }
    if (abs >= 1e6) {
      return "$sign${(abs / 1e6).toStringAsFixed(2)}M";
    }
    if (abs >= 1e3) {
      return "$sign${(abs / 1e3).toStringAsFixed(2)}K";
    }
    return value.toStringAsFixed(0);
  }

  void _drawOBV(
    Canvas canvas,
    Size size,
  ) {
    final scale = ResponsiveChart.scaleFor(size.width);
    final leftPadding = 30.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;
    final labelFontSize = 11.0 * scale;
    final hairlineWidth = 1.0 * scale;
    final dataLineWidth = 2.0 * scale;
    final thinLineWidth = 1.5 * scale;

    final chartWidth =
        size.width -
        leftPadding -
        rightAxisWidth -
        rightPadding;

    final step = chartWidth / candles.length;

    final values = [
      for (final v in obv) if (v != null) v,
    ];

    if (values.isEmpty) return;

    final maxObv = values.reduce((a, b) => a > b ? a : b);
    final minObv = values.reduce((a, b) => a < b ? a : b);

    final range = (maxObv - minObv) == 0 ? 1.0 : maxObv - minObv;

    double y(double value) {
      const topPadding = 10.0;
      const bottomPadding = 10.0;
      return topPadding +
          (maxObv - value) /
              range *
              (size.height - topPadding - bottomPadding);
    }

    final path = Path();
    bool started = false;
    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = dataLineWidth
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < obv.length; i++) {
      final v = obv[i];
      if (v == null) continue;
      final x = leftPadding + i * step + step / 2;
      final py = y(v);
      if (!started) {
        path.moveTo(x, py);
        started = true;
      } else {
        path.lineTo(x, py);
      }
    }

    canvas.drawPath(path, linePaint);

    if (selectedIndex != null) {
      final x =
          leftPadding +
          selectedIndex! * step +
          step / 2;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = hairlineWidth,
      );
    }

    final idx = selectedIndex ?? (candles.length - 1);
    final obvVal = idx >= 0 && idx < obv.length ? obv[idx] : null;

    _drawTopLeftLabel(canvas, [
      TextSpan(
        text: "OBV  ",
        style: TextStyle(fontSize: labelFontSize, color: Colors.grey),
      ),
      TextSpan(
        text: obvVal == null ? '--' : _formatObv(obvVal),
        style: TextStyle(
          fontSize: labelFontSize,
          color: Colors.blue,
          fontWeight: FontWeight.bold,
        ),
      ),
    ]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}