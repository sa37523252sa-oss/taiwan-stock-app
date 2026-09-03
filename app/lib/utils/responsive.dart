import 'package:flutter/material.dart';

/// 共用的響應式尺寸工具。
///
/// 問題：CustomPainter 畫圖表時，留白、字體大小、圓點半徑這些
/// 數字如果寫死（例如 leftPadding = 44.0），在手機上看起來剛好，
/// 放到平板（畫布寬度可能是手機的 2~3 倍）就會顯得過小、比例
/// 跑掉——因為畫布變寬了，但留白/字體還是同一個絕對像素值。
///
/// 做法：所有尺寸都不要寫死常數，改成「基準值 × 縮放係數」，
/// 縮放係數依畫布寬度（不是螢幕寬度，是實際拿到的繪圖區域寬度，
/// 因為同一個螢幕上，圖表可能只佔一部分寬度）換算。
class ResponsiveChart {
  const ResponsiveChart._();

  /// 手機基準寬度（低於這個寬度不會再縮小，避免字體小到看不見）
  static const double _baseWidth = 380.0;

  /// 縮放上限（避免在超大平板上，字體/留白被放大到不成比例）
  static const double _maxScale = 1.6;

  /// 縮放下限
  static const double _minScale = 1.0;

  /// 依實際畫布寬度算出縮放係數。
  static double scaleFor(double canvasWidth) {
    final raw = canvasWidth / _baseWidth;
    return raw.clamp(_minScale, _maxScale);
  }

  /// 依畫布寬度換算字體大小。
  static double fontSize(double canvasWidth, double base) {
    return base * scaleFor(canvasWidth);
  }

  /// 依畫布寬度換算留白/邊距。
  static double padding(double canvasWidth, double base) {
    return base * scaleFor(canvasWidth);
  }

  /// 依畫布寬度換算圓點半徑、線寬這類小尺寸元素。
  static double strokeSize(double canvasWidth, double base) {
    return base * scaleFor(canvasWidth);
  }
}

/// 版面斷點（手機 vs 平板），給卡片列表這類 Widget 層級使用，
/// 跟上面 ResponsiveChart（給 CustomPainter 用）是兩套機制。
class ResponsiveLayout {
  const ResponsiveLayout._();

  static const double tabletBreakpoint = 600.0;

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }

  /// 卡片列表在平板上限制最大寬度並置中，避免卡片被拉伸到
  /// 螢幕全寬、內容跟留白比例失衡；手機上維持原本全寬。
  static double contentMaxWidth(BuildContext context) {
    return isTablet(context) ? 720.0 : double.infinity;
  }

  /// 平板上字體/圖示可以比手機大一點，閱讀距離通常也比較遠。
  static double scaleFont(BuildContext context, double base) {
    return isTablet(context) ? base * 1.15 : base;
  }

  static double scalePadding(BuildContext context, double base) {
    return isTablet(context) ? base * 1.3 : base;
  }
}

/// 包住頁面內容，平板上限制最大寬度並置中，手機上不受影響。
/// 用法：把原本 ListView(...) 外面包一層 ResponsiveContentWrapper。
class ResponsiveContentWrapper extends StatelessWidget {
  const ResponsiveContentWrapper({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveLayout.contentMaxWidth(context),
        ),
        child: child,
      ),
    );
  }
}