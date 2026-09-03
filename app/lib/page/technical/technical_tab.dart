import 'package:flutter/material.dart';

import '../../api/kline_api.dart';
import '../../models/candle.dart';

import 'kline_chart.dart';
import 'volume_chart.dart';
import 'indicator_selector.dart';
import '../../utils/indicator_utils.dart';
import '../../models/indicator_setting.dart';
import '../../utils/responsive.dart';

class TechnicalTab extends StatefulWidget {
  const TechnicalTab({
    super.key,
    required this.code,
    this.useMarketKline = false,
  });

  final String code;

  // 大盤指數/期貨頁用：改呼叫 /market/kline（volume 是成交金額，
  // 不是股數/口數）。一般股票頁不用傳，維持原本行為。
  final bool useMarketKline;

  @override
  State<TechnicalTab> createState() => _TechnicalTabState();
}

class _TechnicalTabState extends State<TechnicalTab> {
  bool loading = true;

  List<Candle> candles = [];
  final indicator = IndicatorSetting();

  late List<double?> ma5;
  late List<double?> ma10;
  late List<double?> ma20;
  late List<double?> ma60;
  late List<double?> ma120;
  late List<double?> ma240;

  late List<double?> k;
  late List<double?> d;

  late List<double?> dif;
  late List<double?> dea;
  late List<double?> osc;

  late List<double?> rsi5;
  late List<double?> rsi10;
  late List<double?> obv;

  late List<double?> bollUpper;
  late List<double?> bollMiddle;
  late List<double?> bollLower;

  LowerIndicator lowerIndicator =
      LowerIndicator.volume;

  int visibleCount = 60;

/// -1 代表第一次開啟，自動顯示最新 visibleCount 根
  int startIndex = -1;

  int? selectedIndex;

  Candle? selectedCandle;

  double _lastScale = 1.0;
  double _dragDx = 0;
  double _lastFocalX = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    candles = widget.useMarketKline
        ? await KlineApi.getMarketKline(widget.code)
        : await KlineApi.getKline(widget.code);

    ma5 = IndicatorUtils.calculateMA(candles, 5);
    ma10 = IndicatorUtils.calculateMA(candles, 10);
    ma20 = IndicatorUtils.calculateMA(candles, 20);
    ma60 = IndicatorUtils.calculateMA(candles, 60);
    ma120 = IndicatorUtils.calculateMA(candles, 120);
    ma240 = IndicatorUtils.calculateMA(candles, 240);

    final kd = IndicatorUtils.calculateKD(candles);
    k = kd.k;
    d = kd.d;

    final macd =
        IndicatorUtils.calculateMACD(candles);

    dif = macd.dif;
    dea = macd.dea;
    osc = macd.osc;

    rsi5 = IndicatorUtils.calculateRSI(candles, 5);
    rsi10 = IndicatorUtils.calculateRSI(candles, 10);
    obv = IndicatorUtils.calculateOBV(candles);

    final boll = IndicatorUtils.calculateBoll(
      candles,
      indicator.bollPeriod,
      indicator.bollStd,
    );

