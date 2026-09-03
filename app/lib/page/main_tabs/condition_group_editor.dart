import 'package:flutter/material.dart';

import '../../models/backtest_condition.dart';

enum AddConditionType { technical, price, volume, liquidity, fundamental, custom }

const List<int> kMaOptions = [5, 10, 20, 60, 120, 240];

/// 條件群組編輯器：外層是 OR（多個群組），每個群組內部是 AND
/// （多個條件）。單一股票、多股票組合的「個別策略」模式都共用
/// 這個元件，不用各自重複實作一份。
class ConditionGroupEditor extends StatelessWidget {
  const ConditionGroupEditor({
    super.key,
    required this.title,
    required this.groups,
    required this.defaultDirection,
    required this.onAddCondition,
    required this.onRemoveCondition,
    required this.onAddGroup,
    required this.onRemoveGroup,
    this.availableTypes,
  });

  final String title;
  final List<List<BacktestCondition>> groups;
  final String defaultDirection;
  final void Function(int groupIndex, BacktestCondition c) onAddCondition;
  final void Function(int groupIndex, int condIndex) onRemoveCondition;
  final VoidCallback onAddGroup;
  final ValueChanged<int> onRemoveGroup;

  /// 這次要開放哪些條件類型可以選，不給的話預設全部開放
  /// （單一股票、多股票組合用）。選股策略會傳入限縮過的清單
  /// （不含技術指標，成交量換成流通性）。
  final List<AddConditionType>? availableTypes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),

          for (int g = 0; g < groups.length; g++) ...[

            if (g > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Text(
                    "OR",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                ),
              ),

            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  if (groups[g].isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        "尚未設定條件",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    )
                  else
                    ...groups[g].asMap().entries.map((entry) {
                      final ci = entry.key;
                      final c = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            if (ci > 0)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Text(
                                  "AND",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                child: Text(c.label,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onRemoveCondition(g, ci),
                            ),
                          ],
                        ),
                      );
                    }),

                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final list = await showAddConditionDialog(
                              context, defaultDirection,
                              availableTypes: availableTypes);
                          if (list != null) {
                            for (final c in list) {
                              onAddCondition(g, c);
                            }
                          }
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text("新增條件"),
                      ),
                      if (groups.length > 1)
                        TextButton.icon(
                          onPressed: () => onRemoveGroup(g),
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: Colors.red),
                          label: const Text(
                            "刪除此群組",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),

                ],
              ),
            ),

          ],

          const SizedBox(height: 6),

          TextButton.icon(
            onPressed: onAddGroup,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text("新增 OR 群組"),
          ),

        ],
      ),
    );
  }
}

void _showVolumeBreakoutHelp(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("大量日判定門檻是什麼？"),
      content: const SingleChildScrollView(
        child: Text(
          "為什麼不能單純選「那段時間成交最多的那天」：\n\n"
          "假設你選20天期間，每天成交量大概都在98萬~103萬股之間"
          "正常波動，剛好有一天量是103萬，數字上是這20天最高的一"
          "天。如果不設門檻，程式就會把那天當成「大量表態日」，"
          "記下當天高低點，之後等股價突破。\n\n"
          "但那天其實只是正常波動裡剛好稍微高一點點，不是真的有"
          "主力進出、法人表態的那種大量——用它的高低點當突破基"
          "準，等於是在對雜訊反應，不是真正的訊號。\n\n"
          "這個門檻就是用來擋掉這種情況：只有真的「量夠大、明顯"
          "突出」的那天才會被採用，不然這個條件當天就不觸發。\n\n"
          "怎麼設定這個數字：\n"
          "• 設 1（或更低）：不設篩選，單純選這段期間成交量"
          "最大的那一天當基準\n"
          "• 設 1.5（預設）：那天的量至少要比整段期間的平均量"
          "明顯突出（多50%以上）才算數\n"
          "• 設更高（例如2、3）：門檻拉更嚴，只挑真正爆量、"
          "非常誇張的那種天",
          style: TextStyle(height: 1.6),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("關閉"),
        ),
      ],
    ),
  );
}

