import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api.dart';
import '../../models/stock.dart';
import '../../models/backtest_result.dart';
import '../../models/backtest_condition.dart';
import '../../api/backtest_api.dart';
import 'asset_curve_chart.dart';
import 'condition_group_editor.dart';
import 'portfolio_form.dart';
import 'screener_form.dart';
import 'dca_form.dart';

enum _BacktestMode { singleStock, portfolio, screener, dca }

class BacktestTab extends StatefulWidget {
  const BacktestTab({super.key});

  @override
  State<BacktestTab> createState() => _BacktestTabState();
}

class _BacktestTabState extends State<BacktestTab> {

  _BacktestMode mode = _BacktestMode.singleStock;

  Timer? _debounce;
  final TextEditingController searchController = TextEditingController();
  List<Stock> searchResults = [];
  Stock? selectedStock;

  DateTime startDate = DateTime.now().subtract(const Duration(days: 365 * 3));
  DateTime endDate = DateTime.now();

  List<List<BacktestCondition>> buyConditionGroups = [
    [BacktestCondition.maCross(fast: 5, slow: 20, direction: "above")],
  ];
  List<List<BacktestCondition>> sellConditionGroups = [
    [BacktestCondition.maCross(fast: 5, slow: 20, direction: "below")],
  ];

  final TextEditingController capitalController =
      TextEditingController(text: "1000000");

  bool running = false;
  String? error;
  BacktestResult? result;

