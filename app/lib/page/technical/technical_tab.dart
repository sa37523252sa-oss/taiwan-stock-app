import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../api/kline_api.dart';
import '../../models/candle.dart';

import 'kline_chart.dart';
import 'volume_chart.dart';
import 'indicator_selector.dart';
import '../../utils/indicator_utils.dart';
import '../../models/indicator_setting.dart';
import '../../utils/responsive.dart';

/// 會爭取橫向手勢、但把直向讓給外層的縮放辨識器。
///
/// 兩個衝突要同時解決：
///
///   個股頁的 K 線包在 TabBarView 裡，TabBarView 有自己的橫向
///   拖曳辨識器，預設會贏 —— 想左右滑 K 線結果整頁跳到「法人」。
///
///   大盤頁的 K 線包在 ListView 裡，如果無條件搶下所有手勢，
///   在圖上直向滑就沒辦法捲動頁面。
///
/// 所以判斷方向：多指（縮放）或橫向位移較大時才搶，直向為主
/// 就照常讓給外層。
class _EagerScaleRecognizer extends ScaleGestureRecognizer {

  Offset _delta = Offset.zero;
  final Set<int> _pointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointers.isEmpty) _delta = Offset.zero;
    _pointers.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _delta += event.delta;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {

    final horizontal = _delta.dx.abs() > _delta.dy.abs();

    if (_pointers.length > 1 || horizontal) {
      acceptGesture(pointer);
    } else {
      super.rejectGesture(pointer);
    }
  }
}


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

  // K 線手勢區域的實際寬度。
  //
  // 原本用 context.size!.width，那取到的是整個 TechnicalTab 的寬度，
  // 不是 Expanded(flex:7) 那塊畫布的寬度。內嵌在大盤頁時（固定 480
  // 高的卡片）跟全螢幕時容器不同，兩者差距讓 _lastFocalX / width 算
  // 出的 ratio 超出 0~1，centerIndex 被推到資料範圍外，縮放幾次之後
  // begin 和 end 相等，visibleCandles 變成空的，painter 的 reduce 就
  // 丟 StateError，整張圖消失。
  //
  // 改由 LayoutBuilder 提供真實寬度。
  double _chartAreaWidth = 0;

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
            // 不要固定高度，也不要包橫向捲動的 SingleChildScrollView
            // ——那會給 Wrap 無限寬度，Wrap 就永遠不換行，手機上
            // 後面的 MA 數值全部被擠到畫面外，還得橫向滑才看得到。
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            alignment: Alignment.centerLeft,
            child: (() {
                final begin =
                    startIndex < 0
                        ? (candles.length - visibleCount).clamp(0, candles.length)
                        : startIndex;
                // selectedIndex 是「可見視窗內」的位置，但縮放和
                // 拖曳都會改變 startIndex 和 visibleCount，視窗移動
                // 之後 begin + selectedIndex 就可能衝出資料範圍。
                // 6590 筆資料卻去取 [6590]，就是這裡爆的。
                final realIndex = (begin + (selectedIndex ?? 0))
                    .clamp(0, candles.length - 1);

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
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        Text(
                          "${selectedCandle!.date.year}/${selectedCandle!.date.month}/${selectedCandle!.date.day}",
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text("開 $open", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text("高 $high", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text("低 $low", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text("收 $close", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text("量 $volumeText", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        Text(
                          "漲跌 "
                          "${change > 0 ? "+" : ""}"
                          "${change.toStringAsFixed(2)}"
                          " "
                          "(${changePercent.toStringAsFixed(2)}%)",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: change >= 0 ? Colors.red : Colors.green,
                          ),
                        ),
                        Text(
                          "振幅 ${amplitude.toStringAsFixed(2)}%",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        if (indicator.mainIndicator == MainIndicator.ma) ...[
                          if (indicator.ma5)
                            Text("MA5 ${ma5[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber)),
                          if (indicator.ma10)
                            Text("MA10 ${ma10[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue)),
                          if (indicator.ma20)
                            Text("MA20 ${ma20[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple)),
                          if (indicator.ma60)
                            Text("MA60 ${ma60[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                          if (indicator.ma120)
                            Text("MA120 ${ma120[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                          if (indicator.ma240)
                            Text("MA240 ${ma240[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                        ] else ...[
                          Text("UP ${bollUpper[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                          Text("MID ${bollMiddle[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple)),
                          Text("LOW ${bollLower[realIndex]?.toStringAsFixed(2) ?? '--'}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ],
                    ),
                  ],
                );
              })(),
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
          child: LayoutBuilder(
            builder: (context, constraints) {

              _chartAreaWidth = constraints.maxWidth;

              return RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  // 縮放/拖曳：用永不退讓的辨識器，才不會被
                  // TabBarView 的分頁切換搶走橫向手勢。
                  _EagerScaleRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          _EagerScaleRecognizer>(
                    () => _EagerScaleRecognizer(),
                    (instance) {
                      instance
                        ..onStart = _onScaleStart
                        ..onUpdate = _onScaleUpdate;
                    },
                  ),
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer>(
                    () => TapGestureRecognizer(),
                    (instance) {
                      instance.onTapDown = _onTap;
                    },
                  ),
                },
            child: Listener(
              // 桌機沒有雙指手勢，用滾輪縮放。也讓問題能在電腦上
              // 重現，比接手機偵錯快。
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _zoom(
                    zoomIn: event.scrollDelta.dy < 0,
                    focalRatio: _chartAreaWidth <= 0
                        ? 0.5
                        : (event.localPosition.dx / _chartAreaWidth)
                            .clamp(0.0, 1.0),
                  );
                }
              },
              child: Stack(
                children: [
                  // Size.infinite 的 CustomPaint 在 Stack 裡會變成
                  // 無界限，一定要用 Positioned.fill 給它明確範圍。
                  Positioned.fill(
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

                  // 縮放按鈕。手勢在某些裝置上不好操作，按鈕是
                  // 確定可用的備案，也方便逐次重現問題。
                  Positioned(
                    right: 60,
                    top: 4,
                    child: Column(
                      children: [
                        _zoomButton(Icons.add, () => _zoom(zoomIn: true)),
                        const SizedBox(height: 4),
                        _zoomButton(Icons.remove, () => _zoom(zoomIn: false)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
              );
            },
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



  void _onScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
    _dragDx = 0;
    _lastFocalX = details.localFocalPoint.dx;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {


              //---------------------------------
              // 一根手指 = 左右拖曳
              //---------------------------------

              if (details.pointerCount == 1) {

                _dragDx += details.focalPointDelta.dx;

                final scale = ResponsiveChart.scaleFor(_chartAreaWidth);
                final leftPadding = 30.0 * scale;
                final rightAxisWidth = 55.0 * scale;
                final rightPadding = 20.0 * scale;

                final chartWidth =
                    _chartAreaWidth -
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

                    // 拖曳也會位移視窗，同樣要清掉選取
                    selectedIndex = null;
                    selectedCandle = null;

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
                _zoom(
                  zoomIn: delta > 0,
                  focalRatio: _chartAreaWidth <= 0
                      ? 0.5
                      : (_lastFocalX / _chartAreaWidth).clamp(0.0, 1.0),
                );
                _lastScale = details.scale;
              }

            
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(0.85),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: Colors.black54),
        ),
      ),
    );
  }

  /// 縮放。手勢、滑鼠滾輪、按鈕都走這一條，邏輯只有一份。
  ///
  /// focalRatio 是縮放中心在圖表寬度上的比例（0=最左，1=最右），
  /// 用來決定縮放時要以哪一根 K 棒為軸心。
  void _zoom({required bool zoomIn, double focalRatio = 0.5}) {

    if (candles.isEmpty) return;

    setState(() {

      // 縮放會讓可見視窗整個位移，原本選取的那根 K 棒在新視窗裡
      // 已經不是同一個位置了，留著只會顯示錯的資料。
      selectedIndex = null;
      selectedCandle = null;

      if (startIndex < 0) {
        startIndex =
            (candles.length - visibleCount).clamp(0, candles.length);
      }

      final centerIndex =
          startIndex + (visibleCount * focalRatio).round();

      visibleCount += zoomIn ? -8 : 8;

      // 上限不能超過實際資料筆數，下限也要讓步：資料只有 20 根
      // 時不能硬要 30。maxStart 為負時 clamp(0, 負數) 會丟
      // ArgumentError，整張圖就崩掉不見。
      final upper = candles.length < 300 ? candles.length : 300;
      final lower = candles.length < 30 ? candles.length : 30;

      visibleCount = visibleCount.clamp(
        lower,
        upper < lower ? lower : upper,
      );

      startIndex = centerIndex - (visibleCount * focalRatio).round();

      final maxStart = candles.length - visibleCount;

      startIndex = startIndex.clamp(0, maxStart < 0 ? 0 : maxStart);
    });
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

    // 空清單的話，下面 clamp(0, visible.length - 1) 會變成
    // clamp(0, -1)，Dart 直接丟 ArgumentError。
    if (visible.isEmpty) return;

    final scale = ResponsiveChart.scaleFor(_chartAreaWidth);
    final leftPadding = 30.0 * scale;
    final rightAxisWidth = 55.0 * scale;
    final rightPadding = 20.0 * scale;

    final chartWidth =
        _chartAreaWidth -
        leftPadding -
        rightAxisWidth -
        rightPadding;

    // 版面還沒量到寬度時不處理點擊，否則 step 會是 0 或負數
    if (chartWidth <= 0) return;

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