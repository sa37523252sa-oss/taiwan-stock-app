import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/financial.dart';
import '../../utils/responsive.dart';
import '../../models/stock.dart';

enum FinancialChartType {
  line,
  bar,
}

class FinancialChart extends StatefulWidget {
  const FinancialChart({
    super.key,
    required this.metrics,
    required this.category,
    required this.financial,
    required this.stock,
    this.chartType,
    this.selectedIndex,
    this.onSelectIndex,
    this.priceValues,
  });

  final List<String> metrics;
  final String category;
  final FinancialData financial;
  final Stock stock;
  final FinancialChartType? chartType;

  /// 目前選中（表格點擊）的資料點 index，對應 monthData/quarterData
  /// 的原始索引（不是反轉後的顯示順序）。
  final int? selectedIndex;
  final ValueChanged<int>? onSelectIndex;

  /// 每個月對應的收盤價（跟 monthData 一一對應，順序相同），
  /// 目前還沒有資料來源，先留接口，之後有月收盤價可以直接傳進來。
  final List<double?>? priceValues;

  static const List<Color> colors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.brown,
    Colors.cyan,
  ];
  static const Set<String> barMetrics = {
    "營收","EPS","殖利率","現金股利","股票股利",
  };

  @override
  State<FinancialChart> createState() => _FinancialChartState();
}

class _FinancialChartState extends State<FinancialChart> {

  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 單位差太多、混在同一張圖會被壓扁看不出來的指標：
  // 只在「跟別的指標混在一起」時才排除，單獨選它自己還是會畫。
  // 總覽的本益比、獲利的 EPS 改用右側獨立座標軸處理，不用再排除。
  static const Map<String, Set<String>> _chartExcludedMetrics = {
    "體質": {"股東權益"},
    "股利": {"除權息日", "現金股利發放日", "股票股利發放日"},
  };

  // 日期欄位本來就畫不出線，不管有沒有跟別的指標混在一起，
  // 永遠不放進圖表（只留在表格）。
  static const Set<String> _nonChartableMetrics = {
    "除權息日",
    "現金股利發放日",
    "股票股利發放日",
  };

  List<String> get metrics {
    final raw = widget.metrics
        .where((m) => !_nonChartableMetrics.contains(m))
        .toList();

    if (raw.length <= 1) return raw;

    final excluded = _chartExcludedMetrics[category] ?? const {};
    final filtered = raw.where((m) => !excluded.contains(m)).toList();

    return filtered.isEmpty ? raw : filtered;
  }
  String get category => widget.category;
  FinancialData get financial => widget.financial;
  Stock get stock => widget.stock;
  FinancialChartType? get chartType => widget.chartType;
  int? get selectedIndex => widget.selectedIndex;
  List<double?>? get priceValues => widget.priceValues;

  /// 總覽的本益比、獲利頁的 EPS，單位跟其他百分比指標差太多，
  /// 改用右側獨立座標軸畫成長條圖，跟折線分開，不會互相壓縮。
  static const Map<String, String> _barAxisMetric = {
    "總覽": "本益比",
    "獲利": "EPS",
  };

  List<String> get lineMetrics {
    final bar = _barAxisMetric[category];
    if (bar != null && metrics.contains(bar)) {
      return metrics.where((m) => m != bar).toList();
    }
    return metrics;
  }

  String? get barMetric {
    final bar = _barAxisMetric[category];
    if (bar != null && metrics.contains(bar)) {
      return bar;
    }
    return null;
  }

  List<FinancialQuarter> get _allQuarterData => financial.quarter;

  static const int _recentQuarterLimit = 20;

  bool get _isWindowedCategory =>
      category == "現金流" || category == "股利";

  /// 現金流／股利這兩頁圖表只顯示最近幾季，其他頁面維持全部。
  List<FinancialQuarter> get quarterData {
    final full = _allQuarterData;
    if (_isWindowedCategory && full.length > _recentQuarterLimit) {
      return full.sublist(full.length - _recentQuarterLimit);
    }
    return full;
  }

  /// selectedIndex 是對照完整的 financial.quarter（跟表格一致），
  /// 圖表資料如果被裁切過，畫十字線時要扣掉這個 offset 才會對齊。
  int get _indexOffset {
    final full = _allQuarterData;
    if (_isWindowedCategory && full.length > _recentQuarterLimit) {
      return full.length - _recentQuarterLimit;
    }
    return 0;
  }

  List<FinancialMonth> get monthData => financial.month;

