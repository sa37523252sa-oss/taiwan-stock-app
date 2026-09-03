import 'package:flutter/material.dart';

import '../../models/market_index.dart';
import '../../models/market_institutional_day.dart';
import '../../models/market_margin_day.dart';
import '../../api/market_api.dart';
import '../technical/technical_tab.dart';
import 'market_detail_page.dart';
import 'institutional_mini_chart.dart';
import 'institutional_detail_page.dart';
import 'margin_mini_chart.dart';
import 'margin_detail_page.dart';

class MarketTab extends StatefulWidget {
  const MarketTab({super.key});

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> {

  bool loading = true;
  String? error;

  List<MarketIndexInfo> indexes = [];
  String selectedCode = "TAIEX";

  List<MarketInstitutionalDay> institutionalDays = [];
  List<MarketMarginDay> marginDays = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {

    setState(() {
      loading = true;
      error = null;
    });

    try {

      final results = await Future.wait([
        MarketApi.getOverview(),
        MarketApi.getInstitutionalHistory(limit: 15),
        MarketApi.getMarginHistory(limit: 15),
      ]);

      if (!mounted) return;

      setState(() {
        indexes = results[0] as List<MarketIndexInfo>;
        institutionalDays = results[1] as List<MarketInstitutionalDay>;
        marginDays = results[2] as List<MarketMarginDay>;
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

  String get selectedName {
    final match = indexes.where((e) => e.code == selectedCode);
    return match.isEmpty ? selectedCode : match.first.name;
  }

  void openKlineDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarketDetailPage(
          code: selectedCode,
          name: selectedName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(child: Text(error!));
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [

          Row(
            children: indexes.map((idx) {

              final selected = idx.code == selectedCode;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _indexCard(idx, selected),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          _sectionCard(
            title: "$selectedName K線",
            trailing: IconButton(
              icon: const Icon(Icons.fullscreen),
              tooltip: "放大檢視",
              onPressed: openKlineDetail,
            ),
            child: SizedBox(
              height: 480,
              child: TechnicalTab(
                key: ValueKey(selectedCode),
                code: selectedCode,
                useMarketKline: true,
              ),
            ),
          ),

          const SizedBox(height: 12),

          _sectionCard(
            title: "大盤三大法人買賣超",
            trailing: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InstitutionalDetailPage(),
                  ),
                );
              },
              child: const Text("查看更多"),
            ),
            child: SizedBox(
              height: 200,
              child: InstitutionalMiniChart(days: institutionalDays),
            ),
            footer: institutionalDays.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _institutionalMiniTable(institutionalDays),
                  ),
          ),

          const SizedBox(height: 12),

          _sectionCard(
            title: "大盤資券餘額",
            trailing: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MarginDetailPage(),
                  ),
                );
              },
              child: const Text("查看更多"),
            ),
            child: SizedBox(
              height: 200,
              child: MarginMiniChart(days: marginDays),
            ),
            footer: marginDays.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _marginMiniTable(marginDays),
                  ),
          ),

          const SizedBox(height: 20),

        ],
      ),
    );
  }

  /// 縮圖區塊的小表格，預設顯示最近約10筆（沿用 load() 裡已經
  /// 抓好的15筆資料，不用另外多打一次 API），由新到舊排列。
  Widget _institutionalMiniTable(List<MarketInstitutionalDay> days) {

    final recent = days.reversed.take(10).toList();

    Widget cell(String label, double value) {
      final color = value > 0
          ? Colors.red
          : value < 0
              ? Colors.green
              : Colors.black;
      return Expanded(
        child: Text(
          "$label ${value >= 0 ? '+' : ''}"
          "${(value / 100000000).toStringAsFixed(0)}億",
          style: TextStyle(fontSize: 14, color: color),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < recent.length; i++) ...[

          if (i > 0) Divider(height: 1, color: Colors.grey.shade200),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    "${recent[i].date.month}/${recent[i].date.day}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                cell("外資", recent[i].foreignNet),
                cell("投信", recent[i].trustNet),
                cell("自營", recent[i].dealerNet),
              ],
            ),
          ),

        ],
      ],
    );
  }

  Widget _marginMiniTable(List<MarketMarginDay> days) {

    final recent = days.reversed.take(10).toList();

    return Column(
      children: [
        for (int i = 0; i < recent.length; i++) ...[

          if (i > 0) Divider(height: 1, color: Colors.grey.shade200),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    "${recent[i].date.month}/${recent[i].date.day}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    "融資 ${(recent[i].marginMoneyTodayBalance / 100000000).toStringAsFixed(0)}億"
                    "（${(recent[i].marginMoneyChange / 100000000) >= 0 ? '+' : ''}"
                    "${(recent[i].marginMoneyChange / 100000000).toStringAsFixed(0)}）",
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    "融券 ${(recent[i].shortSharesTodayBalance / 1000).toStringAsFixed(0)}張"
                    "（${(recent[i].shortSharesChange / 1000) >= 0 ? '+' : ''}"
                    "${(recent[i].shortSharesChange / 1000).toStringAsFixed(0)}）",
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),

        ],
      ],
    );
  }


  Widget _sectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
    Widget? footer,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),

            child,

            if (footer != null) footer,

          ],
        ),
      ),
    );
  }

  Widget _indexCard(MarketIndexInfo idx, bool selected) {

    final change = idx.change;

    final color = change == null
        ? Colors.black
        : change > 0
            ? Colors.red
            : change < 0
                ? Colors.green
                : Colors.black;

    return GestureDetector(
      onTap: () {
        setState(() => selectedCode = idx.code);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              idx.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 4),

            Text(
              idx.price?.toStringAsFixed(2) ?? "--",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),

            const SizedBox(height: 2),

            Text(
              change == null
                  ? "--"
                  : "${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} "
                      "(${idx.changePct?.toStringAsFixed(2) ?? '--'}%)",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),

          ],
        ),
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