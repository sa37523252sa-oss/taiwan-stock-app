import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../utils/responsive.dart';

class HolderPieChart extends StatelessWidget {
  const HolderPieChart({
    super.key,
    required this.levelPercent,
    this.date,
  });

  final Map<String, double> levelPercent;
  final DateTime? date;

  static const colors = [
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFF6366F1),
    Color(0xFF14B8A6),
    Color(0xFF84CC16),
    Color(0xFFF97316),
  ];

  int _levelOrder(String level) => int.tryParse(level) ?? 0;

  @override
  Widget build(BuildContext context) {

    if (levelPercent.isEmpty) {
      return const Center(
        child: Text("沒有籌碼分布資料"),
      );
    }

    // PieChart 的半徑是寫死像素，平板上（畫布較大）要放大，
    // 不然圓餅圖看起來過小、周圍留白過多。
    final isTablet = ResponsiveLayout.isTablet(context);
    final pieScale = isTablet ? 1.4 : 1.0;
    final dateFontSize = ResponsiveLayout.scaleFont(context, 12.0);
    final titleFontSize = ResponsiveLayout.scaleFont(context, 11.0);
    final legendFontSize = ResponsiveLayout.scaleFont(context, 11.0);

    final entries = levelPercent.entries.toList()
      ..sort((a, b) => _levelOrder(a.key).compareTo(_levelOrder(b.key)));

    return Column(
      children: [

        if (date != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "資料日期 ${date!.year}/${date!.month}/${date!.day}",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: dateFontSize,
              ),
            ),
          ),

        Expanded(
          child: PieChart(
            PieChartData(
              sections: [
                for (int i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value,
                    color: colors[i % colors.length],
                    title: entries[i].value >= 3
                        ? "${entries[i].value.toStringAsFixed(1)}%"
                        : "",
                    radius: 90 * pieScale,
                    titleStyle: TextStyle(
                      fontSize: titleFontSize,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
              sectionsSpace: 2,
              centerSpaceRadius: 40 * pieScale,
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (int i = 0; i < entries.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      color: colors[i % colors.length],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Level ${entries[i].key}",
                      style: TextStyle(fontSize: legendFontSize),
                    ),
                  ],
                ),
            ],
          ),
        ),

      ],
    );
  }
}