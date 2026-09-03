import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/holding.dart';
import '../../api/holdings_api.dart';
import '../../screens/stock_page.dart';
import 'add_holding_page.dart';
import 'fee_discount_dialog.dart';
import 'sell_holding_dialog.dart';

final _numFmt = NumberFormat('#,##0');
final _decimalFmt = NumberFormat('#,##0.00');

class HoldingsTab extends StatefulWidget {
  const HoldingsTab({super.key});

  @override
  State<HoldingsTab> createState() => _HoldingsTabState();
}

class _HoldingsTabState extends State<HoldingsTab> {

  bool loading = true;
  String? error;
  List<Holding> holdings = [];

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

      final data = await HoldingsApi.getHoldings();

      if (!mounted) return;

      setState(() {
        holdings = data;
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

  Future<void> openAddPage() async {

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AddHoldingPage()),
    );

    if (result == true) load();
  }

  Future<void> openSettings() async {

    final result = await showFeeDiscountDialog(context);

    if (result == true) load();
  }

  void showCalcExplanation() {

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("成本／市值計算方式"),
        content: const Text(
          "成本＝股數 × 均價 + 買入手續費\n"
          "市值＝股數 × 現價 − 賣出手續費 − 交易稅"
          "（先扣掉現在賣出會產生的費用跟稅，"
          "市值才是真正能拿到手的淨值）\n"
          "損益＝市值 − 成本\n"
          "\n"
          "手續費＝成交金額 × 0.1425%"
          "（買賣都要收，若有設定折扣則按折數計算，"
          "例如 6 折＝0.0855%）\n"
          "交易稅＝成交金額 × 稅率"
          "（僅賣出時收，一般股票 0.3%、ETF 0.1%）",
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

  Future<void> confirmDelete(Holding h) async {

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("刪除庫存"),
        content: Text("確定要刪除 ${h.code} ${h.companyName ?? ''} 嗎？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("刪除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await HoldingsApi.deleteHolding(h.id);
      load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("刪除失敗：$e")),
      );
    }
  }

  String _fmt(double? v, {int decimals = 0}) {
    if (v == null) return "--";
    return decimals == 0 ? _numFmt.format(v) : _decimalFmt.format(v);
  }

  Future<void> openSell(Holding h) async {

    final result = await showSellHoldingDialog(context, h);

    if (result == true) load();
  }

  @override
  Widget build(BuildContext context) {

    final totalCost =
        holdings.fold<double>(0, (sum, h) => sum + h.cost);

    final totalMarketValue = holdings.fold<double>(
      0,
      (sum, h) => sum + (h.marketValue ?? 0),
    );

    final totalProfitLoss = totalMarketValue - totalCost;

    return Scaffold(

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [

                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "庫存總覽",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.info_outline,
                                        ),
                                        tooltip: "成本／市值計算方式說明",
                                        onPressed: showCalcExplanation,
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.settings_outlined,
                                        ),
                                        tooltip: "手續費折扣設定",
                                        onPressed: openSettings,
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              _summaryRow("總成本", "\$${_fmt(totalCost)}"),
                              _summaryRow(
                                "總市值",
                                "\$${_fmt(totalMarketValue)}",
                              ),
                              _summaryRow(
                                "總損益",
                                "${totalProfitLoss >= 0 ? '+' : ''}"
                                    "\$${_fmt(totalProfitLoss)}",
                                color: totalProfitLoss > 0
                                    ? Colors.red
                                    : totalProfitLoss < 0
                                        ? Colors.green
                                        : null,
                              ),

                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (holdings.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              "還沒有庫存股，點右下角新增",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ...holdings.map((h) => _holdingCard(h)),

                    ],
                  ),
                ),

      floatingActionButton: FloatingActionButton(
        onPressed: openAddPage,
        child: const Icon(Icons.add),
      ),

    );
  }

  Widget _summaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _holdingCard(Holding h) {

    final plColor = (h.profitLoss ?? 0) > 0
        ? Colors.red
        : (h.profitLoss ?? 0) < 0
            ? Colors.green
            : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StockPage(
                stockCode: h.code,
                stockName: h.companyName ?? h.code,
              ),
            ),
          );
        },
        onLongPress: () => confirmDelete(h),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${h.code} ${h.companyName ?? ''}",
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        h.profitLoss == null
                            ? "--"
                            : "${h.profitLoss! >= 0 ? '+' : ''}"
                                "\$${_fmt(h.profitLoss)}"
                                "（${_fmt(h.profitLossPct, decimals: 1)}%）",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: plColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.sell_outlined, size: 20),
                        tooltip: "賣出",
                        visualDensity: VisualDensity.compact,
                        onPressed: () => openSell(h),
                      ),
                    ],
                  ),
                ],
              ),

              if (h.totalReturn != null &&
                  h.dividendTotal != null &&
                  h.dividendTotal! > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "含息總報酬 ${h.totalReturn! >= 0 ? '+' : ''}"
                        "\$${_fmt(h.totalReturn)}"
                        "（${_fmt(h.totalReturnPct, decimals: 1)}%）",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),

              const SizedBox(height: 8),

              Row(
                children: [
                  _miniStat("股數", "${h.shares}"),
                  _miniStat("均價", _fmt(h.avgPrice, decimals: 2)),
                  _miniStat("現價", _fmt(h.currentPrice, decimals: 2)),
                  _miniStat("成本", _fmt(h.cost)),
                  _miniStat("市值", _fmt(h.marketValue)),
                ],
              ),

              const SizedBox(height: 6),

              Row(
                children: [
                  _miniStat("股利", "\$${_fmt(h.dividendTotal ?? 0)}"),
                  if (h.dividendCount != null && h.dividendCount! > 0)
                    _miniStat("領息次數", "${h.dividendCount}"),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}