  List<double?> getMetricValues(String metric) {
    switch (metric) {

      case "營收":
        return monthData.map((e) => e.revenue).toList();

      case "MoM":
        return monthData.map((e) => e.mom).toList();

      case "YoY":
        return monthData.map((e) => e.yoy).toList();

      case "EPS":
        return quarterData.map((e) => e.eps).toList();

      case "ROE":
        return quarterData.map((e) => e.roe).toList();

      case "ROA":
        return quarterData.map((e) => e.roa).toList();

      case "毛利率":
        return quarterData.map((e) => e.grossMargin).toList();

      case "營益率":
        return quarterData.map((e) => e.operatingMargin).toList();

      case "淨利率":
        return quarterData.map((e) => e.netMargin).toList();

      case "負債比":
        return quarterData.map((e) => e.debtRatio).toList();

      case "流動比":
        return quarterData.map((e) => e.currentRatio).toList();

      case "速動比":
        return quarterData.map((e) => e.quickRatio).toList();

      case "股東權益":
        return quarterData.map((e) => e.equity).toList();

      case "營業現金流":
        return quarterData.map((e) => e.operatingCashFlow).toList();

      case "自由現金流":
        return quarterData.map((e) => e.freeCashFlow).toList();

      case "資本支出":
        return quarterData.map((e) => e.investingCashFlow).toList();
      case "本益比":
        return quarterData.map((e)=>e.pe ?? 0).toList();
      case "股價淨值比":
        return quarterData.map((e)=>e.pb ?? 0).toList();
      case "殖利率":
        return quarterData.map((e) => e.dividendYield).toList();

      case "現金股利":
        return quarterData.map((e) => e.cashDividend).toList();

      case "股票股利":
        return quarterData.map((e) => e.stockDividend).toList();

      default:
        return [];
    }
  }

  String metricName(String metric) => metric;

  Color metricColor(String metric) {
    switch (metric) {
      case "營收":
        return Colors.blue;
      case "EPS":
        return Colors.orange;
      case "ROE":
        return Colors.green;
      case "ROA":
        return Colors.teal;
      case "毛利率":
        return Colors.purple;
      case "營益率":
        return Colors.deepOrange;
      case "淨利率":
        return Colors.red;
      default:
        return FinancialChart.colors[
            metrics.indexOf(metric) % FinancialChart.colors.length];
    }
  }

  String _unitFor(String metric) {
    switch (metric) {

      case "營收":
      case "股東權益":
      case "營業現金流":
      case "自由現金流":
      case "資本支出":
        return "億元";

      case "EPS":
      case "現金股利":
      case "股票股利":
        return "元";

      case "MoM":
      case "YoY":
      case "ROE":
      case "ROA":
      case "毛利率":
      case "營益率":
      case "淨利率":
      case "殖利率":
        return "%";

      case "負債比":
      case "流動比":
      case "速動比":
        return "倍";

      case "本益比":
      case "股價淨值比":
        return "倍";

      default:
        return "";
    }
  }

  String _formatMetricValue(String metric, double v) {
    final u = _unitFor(metric);
    if (u == "億元") return "${(v / 100000000).toStringAsFixed(2)}億";
    if (u == "%") return "${v.toStringAsFixed(2)}%";
    return v.toStringAsFixed(2);
  }

  String get unit {

    if (metrics.isEmpty) return "";

    final units = metrics.map(_unitFor).where((u) => u.isNotEmpty).toSet();

    if (units.isEmpty) return "";

    return units.join(" / ");
  }

  bool get canUseBarChart {
    if (metrics.length != 1) return false;
    return FinancialChart.barMetrics.contains(metrics.first);
  }

  FinancialChartType get currentChartType {
    if (chartType != null) {
      if (chartType == FinancialChartType.bar && !canUseBarChart) {
        return FinancialChartType.line;
      }
      return chartType!;
    }
    return canUseBarChart ? FinancialChartType.bar : FinancialChartType.line;
  }

  List<FlSpot> buildSpots(String metric) {
    final values = getMetricValues(metric);

    final spots = <FlSpot>[];

    for (int i = 0; i < values.length; i++) {
      final value = values[i];

      if (value == null) continue;

      spots.add(
        FlSpot(
          i.toDouble(),
          value,
        ),
      );
    }

    return spots;
  }

