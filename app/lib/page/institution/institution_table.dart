import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/institution_flow.dart';
import '../../models/investor_setting.dart';
import '../../utils/responsive.dart';

class InstitutionTable extends StatefulWidget {
  const InstitutionTable({
    super.key,
    required this.flows,
    this.selectedDate,
    required this.onSelect,
  });

  final List<InstitutionFlow> flows;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelect;

  @override
  State<InstitutionTable> createState() =>
      _InstitutionTableState();
}

class _InstitutionTableState extends State<InstitutionTable> {

  InvestorPeriod period = InvestorPeriod.day5;

  final _formatter = NumberFormat('#,###');

  String _fmt(double v) {
    final sign = v > 0 ? "+" : (v < 0 ? "-" : "");
    return "$sign${_formatter.format(v.abs().round())}";
  }

  Color _color(double v) {
    if (v > 0) return Colors.red;
    if (v < 0) return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {

    // 平板上字體放大一點
    final labelFontSize = ResponsiveLayout.scaleFont(context, 12.0);
    final periodFontSize = ResponsiveLayout.scaleFont(context, 14.0);
    final valueFontSize = ResponsiveLayout.scaleFont(context, 15.0);

    final days = period.days;

    final recent = widget.flows.length >= days
        ? widget.flows.sublist(widget.flows.length - days)
        : widget.flows;

    double sumForeign = 0;
    double sumTrust = 0;
    double sumDealer = 0;
    double sumTotal = 0;

    for (final f in recent) {
      sumForeign += f.foreign;
      sumTrust += f.trust;
      sumDealer += f.dealer;
      sumTotal += f.total;
    }

    final reversed = widget.flows.reversed.toList();

    return Column(
      children: [

        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 8,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  "日期",
                  style: TextStyle(color: Colors.grey, fontSize: labelFontSize),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    "● 外資",
                    style: TextStyle(color: const Color(0xFF3B82F6), fontSize: labelFontSize),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    "● 投信",
                    style: TextStyle(color: const Color(0xFFEF4444), fontSize: labelFontSize),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    "● 自營商",
                    style: TextStyle(color: const Color(0xFF8B5CF6), fontSize: labelFontSize),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    "合計",
                    style: TextStyle(color: Colors.grey, fontSize: labelFontSize),
                  ),
                ),
              ),
            ],
          ),
        ),

        Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 8,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: DropdownButton<InvestorPeriod>(
                  value: period,
                  underline: const SizedBox(),
                  isDense: true,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: periodFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                  items: InvestorPeriod.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      period = v;
                    });
                  },
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _fmt(sumForeign),
                    style: TextStyle(
                      color: _color(sumForeign),
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _fmt(sumTrust),
                    style: TextStyle(
                      color: _color(sumTrust),
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _fmt(sumDealer),
                    style: TextStyle(
                      color: _color(sumDealer),
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _fmt(sumTotal),
                    style: TextStyle(
                      color: _color(sumTotal),
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.separated(
            itemCount: reversed.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, index) {

              final f = reversed[index];

              final selected = widget.selectedDate != null &&
                  f.date.year == widget.selectedDate!.year &&
                  f.date.month == widget.selectedDate!.month &&
                  f.date.day == widget.selectedDate!.day;

              return InkWell(
                onTap: () => widget.onSelect(f.date),
                child: Container(
                  color: selected
                      ? Colors.grey.shade300
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 8,
                  ),
                  child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        "${f.date.month.toString().padLeft(2, '0')}/"
                        "${f.date.day.toString().padLeft(2, '0')}",
                        style: TextStyle(
                          fontSize: valueFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _fmt(f.foreign),
                          style: TextStyle(
                            color: _color(f.foreign),
                            fontSize: valueFontSize,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _fmt(f.trust),
                          style: TextStyle(
                            color: _color(f.trust),
                            fontSize: valueFontSize,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _fmt(f.dealer),
                          style: TextStyle(
                            color: _color(f.dealer),
                            fontSize: valueFontSize,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _fmt(f.total),
                          style: TextStyle(
                            color: _color(f.total),
                            fontSize: valueFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
              );
            },
          ),
        ),

      ],
    );
  }
}