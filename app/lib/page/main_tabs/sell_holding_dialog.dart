import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/holding.dart';
import '../../api/holdings_api.dart';

final _numFmt = NumberFormat('#,##0');

/// 賣出對話框。回傳 true 代表有成功執行賣出，呼叫端應該重新整理。
Future<bool?> showSellHoldingDialog(BuildContext context, Holding h) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _SellHoldingDialog(holding: h),
  );
}

class _SellHoldingDialog extends StatefulWidget {
  const _SellHoldingDialog({required this.holding});

  final Holding holding;

  @override
  State<_SellHoldingDialog> createState() => _SellHoldingDialogState();
}

class _SellHoldingDialogState extends State<_SellHoldingDialog> {

  late final TextEditingController sharesController;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    // 預設賣出全部股數
    sharesController =
        TextEditingController(text: "${widget.holding.shares}");
  }

  @override
  void dispose() {
    sharesController.dispose();
    super.dispose();
  }

  /// 按比例從整批市值/成本/損益算出「賣這幾股」的預覽數字。
  /// 因為手續費／稅都是線性比例（股數 × 價格 × 費率），
  /// 按股數比例縮放是準確的，不用重打一次後端。
  Map<String, double>? _preview(int sellShares) {

    final h = widget.holding;

    if (h.marketValue == null || h.shares == 0) return null;

    final ratio = sellShares / h.shares;

    final proceeds = h.marketValue! * ratio;
    final costPortion = h.cost * ratio;
    final profit = proceeds - costPortion;

    return {
      "proceeds": proceeds,
      "cost": costPortion,
      "profit": profit,
    };
  }

  Future<void> confirmSell() async {

    final h = widget.holding;
    final sellShares = int.tryParse(sharesController.text);

    if (sellShares == null || sellShares <= 0) {
      setState(() => error = "請輸入正確的股數");
      return;
    }

    if (sellShares > h.shares) {
      setState(() => error = "賣出股數不能超過持有股數（${h.shares} 股）");
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {

      if (sellShares == h.shares) {
        // 全部賣出，直接刪除這筆庫存
        await HoldingsApi.deleteHolding(h.id);
      } else {
        // 部分賣出，剩餘股數的均價不變（賣掉的部分不影響剩下
        // 股票的原始成本單價）
        await HoldingsApi.updateHolding(
          id: h.id,
          avgPrice: h.avgPrice,
          shares: h.shares - sellShares,
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);

    } catch (e) {

      if (!mounted) return;

      setState(() {
        saving = false;
        error = "賣出失敗：$e";
      });

    }
  }

  @override
  Widget build(BuildContext context) {

    final h = widget.holding;
    final sellShares = int.tryParse(sharesController.text) ?? 0;
    final preview = _preview(sellShares);

    return AlertDialog(
      title: Text("賣出 ${h.code} ${h.companyName ?? ''}"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Text(
            "目前持有 ${h.shares} 股，現價 "
            "${h.currentPrice == null ? '--' : _numFmt.format(h.currentPrice)}",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: sharesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "賣出股數",
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          if (preview != null) ...[
            _previewRow("預估收入", preview["proceeds"]!),
            _previewRow("成本", preview["cost"]!),
            _previewRow(
              "損益",
              preview["profit"]!,
              color: preview["profit"]! >= 0 ? Colors.red : Colors.green,
              showSign: true,
            ),
          ],

          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],

        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("取消"),
        ),
        FilledButton(
          onPressed: saving ? null : confirmSell,
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("確認賣出"),
        ),
      ],
    );
  }

  Widget _previewRow(
    String label,
    double value, {
    Color? color,
    bool showSign = false,
  }) {

    final sign = showSign && value >= 0 ? "+" : "";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(
            "$sign\$${_numFmt.format(value)}",
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}