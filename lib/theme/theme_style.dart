import 'package:flutter/material.dart';

/// 主题风格维度。和亮暗（[ThemeMode]）正交：每种风格都要给全亮暗两套取值。
///
/// [ThemeStyle.material] 保持原有行为不变——真动态取色（`dynamic_color`）、
/// 用户自定义 seed、FlexColorScheme 的 tonal palette 生成。
/// 其余风格是手工色板，不参与取色，色值按下面的 [ThemeStylePalette] 原样落地。
///
/// **加新风格时只需要新增一组 [ThemeStylePalette] 常量并在 [palette] 里登记，
/// 不要碰主题构建逻辑，更不要碰任何 widget。** 任何
/// `if (style == ThemeStyle.paper)` 式的二元判断都是错的：已经确定不止两套。
enum ThemeStyle {
  /// 标准 Material：跟随系统动态取色。
  material,

  /// 纸与墨（暖）：官网 `res/style.css` 色板移植。
  paper,

  /// 素笺（冷）：冷灰纸、蓝黑墨、深青灰强调。
  plain;

  /// 手工色板。[ThemeStyle.material] 没有固定色板（它由取色算法生成），返回 null。
  ThemeStylePalette? get palette => switch (this) {
        ThemeStyle.material => null,
        ThemeStyle.paper => ThemeStylePalette.paper,
        ThemeStyle.plain => ThemeStylePalette.plain,
      };

  /// 形状、字体、阴影令牌。这三样比颜色更能拉开风格辨识度：
  /// 只换颜色的结果就是「换了一套 Material 主题色」。
  ThemeStyleForm get form => switch (this) {
        ThemeStyle.material => ThemeStyleForm.material,
        ThemeStyle.paper => ThemeStyleForm.paper,
        ThemeStyle.plain => ThemeStyleForm.plain,
      };

  /// 是否走取色算法。material 之外的风格都要原样保留手工色值，
  /// 不能再喂给 seed 生成器，否则色板会被算法重新推导掉。
  bool get isGenerated => palette == null;

  /// 新装与未做过选择的用户拿到的风格。
  ///
  /// 2026-08-01 从 [ThemeStyle.material] 翻成 [ThemeStyle.paper]：纸墨是心迹的
  /// 品牌外观，Material 是「想要系统观感」时的退路，不该是默认。
  /// **没有迁移逻辑**——老用户升级后外观会直接变，由升级引导页告知可以切回去。
  ///
  /// 默认值只写在这里一处，其它地方（字段初值、异常兜底）都引用它。
  static const ThemeStyle defaultStyle = ThemeStyle.paper;

  static ThemeStyle fromName(String? name) {
    if (name == null) return defaultStyle;
    for (final style in ThemeStyle.values) {
      if (style.name == name) return style;
    }
    return defaultStyle;
  }
}

/// 一种风格的形状、字体、阴影令牌。
///
/// 这些和颜色一样是纯数值，所以品牌差异全部能通过令牌表达，
/// widget 里不需要出现任何 `if (style == ...)`。
@immutable
class ThemeStyleForm {
  const ThemeStyleForm({
    required this.cardRadius,
    required this.dialogRadius,
    required this.buttonRadius,
    required this.inputRadius,
    required this.fabRadius,
    required this.borderWidth,
    required this.shadowOpacityLight,
    required this.shadowOpacityDark,
    required this.shadowBlur,
    required this.ruleSpacing,
    required this.ruleOpacity,
    required this.fontFamily,
    required this.fontFamilyFallback,
  });

  final double cardRadius;
  final double dialogRadius;
  final double buttonRadius;
  final double inputRadius;

  /// 悬浮按钮圆角。**它有自己的令牌不是遗漏**：M3 规范里 FAB 的圆角本来就独立于
  /// 卡片和按钮（默认 16），硬映射到 cardRadius(18) 或 buttonRadius(12)
  /// 都会让 material 风格出现可见的像素变化。
  final double fabRadius;

  /// 卡片描边宽度。纸的层次靠发丝边框而不是投影，所以手工风格把边框加出来、
  /// 把投影压下去。
  final double borderWidth;

