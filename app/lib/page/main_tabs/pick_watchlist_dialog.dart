import 'package:flutter/material.dart';

import '../../models/watchlist.dart';
import '../../api/watchlist_api.dart';

/// 在股票詳情頁點「+」時用的對話框：已經知道股票代號，
/// 只需要選要加到哪個自選股清單。
/// 回傳 true 代表成功加入。
Future<bool?> showPickWatchlistDialog(
  BuildContext context, {
  required String code,
  required String name,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _PickWatchlistDialog(code: code, name: name),
  );
}

class _PickWatchlistDialog extends StatefulWidget {
  const _PickWatchlistDialog({
    required this.code,
    required this.name,
  });

  final String code;
  final String name;

  @override
  State<_PickWatchlistDialog> createState() => _PickWatchlistDialogState();
}

class _PickWatchlistDialogState extends State<_PickWatchlistDialog> {

  bool loading = true;
  String? error;
  List<WatchlistInfo> watchlists = [];
  int? selectedId;

  bool saving = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {

    try {

      final data = await WatchlistApi.getWatchlists();

      if (!mounted) return;

      setState(() {
        watchlists = data;
        selectedId = data.isNotEmpty ? data.first.id : null;
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

  Future<void> confirm() async {

    if (selectedId == null) return;

    setState(() {
      saving = true;
      error = null;
    });

    try {

      await WatchlistApi.addStock(selectedId!, widget.code);

      if (!mounted) return;

      Navigator.pop(context, true);

    } catch (e) {

      if (!mounted) return;

      setState(() {
        saving = false;
        error = "加入失敗：$e";
      });

    }
  }

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      title: Text("加入自選股：${widget.code} ${widget.name}"),
      content: loading
          ? const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...watchlists.map((w) {
                  return RadioListTile<int>(
                    title: Text(w.name),
                    subtitle: Text("目前 ${w.stockCount} 檔"),
                    value: w.id,
                    groupValue: selectedId,
                    onChanged: (value) {
                      setState(() => selectedId = value);
                    },
                  );
                }),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("取消"),
        ),
        FilledButton(
          onPressed: (loading || saving) ? null : confirm,
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("加入"),
        ),
      ],
    );
  }
}