import 'package:flutter/material.dart';

import '../../models/institution_tab.dart';
import '../../models/institution_flow.dart';
import '../../models/investor_setting.dart';
import '../../models/holder_level.dart';
import '../../models/holder_point.dart';
import '../../models/margin_flow.dart';
import '../../api/institution_api.dart';
import '../../api/holder_api.dart';
import '../../api/margin_api.dart';

import 'institution_chart.dart';
import 'institution_table.dart';
import 'holder_chart.dart';
import 'holder_pie_chart.dart';
import 'margin_chart.dart';
import 'margin_table.dart';

class InstitutionTabPage extends StatefulWidget {
  const InstitutionTabPage({
    super.key,
    required this.code,
  });

  final String code;

  @override
  State<InstitutionTabPage> createState() =>
      _InstitutionTabPageState();
}

class _InstitutionTabPageState
    extends State<InstitutionTabPage> {

  InstitutionTab currentTab =
      InstitutionTab.investor;

  final tabs = const [

    (InstitutionTab.investor, "三大法人"),

    (InstitutionTab.holder, "大戶散戶"),

    (InstitutionTab.broker, "券商分點"),

    (InstitutionTab.margin, "資券當沖"),

    (InstitutionTab.chip, "籌碼分布"),

    (InstitutionTab.mainForce, "主力進出"),

    (InstitutionTab.director, "董監持股"),

  ];

  static const double _horizontalPadding = 20.0;
  static const double _gap = 24.0;

  bool loading = true;
  String? error;
  List<InstitutionFlow> flows = [];

  InvestorChartType chartType = InvestorChartType.price;

  DateTime? selectedDate;

  static const int visibleChartCount = 12;

  bool holderLoading = false;
  String? holderError;
  List<HolderPoint> holderPoints = [];
  Map<String, double> latestLevelPercent = {};
  DateTime? latestHolderDate;

  bool marginLoading = false;
  String? marginError;
  List<MarginFlow> marginFlows = [];

  @override
  void initState() {
    super.initState();
    loadInvestor();
  }

  Future<void> loadInvestor() async {

    setState(() {
      loading = true;
      error = null;
    });

    try {

      final data =
          await InstitutionApi.getInstitution(widget.code);

      if (!mounted) return;

      setState(() {
        flows = data;
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

  Future<void> loadHolder() async {

    if (holderLoading || holderPoints.isNotEmpty) return;

    setState(() {
      holderLoading = true;
      holderError = null;
    });

    try {

      final levels = await HolderApi.getHolder(widget.code);

      final points = HolderPoint.fromLevels(levels);

      if (!mounted) return;

      setState(() {
        holderPoints = points;
        if (points.isNotEmpty) {
          latestLevelPercent = points.last.levelPercent;
          latestHolderDate = points.last.date;
        }
        holderLoading = false;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() {
        holderError = e.toString();
        holderLoading = false;
      });

    }
  }

  Future<void> loadMargin() async {

    if (marginLoading || marginFlows.isNotEmpty) return;

    setState(() {
      marginLoading = true;
      marginError = null;
    });

    try {

      final data = await MarginApi.getMargin(widget.code);

      if (!mounted) return;

      setState(() {
        marginFlows = data;
        marginLoading = false;
      });

    } catch (e) {

      if (!mounted) return;

      setState(() {
        marginError = e.toString();
        marginLoading = false;
      });

    }
  }

  double _measureTabsWidth() {

    double total = _horizontalPadding * 2;

    for (int i = 0; i < tabs.length; i++) {

      final tp = TextPainter(
        text: TextSpan(
          text: tabs[i].$2,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      total += tp.width;

      if (i > 0) total += _gap;
    }

    return total;
  }

  Widget _buildTabItem(
    (InstitutionTab, String) item,
    Color primary,
  ) {

    final selected = item.$1 == currentTab;

    return InkWell(

      onTap: () {

        setState(() {

          currentTab = item.$1;

        });

        // ⚠️ 大戶持股（TaiwanStockHoldingSharesPer）需要 FinMind
        // 付費會員才能用，免費帳號會收到 400。暫時停用觸發，
        // 等升級或換資料源後再打開。
        // if (item.$1 == InstitutionTab.holder ||
        //     item.$1 == InstitutionTab.chip) {
        //   loadHolder();
        // }

        if (item.$1 == InstitutionTab.margin) {
          loadMargin();
        }

      },

      child: Column(

        mainAxisAlignment: MainAxisAlignment.center,

        children: [

          Text(

            item.$2,

            style: TextStyle(

              fontSize: 16,

              fontWeight: selected
                  ? FontWeight.w700
                  : FontWeight.w500,

              color: selected
                  ? primary
                  : Colors.grey[700],

            ),

          ),

          const SizedBox(height: 8),

          Container(
            height: 3,
            width: 32,
            color: selected
                ? primary
                : Colors.transparent,
          ),

        ],

      ),

    );
  }

  @override
  Widget build(BuildContext context) {

    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [

        SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) {

              final fits =
                  _measureTabsWidth() <= constraints.maxWidth;

              if (fits) {

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _horizontalPadding,
                  ),
                  child: Row(
                    children: [
                      for (final item in tabs)
                        Expanded(
                          child: _buildTabItem(item, primary),
                        ),
                    ],
                  ),
                );

              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: _horizontalPadding,
                ),
                child: Row(
                  children: [
                    for (int i = 0; i < tabs.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      _buildTabItem(tabs[i], primary),
                    ],
                  ],
                ),
              );

            },
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: _buildBody(),
        ),

      ],
    );
  }

  Widget _buildBody() {

    switch (currentTab) {

      case InstitutionTab.investor:
        return _buildInvestorContent();

      case InstitutionTab.margin:
        return _buildMarginContent();

      // ⚠️ 大戶散戶／籌碼分布需要的 FinMind dataset
      // (TaiwanStockHoldingSharesPer) 是付費會員才能用，
      // 免費帳號打會 400。先退回「開發中」佔位，
      // _buildHolderChartContent() / _buildHolderPieContent()
      // 都還在，之後升級或換資料源時把下面兩行取消註解即可：
      // case InstitutionTab.holder:
      //   return _buildHolderChartContent();
      // case InstitutionTab.chip:
      //   return _buildHolderPieContent();

      default:
        return Center(
          child: Text(
            "${tabs.firstWhere((t) => t.$1 == currentTab).$2} 開發中",
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 15,
            ),
          ),
        );
    }
  }

  Widget _buildInvestorContent() {

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

    if (flows.isEmpty) {
      return const Center(
        child: Text("沒有三大法人資料"),
      );
    }

    return Column(
      children: [

        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DropdownButton<InvestorChartType>(
                value: chartType,
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(
                    value: InvestorChartType.price,
                    child: Text("股價"),
                  ),
                  DropdownMenuItem(
                    value: InvestorChartType.total,
                    child: Text("合計張數"),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    chartType = v;
                  });
                },
              ),
            ],
          ),
        ),

        Expanded(
          flex: 4,
          child: InstitutionChart(
            flows: flows.length > visibleChartCount
                ? flows.sublist(flows.length - visibleChartCount)
                : flows,
            chartType: chartType,
            selectedDate: selectedDate,
          ),
        ),

        const Divider(height: 1),

        Expanded(
          flex: 6,
          child: InstitutionTable(
            flows: flows,
            selectedDate: selectedDate,
            onSelect: (date) {
              setState(() {
                selectedDate =
                    selectedDate == date ? null : date;
              });
            },
          ),
        ),

      ],
    );
  }

  Widget _buildHolderChartContent() {

    if (holderLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (holderError != null) {
      return Center(
        child: Text(holderError!),
      );
    }

    if (holderPoints.isEmpty) {
      return const Center(
        child: Text("沒有大戶持股資料"),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: HolderChart(points: holderPoints),
    );
  }

  Widget _buildHolderPieContent() {

    if (holderLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (holderError != null) {
      return Center(
        child: Text(holderError!),
      );
    }

    if (latestLevelPercent.isEmpty) {
      return const Center(
        child: Text("沒有籌碼分布資料"),
      );
    }

    return HolderPieChart(
      levelPercent: latestLevelPercent,
      date: latestHolderDate,
    );
  }

  Widget _buildMarginContent() {

    if (marginLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (marginError != null) {
      return Center(
        child: Text(marginError!),
      );
    }

    if (marginFlows.isEmpty) {
      return const Center(
        child: Text("沒有資券資料"),
      );
    }

    return Column(
      children: [

        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MarginChart(flows: marginFlows),
          ),
        ),

        const Divider(height: 1),

        Expanded(
          flex: 6,
          child: MarginTable(flows: marginFlows),
        ),

      ],
    );
  }
}