  LineChartBarData buildLine(
    String metric,
    int index, {
    int? highlightIndex,
  }) {
    final color = metricColor(metric);

    return LineChartBarData(
      spots: buildSpots(metric),
      color: color,
      isCurved: false,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, i) {
          final selected = highlightIndex != null && i == highlightIndex;
          return FlDotCirclePainter(
            radius: selected ? 6 : 3,
            color: color,
            strokeWidth: selected ? 2 : 0,
            strokeColor: Colors.white,
          );
        },
      ),
    );
  }

  List<LineChartBarData> buildLines({int? highlightIndex}) {
    return metrics.asMap().entries.map(
      (e) {
        return buildLine(
          e.value,
          e.key,
          highlightIndex: highlightIndex,
        );
      },
    ).toList();
  }

  List<double> collectYValues(
    List<LineChartBarData> lines,
  ) {
    return lines
        .expand((e) => e.spots)
        .map((e) => e.y)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return _buildCustomPainterCard(context);
  }

  Widget _buildRevenueCard(BuildContext context) {
    final lines = buildLines();
    final allValues = collectYValues(lines);

    final double min = allValues.isEmpty
        ? 0
        : allValues.reduce((a, b) => a < b ? a : b);

    final double max = allValues.isEmpty
        ? 1
        : allValues.reduce((a, b) => a > b ? a : b);

    final double padding =
        max == min ? 1 : (max - min) * 0.1;

    final isRevenue = category == "營收";

    if (isRevenue && monthData.isEmpty) {
      return const Center(
        child: Text("尚無月營收資料"),
      );
    }

    if (!isRevenue && quarterData.isEmpty) {
      return const Center(
        child: Text("尚無季財報資料"),
      );
    }

    final labels = isRevenue
        ? monthData.map((e)=>"${e.year}/${e.month.toString().padLeft(2,"0")}").toList()
        : quarterData.map((e) => "${e.year}Q${e.quarter}").toList();

    final interval =
        labels.length > 40 ? 6 : labels.length > 20 ? 3 : 1;

    // 營收改成緊密排列的長條圖，其他類別維持原本寬度
    final double pointWidth = isRevenue ? 26 : 42;

    // 營收最高點（畫「最高」標記用）
    int? peakIndex;
    if (isRevenue) {
      double? peakValue;
      final revenueValues = getMetricValues("營收");
      for (int i = 0; i < revenueValues.length; i++) {
        final v = revenueValues[i];
        if (v == null) continue;
        if (peakValue == null || v > peakValue) {
          peakValue = v;
          peakIndex = i;
        }
      }
    }

    // 價格折線（如果有傳進來）
    List<FlSpot>? priceSpots;
    double priceMin = 0;
    double priceMax = 1;

    if (priceValues != null) {
      final spots = <FlSpot>[];
      for (int i = 0; i < priceValues!.length; i++) {
        final v = priceValues![i];
        if (v == null) continue;
        spots.add(FlSpot(i.toDouble(), v));
      }
      if (spots.isNotEmpty) {
        priceSpots = spots;
        final vals = spots.map((e) => e.y).toList();
        priceMin = vals.reduce((a, b) => a < b ? a : b);
        priceMax = vals.reduce((a, b) => a > b ? a : b);
        final p = priceMax == priceMin ? 1 : (priceMax - priceMin) * 0.15;
        priceMin -= p;
        priceMax += p;
      }
    }

    final int? chartIndex =
        selectedIndex == null ? null : selectedIndex! - _indexOffset;

    // 選中資料點的資訊框（取代 fl_chart 內建 tooltip——
    // 內建 tooltip 會跟外層手動的點擊手勢互相干擾，卡住不消失）。
    Widget? selectedInfoBox;
    if (chartIndex != null &&
        chartIndex >= 0 &&
        chartIndex < labels.length) {

      final parts = <String>[];

      for (final m in metrics) {
        final vals = getMetricValues(m);
        if (chartIndex >= vals.length) continue;
        final v = vals[chartIndex];
        if (v == null) continue;
        parts.add("${metricName(m)} ${_formatMetricValue(m, v)}");
      }

      if (parts.isNotEmpty) {
        selectedInfoBox = Positioned(
          left: 4,
          top: 4,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: Text(
                "${labels[chartIndex]}  ${parts.join('   ')}",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        );
      }
    }

    final chartContent = LayoutBuilder(
      builder: (context, constraints) {

        final chartHeight = constraints.maxHeight;

        void handleTapX(double dx) {
          if (widget.onSelectIndex == null) return;
          if (currentChartType == FinancialChartType.bar) return;
          final index = (dx / pointWidth).floor().clamp(0, labels.length - 1);
          widget.onSelectIndex!(index + _indexOffset);
        }

        return GestureDetector(
          onTapDown: (details) => handleTapX(details.localPosition.dx),
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(
                constraints.maxWidth,
                labels.length * pointWidth,
              ),
              height: chartHeight,
              child: Stack(
                children: [

                  currentChartType == FinancialChartType.line
                      ? _buildLineChart(min, max, padding, labels, interval, isRevenue, chartIndex)
                      : _buildBarChart(min, max, padding, labels, interval, isRevenue, chartIndex, peakIndex),

                  if (priceSpots != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: LineChart(
                          LineChartData(
                            minY: priceMin,
                            maxY: priceMax,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            lineTouchData: const LineTouchData(enabled: false),
                            titlesData: FlTitlesData(
                              show: true,
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 50,
                                  getTitlesWidget: (value, meta) => Text(
                                    value.toStringAsFixed(0),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: priceSpots,
                                color: Colors.orange,
                                barWidth: 2,
                                isCurved: false,
                                dotData: const FlDotData(show: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (selectedInfoBox != null) selectedInfoBox,

                  if (isRevenue && peakIndex != null)
                    Positioned(
                      left: peakIndex * pointWidth + pointWidth / 2 - 14,
                      top: 4,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: const Text(
                            "最高",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ),
                    ),

                ],
              ),
            ),
          ),
        );
      },
    );

    final legend = Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        ...List.generate(
          metrics.length,
          (i) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: metricColor(metrics[i]),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                metricName(metrics[i]),
                style: TextStyle(
                  color: null,
                ),
              ),
            ],
          ),
        ),
        if (priceSpots != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 14, height: 2, color: Colors.orange),
              const SizedBox(width: 6),
              Text(
                "股價",
                style: TextStyle(
                  color: null,
                ),
              ),
            ],
          ),
      ],
    );

    return Card(
      margin: const EdgeInsets.all(12),
      color: null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "單位：$unit",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                ),
              ),
            ),

            const SizedBox(height: 6),

            Expanded(child: chartContent),

            const SizedBox(height: 8),

            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isRevenue
                        ? "圖表顯示 ${monthData.first.year}/${monthData.first.month.toString().padLeft(2,'0')} ～ ${monthData.last.year}/${monthData.last.month.toString().padLeft(2,'0')}，"
                          "共 ${monthData.length} 個月資料"
                          "${peakIndex != null ? "，最高為 ${labels[peakIndex]}（${_formatMetricValue("營收", getMetricValues("營收")[peakIndex]!)}）" : ""}"
                        : "圖表顯示 ${quarterData.first.year}Q${quarterData.first.quarter} ～ ${quarterData.last.year}Q${quarterData.last.quarter}，共 ${quarterData.length} 季資料",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            legend,
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(
    double min,
    double max,
    double padding,
    List<String> labels,
    int interval,
    bool isRevenue,
    int? chartIndex,
  ) {
    final lines = buildLines(highlightIndex: chartIndex);

    final showCrosshair =
        chartIndex != null && chartIndex >= 0 && chartIndex < labels.length;

    return LineChart(
      LineChartData(
        minY: min - padding,
        maxY: max + padding,

        borderData: FlBorderData(
          show: true,
          border: null,
        ),

        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.grey.shade300,
            strokeWidth: 1,
          ),
        ),

        lineTouchData: const LineTouchData(enabled: false),

        // 用 fl_chart 原生座標系統畫十字線，保證跟資料點對齊
        // （不用自己算像素位置，之前手動算的會跟座標軸留白錯開）。
        extraLinesData: showCrosshair
            ? ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: chartIndex.toDouble(),
                    color: Colors.grey,
                    strokeWidth: 1,
                  ),
                ],
              )
            : const ExtraLinesData(),

        titlesData: FlTitlesData(

          topTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
            ),
          ),

          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                String text;
                switch (metrics.first) {
                  case "營收":
                  case "股東權益":
                  case "營業現金流":
                  case "自由現金流":
                  case "資本支出":
                    text =
                        "${(value / 100000000).toStringAsFixed(0)}億";
                    break;
                  case "EPS":
                    text = value.toStringAsFixed(1);
                    break;
                  default:
                    text = "${value.toStringAsFixed(1)}%";
                }
                return Text(
                  text,
                  style: TextStyle(
                    fontSize: 11,
                    color: null,
                  ),
                );
              },
            ),
          ),

          rightTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
              reservedSize: 50,
            ),
          ),

          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: interval.toDouble(),

              getTitlesWidget:
                  (value, meta) {

                final index = value.toInt();

                if (index < 0 ||
                    index >= labels.length) {
                  return const SizedBox();
                }

                if (index % interval != 0) {
                  return const SizedBox();
                }

                return Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 10,
                    color: null,
                  ),
                );
              },
            ),
          ),
        ),

        lineBarsData: lines,
      ),
    );
  }

  Widget _buildBarChart(
    double min,
    double max,
    double padding,
    List<String> labels,
    int interval,
    bool isRevenue,
    int? chartIndex,
    int? peakIndex,
  ) {
    assert(metrics.length == 1, "柱狀圖一次只能顯示一個指標");

    final vals = getMetricValues(metrics.first);
    final barWidth = isRevenue ? 14.0 : 16.0;

    return BarChart(
      BarChartData(
        minY: min - padding,
        maxY: max + padding,
        // handleBuiltInTouches: false 讓 fl_chart 不要自己畫任何
        // tooltip／指示器（那個會跟外層手動點擊卡在一起顯示不消失），
        // 但 touchCallback 還是能正確收到點擊了哪一根柱子。
        barTouchData: BarTouchData(
          handleBuiltInTouches: false,
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            if (widget.onSelectIndex == null) return;
            final index = response?.spot?.touchedBarGroupIndex;
            if (index != null) {
              widget.onSelectIndex!(index + _indexOffset);
            }
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: null,
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.grey.shade300,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                final text = isRevenue
                    ? "${(value / 100000000).toStringAsFixed(1)}億"
                    : value.toStringAsFixed(1);
                return Text(
                  text,
                  style: TextStyle(
                    fontSize: 10,
                    color: null,
                  ),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
              reservedSize: 50,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: interval.toDouble(),
              getTitlesWidget: (value, meta) {
                final index=value.toInt();
                if(index<0||index>=labels.length||index%interval!=0){return const SizedBox();}
                return Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 10,
                    color: null,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(labels.length, (i) {
          final v = (i < vals.length ? vals[i] : null) ?? 0;
          final selected = chartIndex == i;

          Color color = metricColor(metrics.first)
              .withOpacity(isRevenue ? 0.85 : 1);

          if (selected) color = metricColor(metrics.first);

          return BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: v,
              color: color,
              width: barWidth,
              borderRadius: BorderRadius.zero,
            )
          ]);
        }),
      ),
    );
  }

  // =====================================================
  // 非營收頁：改用跟三大法人一樣的 CustomPainter 架構，
  // 座標軸固定不會隨橫向捲動消失。
  // =====================================================

  int _visibleCount = 20;
  int _startIndex = -1;

  double _lastScale = 1.0;
  double _dragDx = 0;
  double _lastFocalX = 0;

  Widget _buildCustomPainterCard(BuildContext context) {

    final isRevenue = category == "營收";

    if (isRevenue ? monthData.isEmpty : quarterData.isEmpty) {
      return Center(
        child: Text(isRevenue ? "尚無月營收資料" : "尚無季財報資料"),
      );
    }

    final labels = isRevenue
        ? monthData
            .map((e) => "${e.year}/${e.month.toString().padLeft(2, '0')}")
            .toList()
        : quarterData.map((e) => "${e.year}Q${e.quarter}").toList();

    // 營收頁只有一個指標，畫成長條、用左軸（不是右軸），
    // 其他頁維持原本折線 + 可選的右軸長條（本益比/EPS）邏輯。
    final lMetrics = isRevenue ? <String>[] : lineMetrics;
    final bMetric = isRevenue ? null : barMetric;

    final leftBarValues = isRevenue ? getMetricValues("營收") : null;
    final leftBarColor = isRevenue ? metricColor("營收") : Colors.transparent;

    final lineSeries = <String, List<double?>>{
      for (final m in lMetrics) m: getMetricValues(m),
    };

    final lineColors = <String, Color>{
      for (final m in lMetrics) m: metricColor(m),
    };

    final barValues =
        bMetric != null ? getMetricValues(bMetric) : null;

    final barColor =
        bMetric != null ? metricColor(bMetric) : Colors.transparent;

    final int? chartIndex =
        selectedIndex == null ? null : selectedIndex! - _indexOffset;

    final effectiveVisibleCount =
        _visibleCount.clamp(8, labels.length);

    final chart = LayoutBuilder(
      builder: (context, constraints) {

        final chartWidth = constraints.maxWidth;

        void handleTapX(double dx) {

          if (widget.onSelectIndex == null) return;

          final begin = _startIndex < 0
              ? (labels.length - effectiveVisibleCount)
                  .clamp(0, labels.length)
              : _startIndex;

          // 一定要跟 _FinancialLinePainter 用同一套留白/寬度算法，
          // 不然點擊座標換算出來的 index 會跟畫面上實際的點對不上
          // （chartWidth 是整個元件寬度，畫圖時用的是扣掉左右留白
          // 後的 chartRect.width，兩者不一樣）。
          final scale = ResponsiveChart.scaleFor(chartWidth);
          final leftPadding = 46.0 * scale;
          final rightAxisWidth = (bMetric != null ? 46.0 : 8.0) * scale;
          final plotWidth = chartWidth - leftPadding - rightAxisWidth - 4;

          final adjustedDx = dx - leftPadding;

          if (adjustedDx < 0 || plotWidth <= 0) return;

          final unit = plotWidth / effectiveVisibleCount;

          final index =
              (begin + (adjustedDx / unit).floor())
                  .clamp(0, labels.length - 1);

          widget.onSelectIndex!(index + _indexOffset);
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

                  if (_startIndex < 0) {
                    _startIndex =
                        (labels.length - effectiveVisibleCount)
                            .clamp(0, labels.length);
                  }

                  final move = (_dragDx / unit).round();

                  _startIndex -= move;

                  final maxStart =
                      (labels.length - effectiveVisibleCount)
                          .clamp(0, labels.length);

                  _startIndex = _startIndex.clamp(0, maxStart);

                });

                _dragDx = 0;
              }

              return;
            }

            final delta = details.scale - _lastScale;

            if (delta.abs() > 0.05) {

              setState(() {

                if (_startIndex < 0) {
                  _startIndex =
                      (labels.length - _visibleCount)
                          .clamp(0, labels.length);
                }

                final ratio = _lastFocalX / chartWidth;

                final centerIndex =
                    _startIndex + (_visibleCount * ratio).round();

                if (delta > 0) {
                  _visibleCount -= 2;
                } else {
                  _visibleCount += 2;
                }

                _visibleCount = _visibleCount.clamp(8, labels.length);

                _startIndex =
                    centerIndex - (_visibleCount * ratio).round();

                _startIndex = _startIndex.clamp(
                  0,
                  (labels.length - _visibleCount).clamp(0, labels.length),
                );

              });

              _lastScale = details.scale;
            }
          },

          child: CustomPaint(
            painter: _FinancialLinePainter(
              labels: labels,
              leftInYi: isRevenue ||
                  (lMetrics.isNotEmpty &&
                      lMetrics.every((m) => _unitFor(m) == "億元")),
              barInYi: bMetric != null && _unitFor(bMetric) == "億元",
              lineSeries: lineSeries,
              lineColors: lineColors,
              barValues: barValues,
              barColor: barColor,
              leftBarValues: leftBarValues,
              leftBarColor: leftBarColor,
              visibleCount: effectiveVisibleCount,
              startIndex: _startIndex,
              selectedIndex: chartIndex,
            ),
            size: Size.infinite,
          ),

        );
      },
    );

    final legend = Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        if (isRevenue)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                color: leftBarColor.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              const Text("營收"),
            ],
          ),
        ...lMetrics.map(
          (m) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 3,
                color: lineColors[m],
              ),
              const SizedBox(width: 6),
              Text(metricName(m)),
            ],
          ),
        ),
        if (bMetric != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                color: barColor.withOpacity(0.4),
              ),
              const SizedBox(width: 6),
              Text("$bMetric（右軸）"),
            ],
          ),
      ],
    );

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "單位：$unit",
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                ),
              ),
            ),

            const SizedBox(height: 6),

            Expanded(child: chart),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isRevenue
                        ? "圖表顯示 ${monthData.first.year}/${monthData.first.month.toString().padLeft(2, '0')} "
                            "～ ${monthData.last.year}/${monthData.last.month.toString().padLeft(2, '0')}，"
                            "共 ${monthData.length} 個月資料"
                        : "圖表顯示 ${quarterData.first.year}Q${quarterData.first.quarter} "
                            "～ ${quarterData.last.year}Q${quarterData.last.quarter}，"
                            "共 ${quarterData.length} 季資料",
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            legend,

          ],
        ),
      ),
    );
  }
}

