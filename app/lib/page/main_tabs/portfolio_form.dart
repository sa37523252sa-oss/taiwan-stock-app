import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api.dart';
import '../../models/stock.dart';
import '../../models/backtest_result.dart';
import '../../models/backtest_condition.dart';
import '../../models/portfolio_stock_input.dart';
import '../../api/backtest_api.dart';
import 'asset_curve_chart.dart';
import 'condition_group_editor.dart';

class PortfolioForm extends StatefulWidget {
  const PortfolioForm({super.key});

  @override
  State<PortfolioForm> createState() => _PortfolioFormState();
}

class _PortfolioFormState extends State<PortfolioForm> {

  Timer? _debounce;
  final TextEditingController searchController = TextEditingController();
  List<Stock> searchResults = [];

  final List<PortfolioStockInput> stocks = [];

  bool sharedStrategy = true;

  List<List<BacktestCondition>> sharedBuyGroups = [
    [BacktestCondition.maCross(fast: 5, slow: 20, direction: "above")],
  ];
  List<List<BacktestCondition>> sharedSellGroups = [
    [BacktestCondition.maCross(fast: 5, slow: 20, direction: "below")],
  ];

  DateTime startDate = DateTime.now().subtract(const Duration(days: 365 * 3));
  DateTime endDate = DateTime.now();

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

  void addStock(Stock s) {

    if (stocks.any((e) => e.code == s.code)) return;

    setState(() {
      stocks.add(PortfolioStockInput(
        code: s.code,
        name: s.name,
        weight: null,
        buyConditionGroups: [
          [BacktestCondition.maCross(fast: 5, slow: 20, direction: "above")],
        ],
        sellConditionGroups: [
          [BacktestCondition.maCross(fast: 5, slow: 20, direction: "below")],
        ],
      ));
      searchResults = [];
      searchController.clear();
    });
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

    if (stocks.isEmpty) {
      setState(() => error = "請至少選擇一支股票");
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

      // 統一策略模式：送出時把共用的買賣條件複製給每支股票，
      // 每支股票自己原本各別設定的條件（如果有）不會被送出。
      final effectiveStocks = sharedStrategy
          ? stocks.map((s) {
              return PortfolioStockInput(
                code: s.code,
                name: s.name,
                weight: s.weight,
                buyConditionGroups: sharedBuyGroups,
                sellConditionGroups: sharedSellGroups,
              );
            }).toList()
          : stocks;

      final res = await BacktestApi.runPortfolioBacktest(
        stocks: effectiveStocks,
        startDate: startDate,
        endDate: endDate,
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
    return Column(
      children: [

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showInfoDialog(context),
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text("多股票組合規則說明"),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                const Text("股票組合", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),

                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: "輸入股票代號或名稱，新增到組合",
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
                          onTap: () => addStock(s),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 10),

                if (stocks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      "尚未加入任何股票",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  )
                else
                  ...stocks.asMap().entries.map((entry) {
                    return _stockRow(entry.key, entry.value);
                  }),

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

                const Text("策略設定", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text("統一策略"),
                      selected: sharedStrategy,
                      onSelected: (_) => setState(() => sharedStrategy = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("每支股票各自設定"),
                      selected: !sharedStrategy,
                      onSelected: (_) => setState(() => sharedStrategy = false),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                if (sharedStrategy) ...[

                  ConditionGroupEditor(
                    title: "買進條件（套用到所有股票）",
                    groups: sharedBuyGroups,
                    defaultDirection: "above",
                    onAddCondition: (g, c) =>
                        setState(() => sharedBuyGroups[g].add(c)),
                    onRemoveCondition: (g, ci) =>
                        setState(() => sharedBuyGroups[g].removeAt(ci)),
                    onAddGroup: () => setState(() => sharedBuyGroups.add([])),
                    onRemoveGroup: (g) =>
                        setState(() => sharedBuyGroups.removeAt(g)),
                  ),

                  const SizedBox(height: 12),

                  ConditionGroupEditor(
                    title: "賣出條件（套用到所有股票）",
                    groups: sharedSellGroups,
                    defaultDirection: "below",
                    onAddCondition: (g, c) =>
                        setState(() => sharedSellGroups[g].add(c)),
                    onRemoveCondition: (g, ci) =>
                        setState(() => sharedSellGroups[g].removeAt(ci)),
                    onAddGroup: () => setState(() => sharedSellGroups.add([])),
                    onRemoveGroup: (g) =>
                        setState(() => sharedSellGroups.removeAt(g)),
                  ),

                ] else
                  ...stocks.map((s) => _perStockStrategyEditor(s)),

                const SizedBox(height: 16),

                const Text("初始資金（總額）", style: TextStyle(fontWeight: FontWeight.bold)),
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
        ),

        if (result != null && result!.error == null) ...[
          const SizedBox(height: 16),
          _resultSection(),
        ],

      ],
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("多股票組合規則說明"),
        content: const Text(
          "• 權重：手動設定的股票用你填的比例，沒填的股票平分"
          "「剩餘額度」（不是平分全部100%）\n\n"
          "• 如果手動設定的權重加總沒有滿100%、又沒有股票留給"
          "系統自動分配，剩下的比例會當作保留現金、不投入\n\n"
          "• 每支股票用各自分配到的資金獨立操作，某支股票賣出"
          "空出來的錢會留在該股票自己的現金部位，不會拿去加碼"
          "其他股票（不做再平衡）\n\n"
          "• 統一策略：所有股票共用同一組買賣條件；"
          "個別設定：每支股票可以有完全不同的條件",
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("關閉"),
          ),
        ],
      ),
    );
  }

