import 'dart:math';

import '../models/candle.dart';

class IndicatorUtils {
  static List<double?> calculateMA(
    List<Candle> candles,
    int period,
  ) {
    final result = List<double?>.filled(candles.length, null);

    if (candles.length < period) return result;

    double sum = 0;

    for (int i = 0; i < candles.length; i++) {
      sum += candles[i].close;

      if (i >= period) {
        sum -= candles[i - period].close;
      }

      if (i >= period - 1) {
        result[i] = sum / period;
      }
    }

    return result;
  }

  static ({List<double?> k, List<double?> d}) calculateKD(
    List<Candle> candles, {
    int period = 9,
  }) {
    final kList = List<double?>.filled(candles.length, null);
    final dList = List<double?>.filled(candles.length, null);

    if (candles.length < period) return (k: kList, d: dList);

    double prevK = 50;
    double prevD = 50;

    for (int i = 0; i < candles.length; i++) {
      if (i < period - 1) continue;

      final window = candles.sublist(i - period + 1, i + 1);

      final highest =
          window.map((e) => e.high).reduce((a, b) => a > b ? a : b);
      final lowest =
          window.map((e) => e.low).reduce((a, b) => a < b ? a : b);

      final range = highest - lowest;

      final rsv =
          range == 0 ? 0.0 : (candles[i].close - lowest) / range * 100;

      final currentK = prevK * 2 / 3 + rsv * 1 / 3;
      final currentD = prevD * 2 / 3 + currentK * 1 / 3;

      kList[i] = currentK;
      dList[i] = currentD;

      prevK = currentK;
      prevD = currentD;
    }

    return (k: kList, d: dList);
  }

  static List<double?> _ema(
    List<double> values,
    int period,
  ) {
    final result = List<double?>.filled(values.length, null);

    if (values.isEmpty) return result;

    final multiplier = 2 / (period + 1);

    result[0] = values[0];

    for (int i = 1; i < values.length; i++) {
      result[i] =
          (values[i] - result[i - 1]!) * multiplier +
          result[i - 1]!;
    }

    return result;
  }

  static ({
    List<double?> dif,
    List<double?> dea,
    List<double?> osc,
  }) calculateMACD(List<Candle> candles) {

    final close =
        candles.map((e) => e.close).toList();

    final ema12 = _ema(close, 12);

    final ema26 = _ema(close, 26);

    final dif =
        List<double?>.filled(close.length, null);

    for (int i = 0; i < close.length; i++) {

      if (ema12[i] == null ||
          ema26[i] == null) continue;

      dif[i] = ema12[i]! - ema26[i]!;
    }

    //-------------------------
    // DEA
    //-------------------------

    final dea =
        List<double?>.filled(close.length, null);

    double? last;

    const alpha = 2 / (9 + 1);

    for (int i = 0; i < dif.length; i++) {

      if (dif[i] == null) continue;

      if (last == null) {

        last = dif[i];

      } else {

        last =
            last +
            alpha *
                (dif[i]! - last);

      }

      dea[i] = last;

    }

    //-------------------------
    // OSC
    //-------------------------

    final osc =
        List<double?>.filled(close.length, null);

    for (int i = 0; i < dif.length; i++) {

      if (dif[i] == null ||
          dea[i] == null) continue;

      osc[i] =
          dif[i]! - dea[i]!;
    }

    return (

      dif: dif,

      dea: dea,

      osc: osc,

    );

  }

  static List<double?> calculateRSI(
    List<Candle> candles,
    int period,
  ) {
    final result = List<double?>.filled(candles.length, null);

    if (candles.length <= period) return result;

    final gains = List<double>.filled(candles.length, 0);
    final losses = List<double>.filled(candles.length, 0);

    for (int i = 1; i < candles.length; i++) {
      final diff = candles[i].close - candles[i - 1].close;
      gains[i] = diff > 0 ? diff : 0;
      losses[i] = diff < 0 ? -diff : 0;
    }

    //-------------------------
    // 第一筆 Average Gain / Loss
    // 用前 period 天的簡單平均
    //-------------------------

    double avgGain = 0;
    double avgLoss = 0;

    for (int i = 1; i <= period; i++) {
      avgGain += gains[i];
      avgLoss += losses[i];
    }

    avgGain /= period;
    avgLoss /= period;

    result[period] =
        avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);

    //-------------------------
    // 之後每一筆用 Wilder Moving Average
    //-------------------------

    for (int i = period + 1; i < candles.length; i++) {
      avgGain = (avgGain * (period - 1) + gains[i]) / period;
      avgLoss = (avgLoss * (period - 1) + losses[i]) / period;

      result[i] =
          avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
    }

    return result;
  }

  static List<double?> calculateOBV(List<Candle> candles) {
    final result = List<double?>.filled(candles.length, null);

    if (candles.isEmpty) return result;

    double obv = 0;
    result[0] = 0;

    for (int i = 1; i < candles.length; i++) {
      if (candles[i].close > candles[i - 1].close) {
        obv += candles[i].volume;
      } else if (candles[i].close < candles[i - 1].close) {
        obv -= candles[i].volume;
      }

      result[i] = obv;
    }

    return result;
  }

  static ({
    List<double?> upper,
    List<double?> middle,
    List<double?> lower,
  }) calculateBoll(
    List<Candle> candles,
    int period,
    double stdMultiplier,
  ) {

    final middle = calculateMA(candles, period);

    final upper = List<double?>.filled(candles.length, null);
    final lower = List<double?>.filled(candles.length, null);

    if (candles.length < period) {
      return (upper: upper, middle: middle, lower: lower);
    }

    for (int i = period - 1; i < candles.length; i++) {

      final window = candles.sublist(i - period + 1, i + 1);

      final mean = middle[i]!;

      double sumSq = 0;

      for (final c in window) {
        final diff = c.close - mean;
        sumSq += diff * diff;
      }

      final stdDev = sqrt(sumSq / period);

      upper[i] = mean + stdMultiplier * stdDev;
      lower[i] = mean - stdMultiplier * stdDev;
    }

    return (upper: upper, middle: middle, lower: lower);
  }
}