  final double shadowOpacityLight;
  final double shadowOpacityDark;
  final double shadowBlur;

  /// 纸张横线的行距，逻辑像素。**0 表示不画**——这是「要不要纹理」的唯一判据，
  /// 不是风格身份。将来任何一套风格把它设成 0 都会自动没有纹理，不用改 widget。
  ///
  /// 纹理是计划文档里唯一允许的视觉隐喻破例（令牌表达不了纹理本身），
  /// 但「画不画、画多密、多淡」仍然是令牌取值。
  final double ruleSpacing;

  /// 横线相对 `colorScheme.outlineVariant` 的不透明度。
  final double ruleOpacity;

  /// 首选字体族。null 表示用系统默认（material 风格保持原样）。
  ///
  /// 手工风格指向**系统自带**的中文衬线体，不打包任何字体文件——
  /// 增量 0 字节，缺失时按 [fontFamilyFallback] 逐个回退，最终回落到系统默认。
  /// 正文从黑体变衬线，是「纸墨」观感里最省成本的一步。
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  double shadowOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? shadowOpacityDark : shadowOpacityLight;

  /// 各平台自带的中文衬线体，按覆盖面排序。
  /// Songti SC / STSong 是 iOS 和 macOS，Noto Serif CJK SC 和 Source Han Serif
  /// 是 Android 与多数 Linux 发行版，SimSun 是 Windows。
  static const List<String> _systemSerifFallback = [
    'Songti SC',
    'STSong',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'Source Han Serif SC',
    'SimSun',
    'serif',
  ];

  /// 现状：Material 3 默认圆角与投影，系统默认字体。
  static const material = ThemeStyleForm(
    cardRadius: 18,
    dialogRadius: 24,
    buttonRadius: 12,
    inputRadius: 12,
    fabRadius: 16,
    borderWidth: 0,
    shadowOpacityLight: 0.06,
    shadowOpacityDark: 0.24,
    shadowBlur: 12,
    ruleSpacing: 0,
    ruleOpacity: 0,
    fontFamily: null,
    fontFamilyFallback: null,
  );

  /// 纸与墨：纸不该有 18 圆角。小圆角 + 发丝边框 + 极淡投影 + 衬线体。
  static const paper = ThemeStyleForm(
    cardRadius: 6,
    dialogRadius: 8,
    buttonRadius: 4,
    inputRadius: 4,
    fabRadius: 6,
    borderWidth: 1,
    shadowOpacityLight: 0.03,
    shadowOpacityDark: 0.14,
    shadowBlur: 6,
    ruleSpacing: 26,
    ruleOpacity: 0.55,
    fontFamily: 'Songti SC',
    fontFamilyFallback: _systemSerifFallback,
  );

  /// 素笺：比纸墨更硬朗，接近方角，几乎不用投影。
  static const plain = ThemeStyleForm(
    cardRadius: 3,
    dialogRadius: 4,
    buttonRadius: 2,
    inputRadius: 2,
    fabRadius: 3,
    borderWidth: 1,
    shadowOpacityLight: 0.02,
    shadowOpacityDark: 0.10,
    shadowBlur: 4,
    // 素笺是「素」的：不画横线。这也让两套手工风格除了颜色和圆角之外有了真正的差别。
    ruleSpacing: 0,
    ruleOpacity: 0,
    fontFamily: 'Songti SC',
    fontFamilyFallback: _systemSerifFallback,
  );
}

/// 把当前风格的形状令牌下发给 widget。
///
/// `AppTheme.cardRadius` 那组 `static const` 是 material 的取值，无法随风格变化。
/// 自绘表面的 widget 应该改读这里：`AppShapeTokens.of(context).cardRadius`。
@immutable
class AppShapeTokens extends ThemeExtension<AppShapeTokens> {
  const AppShapeTokens({
    required this.cardRadius,
    required this.dialogRadius,
    required this.buttonRadius,
    required this.inputRadius,
    required this.fabRadius,
    required this.borderWidth,
    required this.shadowOpacity,
    required this.shadowBlur,
    required this.ruleSpacing,
    required this.ruleOpacity,
  });

