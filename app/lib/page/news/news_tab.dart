import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/news_item.dart';
import '../../api/news_api.dart';
import '../../utils/responsive.dart';

class NewsTab extends StatefulWidget {
  const NewsTab({
    super.key,
    required this.code,
  });

  final String code;

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {

  bool loading = true;
  String? error;
  List<NewsItem> news = [];

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

      final data = await NewsApi.getNews(widget.code);

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

  @override
  Widget build(BuildContext context) {

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
      return const Center(
        child: Text(
          "目前沒有相關新聞",
          style: TextStyle(color: Colors.grey),
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