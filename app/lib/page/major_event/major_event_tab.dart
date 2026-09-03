import 'package:flutter/material.dart';

import '../../models/disclosure.dart';
import '../../api/disclosure_api.dart';
import '../../utils/responsive.dart';

class MajorEventTab extends StatefulWidget {
  const MajorEventTab({
    super.key,
    required this.code,
  });

  final String code;

  @override
  State<MajorEventTab> createState() => _MajorEventTabState();
}

class _MajorEventTabState extends State<MajorEventTab> {

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

      final data = await DisclosureApi.getMajorEvents(widget.code);

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

  Color _tierColor(String tier) {
    switch (tier) {
      case "S":
        return Colors.red;
      case "A":
        return Colors.orange;
      default:
        return Colors.grey;
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

                  if (item.detail.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      item.detail,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ],

                  if (item.relatedId != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      "來源會議：${item.relatedId}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],

                ],
              ),
            );
          },
        );
      },
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

    if (items.isEmpty) {
      return const Center(
        child: Text(
          "目前沒有重大動態",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ResponsiveContentWrapper(
        child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {

          final item = items[index];
          final color = _tierColor(item.tier);

          return InkWell(
            onTap: () => _showDetail(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Container(
                    width: 4,
                    height: 40,
                    margin: const EdgeInsets.only(right: 10, top: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        Row(
                          children: [
                            Text(
                              item.categoryLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
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