class _FinancialLinePainter extends CustomPainter {
  const _FinancialLinePainter({
    required this.labels,
    required this.lineSeries,
    required this.lineColors,
    required this.barValues,
    required this.barColor,
    required this.visibleCount,
    required this.startIndex,
    required this.selectedIndex,
    this.leftInYi = false,
    this.barInYi = false,
    this.leftBarValues,
    this.leftBarColor = Colors.blue,
  });

  final List<String> labels;
  final Map<String, List<double?>> lineSeries;
  final Map<String, Color> lineColors;
  final List<double?>? barValues;
  final Color barColor;
  final int visibleCount;
  final int startIndex;

  // 左軸／右軸的值是不是「億元」單位，是的話軸上文字要除以
  // 一億再顯示，不然會印出一長串原始數字看不懂。
  final bool leftInYi;
  final bool barInYi;
  final int? selectedIndex;

  // 營收頁專用：單一指標畫成長條、用左軸（不是右軸），
  // 跟 lineSeries（折線）、barValues（右軸長條）都是分開的。
  final List<double?>? leftBarValues;
  final Color leftBarColor;

  @override
  void paint(Canvas canvas, Size size) {

    if (labels.isEmpty) return;

    final maxStart =
        (labels.length - visibleCount).clamp(0, labels.length);

    final begin = startIndex < 0
        ? maxStart
        : startIndex.clamp(0, maxStart);

    final end = (begin + visibleCount).clamp(0, labels.length);

    final visibleLabels = labels.sublist(begin, end);

    if (visibleLabels.isEmpty) return;

    final hasBar = barValues != null;

    // 留白、字體、線寬都依實際畫布寬度換算，不再寫死，
    // 平板上（畫布較寬）會等比例放大，比例才不會跑掉。
    final scale = ResponsiveChart.scaleFor(size.width);

    final leftPadding = 46.0 * scale;
    final rightAxisWidth = (hasBar ? 46.0 : 8.0) * scale;
    final bottomAxisHeight = 20.0 * scale;
    final topPadding = 8.0 * scale;
    final axisFontSize = 10.0 * scale;
    final lineStrokeWidth = 2.0 * scale;
    final dotRadius = 2.0 * scale;
    final selectedDotRadius = 5.0 * scale;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightAxisWidth - 4,
      size.height - topPadding - bottomAxisHeight,
    );

