import 'package:flutter/material.dart';

import '../../models/indicator_setting.dart';

class IndicatorSelector extends StatelessWidget {
  const IndicatorSelector({
    super.key,
    required this.indicator,
    required this.onChanged,
  });

  final IndicatorSetting indicator;
  final VoidCallback onChanged;

  Widget _buildChip(
    String text,
    bool checked,
    VoidCallback onTap,
  ) {
    return FilterChip(
      label: Text(text),
      selected: checked,
      onSelected: (_) => onTap(),
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 30,
          child: SegmentedButton<MainIndicator>(
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -3, vertical: -3),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: MainIndicator.ma,
                label: Text("MA"),
              ),
              ButtonSegment(
                value: MainIndicator.boll,
                label: Text("BOLL"),
              ),
            ],
            selected: {indicator.mainIndicator},
            onSelectionChanged: (value) {
              indicator.mainIndicator = value.first;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 4),
        if (indicator.mainIndicator == MainIndicator.ma)
          SizedBox(
            height: 34,
            child: Wrap(
              spacing: 6,
              children: [
                _buildChip("MA5", indicator.ma5, () { indicator.ma5=!indicator.ma5; onChanged(); }),
                _buildChip("MA10", indicator.ma10, () { indicator.ma10=!indicator.ma10; onChanged(); }),
                _buildChip("MA20", indicator.ma20, () { indicator.ma20=!indicator.ma20; onChanged(); }),
                _buildChip("MA60", indicator.ma60, () { indicator.ma60=!indicator.ma60; onChanged(); }),
                _buildChip("MA120", indicator.ma120, () { indicator.ma120=!indicator.ma120; onChanged(); }),
                _buildChip("MA240", indicator.ma240, () { indicator.ma240=!indicator.ma240; onChanged(); }),
              ],
            ),
          )
        else
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Text(
                  "${indicator.bollPeriod}MA",
                  style: const TextStyle(fontSize: 13, color: Colors.purple, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  "±${indicator.bollStd}σ",
                  style: const TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
      ],
    );
  }
}