import 'package:flutter/material.dart';

import 'page/search/search_page.dart';
import 'page/main_tabs/holdings_tab.dart';
import 'page/main_tabs/watchlist_tab.dart';
import 'page/main_tabs/market_tab.dart';
import 'page/main_tabs/backtest_tab.dart';
import 'page/main_tabs/market_news_tab.dart';
import 'page/main_tabs/me_tab.dart';

void main() {
  runApp(const StockApp());
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      title: 'StockBrain',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeShell(),
    );
  }
}

/// App 的導覽外殼：
///   - 頂部：標題 + 固定在右上角的搜尋圖示（AppBar 本身就是釘在
///     最上方，不會隨內容捲動）
///   - 底部：庫存股／自選股／大盤／回測／新聞／我的 六個分頁
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {

  int currentIndex = 2; // 預設停在「大盤」

  static const _titles = ["庫存股", "自選股", "大盤", "回測", "新聞", "我的"];

  static const _tabs = [
    HoldingsTab(),
    WatchlistTab(),
    MarketTab(),
    BacktestTab(),
    MarketNewsTab(),
    MeTab(),
  ];

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text(_titles[currentIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: "搜尋股票",
            onPressed: _openSearch,
          ),
        ],
      ),

      body: IndexedStack(
        index: currentIndex,
        children: _tabs,
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() => currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: "庫存股",
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: "自選股",
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: "大盤",
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: "回測",
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: "新聞",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: "我的",
          ),
        ],
      ),

    );
  }
}