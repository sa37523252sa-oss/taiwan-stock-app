import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/news_item.dart';
import '../../api/news_api.dart';
import '../../utils/responsive.dart';

// 首頁底部導覽的「新聞」分頁，跟個股頁裡的 NewsTab（單一股票的
// 新聞）是不同東西，檔名特意不叫 news_tab.dart，避免跟既有檔案
// 搞混。用 Tab 切換兩個區塊：持股動態（庫存股+自選股）／
// 大盤國際（大盤+國際財經）。
class MarketNewsTab extends StatefulWidget {
  const MarketNewsTab({super.key});

  @override
  State<MarketNewsTab> createState() => _MarketNewsTabState();
}

class _MarketNewsTabState extends State<MarketNewsTab>
    with SingleTickerProviderStateMixin {

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(text: "持股動態"),
                Tab(text: "大盤國際"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _NewsList(mode: _NewsListMode.portfolio),
                _NewsList(mode: _NewsListMode.market),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _NewsListMode { portfolio, market }

class _NewsList extends StatefulWidget {
  const _NewsList({required this.mode});

  final _NewsListMode mode;

  @override
  State<_NewsList> createState() => _NewsListState();
}

class _NewsListState extends State<_NewsList>
    with AutomaticKeepAliveClientMixin {

  bool loading = true;
  String? error;
  List<NewsItem> news = [];

  @override
  bool get wantKeepAlive => true;

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

      final data = widget.mode == _NewsListMode.portfolio
          ? await NewsApi.getPortfolioNews()
          : await NewsApi.getMarketNews();

      if (!mounted) return;

      setState(() {
        news = data;
        loading = false;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() {
        error = e.toString();
        loading = false;
      });

    }
  }

  Future<void> _openLink(String url) async {

    final uri = Uri.tryParse(url);

    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    }
  }

  String _stripHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String _formatSummary(String raw) {

    final stripped = _stripHtml(raw);

    if (stripped.length <= 90) return stripped;

    return "${stripped.substring(0, 90)}...";
  }

  String _formatDate(DateTime? d) {

    if (d == null) return "";

    return "${d.month}/${d.day} "
        "${d.hour.toString().padLeft(2, '0')}:"
        "${d.minute.toString().padLeft(2, '0')}";
  }

  String get _emptyText {
    return widget.mode == _NewsListMode.portfolio
        ? "目前沒有庫存股/自選股相關新聞"
        : "目前沒有大盤/國際財經新聞";
  }

  @override
  Widget build(BuildContext context) {

    super.build(context);

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (error != null) {
      return Center(
        child: Text(error!),
      );
    }

    if (news.isEmpty) {
      return Center(
        child: Text(
          _emptyText,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    final titleFontSize = ResponsiveLayout.scaleFont(context, 15.0);
    final summaryFontSize = ResponsiveLayout.scaleFont(context, 13.0);
    final metaFontSize = ResponsiveLayout.scaleFont(context, 11.0);

    return RefreshIndicator(
      onRefresh: load,
      child: ResponsiveContentWrapper(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          itemCount: news.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {

            final n = news[index];

            return InkWell(
              onTap: () => _openLink(n.link),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    if (n.relatedCodes != null && n.relatedCodes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(
                          spacing: 4,
                          children: n.relatedCodes!.map((code) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                code,
                                style: TextStyle(
                                  fontSize: metaFontSize,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    Text(
                      n.title,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (n.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatSummary(n.summary),
                        style: TextStyle(
                          fontSize: summaryFontSize,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        Text(
                          n.source,
                          style: TextStyle(
                            fontSize: metaFontSize,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(n.pubDate),
                          style: TextStyle(
                            fontSize: metaFontSize,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.open_in_new,
                          size: 14,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),

                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}