  Widget _stockRow(int index, PortfolioStockInput s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text("${s.code} ${s.name}",
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              key: ValueKey("weight_${s.code}"),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: "自動分配",
                suffixText: "%",
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v);
                setState(() => s.weight = v.isEmpty ? null : parsed);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => stocks.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _perStockStrategyEditor(PortfolioStockInput s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              "${s.code} ${s.name}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            ConditionGroupEditor(
              title: "買進條件",
              groups: s.buyConditionGroups,
              defaultDirection: "above",
              onAddCondition: (g, c) =>
                  setState(() => s.buyConditionGroups[g].add(c)),
              onRemoveCondition: (g, ci) =>
                  setState(() => s.buyConditionGroups[g].removeAt(ci)),
              onAddGroup: () => setState(() => s.buyConditionGroups.add([])),
              onRemoveGroup: (g) =>
                  setState(() => s.buyConditionGroups.removeAt(g)),
            ),

            const SizedBox(height: 8),

            ConditionGroupEditor(
              title: "賣出條件",
              groups: s.sellConditionGroups,
              defaultDirection: "below",
              onAddCondition: (g, c) =>
                  setState(() => s.sellConditionGroups[g].add(c)),
              onRemoveCondition: (g, ci) =>
                  setState(() => s.sellConditionGroups[g].removeAt(ci)),
              onAddGroup: () => setState(() => s.sellConditionGroups.add([])),
              onRemoveGroup: (g) =>
                  setState(() => s.sellConditionGroups.removeAt(g)),
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
          "組合回測結果",
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
                const Text("組合資產曲線", style: TextStyle(fontWeight: FontWeight.bold)),
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

        if (result!.weights != null && result!.perStock != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("各股票實際分配權重與績效",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...result!.weights!.entries.map((entry) {
                    final stockMetrics = result!.perStock![entry.key];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(entry.key,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          Expanded(
                            child: Text("權重 ${entry.value.toStringAsFixed(1)}%"),
                          ),
                          if (stockMetrics != null)
                            Expanded(
                              child: Text(
                                "${stockMetrics.totalReturn >= 0 ? '+' : ''}"
                                "${stockMetrics.totalReturn}%",
                                style: TextStyle(
                                  color: stockMetrics.totalReturn >= 0
                                      ? Colors.red
                                      : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],

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
          if (t.code != null)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(t.code!, style: const TextStyle(fontSize: 11)),
            ),
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