Future<List<BacktestCondition>?> showAddConditionDialog(
  BuildContext context,
  String defaultDirection, {
  List<AddConditionType>? availableTypes,
}) async {

  final types = availableTypes ?? AddConditionType.values;

  AddConditionType type = types.first;

  int fast = 5;
  int slow = 20;
  String direction = defaultDirection;

  // 價格子模式："fixed"(固定數值) / "ma"(均線) / "volume_day"(大量日高低點)
  String priceMode = "fixed";
  final priceController = TextEditingController();
  final Set<int> selectedMaPeriods = {};

  int volPeriod = 20;
  final volMultiplierController = TextEditingController(text: "2.0");

  // 成交量子模式："spike"(爆量倍數) / "new_high"(創新高) / "breakout"(突破大量日高低點)
  String volumeMode = "spike";
  final volBreakoutMinMultiplierController =
      TextEditingController(text: "1.5");

  // 流通性子模式："trading_value"(成交額) / "volume"(成交量)
  String liquidityMode = "trading_value";
  int liquidityWindowDays = 20;
  final liquidityValueController = TextEditingController();

  String fundamentalField = "pe";
  // "threshold"(高於/低於數值) / "new_high"(創新高) / "growth"(成長幅度) / "consistent"(連續維持)
  String fundamentalMode = "threshold";
  String fundamentalOperator = ">"; // 給 threshold 模式用："<"|"<="|"="等
  final fundamentalValueController = TextEditingController();
  int fundamentalQuartersBack = 4;
  int fundamentalQuarters = 4;
  int fundamentalNewHighQuarters = 12; // 創新高的比較範圍，跟consistent的quarters分開

  return showDialog<List<BacktestCondition>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {

          Widget content;

          switch (type) {

            case AddConditionType.technical:
              content = Row(
                children: [
                  DropdownButton<int>(
                    value: fast,
                    items: kMaOptions
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text("MA$m")))
                        .toList(),
                    onChanged: (v) => setDialogState(() => fast = v!),
                  ),
                  const SizedBox(width: 6),
                  DropdownButton<String>(
                    value: direction,
                    items: const [
                      DropdownMenuItem(value: "above", child: Text("向上突破")),
                      DropdownMenuItem(value: "below", child: Text("向下跌破")),
                    ],
                    onChanged: (v) => setDialogState(() => direction = v!),
                  ),
                  const SizedBox(width: 6),
                  DropdownButton<int>(
                    value: slow,
                    items: kMaOptions
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text("MA$m")))
                        .toList(),
                    onChanged: (v) => setDialogState(() => slow = v!),
                  ),
                ],
              );
              break;

            case AddConditionType.price:
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text("固定數值"),
                        selected: priceMode == "fixed",
                        onSelected: (_) =>
                            setDialogState(() => priceMode = "fixed"),
                      ),
                      ChoiceChip(
                        label: const Text("均線"),
                        selected: priceMode == "ma",
                        onSelected: (_) =>
                            setDialogState(() => priceMode = "ma"),
                      ),
                      ChoiceChip(
                        label: const Text("大量日高低點"),
                        selected: priceMode == "volume_day",
                        onSelected: (_) =>
                            setDialogState(() => priceMode = "volume_day"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (priceMode == "volume_day") ...[
                    Row(
                      children: [
                        const Text("近"),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: volPeriod,
                          items: const [5, 10, 20, 60]
                              .map((p) => DropdownMenuItem(
                                  value: p, child: Text("$p日")))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => volPeriod = v!),
                        ),
                        const Text("內成交量最大那天"),
                      ],
                    ),
                    const SizedBox(height: 6),
                    DropdownButton<String>(
                      value: direction,
                      items: const [
                        DropdownMenuItem(
                            value: "above", child: Text("突破那天的高點")),
                        DropdownMenuItem(
                            value: "below", child: Text("跌破那天的低點")),
                      ],
                      onChanged: (v) => setDialogState(() => direction = v!),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: volBreakoutMinMultiplierController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: "大量日判定門檻（選填，已預設1.5倍）",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.help_outline, size: 20),
                          tooltip: "這是什麼？",
                          onPressed: () => _showVolumeBreakoutHelp(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "先在期間內找出成交量最大的那一天，記下那天的高/低點，"
                      "之後股價突破那個價位就觸發",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ] else ...[

                    DropdownButton<String>(
                      value: direction,
                      items: [
                        DropdownMenuItem(
                          value: "above",
                          child: Text(priceMode == "ma" ? "站上" : "股價高於"),
                        ),
                        DropdownMenuItem(
                          value: "below",
                          child: Text(priceMode == "ma" ? "跌破" : "股價低於"),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => direction = v!),
                    ),

                    const SizedBox(height: 6),

                    if (priceMode == "ma")
                      Wrap(
                        spacing: 6,
                        children: kMaOptions.map((m) {
                          final selected = selectedMaPeriods.contains(m);
                          return FilterChip(
                            label: Text("MA$m"),
                            selected: selected,
                            onSelected: (v) {
                              setDialogState(() {
                                if (v) {
                                  selectedMaPeriods.add(m);
                                } else {
                                  selectedMaPeriods.remove(m);
                                }
                              });
                            },
                          );
                        }).toList(),
                      )
                    else
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: "價格",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),

                    if (priceMode == "ma" && selectedMaPeriods.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          "可複選多條均線，每條均線各自新增一筆條件"
                          "（彼此用 AND 組合）",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),

                  ],

                ],
              );
              break;

            case AddConditionType.volume:
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text("爆量倍數"),
                        selected: volumeMode == "spike",
                        onSelected: (_) =>
                            setDialogState(() => volumeMode = "spike"),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("創新高"),
                        selected: volumeMode == "new_high",
                        onSelected: (_) =>
                            setDialogState(() => volumeMode = "new_high"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (volumeMode == "spike") ...[
                    Row(
                      children: [
                        const Text("成交量 >"),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: volPeriod,
                          items: const [5, 10, 20, 60]
                              .map((p) => DropdownMenuItem(
                                  value: p, child: Text("$p日均量")))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => volPeriod = v!),
                        ),
                        const Text(" ×"),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: volMultiplierController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "倍數（例如 2 代表爆量達均量2倍）",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const Text("成交量創"),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: volPeriod,
                          items: const [5, 10, 20, 60, 120]
                              .map((p) => DropdownMenuItem(
                                  value: p, child: Text("$p日")))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => volPeriod = v!),
                        ),
                        const Text("新高"),
                      ],
                    ),
                  ],

                ],
              );
              break;

            case AddConditionType.liquidity:
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text("成交額"),
                        selected: liquidityMode == "trading_value",
                        onSelected: (_) => setDialogState(
                            () => liquidityMode = "trading_value"),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("成交量"),
                        selected: liquidityMode == "volume",
                        onSelected: (_) =>
                            setDialogState(() => liquidityMode = "volume"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      const Text("近"),
                      const SizedBox(width: 6),
                      DropdownButton<int>(
                        value: liquidityWindowDays,
                        items: const [5, 10, 20, 60]
                            .map((d) => DropdownMenuItem(
                                value: d, child: Text("$d日")))
                            .toList(),
                        onChanged: (v) => setDialogState(
                            () => liquidityWindowDays = v!),
                      ),
                      const Text("平均"),
                    ],
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: liquidityValueController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: liquidityMode == "trading_value"
                          ? "成交額大於（億元）"
                          : "成交量大於（張）",
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 6),
                  Text(
                    "用來確保選到的股票有足夠的市場規模跟交易熱度，"
                    "不是挑冷門到很難買賣的股票",
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),

                ],
              );
              break;

            case AddConditionType.fundamental:
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  DropdownButton<String>(
                    isExpanded: true,
                    value: fundamentalField,
                    items: FundamentalField.options
                        .map((f) => DropdownMenuItem(
                            value: f.field, child: Text(f.label)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => fundamentalField = v!),
                  ),

                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text("高於/低於數值"),
                        selected: fundamentalMode == "threshold",
                        onSelected: (_) => setDialogState(
                            () => fundamentalMode = "threshold"),
                      ),
                      ChoiceChip(
                        label: const Text("創新高"),
                        selected: fundamentalMode == "new_high",
                        onSelected: (_) => setDialogState(
                            () => fundamentalMode = "new_high"),
                      ),
                      ChoiceChip(
                        label: const Text("成長幅度"),
                        selected: fundamentalMode == "growth",
                        onSelected: (_) => setDialogState(
                            () => fundamentalMode = "growth"),
                      ),
                      ChoiceChip(
                        label: const Text("連續維持"),
                        selected: fundamentalMode == "consistent",
                        onSelected: (_) => setDialogState(
                            () => fundamentalMode = "consistent"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  if (fundamentalMode == "threshold") ...[
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: fundamentalOperator,
                          items: CompareOperator.options
                              .map((o) => DropdownMenuItem(
                                  value: o.op, child: Text(o.label)))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => fundamentalOperator = v!),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fundamentalValueController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: const InputDecoration(
                              labelText: "數值",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (fundamentalMode == "new_high") ...[
                    Row(
                      children: [
                        const Text("最近"),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: fundamentalNewHighQuarters,
                          items: const [4, 8, 12, 20]
                              .map((q) => DropdownMenuItem(
                                  value: q, child: Text("$q季")))
                              .toList(),
                          onChanged: (v) => setDialogState(
                              () => fundamentalNewHighQuarters = v!),
                        ),
                        const Text("內的新高"),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "最新一季要高於這個範圍內其餘各季，不是跟資料庫"
                      "全部歷史比較",
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ] else if (fundamentalMode == "growth") ...[
                    Row(
                      children: [
                        const Text("跟"),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: fundamentalQuartersBack,
                          items: const [1, 2, 4, 8, 12]
                              .map((q) => DropdownMenuItem(
                                  value: q, child: Text("$q季前")))
                              .toList(),
                          onChanged: (v) => setDialogState(
                              () => fundamentalQuartersBack = v!),
                        ),
                        const Text("比較"),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: direction,
                          items: const [
                            DropdownMenuItem(
                                value: "above", child: Text("成長超過")),
                            DropdownMenuItem(
                                value: "below", child: Text("衰退超過")),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => direction = v!),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fundamentalValueController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: const InputDecoration(
                              labelText: "百分比（%）",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "例如「跟4季前比較、成長超過20%」大約等於年增率門檻",
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const Text("連續"),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: fundamentalQuarters,
                          items: const [2, 3, 4, 6, 8]
                              .map((q) => DropdownMenuItem(
                                  value: q, child: Text("$q季")))
                              .toList(),
                          onChanged: (v) => setDialogState(
                              () => fundamentalQuarters = v!),
                        ),
                        const Text("都要符合"),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: direction,
                          items: const [
                            DropdownMenuItem(
                                value: "above", child: Text("高於")),
                            DropdownMenuItem(
                                value: "below", child: Text("低於")),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => direction = v!),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fundamentalValueController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: const InputDecoration(
                              labelText: "數值",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "不是只看最新一季，是最近N季每一季都要符合門檻，"
                      "用來確認基本面是不是穩定維持，不是曇花一現",
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],

                  const SizedBox(height: 6),
                  Text(
                    "使用當時已公告的最新一季財報數字，不會用到回測當下"
                    "尚未公告的未來財報資料",
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              );
              break;

            case AddConditionType.custom:
              content = const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "此條件類型尚未開放",
                  style: TextStyle(color: Colors.grey),
                ),
              );
              break;
          }

          return AlertDialog(
            title: const Text("新增條件"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  DropdownButton<AddConditionType>(
                    isExpanded: true,
                    value: type,
                    items: [
                      if (types.contains(AddConditionType.technical))
                        const DropdownMenuItem(
                          value: AddConditionType.technical,
                          child: Text("技術指標（均線交叉）"),
                        ),
                      if (types.contains(AddConditionType.price))
                        const DropdownMenuItem(
                          value: AddConditionType.price,
                          child: Text("價格條件"),
                        ),
                      if (types.contains(AddConditionType.volume))
                        const DropdownMenuItem(
                          value: AddConditionType.volume,
                          child: Text("成交量條件"),
                        ),
                      if (types.contains(AddConditionType.liquidity))
                        const DropdownMenuItem(
                          value: AddConditionType.liquidity,
                          child: Text("流通性／規模"),
                        ),
                      if (types.contains(AddConditionType.fundamental))
                        const DropdownMenuItem(
                          value: AddConditionType.fundamental,
                          child: Text("基本面"),
                        ),
                      if (types.contains(AddConditionType.custom))
                        const DropdownMenuItem(
                          value: AddConditionType.custom,
                          child: Text("自訂策略（開發中）"),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => type = v!),
                  ),

                  const SizedBox(height: 12),

                  content,

                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("取消"),
              ),
              FilledButton(
                onPressed: (type == AddConditionType.custom)
                    ? null
                    : () {

                        final List<BacktestCondition> results = [];

                        if (type == AddConditionType.technical) {
                          results.add(BacktestCondition.maCross(
                            fast: fast,
                            slow: slow,
                            direction: direction,
                          ));
                        } else if (type == AddConditionType.price) {

                          if (priceMode == "ma") {
                            if (selectedMaPeriods.isEmpty) return;
                            for (final p in selectedMaPeriods) {
                              results.add(BacktestCondition.priceVsMa(
                                period: p,
                                direction: direction,
                              ));
                            }
                          } else if (priceMode == "volume_day") {
                            final mm = double.tryParse(
                                    volBreakoutMinMultiplierController.text) ??
                                1.5;
                            results.add(BacktestCondition.volumeBreakout(
                              period: volPeriod,
                              direction: direction,
                              minMultiplier: mm,
                            ));
                          } else {
                            final v = double.tryParse(priceController.text);
                            if (v == null) return;
                            results.add(direction == "above"
                                ? BacktestCondition.priceAbove(value: v)
                                : BacktestCondition.priceBelow(value: v));
                          }

                        } else if (type == AddConditionType.volume) {

                          if (volumeMode == "spike") {
                            final m = double.tryParse(
                                volMultiplierController.text);
                            if (m == null) return;
                            results.add(BacktestCondition.volumeSpike(
                              period: volPeriod,
                              multiplier: m,
                            ));
                          } else {
                            results.add(BacktestCondition.volumeNewHigh(
                              period: volPeriod,
                            ));
                          }

                        } else if (type == AddConditionType.liquidity) {

                          final v = double.tryParse(
                              liquidityValueController.text);
                          if (v == null) return;

                          results.add(liquidityMode == "trading_value"
                              ? BacktestCondition.liquidityTradingValueAbove(
                                  value: v,
                                  windowDays: liquidityWindowDays,
                                )
                              : BacktestCondition.liquidityVolumeAbove(
                                  value: v,
                                  windowDays: liquidityWindowDays,
                                ));

                        } else if (type == AddConditionType.fundamental) {

                          if (fundamentalMode == "new_high") {
                            results.add(BacktestCondition.fundamentalNewHigh(
                              field: fundamentalField,
                              quarters: fundamentalNewHighQuarters,
                            ));
                          } else if (fundamentalMode == "growth") {
                            final v = double.tryParse(
                                fundamentalValueController.text);
                            if (v == null) return;
                            results.add(BacktestCondition.fundamentalGrowth(
                              field: fundamentalField,
                              direction: direction,
                              value: v,
                              quartersBack: fundamentalQuartersBack,
                            ));
                          } else if (fundamentalMode == "consistent") {
                            final v = double.tryParse(
                                fundamentalValueController.text);
                            if (v == null) return;
                            results.add(BacktestCondition.fundamentalConsistent(
                              field: fundamentalField,
                              direction: direction,
                              value: v,
                              quarters: fundamentalQuarters,
                            ));
                          } else {
                            final v = double.tryParse(
                                fundamentalValueController.text);
                            if (v == null) return;
                            results.add(
                              (fundamentalOperator == "<" ||
                                      fundamentalOperator == "<=")
                                  ? BacktestCondition.fundamentalBelow(
                                      field: fundamentalField,
                                      value: v,
                                      operator: fundamentalOperator,
                                    )
                                  : BacktestCondition.fundamentalAbove(
                                      field: fundamentalField,
                                      value: v,
                                      operator: fundamentalOperator,
                                    ),
                            );
                          }
                        }

                        Navigator.pop(context, results);
                      },
                child: const Text("新增"),
              ),
            ],
          );
        },
      );
    },
  );
}