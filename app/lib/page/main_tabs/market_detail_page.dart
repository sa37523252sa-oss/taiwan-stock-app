import 'package:flutter/material.dart';

import '../technical/technical_tab.dart';

class MarketDetailPage extends StatelessWidget {
  const MarketDetailPage({
    super.key,
    required this.code,
    required this.name,
  });

  final String code;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: TechnicalTab(
        code: code,
        useMarketKline: true,
      ),
    );
  }
}