import 'package:flutter/material.dart';

class MeTab extends StatelessWidget {
  const MeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        "我的 開發中",
        style: TextStyle(color: Colors.grey, fontSize: 15),
      ),
    );
  }
}