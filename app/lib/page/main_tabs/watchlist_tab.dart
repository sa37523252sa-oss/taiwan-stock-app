import 'package:flutter/material.dart';

import '../../models/watchlist.dart';
import '../../api/watchlist_api.dart';
import '../../screens/stock_page.dart';
import 'add_to_watchlist_page.dart';

class WatchlistTab extends StatefulWidget {
  const WatchlistTab({super.key});

  @override
  State<WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<WatchlistTab> {

  bool loading = true;
  String? error;

  List<WatchlistInfo> watchlists = [];
  int? selectedWatchlistId;

  List<WatchlistStock> stocks = [];
  bool loadingStocks = false;

  bool editMode = false;
  Set<String> selectedCodes = {};

  @override
  void initState() {
    super.initState();
    loadWatchlists();
  }

  Future<void> loadWatchlists() async {

    setState(() {
      loading = true;
      error = null;
    });

    try {

      final data = await WatchlistApi.getWatchlists();

      if (!mounted) return;

      setState(() {
        watchlists = data;
        loading = false;
        selectedWatchlistId ??=
            data.isNotEmpty ? data.first.id : null;
      });

      if (selectedWatchlistId != null) {
        loadStocks();
      }

    } catch (e) {

      if (!mounted) return;

      setState(() {
        error = "$e";
        loading = false;
      });

    }
  }

  Future<void> loadStocks() async {

    if (selectedWatchlistId == null) return;

    setState(() {
      loadingStocks = true;
      selectedCodes = {};
    });

    try {

      final data =
          await WatchlistApi.getWatchlistStocks(selectedWatchlistId!);

      if (!mounted) return;

      setState(() {
        stocks = data;
        loadingStocks = false;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() => loadingStocks = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("讀取自選股失敗：$e")),
      );

    }
  }

  void selectWatchlist(int id) {

    if (id == selectedWatchlistId) return;

    setState(() {
      selectedWatchlistId = id;
      editMode = false;
    });

    loadStocks();
  }

  Future<void> renameCurrentWatchlist() async {

    final current = watchlists.firstWhere(
      (w) => w.id == selectedWatchlistId,
    );

    final controller = TextEditingController(text: current.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("重新命名清單"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("儲存"),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await WatchlistApi.renameWatchlist(current.id, newName);
      loadWatchlists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("重新命名失敗：$e")),
      );
    }
  }

