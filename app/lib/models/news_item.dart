class NewsItem {
  const NewsItem({
    required this.title,
    required this.link,
    required this.summary,
    required this.source,
    required this.pubDate,
    required this.relevanceScore,
    required this.confidence,
    required this.topics,
    required this.eventType,
    required this.relationType,
    required this.reasons,
    this.relatedCodes,
  });

  final String title;
  final String link;
  final String summary;
  final String source;
  final DateTime? pubDate;
  final int relevanceScore;
  final int? confidence;
  final List<String> topics;
  final String? eventType;
  final String? relationType;
  final List<String> reasons;

  // /news/portfolio/all 用：這則新聞關聯到哪些股票代號
  // （庫存股新聞頁才有，單一股票新聞頁用不到）
  final List<String>? relatedCodes;

  factory NewsItem.fromJson(Map<String, dynamic> json) {

    DateTime? date;

    final raw = json["pub_date"];

    if (raw != null && raw.toString().isNotEmpty) {
      try {
        date = DateTime.parse(raw);
      } catch (_) {
        date = null;
      }
    }

    List<String> toStringList(dynamic v) {
      if (v == null) return [];
      return (v as List).map((e) => e.toString()).toList();
    }

    return NewsItem(
      title: json["title"] ?? "",
      link: json["link"] ?? "",
      summary: json["summary"] ?? "",
      source: json["source"] ?? "",
      pubDate: date,
      relevanceScore: (json["relevance_score"] as num?)?.toInt() ?? 0,
      confidence: (json["confidence"] as num?)?.toInt(),
      topics: toStringList(json["topics"]),
      eventType: json["event_type"],
      relationType: json["relation_type"],
      reasons: toStringList(json["reasons"]),
      relatedCodes: json["related_codes"] == null
          ? null
          : toStringList(json["related_codes"])
              .where((c) => c.isNotEmpty)
              .toList(),
    );
  }
}