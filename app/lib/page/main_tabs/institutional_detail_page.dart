import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/market_institutional_day.dart';
import '../../api/market_api.dart';
import 'institutional_interactive_chart.dart';

class InstitutionalDetailPage extends StatefulWidget {
  const InstitutionalDetailPage({super.key});

  @override
  State<InstitutionalDetailPage> createState() =>
      _InstitutionalDetailPageState();
}

class _InstitutionalDetailPageState extends State<InstitutionalDetailPage> {

  bool loading = true;
  String? error;
  List<MarketInstitutionalDay> days = [];

  int? selectedIndex;

  final _fmt = NumberFormat('#,##0');
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> load() async {

    try {

      final data = await MarketApi.getInstitutionalHistory(limit: 120);

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
        title: const Text("大盤三大法人買賣超"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : Column(
                  children: [

                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 16,
                        children: const [
                          _Legend(
                            color: InstitutionalInteractiveChart.foreignColor,
                            label: "外資",
                          ),
                          _Legend(
                            color: InstitutionalInteractiveChart.trustColor,
                            label: "投信",
                          ),
                          _Legend(
                            color: InstitutionalInteractiveChart.dealerColor,
                            label: "自營商（自行+避險）",
                          ),
                        ],
                      ),
                    ),

                    SizedBox(
                      height: 280,
                      child: InstitutionalInteractiveChart(
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
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: days.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade300),
                        itemBuilder: (context, i) {

                          // 表格由新到舊排列，換算成原始陣列的 index
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

  Widget _row(MarketInstitutionalDay d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${d.date.year}/${d.date.month}/${d.date.day}",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _cell("外資", d.foreignNet),
              _cell("投信", d.trustNet),
              _cell("自營商", d.dealerNet),
            ],
          ),
        ],
      ),
    );
  }

  /// 紅漲綠跌，跟 App 其他地方的漲跌配色一致（正紅負綠），
  /// 不用另外記三大法人各自的分類專屬顏色。
  Widget _cell(String label, double value) {

    final color = value > 0
        ? Colors.red
        : value < 0
            ? Colors.green
            : Colors.black;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text(
            "${value >= 0 ? '+' : ''}${_fmt.format(value / 100000000)}億",
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
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