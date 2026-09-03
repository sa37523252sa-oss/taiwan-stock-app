import 'package:flutter/material.dart';
import 'financial_chart.dart';
import 'financial_table.dart';
import '../../models/financial.dart';
import '../../models/stock.dart';

class FinancialTab extends StatefulWidget {
  const FinancialTab({
    super.key,
    required this.financial,
    required this.stock,
  });

  final FinancialData financial;
  final Stock stock;

  @override
  State<FinancialTab> createState() => _FinancialTabState();
}

class _FinancialTabState extends State<FinancialTab>
    with TickerProviderStateMixin {

  late final TabController _categoryController;

  final categories = const [
  '總覽',
  '獲利',
  '營收',
  '體質',
  '現金流',
  '股利',
];
  final indicators = const ['EPS','毛利率','營益率','淨利率','ROE','ROA'];

  int selectedIndicator = 0;

  final Map<String, int?> selectedIndexMap = {};

  final Map<String, Set<String>> selectedMetrics = {
    "總覽": {
      "ROE",
      "ROA",
      "本益比",
    },

    "營收": {
      "營收",
      "MoM",
      "YoY",
    },

    "獲利": {
      "EPS",
      "ROE",
      "ROA",
      "毛利率",
      "營益率",
      "淨利率",
    },

    "體質": {
      "負債比",
      "流動比",
      "速動比",
      "股東權益",
    },

    "現金流": {
      "營業現金流",
      "自由現金流",
      "資本支出",
    },

    "股利": {
      "現金股利",
      "股票股利",
      "殖利率",
      "除權息日",
      "現金股利發放日",
      "股票股利發放日",
    },
  };

  @override
  void initState() {
    super.initState();
    _categoryController =
        TabController(length: categories.length, vsync: this);
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: List.generate(categories.length, (i) {
              final selected=_categoryController.index==i;
              return Expanded(
                child: InkWell(
                  onTap: (){
                    _categoryController.animateTo(i);
                    setState((){});
                  },
                  child: Column(
                    children:[
                      Text(categories[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize:18,
                          fontWeight:FontWeight.w700,
                          color:selected?Theme.of(context).colorScheme.primary:Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height:8),
                      Container(
                        height:3,
                        width:40,
                        color:selected?Theme.of(context).colorScheme.primary:Colors.transparent,
                      )
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: TabBarView(
            controller: _categoryController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildOverview(),
              _buildProfit(),
              _buildGrowth(),
              _buildHealth(),
              _buildCashflow(),
              _buildDividend(),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildOverview() => _buildCategoryPage(
  category: "總覽",
  metrics: const ["ROE","ROA","本益比"],
);

  Widget _buildProfit() => _buildCategoryPage(
  category: "獲利",
  metrics: const [
    "EPS",
    "ROE",
    "ROA",
    "毛利率",
    "營益率",
    "淨利率",
  ],
);

  Widget _buildGrowth() => _buildCategoryPage(
  category: "營收",
  metrics: const ["MoM","YoY"],
);

  Widget _buildHealth() => _buildCategoryPage(
  category: "體質",
  metrics: const ["負債比","流動比","速動比","股東權益"],
);

  Widget _buildCashflow() => _buildCategoryPage(
  category: "現金流",
  metrics: const ["營業現金流","自由現金流","資本支出"],
);

  Widget _buildDividend() => _buildCategoryPage(
  category: "股利",
  metrics: const [
    "現金股利",
    "股票股利",
    "殖利率",
    "除權息日",
    "現金股利發放日",
    "股票股利發放日",
  ],
);

  Widget _buildCategoryPage({
  required String category,
  required List<String> metrics,
}) {
  final isRevenue = category == "營收";

  return Column(
        children: [

          if (!isRevenue) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) => FilterChip(
                  label: Text(metrics[i]),
                  selected: selectedMetrics[category]!.contains(metrics[i]),
                  onSelected: (v){
                    setState((){
                      if(v){selectedMetrics[category]!.add(metrics[i]);}else{selectedMetrics[category]!.remove(metrics[i]);}
                    });
                  },
                ),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: metrics.length,
              ),
            ),
          ],

          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 5,
                  child: FinancialChart(
                    category: category,
                    metrics: category == "營收"
                        ? const ["營收"]
                        : selectedMetrics[category]!.toList(),
                    financial: widget.financial,
                    stock: widget.stock,
                    selectedIndex: selectedIndexMap[category],
                    onSelectIndex: (i) {
                      setState(() {
                        selectedIndexMap[category] =
                            selectedIndexMap[category] == i ? null : i;
                      });
                    },
                  ),
                ),
                Divider(height:1),
                Expanded(
                  flex: 4,
                  child: FinancialTable(
                    metrics: selectedMetrics[category]!.toList(),
                    category: category,
                    financial: widget.financial,
                    stock: widget.stock,
                    selectedIndex: selectedIndexMap[category],
                    onSelectRow: (i) {
                      setState(() {
                        selectedIndexMap[category] = i < 0 ? null : i;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
}