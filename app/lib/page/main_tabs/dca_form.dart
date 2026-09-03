import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api.dart';
import '../../models/stock.dart';
import '../../models/backtest_result.dart';
import '../../api/backtest_api.dart';
import 'asset_curve_chart.dart';

class DcaForm extends StatefulWidget {
  const DcaForm({super.key});

  @override
  State<DcaForm> createState() => _DcaFormState();
}

class _DcaFormState extends State<DcaForm> {

  Timer? _debounce;
  final TextEditingController searchController = TextEditingController();
  List<Stock> searchResults = [];
  Stock? selectedStock;

  DateTime startDate = DateTime.now().subtract(const Duration(days: 365 * 3));
  DateTime endDate = DateTime.now();

  final TextEditingController amountController =
      TextEditingController(text: "10000");

  int intervalMonths = 1;

  bool running = false;
  String? error;
  BacktestResult? result;

  final _fmt = NumberFormat('#,##0');
  final _fmtShares = NumberFormat('#,##0.####');

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    amountController.dispose();
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

    final amount = double.tryParse(amountController.text);

    if (amount == null || amount <= 0) {
      setState(() => error = "請輸入正確的每期投入金額");
      return;
    }

    setState(() {
      running = true;
      error = null;
      result = null;
    });

    try {

      final res = await BacktestApi.runDcaBacktest(
        code: selectedStock!.code,
        startDate: startDate,
        endDate: endDate,
        amountPerPeriod: amount,
        intervalMonths: intervalMonths,
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

                const Text("每期投入金額", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixText: "元",
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("每", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: intervalMonths,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text("1個月")),
                        DropdownMenuItem(value: 2, child: Text("2個月")),
                        DropdownMenuItem(value: 3, child: Text("3個月（每季）")),
                        DropdownMenuItem(value: 6, child: Text("6個月（半年）")),
                      ],
                      onChanged: (v) => setState(() => intervalMonths = v!),
                    ),
                    const SizedBox(width: 8),
                    const Text("扣款一次", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
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
              "固定週期投入固定金額，不管股價高低都買，允許買進零股，"
              "年化報酬率用考慮每筆錢實際投入時間的XIRR計算，"
              "不是單純的CAGR",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultSection() {

    final m = result!.metrics!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const Text(
          "定期定額回測結果",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),

        if (result!.totalInvested != null && result!.finalValue != null) ...[
          const SizedBox(height: 4),
          Text(
            "累積投入 ${_fmt.format(result!.totalInvested)}元 → "
                "${_fmt.format(result!.finalValue)}元",
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],

        if (result!.totalDividend != null && result!.totalDividend! > 0) ...[
          const SizedBox(height: 2),
          Text(
            "最終資產已包含股利收入",
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
            _metricCard("年化報酬率(XIRR)", "${m.cagr >= 0 ? '+' : ''}${m.cagr}%",
                m.cagr >= 0 ? Colors.red : Colors.green),
            _metricCard("最大回撤", "${m.maxDrawdown}%", Colors.green),
            _metricCard("Sharpe", "${m.sharpe}", Colors.black),
            _metricCard("扣款次數", "${m.tradeCount}", Colors.black),
            if (result!.totalShares != null)
              _metricCard("累積股數", _fmtShares.format(result!.totalShares), Colors.black),
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
                    initialCapital: result!.totalInvested ??
                        (double.tryParse(amountController.text) ?? 0),
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
                  "扣款紀錄（共 ${result!.trades.length} 筆）",
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
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _tradeRow(BacktestTrade t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              "買入",
              style: TextStyle(fontSize: 11, color: Colors.red),
            ),
          ),
          const SizedBox(width: 8),
          Text("${t.date.year}/${t.date.month}/${t.date.day}"),
          const SizedBox(width: 8),
          Text("\$${t.price.toStringAsFixed(1)}"),
          const Spacer(),
          Text(
            "${_fmtShares.format(t.shares)}股",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}