    //-------------------------
    // 左軸範圍（折線）
    //-------------------------

    double? lineMin;
    double? lineMax;

    // 順便蒐集所有可視範圍內的數值，等一下用來判斷資料分散程度。
    final allVisibleValues = <double>[];

    for (final values in lineSeries.values) {
      for (int i = begin; i < end; i++) {
        if (i >= values.length) continue;
        final v = values[i];
        if (v == null) continue;
        lineMin = lineMin == null ? v : (v < lineMin ? v : lineMin);
        lineMax = lineMax == null ? v : (v > lineMax ? v : lineMax);
        allVisibleValues.add(v);
      }
    }

    if (leftBarValues != null) {
      for (int i = begin; i < end; i++) {
        if (i >= leftBarValues!.length) continue;
        final v = leftBarValues![i];
        if (v == null) continue;
        lineMin = lineMin == null ? v : (v < lineMin ? v : lineMin);
        lineMax = lineMax == null ? v : (v > lineMax ? v : lineMax);
        allVisibleValues.add(v);
      }
      // 長條圖底線通常從 0 開始看比較直覺（除非資料本身有負值）
      lineMin = lineMin == null ? 0 : (lineMin > 0 ? 0 : lineMin);
    }

    lineMin ??= 0;
    lineMax ??= 1;

