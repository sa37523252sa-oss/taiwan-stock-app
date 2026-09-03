import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../models/stock.dart';
import '../../api/holdings_api.dart';

class AddHoldingPage extends StatefulWidget {
  const AddHoldingPage({super.key});

  @override
  State<AddHoldingPage> createState() => _AddHoldingPageState();
}

class _AddHoldingPageState extends State<AddHoldingPage> {

  Timer? _debounce;
  final TextEditingController searchController = TextEditingController();
  List<Stock> searchResults = [];
  bool searching = false;

  Stock? selectedStock;

  final TextEditingController avgPriceController = TextEditingController();
  final TextEditingController sharesController = TextEditingController();

  bool saving = false;
  String? error;

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    avgPriceController.dispose();
    sharesController.dispose();
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

    if (selectedStock == null) return;

    final avgPrice = double.tryParse(avgPriceController.text);
    final shares = int.tryParse(sharesController.text);

    if (avgPrice == null || avgPrice <= 0) {
      setState(() => error = "請輸入正確的均價");
      return;
    }

    if (shares == null || shares <= 0) {
      setState(() => error = "請輸入正確的股數");
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {

      await HoldingsApi.addHolding(
        code: selectedStock!.code,
        avgPrice: avgPrice,
        shares: shares,
      );

      if (!mounted) return;

      Navigator.pop(context, true);

    } catch (e) {

      if (!mounted) return;

      setState(() {
        saving = false;
        error = "新增失敗：$e";
      });

    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("新增庫存股"),
      ),
      body: selectedStock == null
          ? _buildSearchStep()
          : _buildInputStep(),
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

  Widget _buildInputStep() {

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

          const SizedBox(height: 20),

          TextField(
            controller: avgPriceController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: "均價",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: sharesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "股數",
              border: OutlineInputBorder(),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 24),

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
                  : const Text("新增"),
            ),
          ),

        ],
      ),
    );
  }
}