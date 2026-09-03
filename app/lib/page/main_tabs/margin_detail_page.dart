import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/market_margin_day.dart';
import '../../api/market_api.dart';
import 'margin_interactive_chart.dart';

class MarginDetailPage extends StatefulWidget {
  const MarginDetailPage({super.key});

  @override
  State<MarginDetailPage> createState() => _MarginDetailPageState();
}

class _MarginDetailPageState extends State<MarginDetailPage> {

  bool loading = true;
  String? error;
  List<MarketMarginDay> days = [];

  int? selectedIndex;

  final _fmt = NumberFormat('#,##0');

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {

    try {

      final data = await MarketApi.getMarginHistory(limit: 120);

      if (!mounted) return;

      setState(() {
        days = data;
        loading = false;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() {
        error = "$e";
        loading = false;
      });

    }
  }

  void onSelectIndex(int? index) {
    setState(() => selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("大盤資券餘額"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : Column(
                  children: [

                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Wrap(
                        spacing: 16,
                        children: const [
                          _Legend(
                            color: MarginInteractiveChart.marginColor,
                            label: "融資餘額（左軸，億元）",
                          ),
                          _Legend(
                            color: MarginInteractiveChart.shortColor,
                            label: "融券餘額（右軸，張）",
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        "注意：融資是金額、融券是張數，兩者單位不同，"
                        "不能直接比較數字大小",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),

                    SizedBox(
                      height: 280,
                      child: MarginInteractiveChart(
                        days: days,
                        selectedIndex: selectedIndex,
                        onSelectIndex: onSelectIndex,
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        "單指拖曳橫移，雙指縮放，點擊圖表或下方列表可標記對照",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),

                    const Divider(height: 1),

                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: days.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade300),
                        itemBuilder: (context, i) {

                          final index = days.length - 1 - i;
                          final d = days[index];
                          final selected = selectedIndex == index;

                          return InkWell(
                            onTap: () => onSelectIndex(
                              selectedIndex == index ? null : index,
                            ),
                            child: Container(
                              color: selected
                                  ? Colors.blue.withOpacity(0.08)
                                  : null,
                              child: _row(d),
                            ),
                          );
                        },
                      ),
                    ),

                  ],
                ),
    );
  }

  Widget _row(MarketMarginDay d) {

    final marginChange = d.marginMoneyChange / 100000000;
    final shortChange = d.shortSharesChange / 1000;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              "${d.date.year}/${d.date.month}/${d.date.day}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("融資餘額", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(
                  "${_fmt.format(d.marginMoneyTodayBalance / 100000000)}億"
                  "（${marginChange >= 0 ? '+' : ''}${_fmt.format(marginChange)}）",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: MarginInteractiveChart.marginColor,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("融券餘額", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(
                  "${_fmt.format(d.shortSharesTodayBalance / 1000)}張"
                  "（${shortChange >= 0 ? '+' : ''}${_fmt.format(shortChange)}）",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: MarginInteractiveChart.shortColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}