    final lineRawRange = lineMax - lineMin;
    final linePad = lineRawRange == 0 ? 1.0 : lineRawRange * 0.15;

    final lChartMin = lineMin - linePad;
    final lChartMax = lineMax + linePad;
    final lRange = lChartMax - lChartMin;

    double lineToY(double v) {
      return chartRect.top +
          (lChartMax - v) / lRange * chartRect.height;
    }

    //-------------------------
    // 右軸範圍（長條，從 0 開始）
    //-------------------------

    double barMax = 0;

    if (hasBar) {
      for (int i = begin; i < end; i++) {
        if (i >= barValues!.length) continue;
        final v = barValues![i];
        if (v == null) continue;
        if (v > barMax) barMax = v;
      }
    }

    final bChartMax = barMax == 0 ? 1.0 : barMax * 1.15;

    double barToY(double v) {
      return chartRect.bottom - (v / bChartMax) * chartRect.height;
    }

    final step = chartRect.width / visibleLabels.length;

    //-------------------------
    // 網格 + 左軸文字
    //-------------------------

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    // 資料分散程度＝全距 ÷ 資料典型量級（用中位數的絕對值代表）。
    // 比值越大，代表資料裡有少數幾筆極端值把範圍撐得很開、大部分
    // 資料反而擠在一起，這種情況格線切多一點，才能在擁擠的那段
    // 裡多幾條參考線，比較容易讀出實際數字；資料本身分佈平均的話
    // 沒有這個問題，格線少一點、畫面不用那麼擠。
    final gridCount = _gridCountFor(
      allVisibleValues,
      chartRect.height,
      axisFontSize,
    );