  factory AppShapeTokens.fromForm(
    ThemeStyleForm form,
    Brightness brightness,
  ) {
    return AppShapeTokens(
      cardRadius: form.cardRadius,
      dialogRadius: form.dialogRadius,
      buttonRadius: form.buttonRadius,
      inputRadius: form.inputRadius,
      fabRadius: form.fabRadius,
      borderWidth: form.borderWidth,
      shadowOpacity: form.shadowOpacity(brightness),
      shadowBlur: form.shadowBlur,
      ruleSpacing: form.ruleSpacing,
      ruleOpacity: form.ruleOpacity,
    );
  }

  final double cardRadius;
  final double dialogRadius;
  final double buttonRadius;
  final double inputRadius;
  final double fabRadius;
  final double borderWidth;
  final double shadowOpacity;
  final double shadowBlur;

  /// 纸张横线行距，0 表示不画。见 [ThemeStyleForm.ruleSpacing]。
  final double ruleSpacing;
  final double ruleOpacity;

  /// 四档投影，对应 `AppTheme` 里那四组 `static const`：
  /// [restShadow]≈defaultShadow、[lowShadow]≈lightShadow、
  /// [raisedShadow]≈hoverShadow、[accentShadow]≈accentShadow。
  ///
  /// 静态常量没法随风格变化，导致「圆角迁移了、投影忘了」——纸墨下卡片方了但还浮着。
  /// 这四个 getter 由 [shadowOpacity] / [shadowBlur] 按固定比例推导，
  /// material 取值下与原静态常量在肉眼无差的范围内（alpha 差 < 0.002），
  /// 手工风格下自动跟着压扁。
  ///
  /// 自绘表面用这些，不要再引用 `AppTheme.*Shadow`。
  List<BoxShadow> get restShadow => _shadow(const [
        (4 / 3, 1.0, 4.0, -2.0),
        (2 / 3, 2.0, 8.0, -4.0),
      ]);

  List<BoxShadow> get lowShadow => _shadow(const [
        (1.0, 2 / 3, 2.0, -1.0),
      ]);

  List<BoxShadow> get raisedShadow => _shadow(const [
        (5 / 3, 4 / 3, 6.0, -2.0),
        (5 / 6, 8 / 3, 12.0, -6.0),
      ]);

  List<BoxShadow> get accentShadow => _shadow(const [
        (2.0, 5 / 3, 8.0, -4.0),
        (4 / 3, 10 / 3, 16.0, -8.0),
      ]);

  /// `(alpha 倍率, blur 倍率, dy, spread)` → 一层投影。
  List<BoxShadow> _shadow(
    List<(double, double, double, double)> layers,
  ) {
    if (shadowOpacity <= 0) return const <BoxShadow>[];
    return [
      for (final (alphaScale, blurScale, dy, spread) in layers)
        BoxShadow(
          color: const Color(0xFF000000)
              .withValues(alpha: (shadowOpacity * alphaScale).clamp(0.0, 1.0)),
          blurRadius: shadowBlur * blurScale,
          offset: Offset(0, dy),
          spreadRadius: spread,
        ),
    ];
  }

