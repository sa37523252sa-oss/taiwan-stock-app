import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/financial.dart';
import '../../api/financial_api.dart';
import '../../utils/responsive.dart';

class EbookTab extends StatefulWidget {
  const EbookTab({
    super.key,
    required this.code,
  });

  final String code;

  @override
  State<EbookTab> createState() => _EbookTabState();
}

class _QuarterEntry {
  const _QuarterEntry({
    required this.label,
    required this.url,
    this.enUrl,
    this.note,
  });

  final String label; // 第1季財報 / 年報
  final String url;

  // 只有季報才有英文版直連；年報沒辦法做到，見下方說明
  final String? enUrl;

  // 額外的小提示文字，顯示在標籤下方
  final String? note;
}

class _EbookTabState extends State<EbookTab> {

  bool loading = true;
  String? error;

  // 依年度分組，同一年的 Q1~Q4 + 年報 放在同一個框框裡
  Map<int, List<_QuarterEntry>> byYear = {};
  List<int> years = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  /// 季報：檔名可以自己完整算出來（年+季+代號固定格式），
  /// 直接連到那一份 PDF 本身。
  String _quarterlyUrl(int year, int quarter, String suffix) {

    final q = quarter.toString().padLeft(2, '0');
    final filename = "$year${q}_${widget.code}_$suffix.pdf";

    return "https://doc.twse.com.tw/server-java/t57sb01"
        "?co_id=${widget.code}&colorchg=1&kind=A&step=9"
        "&filename=$filename";
  }

  /// 年報：連續猜了兩次查詢參數（先猜 mtype=F 是股東會、
  /// 再猜 mtype=A 是純財報）都被使用者實測證明不對，不再
  /// 繼續猜。目前唯一有實際截圖證實「打開後真的看得到年報
  /// PDF」的，就是這個 mtype=F 查詢頁——雖然分類標籤寫的是
  /// 「股東會相關資料」，但裡面確實包含「股東會年報」那一列。
  /// 年報的檔名一樣帶有無法事先算出來的申報時間戳，沒辦法
  /// 精確直連單一檔案，只能連到這張清單頁，使用者自己找。
  String _annualReportUrl() {

    return "https://doc.twse.com.tw/server-java/t57sb01"
        "?step=1&colorchg=1&co_id=${widget.code}&year=&mtype=F";
  }

  Future<void> load() async {

    setState(() {
      loading = true;
      error = null;
    });

    try {

      final financial = await FinancialApi.getFinancial(widget.code);

      final grouped = <int, List<_QuarterEntry>>{};

      for (final q in financial.quarter) {
        grouped.putIfAbsent(q.year, () => []);
        grouped[q.year]!.add(_QuarterEntry(
          label: "第${q.quarter}季財報",
          url: _quarterlyUrl(q.year, q.quarter, "AI1"),
          enUrl: _quarterlyUrl(q.year, q.quarter, "AIA"),
        ));
      }

      // 每年附加一筆「年報」。連結會開啟一張標題寫著「股東會
      // 相關資料」的查詢頁表，這是唯一實測證實真的能找到年報
      // PDF 的地方（見上方 _annualReportUrl 說明），不是分類
      // 錯誤，是證交所系統本身把年報歸在這個分類底下。
      for (final year in grouped.keys) {
        grouped[year]!.add(_QuarterEntry(
          label: "年報",
          url: _annualReportUrl(),
          note: "將開啟查詢頁表（標題為股東會相關資料），"
              "請於其中點選「股東會年報」該列的檔案",
        ));
      }

      final sortedYears = grouped.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      if (!mounted) return;

      setState(() {
        byYear = grouped;
        years = sortedYears;
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
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "點擊會開啟證交所電子檔案，內容不經過本 App 儲存或處理。"
              "法說會簡報、股東會電子書請至「法說/股東會」分頁查看。",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ),

          ...years.map((year) {

            final list = byYear[year]!;

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.shade100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    "$year 年",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),

                  const Divider(height: 16),

                  ...list.map((q) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [

                            Expanded(
                              child: InkWell(
                                onTap: () => _openLink(q.url),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.description_outlined,
                                          size: 18,
                                          color: Colors.blue.shade400,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          q.label,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (q.note != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 3,
                                          left: 26,
                                        ),
                                        child: Text(
                                          q.note!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            if (q.enUrl != null)
                              OutlinedButton(
                                onPressed: () => _openLink(q.enUrl!),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  minimumSize: const Size(0, 36),
                                ),
                                child: const Text(
                                  "英文版",
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),

                          ],
                        ),
                      )),

                ],
              ),
            );
          }),

          if (years.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  "目前沒有財報資料",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),

        ],
        ),
      ),
    );
  }
}