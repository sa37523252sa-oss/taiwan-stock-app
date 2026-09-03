import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/disclosure.dart';
import '../../api/disclosure_api.dart';
import '../../utils/responsive.dart';

class InvestorMeetingTab extends StatefulWidget {
  const InvestorMeetingTab({
    super.key,
    required this.code,
  });

  final String code;

  @override
  State<InvestorMeetingTab> createState() =>
      _InvestorMeetingTabState();
}

class _InvestorMeetingTabState extends State<InvestorMeetingTab> {

  bool loading = true;
  String? error;
  List<Disclosure> items = [];

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

      final data = await DisclosureApi.getMeetings(widget.code);

      if (!mounted) return;

      setState(() {
        items = data;
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

  String _formatDate(DateTime? d) {
    if (d == null) return "";
    return "${d.year}/${d.month.toString().padLeft(2, '0')}/"
        "${d.day.toString().padLeft(2, '0')}";
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

  void _showDetail(Disclosure item) {

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      Text(
                        item.categoryLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(item.factDate ?? item.speakDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    item.subject,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    item.detail.isNotEmpty ? item.detail : "（無進一步說明內容）",
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),

                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader() {

    final investorConfDates = items
        .where((d) => d.category == "investor_conference")
        .map((d) => d.factDate ?? d.speakDate)
        .whereType<DateTime>()
        .toList();

    String icNote = "";
    if (investorConfDates.isNotEmpty) {
      investorConfDates.sort((a, b) => b.compareTo(a));
      icNote = "（最近一次公告：${_formatDate(investorConfDates.first)}）";
    }

    final agmDates = items
        .where((d) => d.category == "agm" || d.category == "egm")
        .map((d) => d.factDate ?? d.speakDate)
        .whereType<DateTime>()
        .toList();

    String aNote = "";
    if (agmDates.isNotEmpty) {
      agmDates.sort((a, b) => b.compareTo(a));
      aNote = "（最近一次股東會：${_formatDate(agmDates.first)}）";
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [

          _LinkCard(
            color: Colors.teal,
            title: "法說會簡報",
            subtitle: "查看歷年法人說明會簡報清單 $icNote",
            onTap: () => _openLink(
              "https://finmoconf.diveinvest.net/company/${widget.code}",
            ),
          ),

          const SizedBox(height: 10),

          _LinkCard(
            color: Colors.purple,
            title: "股東會電子書 / 年報",
            subtitle: "開會通知、議事手冊、議事錄、年報等資料 $aNote",
            onTap: () => _openLink(
              "https://doc.twse.com.tw/server-java/t57sb01"
              "?step=1&colorchg=1&co_id=${widget.code}&year=&mtype=F",
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

        ],
      ),
    );
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

    return RefreshIndicator(
      onRefresh: load,
      child: ResponsiveContentWrapper(
        child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: items.isEmpty ? 2 : items.length + 1,
        separatorBuilder: (context, index) {
          if (index == 0) return const SizedBox.shrink();
          return const Divider(height: 1);
        },
        itemBuilder: (context, index) {

          if (index == 0) {
            return _buildHeader();
          }

          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  "目前沒有相關公司會議資訊",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          final item = items[index - 1];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
            onTap: () => _showDetail(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    children: [
                      Text(
                        item.categoryLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      if (item.isAnnouncementOnly) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            "公告",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(item.factDate ?? item.speakDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  Text(
                    item.subject,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                ],
              ),
            ),
            ),
          );
        },
      ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [

              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.open_in_new,
                size: 16,
                color: Colors.grey.shade400,
              ),

            ],
          ),
        ),
      ),
    );
  }
}