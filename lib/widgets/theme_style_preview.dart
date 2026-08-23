import 'package:flutter/material.dart';

import '../theme/theme_style.dart';
import 'common/paper_rule_background.dart';

/// 主题风格的缩略预览：一张按该风格真实令牌绘制的迷你笔记卡片。
///
/// 之前这里是三条色带，只能表达颜色；而三套风格的差别有一大半在**形状、层次、
/// 字体**上——圆角多大、用边框还是投影、有没有纸张横线、正文是不是衬线。
/// 缩略卡片把这些一次画全，用户不用切过去才知道长什么样。
///
/// 两条纪律和主题其它部分一致：
/// - 画的是「[style] 这个风格长什么样」，**不是当前生效的风格**。所以颜色由外部传入
///   `AppTheme.colorSchemeFor(style, brightness)`，形状取 `style.form`，
///   一律不从 `Theme.of(context)` 取风格相关的东西（那是当前主题）。样张的字体族
///   同理：`form.fontFamily` 为 null 时要落到平台默认黑体，**不能让 TextStyle
///   去继承外层**——外层就是当前风格，material 那张卡会跟着变成宋体。
///   `Theme.of(context).platform` 是唯一的例外，它与风格无关。
/// - 没有 `if (style == ThemeStyle.paper)`。边框还是投影看 `borderWidth > 0`，
///   画不画横线看 `ruleSpacing > 0`，都是令牌**取值**。加第四套风格不用改这里。
class ThemeStylePreview extends StatelessWidget {
  const ThemeStylePreview({
    super.key,
    required this.style,
    required this.brightness,
    required this.colorScheme,
  });

  final ThemeStyle style;
  final Brightness brightness;

  /// 该风格应有的配色，由 `AppTheme.colorSchemeFor` 算出。
  final ColorScheme colorScheme;

  static const double _width = 72;
  static const double _height = 56;

  /// 卡片离预览边缘的留白，露出该风格的页面底色，体现「纸叠在桌面上」的层次。
  static const double _inset = 6;

  /// 横线行距的缩略比例。真实取值 26 在 44 像素高的迷你卡里只画得下一条，
  /// 看不出「横格纸」的意思，所以按比例缩。**开关仍然是 ruleSpacing 是否为 0**，
  /// 缩放只影响画出来的密度。
  static const double _ruleScale = 0.3;

  /// 圆角的缩略比例。迷你卡片只有真实卡片约五分之一宽，直接用 18 会让 material
  /// 那一项糊成一颗药丸，看不出是张卡片。按比例缩之后三套的相对差别原样保留。
  static const double _radiusScale = 0.55;

  @override
  Widget build(BuildContext context) {
    final form = style.form;
    final tokens = AppShapeTokens.fromForm(form, brightness).copyWith(
      cardRadius: form.cardRadius * _radiusScale,
      ruleSpacing: form.ruleSpacing * _ruleScale,
    );
    final cardRadius = BorderRadius.circular(tokens.cardRadius);

    // 用一层 Theme 把预览子树整个切到目标风格：这样 PaperRuleBackground 这类
    // 读令牌的 widget 能直接复用，不必为预览再写一份绘制逻辑。
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: brightness,
        colorScheme: colorScheme,
        extensions: <ThemeExtension<dynamic>>[tokens],
      ),
      child: Container(
        width: _width,
        height: _height,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(tokens.cardRadius + _inset / 2),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(_inset),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: cardRadius,
              // 层次的判据是取值不是风格：有描边宽度就用发丝边框，没有就用投影。
              border: form.borderWidth > 0
                  ? Border.all(
                      color: colorScheme.outlineVariant,
                      width: form.borderWidth,
                    )
                  : null,
              boxShadow: form.borderWidth > 0 ? null : tokens.lowShadow,
            ),
            child: PaperRuleBackground(
              borderRadius: cardRadius,
              topInset: 4,
              bottomInset: 4,
              child: _content(Theme.of(context).platform),
            ),
          ),
        ),
      ),
    );
  }

  /// 卡片内容：一个用该风格字体渲染的「永」，加一条正文示意线和一点强调色。
  /// 「永」是字体样张的传统选字，八个基本笔画齐全，衬线和黑体一眼能分辨。
  ///
  /// [platform] 只用来把 material 那张卡的「没有指定字体族」落成平台默认黑体，
  /// 见 `ThemeStyleForm.resolvedFontFamily`。
  Widget _content(TargetPlatform platform) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '永',
            style: TextStyle(
              fontSize: 17,
              height: 1.1,
              color: colorScheme.onSurface,
              // **不能直接传 form.fontFamily**：material 风格那一项是 null，而 null
              // 在 TextStyle 里的意思是「继承外层」——外层正是当前生效的风格。
              // 用户已经切到纸墨时，material 预览卡的样张会跟着变成宋体，
              // 三张卡看起来字体一样，预览最该说清楚的那件事反而没了。
              fontFamily: style.form.resolvedFontFamily(platform),
              fontFamilyFallback: style.form.fontFamilyFallback,
              // 样张要和正文一致，字重也得过一遍风格的正文下限，
              // 否则预览里的「永」比真正的正文细一档。
              fontWeight: style.form.bodyWeight(FontWeight.w400),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
