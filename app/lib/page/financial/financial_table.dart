import 'package:flutter/material.dart';
import '../../models/financial.dart';
import '../../models/stock.dart';
import '../../utils/responsive.dart';

class FinancialTable extends StatefulWidget {
  const FinancialTable({
    super.key,
    required this.metrics,
    required this.category,
    required this.financial,
    required this.stock,
    this.selectedIndex,
    this.onSelectRow,
  });

  final List<String> metrics;
  final String category;
  final FinancialData financial;
  final Stock stock;
  final int? selectedIndex;
  final ValueChanged<int>? onSelectRow;

  @override
  State<FinancialTable> createState() => _FinancialTableState();
}

class _FinancialTableState extends State<FinancialTable> {

  // 表頭固定在最上面，跟表格內容各自有自己的橫向捲動元件，
  // 用這兩個 controller 互相同步位移，看起來就像同一張表。
  final ScrollController _headerHCtrl = ScrollController();
  final ScrollController _bodyHCtrl = ScrollController();

  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _bodyHCtrl.addListener(_syncHeaderFromBody);
    _headerHCtrl.addListener(_syncBodyFromHeader);
  }

  @override
  void dispose() {
    _bodyHCtrl.removeListener(_syncHeaderFromBody);
    _headerHCtrl.removeListener(_syncBodyFromHeader);
    _headerHCtrl.dispose();
    _bodyHCtrl.dispose();
    super.dispose();
  }

  void _syncHeaderFromBody() {
    if (_syncing) return;
    if (!_headerHCtrl.hasClients) return;
    _syncing = true;
    _headerHCtrl.jumpTo(_bodyHCtrl.offset);
    _syncing = false;
  }

  void _syncBodyFromHeader() {
    if (_syncing) return;
    if (!_bodyHCtrl.hasClients) return;
    _syncing = true;
    _bodyHCtrl.jumpTo(_headerHCtrl.offset);
    _syncing = false;
  }

  List<String> get metrics => widget.metrics;
  String get category => widget.category;
  FinancialData get financial => widget.financial;
  Stock get stock => widget.stock;
  int? get selectedIndex => widget.selectedIndex;
  ValueChanged<int>? get onSelectRow => widget.onSelectRow;

  bool get isRevenue => category == "營收";

  List<FinancialQuarter> get quarterData => financial.quarter;
  List<FinancialMonth> get monthData => financial.month;

  static const Set<String> _dateMetrics = {
    "除權息日", "現金股利發放日", "股票股利發放日",
  };

  double _colWidth(String metric, double scale) {
    if (_dateMetrics.contains(metric)) return 110 * scale;
    if (metric == "營收") return 90 * scale;
    return 80 * scale;
  }

  String _cellValue(dynamic row, String metric) {
    switch (metric) {
      case "EPS":
        return row.eps?.toStringAsFixed(2) ?? "--";
      case "ROE":
        return row.roe?.toStringAsFixed(2) ?? "--";
      case "ROA":
        return row.roa?.toStringAsFixed(2) ?? "--";
      case "毛利率":
        return row.grossMargin == null
            ? "--"
            : "${row.grossMargin!.toStringAsFixed(2)}%";
      case "營益率":
        return row.operatingMargin == null
            ? "--"
            : "${row.operatingMargin!.toStringAsFixed(2)}%";
      case "淨利率":
        return row.netMargin == null
            ? "--"
            : "${row.netMargin!.toStringAsFixed(2)}%";
      case "營收":
        return row.revenue == null
            ? "--"
            : (row.revenue! / 100000000).toStringAsFixed(2);
      case "MoM":
        return row.mom == null ? "--" : "${row.mom!.toStringAsFixed(2)}%";
      case "YoY":
        return row.yoy == null ? "--" : "${row.yoy!.toStringAsFixed(2)}%";
      case "負債比":
        return row.debtRatio?.toStringAsFixed(2) ?? "--";
      case "流動比":
        return row.currentRatio?.toStringAsFixed(2) ?? "--";
      case "速動比":
        return row.quickRatio?.toStringAsFixed(2) ?? "--";
      case "股東權益":
        return row.equity == null
            ? "--"
            : (row.equity! / 100000000).toStringAsFixed(2);
      case "營業現金流":
        return row.operatingCashFlow == null
            ? "--"
            : (row.operatingCashFlow! / 100000000).toStringAsFixed(2);
      case "自由現金流":
        return row.freeCashFlow == null
            ? "--"
            : (row.freeCashFlow! / 100000000).toStringAsFixed(2);
      case "資本支出":
        return row.investingCashFlow == null
            ? "--"
            : (row.investingCashFlow!.abs() / 100000000).toStringAsFixed(2);
      case "本益比":
        return row.pe?.toStringAsFixed(2) ?? "--";
      case "股價淨值比":
        return row.pb?.toStringAsFixed(2) ?? "--";
      case "殖利率":
        return row.dividendYield == null
            ? "--"
            : "${row.dividendYield!.toStringAsFixed(2)}%";
      case "現金股利":
        return row.cashDividend?.toStringAsFixed(2) ?? "--";
      case "股票股利":
        return row.stockDividend?.toStringAsFixed(2) ?? "--";
      case "除權息日":
        return row.exDividendDate?.isNotEmpty == true
            ? row.exDividendDate!
            : "--";
      case "現金股利發放日":
        return row.cashDividendDate?.isNotEmpty == true
            ? row.cashDividendDate!
            : "--";
      case "股票股利發放日":
        return row.stockDividendDate?.isNotEmpty == true
            ? row.stockDividendDate!
            : "--";
      default:
        return "--";
    }
  }

  Color? _cellColor(dynamic row, String metric) {
    if (metric == "MoM" || metric == "YoY") {
      final v = metric == "MoM" ? row.mom : row.yoy;
      if (v != null) {
        if (v > 0) return Colors.red;
        if (v < 0) return Colors.green;
      }
    }
    return null;
  }

  Widget _headerCell(String text, double width, double fontSize) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }

  Widget _bodyCell(String text, double width, double fontSize, {Color? color}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: fontSize,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    // 平板上欄位寬度、字體都放大一點，不然固定像素的窄欄位
    // 在大螢幕上會看起來過窄，右邊留一堆空白。
    final colScale = ResponsiveLayout.isTablet(context) ? 1.25 : 1.0;
    final cellFontSize = ResponsiveLayout.scaleFont(context, 13.0);

    final List<dynamic> rows = isRevenue ? monthData : quarterData;

    // 先把「原始 index + 資料」配對好，避免每列都重複呼叫
    // rows.indexOf(row)（那是 O(n) 查詢，資料一多會很慢）。
    final indexedRows = <MapEntry<int, dynamic>>[
      for (int i = 0; i < rows.length; i++) MapEntry(i, rows[i]),
    ];

    final List<String> visibleMetrics = metrics.where((metric) {

      if (isRevenue) return true;

      return rows.any((row) {
        switch (metric) {
          case "現金股利":
            return row.cashDividend != null;
          case "股票股利":
            return row.stockDividend != null;
          case "殖利率":
            return row.dividendYield != null;
          case "除權息日":
            return row.exDividendDate?.isNotEmpty == true;
          case "現金股利發放日":
            return row.cashDividendDate?.isNotEmpty == true;
          case "股票股利發放日":
            return row.stockDividendDate?.isNotEmpty == true;
          default:
            return true;
        }
      });

    }).toList();

    final List<MapEntry<int, dynamic>> visibleIndexedRows =
        category == "股利"
            ? indexedRows.where((e) {
                final row = e.value;
                return row.cashDividend != null ||
                    row.stockDividend != null ||
                    (row.exDividendDate?.isNotEmpty ?? false) ||
                    (row.cashDividendDate?.isNotEmpty ?? false) ||
                    (row.stockDividendDate?.isNotEmpty ?? false);
              }).toList()
            : indexedRows;

    // 表格由下往上顯示（最新在最上面），這裡一次反轉，
    // itemBuilder 裡直接照 index 拿，不用每列重算。
    final displayRows = visibleIndexedRows.reversed.toList();

    final dateColWidth = 70.0 * colScale;

    final columnWidths = [
      dateColWidth,
      ...visibleMetrics.map((m) => _colWidth(m, colScale)),
    ];

    final totalWidth = columnWidths.fold<double>(0, (a, b) => a + b);

    // 表頭（固定，不隨表格內容垂直捲動）
    final header = SingleChildScrollView(
      controller: _headerHCtrl,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Container(
        width: totalWidth,
        color: Colors.grey.shade100,
        child: Row(
          children: [
            _headerCell(isRevenue ? "月份" : "季度", dateColWidth, cellFontSize),
            ...visibleMetrics.map(
              (e) => _headerCell(
                e == "營收" ? "營收（億）" : e,
                _colWidth(e, colScale),
                cellFontSize,
              ),
            ),
          ],
        ),
      ),
    );

    // 表格內容（虛擬化：只建目前看得到的列，橫向捲動跟表頭同步）
    final body = SingleChildScrollView(
      controller: _bodyHCtrl,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: ListView.builder(
          itemCount: displayRows.length,
          itemBuilder: (context, i) {

            final entry = displayRows[i];
            final originalIndex = entry.key;
            final row = entry.value;
            final selected = selectedIndex == originalIndex;

            return InkWell(
              onTap: onSelectRow == null
                  ? null
                  : () => onSelectRow!(selected ? -1 : originalIndex),
              child: Container(
                color: selected ? Colors.grey.shade300 : null,
                child: Row(
                  children: [
                    _bodyCell(
                      isRevenue
                          ? "${row.year}/${row.month.toString().padLeft(2, '0')}"
                          : "${row.year}Q${row.quarter}",
                      dateColWidth,
                      cellFontSize,
                    ),
                    ...visibleMetrics.map(
                      (metric) => _bodyCell(
                        _cellValue(row, metric),
                        _colWidth(metric, colScale),
                        cellFontSize,
                        color: _cellColor(row, metric),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}