  /// 主题未注册扩展时回退到 material 取值，避免空断言崩溃。
  static AppShapeTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppShapeTokens>() ??
        AppShapeTokens.fromForm(ThemeStyleForm.material, theme.brightness);
  }

  @override
  AppShapeTokens copyWith({
    double? cardRadius,
    double? dialogRadius,
    double? buttonRadius,
    double? inputRadius,
    double? fabRadius,
    double? borderWidth,
    double? shadowOpacity,
    double? shadowBlur,
    double? ruleSpacing,
    double? ruleOpacity,
  }) {
    return AppShapeTokens(
      cardRadius: cardRadius ?? this.cardRadius,
      dialogRadius: dialogRadius ?? this.dialogRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      inputRadius: inputRadius ?? this.inputRadius,
      fabRadius: fabRadius ?? this.fabRadius,
      borderWidth: borderWidth ?? this.borderWidth,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      ruleSpacing: ruleSpacing ?? this.ruleSpacing,
      ruleOpacity: ruleOpacity ?? this.ruleOpacity,
    );
  }

  @override
  AppShapeTokens lerp(ThemeExtension<AppShapeTokens>? other, double t) {
    if (other is! AppShapeTokens) return this;
    double mix(double a, double b) => a + (b - a) * t;
    return AppShapeTokens(
      cardRadius: mix(cardRadius, other.cardRadius),
      dialogRadius: mix(dialogRadius, other.dialogRadius),
      buttonRadius: mix(buttonRadius, other.buttonRadius),
      inputRadius: mix(inputRadius, other.inputRadius),
      fabRadius: mix(fabRadius, other.fabRadius),
      borderWidth: mix(borderWidth, other.borderWidth),
      shadowOpacity: mix(shadowOpacity, other.shadowOpacity),
      shadowBlur: mix(shadowBlur, other.shadowBlur),
      // 行距**不能**插值：从 0（无纹理）过渡到 26 会经过 0 附近的极小值，
      // 绘制循环的次数按 1/spacing 爆炸。改成离散切换，淡入淡出交给 ruleOpacity。
      ruleSpacing: t < 0.5 ? ruleSpacing : other.ruleSpacing,
      ruleOpacity: mix(ruleOpacity, other.ruleOpacity),
    );
  }
}

/// 一种风格在一个亮度下的语义角色取值。
///
/// 角色名按「纸墨」的语汇取，而不是 Material 的槽位名——色板是先按纸和墨设计的，
/// 映射到 [ColorScheme] 是后一步（见 [toColorScheme]）。
@immutable
class ThemeStyleColors {
  const ThemeStyleColors({
    required this.background,
    required this.card,
    required this.outline,
    required this.outlineStrong,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.secondary,
    required this.tertiary,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
  });

  /// 页面底色（纸）。
  final Color background;

  /// 卡片底色，比 [background] 更亮（亮色）或更浅（暗色），制造纸张叠放的层次。
  final Color card;

  /// 常规描边。
  final Color outline;

  /// 强调描边，也是笔记本横线的颜色。
  final Color outlineStrong;

  /// 正文墨色。
  final Color ink;

  /// 次要墨色，用于辅助文字和图标。
  final Color inkMuted;

  /// 强调色。
  final Color accent;

  /// 绘制在 [accent] 之上的文字。
  final Color onAccent;

  /// 强调色的浅色容器。
  final Color accentContainer;

  /// 绘制在 [accentContainer] 之上的文字。
  final Color onAccentContainer;

  /// 第二、第三辅助色，用于图表和分类标识。
  final Color secondary;
  final Color tertiary;

  /// 危险 / 错误状态。手工色板不能借用 M3 生成的 error，
  /// 否则红色的饱和度会和整套低饱和色板打架。
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  /// 映射到 Material 的 [ColorScheme]。
  ///
  /// surfaceContainer 那一族 M3 期望是一条由浅到深的连续梯度，手工色板只给了
  /// 「纸」和「卡片」两档，所以中间档按 [card] → [background] → [outline]
  /// 线性插值补齐，保证组件拿到的层次关系和 M3 一致。
  ColorScheme toColorScheme(Brightness brightness) {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

    return ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentContainer,
      onPrimaryContainer: onAccentContainer,
      secondary: secondary,
      onSecondary: onAccent,
      secondaryContainer: accentContainer,
      onSecondaryContainer: onAccentContainer,
      tertiary: tertiary,
      onTertiary: onAccent,
      tertiaryContainer: accentContainer,
      onTertiaryContainer: onAccentContainer,
      error: danger,
      onError: onDanger,
      errorContainer: dangerContainer,
      onErrorContainer: onDangerContainer,
      surface: background,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      surfaceDim: mix(background, outline, 0.25),
      surfaceBright: card,
      surfaceContainerLowest: card,
      surfaceContainerLow: mix(card, background, 0.5),
      surfaceContainer: background,
      surfaceContainerHigh: mix(background, outline, 0.35),
      surfaceContainerHighest: mix(background, outline, 0.6),
      outline: outlineStrong,
      outlineVariant: outline,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: ink,
      onInverseSurface: background,
      inversePrimary: accentContainer,
      surfaceTint: accent,
    );
  }
}