  Future<void> openAdd() async {

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddToWatchlistPage(
          watchlists: watchlists,
          defaultWatchlistId: selectedWatchlistId,
        ),
      ),
    );

    if (result == true) {
      loadWatchlists();
      loadStocks();
    }
  }

  void toggleEditMode() {

    final entering = !editMode;

    setState(() {
      editMode = !editMode;
      selectedCodes = {};
    });

    if (entering) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("長按卡片可拖曳調整順序；點擊卡片可勾選要移除的股票"),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> removeSelected() async {

    if (selectedCodes.isEmpty || selectedWatchlistId == null) return;

    try {

      for (final code in selectedCodes) {
        await WatchlistApi.removeStock(selectedWatchlistId!, code);
      }

      setState(() {
        editMode = false;
        selectedCodes = {};
      });

      loadWatchlists();
      loadStocks();

    } catch (e) {

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("移除失敗：$e")),
      );

    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {

    if (oldIndex == newIndex || selectedWatchlistId == null) return;

    // 先在畫面上立刻反映新順序（不用等後端回應），
    // 失敗的話再跳提示，不特別復原畫面順序，重新整理一次
    // 清單即可回到伺服器實際狀態。
    setState(() {
      final item = stocks.removeAt(oldIndex);
      stocks.insert(newIndex, item);
    });

    try {

      await WatchlistApi.reorderStocks(
        selectedWatchlistId!,
        stocks.map((s) => s.code).toList(),
      );

    } catch (e) {

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("排序儲存失敗：$e")),
      );

    }
  }

  @override
  Widget build(BuildContext context) {

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(child: Text(error!));
    }

    return Scaffold(

      body: Column(
        children: [

          _buildListTabs(),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (editMode && selectedCodes.isNotEmpty)
                  TextButton.icon(
                    onPressed: removeSelected,
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: Text(
                      "移除 (${selectedCodes.length})",
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton.icon(
                  onPressed: toggleEditMode,
                  icon: Icon(editMode ? Icons.check : Icons.edit_outlined),
                  label: Text(editMode ? "完成" : "編輯"),
                ),
              ],
            ),
          ),

          Expanded(
            child: loadingStocks
                ? const Center(child: CircularProgressIndicator())
                : stocks.isEmpty
                    ? const Center(
                        child: Text(
                          "這個清單還沒有股票，點右下角新增",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: loadStocks,
                        child: LayoutBuilder(
                          builder: (context, constraints) {

                            const crossAxisCount = 2;
                            const spacing = 10.0;
                            const gridPadding = 12.0;

                            final cardWidth = (constraints.maxWidth -
                                    gridPadding * 2 -
                                    spacing * (crossAxisCount - 1)) /
                                crossAxisCount;

                            return GridView.builder(
                              padding: const EdgeInsets.all(gridPadding),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: 1.6,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                              ),
                              itemCount: stocks.length,
                              itemBuilder: (context, index) {

                                final card = _stockCard(stocks[index]);

                                if (!editMode) {
                                  return card;
                                }

                                // 編輯模式才能拖曳排序，平常點擊維持
                                // 原本「進股票頁」的行為不受影響。
                                return DragTarget<int>(
                                  onWillAcceptWithDetails: (details) =>
                                      details.data != index,
                                  onAcceptWithDetails: (details) =>
                                      reorder(details.data, index),
                                  builder:
                                      (context, candidateData, rejectedData) {
                                    return LongPressDraggable<int>(
                                      data: index,
                                      feedback: Material(
                                        color: Colors.transparent,
                                        child: SizedBox(
                                          width: cardWidth,
                                          child: Opacity(
                                            opacity: 0.85,
                                            child: card,
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.3,
                                        child: card,
                                      ),
                                      child: candidateData.isNotEmpty
                                          ? Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  width: 2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: card,
                                            )
                                          : card,
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
          ),

        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: openAdd,
        child: const Icon(Icons.add),
      ),

    );
  }

  Widget _buildListTabs() {

    final primaryColor = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < watchlists.length; i++) ...[

              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Colors.grey.shade300,
                  ),
                ),

              GestureDetector(
                onTap: () => selectWatchlist(watchlists[i].id),
                onLongPress: watchlists[i].id == selectedWatchlistId
                    ? renameCurrentWatchlist
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 3,
                        color: watchlists[i].id == selectedWatchlistId
                            ? primaryColor
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    watchlists[i].name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: watchlists[i].id == selectedWatchlistId
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: watchlists[i].id == selectedWatchlistId
                          ? primaryColor
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),

            ],
          ],
        ),
      ),
    );
  }

  Widget _stockCard(WatchlistStock s) {

    final change = s.change;

    // 上漲紅、平盤黑、下跌綠，股價數字跟漲跌都用同一套顏色
    final color = change == null
        ? Colors.black
        : change > 0
            ? Colors.red
            : change < 0
                ? Colors.green
                : Colors.black;

    final selected = selectedCodes.contains(s.code);

    return Card(
      color: selected ? Colors.blue.shade50 : null,
      child: InkWell(
        onTap: () {

          if (editMode) {
            setState(() {
              if (selected) {
                selectedCodes.remove(s.code);
              } else {
                selectedCodes.add(s.code);
              }
            });
            return;
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StockPage(
                stockCode: s.code,
                stockName: s.companyName ?? s.code,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "${s.code} ${s.companyName ?? ''}",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (editMode)
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 18,
                      color: selected ? Colors.blue : Colors.grey,
                    ),
                ],
              ),

              const SizedBox(height: 4),

              Text(
                s.currentPrice == null
                    ? "--"
                    : s.currentPrice!.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                change == null
                    ? "--"
                    : "${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}"
                        "(${s.changePct?.toStringAsFixed(2) ?? '--'}%)",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                "總量 ${s.volume == null ? '--' : _formatVolume(s.volume!)}",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                "本益比 ${s.pe?.toStringAsFixed(1) ?? '--'}　"
                "殖利率 ${s.dividendYield?.toStringAsFixed(2) ?? '--'}%",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  String _formatVolume(int volume) {
    // 股數換算成張數（1張=1000股），比較符合台股慣例的顯示方式
    final lots = volume / 1000;
    if (lots >= 10000) {
      return "${(lots / 10000).toStringAsFixed(1)}萬張";
    }
    return "${lots.toStringAsFixed(0)}張";
  }
}