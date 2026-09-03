import 'holder_level.dart';

class HolderPoint {
  const HolderPoint({
    required this.date,
    required this.bigHolderPercent,
    required this.levelPercent,
  });

  final DateTime date;

  // ⚠️ 「大戶」定義是用猜的：level 數字最大的前 3 級視為大戶
  // （FinMind 慣例通常數字愈大代表持股張數愈多），實際語意
  // 要等資料確認後再調整。
  final double bigHolderPercent;

  // level -> percent，籌碼分布圓餅圖直接用這個
  final Map<String, double> levelPercent;

  /// 把原始逐級資料，依日期分組、算出每天的大戶持股比例。
  static List<HolderPoint> fromLevels(List<HolderLevel> levels) {

    final byDate = <DateTime, List<HolderLevel>>{};

    for (final l in levels) {
      byDate.putIfAbsent(l.date, () => []).add(l);
    }

    final dates = byDate.keys.toList()..sort();

    final points = <HolderPoint>[];

    for (final date in dates) {

      final dayLevels = byDate[date]!;

      final sorted = [...dayLevels]
        ..sort((a, b) {
          final an = int.tryParse(a.level) ?? 0;
          final bn = int.tryParse(b.level) ?? 0;
          return bn.compareTo(an); // 大到小
        });

      final topCount = (sorted.length / 3).ceil().clamp(1, sorted.length);

      double big = 0;
      final levelPercent = <String, double>{};

      for (int i = 0; i < sorted.length; i++) {
        final p = sorted[i].percent ?? 0;
        levelPercent[sorted[i].level] = p;
        if (i < topCount) big += p;
      }

      points.add(HolderPoint(
        date: date,
        bigHolderPercent: big,
        levelPercent: levelPercent,
      ));
    }

    return points;
  }
}