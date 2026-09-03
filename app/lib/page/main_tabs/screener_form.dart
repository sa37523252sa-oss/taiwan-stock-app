import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/backtest_result.dart';
import '../../models/backtest_condition.dart';
import '../../models/rank_field.dart';
import '../../api/backtest_api.dart';
import 'asset_curve_chart.dart';
import 'condition_group_editor.dart';

class ScreenerForm extends StatefulWidget {
  const ScreenerForm({super.key});

  @override
  State<ScreenerForm> createState() => _ScreenerFormState();
}

class _ScreenerFormState extends State<ScreenerForm> {

  // 選股策略是基本面/流通性導向，不提供技術指標（那個是給抓
  // 買賣時機用的，跟「定期審核成分股」的邏輯不搭）。
  static const _availableTypes = [
    AddConditionType.price,
    AddConditionType.liquidity,
    AddConditionType.fundamental,
    AddConditionType.custom,
  ];

  List<List<BacktestCondition>> screeningGroups = [
    [
      BacktestCondition.liquidityTradingValueAbove(value: 0.5, windowDays: 20),
      BacktestCondition.fundamentalAbove(field: "roe", value: 15),
    ],
  ];

  DateTime startDate = DateTime.now().subtract(const Duration(days: 365 * 3));
  DateTime endDate = DateTime.now();

  final TextEditingController rebalanceMonthsController =
      TextEditingController(text: "6");

  final TextEditingController maxStocksController = TextEditingController();

  List<RankField> rankFields = [RankField(field: "roe", direction: "desc")];

  final TextEditingController capitalController =
      TextEditingController(text: "1000000");

  bool running = false;
  String? error;
  BacktestResult? result;

  final _fmt = NumberFormat('#,##0');

  @override
  void dispose() {
    rebalanceMonthsController.dispose();
    maxStocksController.dispose();
    capitalController.dispose();
    super.dispose();
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

    final hasCondition = screeningGroups.any((group) => group.isNotEmpty);

    if (!hasCondition) {
      setState(() => error = "請至少設定一個篩選條件");
      return;
    }

    final rebalanceMonths = int.tryParse(rebalanceMonthsController.text);

    if (rebalanceMonths == null || rebalanceMonths <= 0) {
      setState(() => error = "請輸入正確的審核頻率（月數）");
      return;
    }

    final capital = double.tryParse(capitalController.text);

    if (capital == null || capital <= 0) {
      setState(() => error = "請輸入正確的初始資金");
      return;
    }

    final maxStocksText = maxStocksController.text.trim();
    final maxStocks = maxStocksText.isEmpty ? null : int.tryParse(maxStocksText);

    setState(() {
      running = true;
      error = null;
      result = null;
    });

    try {

      final res = await BacktestApi.runScreenerBacktest(
        screeningConditionGroups: screeningGroups,
        startDate: startDate,
        endDate: endDate,
        rebalanceMonths: rebalanceMonths,
        maxStocks: maxStocks,
        rankFields: maxStocks != null ? rankFields : null,
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

        _infoBanner(),

        const SizedBox(height: 12),

        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "建議先加一個「流通性」條件（例如成交額大於某個門檻）"
                          "當第一步篩選，先把冷門、量太少的股票排除，"
                          "避免候選股票過多、回測跑起來太慢",
                          style: TextStyle(
                              fontSize: 11, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                ConditionGroupEditor(
                  title: "篩選條件（全市場股票，符合就入選）",
                  groups: screeningGroups,
                  defaultDirection: "above",
                  availableTypes: _availableTypes,
                  onAddCondition: (g, c) =>
                      setState(() => screeningGroups[g].add(c)),
                  onRemoveCondition: (g, ci) =>
                      setState(() => screeningGroups[g].removeAt(ci)),
                  onAddGroup: () => setState(() => screeningGroups.add([])),
                  onRemoveGroup: (g) =>
                      setState(() => screeningGroups.removeAt(g)),
                ),

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

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("每", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: rebalanceMonthsController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text("個月審核一次成分股",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),

                const SizedBox(height: 16),

                const Text("符合條件的股票數量上限",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: maxStocksController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: "留空代表不限制數量",
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixText: "支",
                  ),
                ),

                if (maxStocksController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    "超過上限時，依下面欄位排名取前幾名（可加多個欄位，"
                    "前面優先，同分時比下一個）",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),

                  ...rankFields.asMap().entries.map((entry) {

                    final i = entry.key;
                    final rf = entry.value;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Text(
                                "再比",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: rf.field,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: RankFieldOption.options
                                  .map((f) => DropdownMenuItem(
                                      value: f.field, child: Text(f.label)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => rf.field = v!),
                            ),
                          ),
                          const SizedBox(width: 6),
                          DropdownButton<String>(
                            value: rf.direction,
                            items: const [
                              DropdownMenuItem(
                                  value: "desc", child: Text("高到低")),
                              DropdownMenuItem(
                                  value: "asc", child: Text("低到高")),
                            ],
                            onChanged: (v) =>
                                setState(() => rf.direction = v!),
                          ),
                          if (rankFields.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => rankFields.removeAt(i)),
                            ),
                        ],
                      ),
                    );
                  }),

                  TextButton.icon(
                    onPressed: () => setState(() => rankFields.add(
                        RankField(field: "pe", direction: "asc"))),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text("新增排名欄位"),
                  ),
                ],

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
        ),

        if (result != null && result!.error == null) ...[
          const SizedBox(height: 16),
          _resultSection(),
        ],

      ],
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              "從全市場股票中，定期審核篩出符合條件的股票，等權重"
              "換股，類似被動式ETF的邏輯",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
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
          "選股策略回測結果",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),

        if (result!.finalValue != null) ...[
          const SizedBox(height: 4),
          Text(
            "${_fmt.format(capital)}元 → ${_fmt.format(result!.finalValue)}元",
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],

        if (result!.totalDividend != null && result!.totalDividend! > 0) ...[
          const SizedBox(height: 2),
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
            if (result!.totalFee != null)
              _metricCard("總手續費", _fmt.format(result!.totalFee), Colors.black),
            if (result!.totalTax != null)
              _metricCard("總交易稅", _fmt.format(result!.totalTax), Colors.black),
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

        if (result!.selections != null && result!.selections!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("每次審核選出的成分股",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...result!.selections!.map((sel) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${sel.date.year}/${sel.date.month}/${sel.date.day}",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sel.codes.isEmpty ? "（沒有股票符合條件）" : sel.codes.join("、"),
                            style: TextStyle(
                              fontSize: 12,
                              color: sel.codes.isEmpty
                                  ? Colors.grey
                                  : Colors.black87,
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