    bollUpper = boll.upper;
    bollMiddle = boll.middle;
    bollLower = boll.lower;

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [

        if (selectedCandle != null)
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: (() {
                final begin =
                    startIndex < 0
                        ? (candles.length - visibleCount).clamp(0, candles.length)
                        : startIndex;
                final realIndex = begin + selectedIndex!;

                final open = candles[realIndex].open;
                final close = candles[realIndex].close;
                final high = candles[realIndex].high;
                final low = candles[realIndex].low;

                // 大盤/期貨頁的 volume 本來就是成交金額，不是股數，
                // 不能再除以1000當張數、標「張」——改成除以一億，
                // 用「億元」顯示；一般股票維持原本的張數邏輯。
                final volumeText = widget.useMarketKline
                    ? "${(candles[realIndex].volume / 100000000).toStringAsFixed(2)} 億元"
                    : "${candles[realIndex].volume.toInt() ~/ 1000} 張";

                double change = 0;
                double changePercent = 0;

                if (realIndex > 0) {
                  change = close - candles[realIndex - 1].close;
                  changePercent =
                      change / candles[realIndex - 1].close * 100;
                }

                final amplitude = (high - low) / open * 100;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      children: [
                        Text(
                          "${selectedCandle!.date.year}/${selectedCandle!.date.month}/${selectedCandle!.date.day}",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Text("開 $open", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text("高 $high", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text("低 $low", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text("收 $close", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text("量 $volumeText", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          "漲跌 "
                          "${change > 0 ? "+" : ""}"
                          "${change.toStringAsFixed(2)}"
                          " "
                          "(${changePercent.toStringAsFixed(2)}%)",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: change >= 0 ? Colors.red : Colors.green,
                          ),
                        ),
                        Text(
                          "振幅 ${amplitude.toStringAsFixed(2)}%",
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        if (indicator.mainIndicator == MainIndicator.ma) ...[
                          if (indicator.ma5)
                            Text("MA5 ${ma5[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber)),
                          if (indicator.ma10)
                            Text("MA10 ${ma10[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue)),
                          if (indicator.ma20)
                            Text("MA20 ${ma20[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple)),
                          if (indicator.ma60)
                            Text("MA60 ${ma60[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                          if (indicator.ma120)
                            Text("MA120 ${ma120[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange)),
                          if (indicator.ma240)
                            Text("MA240 ${ma240[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red)),
                        ] else ...[
                          Text("UP ${bollUpper[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange)),
                          Text("MID ${bollMiddle[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple)),
                          Text("LOW ${bollLower[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ],
                    ),
                  ],
                );
              })(),
            ),
          ),

        const SizedBox(height: 2),

        IndicatorSelector(
          indicator: indicator,
          onChanged: () {
            setState(() {});
          },
        ),

        const SizedBox(height: 6),

        Expanded(
          flex: 7,
          child: GestureDetector(
            onTapDown: _onTap,

            onScaleStart: (details) {
              _lastScale = 1.0;
              _dragDx = 0;
              _lastFocalX = details.localFocalPoint.dx;
            },

            onScaleUpdate: (details) {

              //---------------------------------
              // 一根手指 = 左右拖曳
              //---------------------------------

              if (details.pointerCount == 1) {

                _dragDx += details.focalPointDelta.dx;

                final scale = ResponsiveChart.scaleFor(context.size!.width);
                final leftPadding = 30.0 * scale;
                final rightAxisWidth = 55.0 * scale;
                final rightPadding = 20.0 * scale;

                final chartWidth =
                    context.size!.width -
                    leftPadding -
                    rightAxisWidth -
                    rightPadding;

                final candleWidth = chartWidth / visibleCount;

                if (_dragDx.abs() > candleWidth) {

                  setState(() {

                    if (startIndex < 0) {
                      startIndex =
                          (candles.length - visibleCount)
                              .clamp(0, candles.length);
                    }

                    final move =
                        (_dragDx / candleWidth).round();

                    startIndex -= move;

                    final maxStart =
                        (candles.length - visibleCount)
                            .clamp(0, candles.length);

                    startIndex =
                        startIndex.clamp(0, maxStart);

                  });

                  _dragDx = 0;
                }

                return;
              }

              //---------------------------------
              // 兩根手指 = 縮放
              //---------------------------------

              final delta = details.scale - _lastScale;

              if (delta.abs() > 0.05) {

                setState(() {

                  if (startIndex < 0) {
                    startIndex =
                        (candles.length - visibleCount)
                            .clamp(0, candles.length);
                  }

                  final ratio =
                      _lastFocalX / context.size!.width;

                  final centerIndex =
                      startIndex +
                      (visibleCount * ratio).round();

                  if (delta > 0) {
                    visibleCount -= 8;
                  } else {
                    visibleCount += 8;
                  }

                  visibleCount =
                      visibleCount.clamp(30, 300);

                  startIndex =
                      centerIndex -
                      (visibleCount * ratio).round();

                  startIndex = startIndex.clamp(
                    0,
                    candles.length - visibleCount,
                  );

                });

                _lastScale = details.scale;
              }

            },

            child: KlineChart(
              candles: candles,
              visibleCount: visibleCount,
              startIndex: startIndex,
              selectedIndex: selectedIndex,
              ma5: ma5,
              ma10: ma10,
              ma20: ma20,
              ma60: ma60,
              ma120: ma120,
              ma240: ma240,
              bollUpper: bollUpper,
              bollMiddle: bollMiddle,
              bollLower: bollLower,
              indicator: indicator,
            ),
          ),
        ),

        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: DropdownButton<LowerIndicator>(
            value: lowerIndicator,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: LowerIndicator.volume,
                child: Text("成交量"),
              ),
              DropdownMenuItem(
                value: LowerIndicator.kd,
                child: Text("KD"),
              ),
              DropdownMenuItem(
                value: LowerIndicator.macd,
                child: Text("MACD"),
              ),
              DropdownMenuItem(
                value: LowerIndicator.rsi,
                child: Text("RSI"),
              ),
              DropdownMenuItem(
                value: LowerIndicator.obv,
                child: Text("OBV"),
              ),
            ],
            onChanged: (value){
              if(value==null) return;
              setState(() {
                lowerIndicator=value;
              });
            },
          ),
        ),

        Expanded(
          flex: 3,
          child: buildLowerChart(),
        ),

      ],
    );
  }



  void _onTap(TapDownDetails details) {

    if (candles.isEmpty) return;

    final begin =
        startIndex < 0
            ? (candles.length - visibleCount).clamp(0, candles.length)
            : startIndex;

    final end =
        (begin + visibleCount).clamp(0, candles.length);

    final visible = candles.sublist(begin, end);

    final scale = ResponsiveChart.scaleFor(context.size!.width);
    final leftPadding = 30.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;

    final chartWidth =
        context.size!.width -
        leftPadding -
        rightAxisWidth -
        rightPadding;

    if (details.localPosition.dx < leftPadding ||
        details.localPosition.dx > leftPadding + chartWidth) {
      setState(() {
        selectedIndex = null;
        selectedCandle = null;
      });
      return;
    }

    final step = chartWidth / visible.length;

    final index = ((details.localPosition.dx - leftPadding) / step)
        .floor()
        .clamp(0, visible.length - 1);

    if (selectedIndex == index) {
      setState(() {
        selectedIndex = null;
        selectedCandle = null;
      });
      return;
    }

    setState(() {
      selectedIndex = index;
      selectedCandle = visible[index];
    });
  }

  Widget buildLowerChart(){

    switch(lowerIndicator){

      case LowerIndicator.volume:
      case LowerIndicator.kd:
      case LowerIndicator.macd:
      case LowerIndicator.rsi:
      case LowerIndicator.obv:
        return VolumeChart(
          candles: candles,
          visibleCount: visibleCount,
          startIndex: startIndex,
          selectedIndex: selectedIndex,
          type: lowerIndicator,
          k: k,
          d: d,
          dif: dif,
          dea: dea,
          osc: osc,
          rsi5: rsi5,
          rsi10: rsi10,
          obv: obv,
        );

    }

  }
}