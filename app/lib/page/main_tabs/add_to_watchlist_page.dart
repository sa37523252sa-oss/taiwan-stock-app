import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../models/stock.dart';
import '../../models/watchlist.dart';
import '../../api/watchlist_api.dart';

class AddToWatchlistPage extends StatefulWidget {
  const AddToWatchlistPage({
    super.key,
    required this.watchlists,
    this.defaultWatchlistId,
  });

  final List<WatchlistInfo> watchlists;

  // 如果是從某個清單頁裡點「+」進來的，預設勾選那個清單
  final int? defaultWatchlistId;

  @override
  State<AddToWatchlistPage> createState() => _AddToWatchlistPageState();
}

class _AddToWatchlistPageState extends State<AddToWatchlistPage> {

  Timer? _debounce;
  final TextEditingController searchController = TextEditingController();
  List<Stock> searchResults = [];
  bool searching = false;

  Stock? selectedStock;
  int? selectedWatchlistId;

  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    selectedWatchlistId = widget.defaultWatchlistId ??
        (widget.watchlists.isNotEmpty ? widget.watchlists.first.id : null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> search(String keyword) async {

    keyword = keyword.trim();

    if (keyword.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => searching = true);

    try {

      final result = await ApiService.searchStock(keyword);

      if (!mounted) return;

      setState(() {
        searchResults = result;
        searching = false;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() {
        searchResults = [];
        searching = false;
      });

    }
  }

  Future<void> save() async {

    if (selectedStock == null || selectedWatchlistId == null) return;

    setState(() {
      saving = true;
      error = null;
    });

    try {

      await WatchlistApi.addStock(
        selectedWatchlistId!,
        selectedStock!.code,
      );

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

    return Scaffold(
      appBar: AppBar(
        title: const Text("加入自選股"),
      ),
      body: selectedStock == null
          ? _buildSearchStep()
          : _buildPickListStep(),
    );
  }

  Widget _buildSearchStep() {

    return Column(
      children: [

        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "輸入股票代號或名稱",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => search(value),
              );
            },
          ),
        ),

        if (searching)
          const Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: searchResults.length,
              itemBuilder: (context, index) {
                final stock = searchResults[index];
                return ListTile(
                  title: Text("${stock.code} ${stock.name}"),
                  subtitle: Text(stock.industry),
                  onTap: () {
                    setState(() => selectedStock = stock);
                  },
                );
              },
            ),
          ),

      ],
    );
  }

  Widget _buildPickListStep() {

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => selectedStock = null);
                },
              ),
              Text(
                "${selectedStock!.code} ${selectedStock!.name}",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          const Text(
            "加入哪個清單？",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),

          ...widget.watchlists.map((w) {
            return RadioListTile<int>(
              title: Text(w.name),
              subtitle: Text("目前 ${w.stockCount} 檔"),
              value: w.id,
              groupValue: selectedWatchlistId,
              onChanged: (value) {
                setState(() => selectedWatchlistId = value);
              },
            );
          }),

          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("加入"),
            ),
          ),

        ],
      ),
    );
  }
}