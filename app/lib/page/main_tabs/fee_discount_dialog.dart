import 'package:flutter/material.dart';

import '../../api/holdings_api.dart';

/// 手續費折扣設定對話框。回傳 true 代表有變更、呼叫端應該重新整理。
Future<bool?> showFeeDiscountDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => const _FeeDiscountDialog(),
  );
}

class _FeeDiscountDialog extends StatefulWidget {
  const _FeeDiscountDialog();

  @override
  State<_FeeDiscountDialog> createState() => _FeeDiscountDialogState();
}

class _FeeDiscountDialogState extends State<_FeeDiscountDialog> {

  final TextEditingController controller = TextEditingController();
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {

    try {

      final discount = await HoldingsApi.getFeeDiscount();

      if (!mounted) return;

      setState(() {
        if (discount != null) {
          controller.text = discount.toString();
        }
        loading = false;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() => loading = false);

    }
  }

  Future<void> save() async {

    final text = controller.text.trim();

    double? discount;

    if (text.isNotEmpty) {

      discount = double.tryParse(text);

      if (discount == null || discount <= 0 || discount > 10) {
        setState(() => error = "請輸入 0~10 之間的折數，例如 6 代表 6 折");
        return;
      }
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {

      await HoldingsApi.setFeeDiscount(discount);

      if (!mounted) return;

      Navigator.pop(context, true);

    } catch (e) {

      if (!mounted) return;

      setState(() {
        saving = false;
        error = "儲存失敗：$e";
      });

    }
  }

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      title: const Text("手續費折扣設定"),
      content: loading
          ? const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                const Text(
                  "輸入券商給你的折數（例如 6 代表 6 折）。"
                  "不輸入則以原價 0.1425% 計算。",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "折數（例如 6）",
                    border: OutlineInputBorder(),
                  ),
                ),

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
          onPressed: (loading || saving) ? null : save,
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("儲存"),
        ),
      ],
    );
  }
}