    for (int i = 0; i <= gridCount; i++) {
      final v = lChartMax - (lRange / gridCount) * i;
      final y = lineToY(v);

      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );

      final displayV = leftInYi ? v / 100000000 : v;

      final tp = TextPainter(
        text: TextSpan(
          text: displayV.toStringAsFixed(1),
          style: TextStyle(fontSize: axisFontSize, color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    //-------------------------
    // 右軸文字（長條）
    //-------------------------

    if (hasBar) {
      for (int i = 0; i <= gridCount; i++) {
        final v = bChartMax - (bChartMax / gridCount) * i;
        final y = barToY(v);

        final displayV = barInYi ? v / 100000000 : v;

        final tp = TextPainter(
          text: TextSpan(
            text: displayV.toStringAsFixed(1),
            style: TextStyle(fontSize: axisFontSize, color: barColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        tp.paint(canvas, Offset(chartRect.right + 4, y - tp.height / 2));
      }
    }

    //-------------------------
    // 長條（畫在折線後面當背景）
    //-------------------------

    if (hasBar) {

      const spacing = 4.0;
      final barWidth = (step - spacing).clamp(4.0, 20.0);

      for (int i = 0; i < visibleLabels.length; i++) {

        final idx = begin + i;
        if (idx >= barValues!.length) continue;

        final v = barValues![idx];
        if (v == null) continue;

        final x = chartRect.left + i * step + step / 2;
        final top = barToY(v);

        canvas.drawRect(
          Rect.fromLTRB(
            x - barWidth / 2,
            top,
            x + barWidth / 2,
            chartRect.bottom,
          ),
          Paint()..color = barColor.withOpacity(0.35),
        );
      }
    }

    //-------------------------
    // 左軸長條（營收頁專用）
    //-------------------------

    if (leftBarValues != null) {

      const spacing = 3.0;
      final barWidth = (step - spacing).clamp(3.0, 26.0);

      for (int i = 0; i < visibleLabels.length; i++) {

        final idx = begin + i;
        if (idx >= leftBarValues!.length) continue;

        final v = leftBarValues![idx];
        if (v == null) continue;

        final x = chartRect.left + i * step + step / 2;
        final top = lineToY(v);
        final baseline = lineToY(0);
        final isSelected = selectedIndex == idx;

        canvas.drawRect(
          Rect.fromLTRB(
            x - barWidth / 2,
            top,
            x + barWidth / 2,
            baseline,
          ),
          Paint()
            ..color = isSelected
                ? leftBarColor
                : leftBarColor.withOpacity(0.75),
        );
      }
    }

    //-------------------------
    // 折線 + 資料點
    //-------------------------

    for (final entry in lineSeries.entries) {

      final values = entry.value;
      final color = lineColors[entry.key] ?? Colors.blue;

      final path = Path();
      bool started = false;

      for (int i = 0; i < visibleLabels.length; i++) {

        final idx = begin + i;
        if (idx >= values.length) continue;

        final v = values[idx];
        if (v == null) continue;

        final x = chartRect.left + i * step + step / 2;
        final y = lineToY(v);

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

      for (int i = 0; i < visibleLabels.length; i++) {

        final idx = begin + i;
        if (idx >= values.length) continue;

        final v = values[idx];
        if (v == null) continue;

        final x = chartRect.left + i * step + step / 2;
        final y = lineToY(v);
        final isSelected = selectedIndex == idx;

        canvas.drawCircle(
          Offset(x, y),
          isSelected ? selectedDotRadius : dotRadius,
          Paint()..color = color,
        );

        if (isSelected) {
          canvas.drawCircle(
            Offset(x, y),
            selectedDotRadius,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = lineStrokeWidth,
          );
        }
      }
    }

    //-------------------------
    // 十字線
    //-------------------------

    if (selectedIndex != null &&
        selectedIndex! >= begin &&
        selectedIndex! < end) {

      final x = chartRect.left +
          (selectedIndex! - begin) * step +
          step / 2;

      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 1,
      );
    }

    //-------------------------
    // X 軸日期
    //-------------------------

    final labelStep =
        (visibleLabels.length / 6).round().clamp(1, visibleLabels.length);

    for (int i = 0; i < visibleLabels.length; i += labelStep) {

      final x = chartRect.left + i * step + step / 2;

      final tp = TextPainter(
        text: TextSpan(
          text: visibleLabels[i],
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

  /// 依資料分散程度算出格線數量：全距 ÷ 中位數絕對值 當分散指標，
  /// 比值越大代表資料裡有少數極端值把範圍撐開，格線切多一點；
  /// 資料本身分佈平均就用少一點格線，避免畫面太擠。
  ///
  /// 但不能只看分散程度，還要看畫面實際塞不塞得下——不然分散
  /// 程度算出來要 12 條，圖表高度卻只夠放 6 條，文字會整個疊在
  /// 一起看不清楚（比原本沒調整還糟）。所以最後還要用「畫面高度
  /// ÷ 每條格線至少需要的高度」夾住一次，取兩者較小值。
  int _gridCountFor(
    List<double> values,
    double availableHeight,
    double fontSize,
  ) {

    int wanted;

    if (values.length < 3) {
      wanted = 5;
    } else {

      final sorted = [...values]..sort();
      final median = sorted[sorted.length ~/ 2].abs();
      final range = sorted.last - sorted.first;

      if (median == 0 || range == 0) {
        wanted = 5;
      } else {

        final dispersion = range / median;

        if (dispersion > 8) {
          wanted = 12;
        } else if (dispersion > 4) {
          wanted = 9;
        } else if (dispersion > 1.5) {
          wanted = 7;
        } else {
          wanted = 5;
        }
      }
    }

    // 每條格線的文字大約需要 fontSize 的 2.2 倍高度才不會跟
    // 上下相鄰的文字疊在一起（文字本身高度 + 上下留一點間距）。
    final minHeightPerLine = fontSize * 2.2;

    final maxFittable =
        (availableHeight / minHeightPerLine).floor().clamp(3, 20);

    return wanted > maxFittable ? maxFittable : wanted;
  }

  @override
  bool shouldRepaint(covariant _FinancialLinePainter oldDelegate) {
    // lineSeries/barValues 每次都是新物件（List/Map 用 != 比較永遠算
    // 不一樣，比了也沒用），改比較真正決定畫面長相的幾個純量欄位：
    // 資料筆數沒變、可視範圍沒變、選中點沒變，就不用重畫。
    return oldDelegate.labels.length != labels.length ||
        oldDelegate.visibleCount != visibleCount ||
        oldDelegate.startIndex != startIndex ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.leftInYi != leftInYi ||
        oldDelegate.barInYi != barInYi;
  }
}