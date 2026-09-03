import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/margin_flow.dart';
import '../../utils/responsive.dart';

class MarginTable extends StatelessWidget {
  const MarginTable({
    super.key,
    required this.flows,
  });

  final List<MarginFlow> flows;

  @override
  Widget build(BuildContext context) {

    final labelFontSize = ResponsiveLayout.scaleFont(context, 12.0);
    final valueFontSize = ResponsiveLayout.scaleFont(context, 14.0);
    final changeFontSize = ResponsiveLayout.scaleFont(context, 12.0);

    final formatter = NumberFormat('#,###');

    String fmt(int v) => formatter.format(v);

    String fmtChange(int v) {
      final sign = v > 0 ? "+" : "";
      return "$sign${formatter.format(v)}";
    }

    Color changeColor(int v) {
      if (v > 0) return Colors.red;
      if (v < 0) return Colors.green;
      return Colors.grey;
    }

    final reversed = flows.reversed.toList();

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
                width: 56,
                child: Text(
                  "日期",
                  style: TextStyle(color: Colors.grey, fontSize: labelFontSize),
                ),
              ),
              Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    "融資餘額(增減)",
                    style: TextStyle(color: const Color(0xFFEF4444), fontSize: labelFontSize),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    "融券餘額(增減)",
                    style: TextStyle(color: const Color(0xFF10B981), fontSize: labelFontSize),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    "資券互抵",
                    style: TextStyle(color: const Color(0xFF8B5CF6), fontSize: labelFontSize),
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

              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
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
                      flex: 3,
                      child: Center(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: valueFontSize,
                              color: Colors.black,
                            ),
                            children: [
                              TextSpan(text: fmt(f.marginTodayBalance)),
                              TextSpan(
                                text: " (${fmtChange(f.marginChange)})",
                                style: TextStyle(
                                  fontSize: changeFontSize,
                                  color: changeColor(f.marginChange),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: valueFontSize,
                              color: Colors.black,
                            ),
                            children: [
                              TextSpan(text: fmt(f.shortTodayBalance)),
                              TextSpan(
                                text: " (${fmtChange(f.shortChange)})",
                                style: TextStyle(
                                  fontSize: changeFontSize,
                                  color: changeColor(f.shortChange),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          fmt(f.offsetLoanAndShort),
                          style: TextStyle(
                            fontSize: valueFontSize,
                            color: const Color(0xFF8B5CF6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

      ],
    );
  }
}