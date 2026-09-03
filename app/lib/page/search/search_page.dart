import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../models/stock.dart';
import '../../screens/stock_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {

  Timer? _debounce;

  final TextEditingController controller = TextEditingController();

  List<Stock> searchResults = [];
  bool searching = false;

  @override
  void initState() {
    super.initState();
    // 進頁面直接彈出鍵盤，符合「搜尋頁」的使用情境
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> searchStock(String keyword) async {

    keyword = keyword.trim();

    if (keyword.isEmpty) {
      setState(() {
        searchResults = [];
        searching = false;
      });
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

  void openStock(Stock stock) {

    FocusScope.of(context).unfocus();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StockPage(
          stockCode: stock.code,
          stockName: stock.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: "輸入股票代號或名稱",
            border: InputBorder.none,
          ),
          onChanged: (value) {
            if (_debounce?.isActive ?? false) {
              _debounce!.cancel();
            }
            _debounce = Timer(
              const Duration(milliseconds: 300),
              () => searchStock(value),
            );
          },
          onSubmitted: searchStock,
        ),
        actions: [
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                controller.clear();
                setState(() => searchResults = []);
              },
            ),
        ],
      ),
      body: searching
          ? const Center(child: CircularProgressIndicator())
          : searchResults.isEmpty
              ? Center(
                  child: Text(
                    controller.text.trim().isEmpty
                        ? "輸入股票代號或名稱開始搜尋"
                        : "沒有符合的股票",
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    final stock = searchResults[index];
                    return ListTile(
                      title: Text("${stock.code} ${stock.name}"),
                      subtitle: Text(stock.industry),
                      onTap: () => openStock(stock),
                    );
                  },
                ),
    );
  }
}