  final _fmt = NumberFormat('#,##0');

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    capitalController.dispose();
    super.dispose();
  }

  Future<void> searchStock(String keyword) async {

    keyword = keyword.trim();

    if (keyword.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    try {
      final res = await ApiService.searchStock(keyword);
      if (!mounted) return;
      setState(() => searchResults = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => searchResults = []);
    }
  }

  Future<void> pickDate(bool isStart) async {

    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        startDate = picked;
      } else {
        endDate = picked;
      }
    });
  }

  Future<void> runBacktest() async {

    if (selectedStock == null) {
      setState(() => error = "請先選擇股票");
      return;
    }

    final hasBuyCondition =
        buyConditionGroups.any((group) => group.isNotEmpty);
    final hasSellCondition =
        sellConditionGroups.any((group) => group.isNotEmpty);

    if (!hasBuyCondition || !hasSellCondition) {
      setState(() => error = "買進、賣出條件都至少要有一個");
      return;
    }

    final capital = double.tryParse(capitalController.text);

    if (capital == null || capital <= 0) {
      setState(() => error = "請輸入正確的初始資金");
      return;
    }

    setState(() {
      running = true;
      error = null;
      result = null;
    });

    try {

      final res = await BacktestApi.runBacktest(
        code: selectedStock!.code,
        startDate: startDate,
        endDate: endDate,
        buyConditionGroups: buyConditionGroups,
        sellConditionGroups: sellConditionGroups,
        initialCapital: capital,
      );

      if (!mounted) return;

      setState(() {
        result = res;
        running = false;
        if (res.error != null) error = res.error;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() {
        running = false;
        error = "$e";
      });

    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [

          _modeSelector(),

          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.receipt_long, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  "每筆買賣都已計入手續費與交易稅",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          if (mode == _BacktestMode.singleStock) ...[
            _singleStockForm(),
            if (result != null && result!.error == null) ...[
              const SizedBox(height: 16),
              _resultSection(),
            ],
          ] else if (mode == _BacktestMode.portfolio)
            const PortfolioForm()
          else if (mode == _BacktestMode.screener)
            const ScreenerForm()
          else if (mode == _BacktestMode.dca)
            const DcaForm()
          else
            _placeholderCard(_modeLabel(mode)),

        ],
      ),
    );
  }

  String _modeLabel(_BacktestMode m) {
    switch (m) {
      case _BacktestMode.singleStock:
        return "單一股票";
      case _BacktestMode.portfolio:
        return "多股票組合";
      case _BacktestMode.screener:
        return "選股策略";
      case _BacktestMode.dca:
        return "定期投資";
    }
  }

  Widget _modeSelector() {
    return Row(
      children: _BacktestMode.values.map((m) {

        final selected = mode == m;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => setState(() => mode = m),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                ),
                child: Text(
                  _modeLabel(m),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _placeholderCard(String label) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            "$label 開發中",
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _singleStockForm() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Text("股票", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),

            if (selectedStock != null)
              InkWell(
                onTap: () => setState(() => selectedStock = null),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        "${selectedStock!.code} ${selectedStock!.name}",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Icon(Icons.close, size: 18),
                    ],
                  ),
                ),
              )
            else ...[
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  hintText: "輸入股票代號或名稱",
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => searchStock(v),
                  );
                },
              ),
              if (searchResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  margin: const EdgeInsets.only(top: 4),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: searchResults.length,
                    itemBuilder: (context, i) {
                      final s = searchResults[i];
                      return ListTile(
                        dense: true,
                        title: Text("${s.code} ${s.name}"),
                        onTap: () {
                          setState(() {
                            selectedStock = s;
                            searchResults = [];
                            searchController.clear();
                          });
                        },
                      );
                    },
                  ),
                ),
            ],

            const SizedBox(height: 16),

            const Text("回測期間", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pickDate(true),
                    child: Text(
                      "${startDate.year}/${startDate.month}/${startDate.day}",
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text("～"),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pickDate(false),
                    child: Text(
                      "${endDate.year}/${endDate.month}/${endDate.day}",
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            ConditionGroupEditor(
              title: "買進條件",
              groups: buyConditionGroups,
              defaultDirection: "above",
              onAddCondition: (groupIndex, c) => setState(
                  () => buyConditionGroups[groupIndex].add(c)),
              onRemoveCondition: (groupIndex, condIndex) => setState(
                  () => buyConditionGroups[groupIndex].removeAt(condIndex)),
              onAddGroup: () => setState(() => buyConditionGroups.add([])),
              onRemoveGroup: (groupIndex) =>
                  setState(() => buyConditionGroups.removeAt(groupIndex)),
            ),

            const SizedBox(height: 16),

            ConditionGroupEditor(
              title: "賣出條件",
              groups: sellConditionGroups,
              defaultDirection: "below",
              onAddCondition: (groupIndex, c) => setState(
                  () => sellConditionGroups[groupIndex].add(c)),
              onRemoveCondition: (groupIndex, condIndex) => setState(
                  () => sellConditionGroups[groupIndex].removeAt(condIndex)),
              onAddGroup: () => setState(() => sellConditionGroups.add([])),
              onRemoveGroup: (groupIndex) =>
                  setState(() => sellConditionGroups.removeAt(groupIndex)),
            ),

            const SizedBox(height: 16),

            const Text("初始資金", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: capitalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: "元",
              ),
            ),

            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: running ? null : runBacktest,
                child: running
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("開始回測"),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _resultSection() {

    final m = result!.metrics!;
    final capital = double.tryParse(capitalController.text) ?? 1000000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const Text(
          "回測結果",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),

        if (result!.totalDividend != null && result!.totalDividend! > 0) ...[
          const SizedBox(height: 4),
          Text(
            "總報酬率已包含股利收入",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],

        const SizedBox(height: 8),

        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _metricCard("總報酬率", "${m.totalReturn >= 0 ? '+' : ''}${m.totalReturn}%",
                m.totalReturn >= 0 ? Colors.red : Colors.green),
            _metricCard("年化報酬率", "${m.cagr >= 0 ? '+' : ''}${m.cagr}%",
                m.cagr >= 0 ? Colors.red : Colors.green),
            _metricCard("最大回撤", "${m.maxDrawdown}%", Colors.green),
            _metricCard("Sharpe", "${m.sharpe}", Colors.black),
            _metricCard("勝率", "${m.winRate}%", Colors.black),
            _metricCard("交易次數", "${m.tradeCount}", Colors.black),
            if (result!.totalDividend != null)
              _metricCard("股利收入", _fmt.format(result!.totalDividend), Colors.red),
          ],
        ),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("資產曲線", style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  height: 220,
                  child: AssetCurveChart(
                    points: result!.assetCurve,
                    initialCapital: capital,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "交易紀錄（共 ${result!.trades.length} 筆）",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                ...result!.trades.map((t) => _tradeRow(t)),
              ],
            ),
          ),
        ),

      ],
    );
  }

  Widget _metricCard(String label, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _tradeRow(BacktestTrade t) {

    final isBuy = t.action == "buy";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isBuy ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isBuy ? "買入" : "賣出",
              style: TextStyle(
                fontSize: 11,
                color: isBuy ? Colors.red : Colors.green,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text("${t.date.year}/${t.date.month}/${t.date.day}"),
          const SizedBox(width: 8),
          Text("\$${t.price.toStringAsFixed(1)}"),
          const Spacer(),
          if (t.profit != null)
            Text(
              "${t.profit! >= 0 ? '+' : ''}${_fmt.format(t.profit)}",
              style: TextStyle(
                color: t.profit! >= 0 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}