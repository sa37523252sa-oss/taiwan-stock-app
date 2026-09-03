class Disclosure {
  const Disclosure({
    required this.code,
    required this.companyName,
    required this.category,
    required this.tier,
    required this.subject,
    required this.detail,
    required this.factDate,
    required this.speakDate,
    required this.contentStatus,
    required this.relatedId,
  });

  final String code;
  final String companyName;
  final String category;
  final String tier;
  final String subject;
  final String detail;
  final DateTime? factDate;
  final DateTime? speakDate;

  /// 只有「法說/股東會」（會議類）才有值：
  /// announcement_only（公告）／completed（結果/內容已產生）
  final String? contentStatus;

  /// 只有「從股東會決議內容解析出的衍生重大動態」才有值，
  /// 指向來源那筆會議紀錄的 id。
  final String? relatedId;

  static const Map<String, String> categoryLabels = {
    "investor_conference": "法說會",
    "investor_day": "Investor Day",
    "roadshow": "海外Roadshow",
    "agm": "股東常會",
    "egm": "臨時股東會",
    "financial_report": "財報發布",
    "earnings_preview": "盈餘預告",
    "dividend": "股利決議",
    "investment": "增資/併購/投資/擴產",
    "corporate_change": "公司名稱/股票面額變更",
    "audit_committee": "審計委員會",
    "comp_committee": "薪酬委員會",
    "board_resolution": "董事會重大決議",
    "director_change": "董監事改選",
    "major_strategy_change": "重大經營策略變更",
    "merger": "併購/合併",
    "acquisition": "收購",
    "private_placement": "私募",
    "capital_increase": "增資",
    "capital_reduction": "減資",
  };

  String get categoryLabel => categoryLabels[category] ?? category;

  bool get isAnnouncementOnly => contentStatus == "announcement_only";

  factory Disclosure.fromJson(Map<String, dynamic> json) {

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      if (s.isEmpty) return null;
      try {
        return DateTime.parse(s);
      } catch (_) {
        return null;
      }
    }

    return Disclosure(
      code: json["code"] ?? "",
      companyName: json["company_name"] ?? "",
      category: json["category"] ?? "",
      tier: json["tier"] ?? "",
      subject: json["subject"] ?? "",
      detail: json["detail"] ?? "",
      factDate: parseDate(json["fact_date"]),
      speakDate: parseDate(json["speak_date"]),
      contentStatus: json["content_status"],
      relatedId: json["related_id"],
    );
  }
}