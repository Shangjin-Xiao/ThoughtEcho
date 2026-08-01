import 'package:flutter/material.dart';

import '../../theme/theme_style.dart';

/// 纸张横线纹理：在卡片背景上画一组等距横线，像笔记本内页。
///
/// 这是整套主题里**唯一**允许的视觉隐喻破例——纹理没法用颜色/形状令牌表达。
/// 但「画不画、画多密、多淡」依然全部是令牌取值：
/// [AppShapeTokens.ruleSpacing] 为 0 时本 widget 直接返回 [child]，不插入任何绘制层。
///
/// 所以这里**没有**、将来也不该有 `if (style == ThemeStyle.paper)`：
/// 新加一套风格只要给 ruleSpacing 赋值就自动有纹理，把它设成 0 就自动没有。
///
/// 只用在计划文档点名的 1–2 处（笔记卡片、每日一言卡），不要铺开。
class PaperRuleBackground extends StatelessWidget {
  const PaperRuleBackground({
    super.key,
    required this.child,
    required this.borderRadius,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final Widget child;

  /// 用来裁切纹理，必须和所在卡片的圆角一致，否则线会溢出圆角。
  final BorderRadius borderRadius;

  /// 顶部/底部留白：横线从 [topInset] 之下开始画，到距底 [bottomInset] 为止。
  /// 卡片顶部通常是标题或元信息行，压着横线不好看。
  final double topInset;
  final double bottomInset;

  /// 关掉纹理绘制，供 widget 测试使用（和卡片阴影、背景模糊的开关同一套路数）。
  static bool disableForTesting = false;

  @override
  Widget build(BuildContext context) {
    if (disableForTesting) return child;

    final tokens = AppShapeTokens.of(context);
    if (tokens.ruleSpacing <= 0 || tokens.ruleOpacity <= 0) return child;

    final color = Theme.of(context)
        .colorScheme
        .outlineVariant
        .withValues(alpha: tokens.ruleOpacity);

    return CustomPaint(
      painter: _PaperRulePainter(
        spacing: tokens.ruleSpacing,
        color: color,
        borderRadius: borderRadius,
        topInset: topInset,
        bottomInset: bottomInset,
      ),
      child: child,
    );
  }
}

class _PaperRulePainter extends CustomPainter {
  const _PaperRulePainter({
    required this.spacing,
    required this.color,
    required this.borderRadius,
    required this.topInset,
    required this.bottomInset,
  });

  final double spacing;
  final Color color;
  final BorderRadius borderRadius;
  final double topInset;
  final double bottomInset;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - bottomInset;
    if (spacing <= 0 || bottom <= topInset) return;

    canvas.save();
    canvas.clipRRect(
      borderRadius.toRRect(Offset.zero & size),
    );

    // 发丝线：宽度设 0 让 Canvas 画一像素物理线，不随 devicePixelRatio 变粗。
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0
      ..isAntiAlias = false;

    for (var y = topInset + spacing; y < bottom; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaperRulePainter oldDelegate) {
    return oldDelegate.spacing != spacing ||
        oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.topInset != topInset ||
        oldDelegate.bottomInset != bottomInset;
  }
}