/// 一种风格的亮暗两套取值。
@immutable
class ThemeStylePalette {
  const ThemeStylePalette({
    required this.light,
    required this.dark,
  });

  final ThemeStyleColors light;
  final ThemeStyleColors dark;

  ThemeStyleColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 02 · 纸与墨（暖）。取值移植自官网 `res/style.css`。
  static const paper = ThemeStylePalette(
    light: ThemeStyleColors(
      background: Color(0xFFF9F6F0),
      card: Color(0xFFFEFDFB),
      outline: Color(0xFFE3D9CC),
      outlineStrong: Color(0xFFD4C5B9),
      ink: Color(0xFF2C2416),
      inkMuted: Color(0xFF6B5842),
      accent: Color(0xFF8A6440),
      onAccent: Color(0xFFFEFDFB),
      accentContainer: Color(0xFFEFE4D6),
      onAccentContainer: Color(0xFF4A3722),
      secondary: Color(0xFF9C5F35),
      tertiary: Color(0xFF4F7355),
      danger: Color(0xFF9B3B3B),
      onDanger: Color(0xFFFEFDFB),
      dangerContainer: Color(0xFFF5DCDC),
      onDangerContainer: Color(0xFF5B1F1F),
    ),
    dark: ThemeStyleColors(
      background: Color(0xFF2A2520),
      card: Color(0xFF342E28),
      outline: Color(0xFF4A4037),
      outlineStrong: Color(0xFF5D5147),
      ink: Color(0xFFE8DFD5),
      inkMuted: Color(0xFFB8A99A),
      accent: Color(0xFFC9A077),
      onAccent: Color(0xFF2A2520),
      accentContainer: Color(0xFF423931),
      onAccentContainer: Color(0xFFE0C9AE),
      secondary: Color(0xFFD4895B),
      tertiary: Color(0xFF7CA982),
      danger: Color(0xFFE49595),
      onDanger: Color(0xFF2A2520),
      dangerContainer: Color(0xFF4E2C2C),
      onDangerContainer: Color(0xFFF2C7C7),
    ),
  );

  /// 03 · 素笺（冷）。为避开暖调而专门配的一套。
  static const plain = ThemeStylePalette(
    light: ThemeStyleColors(
      background: Color(0xFFF4F4F2),
      card: Color(0xFFFBFBFA),
      outline: Color(0xFFDCDCD8),
      outlineStrong: Color(0xFFC4C4BF),
      ink: Color(0xFF1F2124),
      inkMuted: Color(0xFF5F6368),
      accent: Color(0xFF3F5D5B),
      onAccent: Color(0xFFFBFBFA),
      accentContainer: Color(0xFFE3EAE9),
      onAccentContainer: Color(0xFF233937),
      secondary: Color(0xFF56646F),
      tertiary: Color(0xFF6B664F),
      danger: Color(0xFF8F3A3A),
      onDanger: Color(0xFFFBFBFA),
      dangerContainer: Color(0xFFF2DDDD),
      onDangerContainer: Color(0xFF541E1E),
    ),
    dark: ThemeStyleColors(
      background: Color(0xFF17191A),
      card: Color(0xFF1F2224),
      outline: Color(0xFF313436),
      outlineStrong: Color(0xFF454A4D),
      ink: Color(0xFFE6E7E8),
      inkMuted: Color(0xFF9DA2A7),
      accent: Color(0xFF8FB5B0),
      onAccent: Color(0xFF17191A),
      accentContainer: Color(0xFF26302F),
      onAccentContainer: Color(0xFFB3D1CD),
      secondary: Color(0xFF9AA8B4),
      tertiary: Color(0xFFB0A98F),
      danger: Color(0xFFE09A9A),
      onDanger: Color(0xFF17191A),
      dangerContainer: Color(0xFF452626),
      onDangerContainer: Color(0xFFF0C9C9),
    ),
  );
}
