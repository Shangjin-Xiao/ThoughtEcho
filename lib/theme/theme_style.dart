import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';

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

  /// 用户没选过墨色时这套风格用哪一支。
  ///
  /// 手工风格过去完全没有个性化维度：选了纸墨就等于放弃动态取色和自定义主色，
  /// 「选它反而少功能」。墨色（[ThemeAccent]）就是补上的那一维——纸色和墨色分开，
  /// 换墨不换纸，风格身份不会因为换了强调色就散掉。
  ///
  /// material 也要给一个值（它不用，但 [ThemeAccent] 的解析路径要有兜底），
  /// 取纸墨的默认支即可。
  ThemeAccent get defaultAccent => switch (this) {
        ThemeStyle.material => ThemeAccent.umber,
        ThemeStyle.paper => ThemeAccent.umber,
        ThemeStyle.plain => ThemeAccent.celadon,
      };

  /// 新装与未做过选择的用户拿到的风格。
  ///
  /// 曾经翻成过 [ThemeStyle.paper]（纸墨是品牌外观），又翻了回来：换默认值意味着
  /// 老用户升级后外观**在他没做任何操作的情况下**变了，而这套主题没有迁移逻辑，
  /// 「变了」就是既成事实。品牌表达不值得用这个代价换——纸与墨改由更新说明页
  /// 介绍并给出一键试用，想要的人一点就有，不想要的人什么都不用做。
  ///
  /// 新装用户同样落在这里：全新安装先给系统观感，风格由他自己在引导页或设置里选。
  ///
  /// 默认值只写在这里一处，其它地方（字段初值、异常兜底）都引用它。
  static const ThemeStyle defaultStyle = ThemeStyle.material;

  static ThemeStyle fromName(String? name) {
    if (name == null) return defaultStyle;
    for (final style in ThemeStyle.values) {
      if (style.name == name) return style;
    }
    return defaultStyle;
  }
}

/// 墨色：手工风格的强调色维度，和风格（纸）、亮暗正交。
///
/// 这是手工风格的**个性化入口**。动态取色和自定义 seed 是 material 专有的能力，
/// 套到手工色板上会把配好的纸色一起推翻重算；墨色则只换强调族，纸色、层次、
/// 字体、纹理全部不动——「换一支笔，不换一叠纸」。
///
/// 每支墨只需要给亮暗两个色值，容器色由 [ThemeAccentColors.resolve] 用**当前风格的
/// 纸色**调出来，所以同一支墨在纸墨（暖）和素笺（冷）下的容器会各自贴合底色，
/// 不需要按风格再写一遍。加第五支墨只要在这里加一个枚举项。
enum ThemeAccent {
  /// 赭石：纸与墨的原色，也是老用户升级前看到的那支。
  umber(light: Color(0xFF7A5530), dark: Color(0xFFC9A077)),

  /// 黛青：素笺的原色。
  celadon(light: Color(0xFF38534F), dark: Color(0xFF8FB5B0)),

  /// 靛蓝。
  indigo(light: Color(0xFF3C4E78), dark: Color(0xFFA3B6E0)),

  /// 朱砂。
  cinnabar(light: Color(0xFF8E3A2C), dark: Color(0xFFE09B84));

  const ThemeAccent({required this.light, required this.dark});

  /// 亮色模式下的墨色。取值全部满足「对纸和卡片两种底色都 ≥ 4.5:1」——
  /// 强调色不只做大色块，它还要当链接文字、图标和小标签用（首页的「今日思考」、
  /// 探索页的「全部」都是），按图形的 3:1 配会糊掉。由 `theme_style_contrast_test`
  /// 对所有「风格 × 墨色 × 亮暗」的组合逐一钉死。
  final Color light;

  /// 暗色模式下的墨色。
  final Color dark;

  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 持久化取值解析。**认不出来返回 null，不要在这里兜底到某一支墨。**
  ///
  /// 「用户没选过」这个状态由 null 表达，兜底到具体某一支会把它永久抹掉：
  /// 存储里出现坏值时若落成当前风格的 [ThemeStyle.defaultAccent]，用户切到另一套
  /// 风格后 `AppTheme.accentFor` 会一直返回上一套风格的默认墨，
  /// 「跟随风格」再也回不来了。兜底属于 `accentFor`，不属于解析。
  static ThemeAccent? tryFromName(String? name) {
    if (name == null) return null;
    for (final accent in ThemeAccent.values) {
      if (accent.name == name) return accent;
    }
    return null;
  }
}

/// 一支墨在某套纸上的完整强调族。
///
/// 容器色是**调出来的**而不是逐个手写：`accent × 纸色` 的组合有
/// 风格数 × 墨数 × 亮暗 这么多，手写一定会漏配、也一定会有人只改一半。
/// 混合比例是两个常量，落地结果由测试逐组合验算。
@immutable
class ThemeAccentColors {
  const ThemeAccentColors({
    required this.accent,
    required this.onAccent,
    required this.container,
    required this.onContainer,
  });

  /// 把一支墨落到一套纸上。
  factory ThemeAccentColors.resolve(
    ThemeAccent accent,
    ThemeStyleColors colors,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    final base = accent.forBrightness(brightness);
    return ThemeAccentColors(
      accent: base,
      // 强调色上的文字用纸色：亮色下是卡片（最白的那张纸），暗色下是页面底色。
      onAccent: isDark ? colors.background : colors.card,
      container: Color.lerp(
        base,
        colors.background,
        isDark ? _containerMixDark : _containerMixLight,
      )!,
      onContainer: Color.lerp(
        base,
        colors.ink,
        isDark ? _onContainerMixDark : _onContainerMixLight,
      )!,
    );
  }

  /// 容器 = 墨色往纸色里兑。比例是「还看得出是哪支墨」和「不喧宾夺主」之间的平衡：
  /// 曾经试过 0.86，四支墨的容器色互相之间只差几个色阶，换墨等于没换。
  static const _containerMixLight = 0.78;
  static const _containerMixDark = 0.76;

  /// 容器上的文字 = 墨色往正文墨里兑。暗色下容器本身已经很深，
  /// 文字只需要往亮处挪一点点，兑太多会失去墨的颜色。
  static const _onContainerMixLight = 0.55;
  static const _onContainerMixDark = 0.32;

  final Color accent;
  final Color onAccent;
  final Color container;
  final Color onContainer;
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
    required this.bodyLineHeight,
    required this.bodyFontScale,
    required this.readingWeightFloor,
    required this.variableWeightCompensation,
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

  /// 阅读文本（display / headline / title / body）的首选字体族。
  /// null 表示用系统默认（material 风格保持原样）。
  ///
  /// 手工风格指向**随包分发**的 [bundledSerif]。之前指的是系统自带衬线体
  /// （通用族名 `serif`），那条路在 iOS 上从未生效，见 [bundledSerif] 的注释。
  /// [fontFamilyFallback] 仍然保留，但角色变了：不再是「字体族没命中时的备胎」，
  /// 而是「子集里没有这个字时去哪儿找」。
  ///
  /// **它不覆盖 `label*`。** 那三级是按钮、胶囊、导航栏这类 11–14sp 的界面标签，
  /// 中文衬线体在这个字号下笔画糊成一团，而且没有人会从一个按钮标签上感知字体风格——
  /// 付出全部可读性代价换不到任何风格辨识度。风格的字体识别度由正文和标题承担。
  /// 见 `AppTheme._applyStyleTypography`。
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  /// 正文行高倍数，直接作用于 `bodyLarge`；`bodyMedium` / `bodySmall` 按
  /// `bodyLineHeight / material.bodyLineHeight` 这个**比例**缩放各自的 M3 默认值，
  /// 所以一个令牌就能整体调松紧，而不会把三级正文压成同一个行高。
  ///
  /// 中文衬线体字面率高、笔画密，M3 给黑体调的 1.5 偏挤，读起来发闷。
  /// 手工风格放到 1.6–1.75 —— 这是「读着舒服」贡献最大的一项，比字重还明显。
  ///
  /// 它同时是 [ruleSpacing] 的来源：横线间距必须等于正文行高，否则文字会逐行
  /// 相对横线漂移。见 [ruleSpacing] 的注释。
  final double bodyLineHeight;

  /// 正文字号缩放，只作用于 `body*` 三级（16 / 14 / 12 各自乘上它）。
  ///
  /// 中文衬线体的横画只有竖画三分之一粗。16sp 配 2x 屏时，一根横画落到大约半个
  /// 物理像素上，抗锯齿后只剩一条浅灰线——**同样的墨色，衬线读起来就是比黑体虚**，
  /// 这跟对比度无关（现有色板全部在 WCAG AA 以上），是笔画物理宽度的问题。
  /// 字号是唯一在所有平台、所有 ROM 上都一定生效的补偿手段：字号涨 6%，
  /// 横画宽度跟着涨 6%，跨过半像素这道坎之后灰度会明显变实。
  ///
  /// 取 1.0625（16 → 17）：整数字号、够到阈值，又不至于让列表和设置项换行。
  /// 标题和标签不缩放——标题字号本来就在横画不失真的区间，标签是黑体。
  ///
  /// 它和 [bodyLineHeight] 一起决定 [ruleSpacing]：横线间距必须等于
  /// 「字号 × 行高」，字号变了横线也得跟着变，否则文字会逐行相对横线漂移。
  final double bodyFontScale;

  /// 阅读文本（`title*` / `body*`）的**最低字重**，0 表示不设下限。所有平台生效。
  ///
  /// 和 [variableWeightCompensation] 是两码事，方向也相反：那个是给**黑体**在
  /// Android Impeller 下变粗做的减重（只跑在 Android），这个是给**衬线体**横画过细
  /// 做的加重（哪儿都跑）。上一轮只是把减重关掉，回到 M3 原生 w400——而 w400 的
  /// 中文衬线本来就偏虚，「不减重」不等于「够粗」。
  ///
  /// 取 500，**现在这是个精确取值**。[bundledSerif] 的字重轴是连续的 400–900，
  /// `TextStyle.fontWeight` 由引擎映射到 wght 轴，500 就是 500，三端一致。
  ///
  /// 换随包字体之前这里只能是「下限 + 听设备的」：系统衬线是可变字体才精确落位，
  /// 只有 Regular / Bold 两档的设备上 500 匹配回 400，等于什么也没发生——
  /// 也就没法判断这个杠杆到底有没有用。现在可以放心调了。
  ///
  /// **是下限不是增量**，这个区别很要紧：M3 的 `titleMedium` / `titleSmall` 本来就是
  /// w500，加增量会把它们顶到 w600，而只有 Regular / Bold 两档的衬线体会把 600
  /// 匹配成 Bold——列表标题会集体变成粗体。抬下限则对它们完全无影响。
  ///
  /// **只作用于 `title*` 和 `body*`**，这是光学尺寸的判断而不是省事：
  /// display / headline 是 24–57sp，横画在那个尺寸上根本不会掉进半像素，
  /// 再加重只会让大标题显得笨重。
  final int readingWeightFloor;

  /// Android 可变字重补偿的强度，0 = 不补偿，1 = 全额补偿。
  ///
  /// `AppTheme._fixAndroidVariableFontWeight` 那套 400→350 的减重，是为了抵消
  /// **黑体**（Roboto / Noto Sans CJK）在 Impeller 精准映射 wght 轴后视觉变粗。
  /// 衬线体横画本来就细，再吃这个减重就会发灰发虚——这正是手工风格「可读性差」
  /// 的一个根因：补偿写在换字体之前，没有随字体族走。
  ///
  /// 所以补偿强度是**令牌取值**而不是风格身份：任何用衬线体的风格设 0 即可，
  /// 且设 0 后 Android 与 iOS/桌面（本来就不跑补偿）的字重终于一致。
  final double variableWeightCompensation;

  double shadowOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? shadowOpacityDark : shadowOpacityLight;

  /// 把一个字重抬到 [readingWeightFloor] 之上：低于下限的抬上来，已经达标的原样返回。
  ///
  /// 抬字重这条规则不止 `textTheme` 一处要用——AppBar 的 `titleTextStyle` 一旦非空
  /// 就不再回落到 `textTheme`，得自己算一遍。规则写在这里，两边就不会走岔。
  FontWeight readingWeight(FontWeight m3Default) =>
      m3Default.value >= readingWeightFloor
          ? m3Default
          : FontWeight(readingWeightFloor);

  /// 随包分发的中文衬线体族名，必须和 `pubspec.yaml` 的 `fonts: - family:` 一致。
  ///
  /// **为什么不再用系统字体。** 这里曾经写通用族名 `serif`，靠 AOSP 从 Android 9
  /// 起给 NotoSerifCJK 标的 `fallbackFor="serif"` 命中系统衬线体。那条路在
  /// Android 上确实有效，但在 iOS 上从未生效：CoreText 不解析通用族名，
  /// `serif` 解析不到时 CJK 字符直接走引擎默认字体（苹方，黑体），而
  /// [TextStyle.fontFamilyFallback] 不是 CSS 的 font-family——它只在
  /// **首选族有这个字形但缺某个字**时逐个回退，首选族整个解析不到时排在后面的
  /// `Songti SC` 根本没机会被查询。所以 iOS 上两套手工风格的正文一直是黑体。
  ///
  /// 换成随包字体之后：族名一定解析得到，三端字形完全一致；更要紧的是
  /// [readingWeightFloor] 从「下限 + 听设备的」变成精确取值——这个字体的字重轴
  /// 是连续的 400–900，`TextStyle.fontWeight` 由引擎映射到 wght 轴，
  /// w500 就是 w500，不再有「设备只有 Regular/Bold 两档所以等于没抬」这回事。
  ///
  /// 代价是包体 +5.2MB，以及子集外的字（生僻字、繁体）会落到
  /// [_systemSerifFallback]。
  static const String bundledSerif = 'NotoSerifSC';

  /// 随包衬线体的 asset 路径，必须和 `pubspec.yaml` 的 `- asset:` 一致。
  ///
  /// 和 [bundledSerif] 放一起是因为这两个值得一起改：族名对不上字体加载不到，
  /// 路径对不上 `rootBundle.load` 直接抛。PDF 导出（`PdfFontService`）和几处
  /// 测试都从这里取，别再各写各的字符串。
  static const String bundledSerifAsset = 'assets/fonts/NotoSerifSC-Subset.ttf';

  /// 子集外字形的去处。
  ///
  /// [bundledSerif] 是 GB2312 子集（约 7800 个字形），覆盖不到的字——生僻人名用字、
  /// 繁体引文、少数民族文字——会按这条链逐个找。**排系统衬线体而不是让它回落到
  /// 引擎默认**，是为了让混排出来的那个字至少还是衬线，而不是段落里突然冒出一个黑体字。
  ///
  /// 链尾不再需要通用族名 `serif`：首选族已经一定解析得到，逐字回退这条路是通的，
  /// 而 `serif` 在 iOS 上本来就解析不到，留着只是噪音。
  static const List<String> _systemSerifFallback = [
    'Songti SC',
    'STSong',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'Source Han Serif SC',
    'SimSun',
  ];

  /// M3 `bodyLarge` 的字号。[ruleSpacing] 由它乘 [bodyFontScale] 再乘
  /// [bodyLineHeight] 推导，因为笔记卡片的正文用的就是 `bodyLarge`
  /// （`quote_item_widget.dart`）。
  static const _bodyLargeFontSize = 16.0;

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
    // M3 bodyLarge 的默认行高（24/16），写在这里是为了让 material 成为其他风格
    // 缩放 bodyMedium/bodySmall 的基准，取值本身不改变 material 的任何像素。
    bodyLineHeight: 1.5,
    bodyFontScale: 1,
    readingWeightFloor: 0,
    variableWeightCompensation: 1,
  );

  /// 衬线风格共用的排版补偿。两套风格的字体族相同，笔画细的问题也就相同，
  /// 补偿量没有理由不同——风格差异由行高、圆角、纹理、色板承担。
  static const _serifFontScale = 1.0625; // 16 → 17
  static const _serifWeightFloor = 500; // 抬起 w400 的那几级，w500 的不动

  static const _paperLineHeight = 1.75;

  /// 纸与墨：纸不该有 18 圆角。小圆角 + 发丝边框 + 极淡投影 + 衬线体。
  static const paper = ThemeStyleForm(
    cardRadius: 6,
    dialogRadius: 8,
    buttonRadius: 4,
    inputRadius: 4,
    fabRadius: 6,
    borderWidth: 1,
    // 0.03 等于没有：纸墨的卡片和页面底色本来就只差一点点，投影再压到看不见，
    // 首页那张大卡就成了一个「空框」。0.05 仍然明显比 material(0.06) 淡，
    // 但足够让卡片从纸面上浮起来一层。层次的另一半由色板承担（card / background
    // 的明度差已经从 1.06 拉到 1.14）。
    shadowOpacityLight: 0.05,
    shadowOpacityDark: 0.14,
    shadowBlur: 6,
    // **必须等于正文行高**，不是随手挑的密度。曾经写死 26，而正文行高是 16×1.5=24，
    // 每往下一行文字就相对横线漂 2px，四五行后完全骑到线上——看起来是「卡片背了一张
    // 格子图」而不是「字写在纸上」。间距等于行高时，文字与横线的相对偏移恒定，
    // 纸感才立得住。
    ruleSpacing: _bodyLargeFontSize * _serifFontScale * _paperLineHeight,
    // 0.55 是横线只画在正文块之前的取值。那时横线铺满整张卡（穿过日期行、图片、
    // 标签胶囊和按钮行），画得淡一点也压不住乱；现在横线只画在正文那一块里，
    // 反而要收着画——它是纸的底纹，不是表格线。
    ruleOpacity: 0.4,
    fontFamily: bundledSerif,
    fontFamilyFallback: _systemSerifFallback,
    bodyLineHeight: _paperLineHeight,
    bodyFontScale: _serifFontScale,
    readingWeightFloor: _serifWeightFloor,
    // 衬线体不吃黑体的减重补偿，否则中文正文发灰发虚。
    variableWeightCompensation: 0,
  );

  /// 素笺：比纸墨更硬朗，接近方角，几乎不用投影。
  static const plain = ThemeStyleForm(
    cardRadius: 3,
    dialogRadius: 4,
    buttonRadius: 2,
    inputRadius: 2,
    fabRadius: 3,
    borderWidth: 1,
    // 同纸墨：抬到肉眼能分辨卡片边界的最低档，仍然远淡于 material。
    shadowOpacityLight: 0.035,
    shadowOpacityDark: 0.10,
    shadowBlur: 4,
    // 素笺是「素」的：不画横线。这也让两套手工风格除了颜色和圆角之外有了真正的差别。
    ruleSpacing: 0,
    ruleOpacity: 0,
    fontFamily: bundledSerif,
    fontFamilyFallback: _systemSerifFallback,
    // 比纸墨紧一档：素笺的性格是硬朗、密实。有了行高令牌，两套手工风格终于不只是
    // 颜色和圆角的差别。仍然比 material 的 1.5 松，因为字体是衬线。
    bodyLineHeight: 1.6,
    bodyFontScale: _serifFontScale,
    readingWeightFloor: _serifWeightFloor,
    variableWeightCompensation: 0,
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

/// 把「页面底色 / 卡片底色 / 记录页底色 / 搜索框底色」四张自绘表面下发给 widget。
///
/// 这四处过去各自调 `ColorUtils.get*BackgroundColor(colorScheme.surface, brightness)`，
/// 那套算法是围绕 **M3 生成色板** 写的：拿 surface 往白色兑一点当卡片、
/// 暗色下直接写死一个中性灰当记录页底色。手工色板里「纸」和「卡片」是色板明确
/// 给出的两档，兑出来的结果既不等于 `card`，暗色下更是把整套暖色纸换成了
/// `0xFF2A2A2A` 这块与色板无关的灰——纸墨暗色下卡片和底色因此完全同色，层次直接塌掉。
///
/// 所以判据仍然是**取值**而不是风格身份：色板给了纸色就用纸色（[fromPalette]），
/// 没给色板的走原来那套算法（[fromScheme]，material 的像素一个不变）。
@immutable
class AppSurfaceTokens extends ThemeExtension<AppSurfaceTokens> {
  const AppSurfaceTokens({
    required this.page,
    required this.card,
    required this.noteList,
    required this.searchBox,
  });

  /// 手工色板：四张表面全部落在色板给的两档纸上。
  ///
  /// 记录页底色刻意等于页面底色——「卡片浮在纸面上」这个关系在亮暗两种模式下
  /// 都由 [ThemeStyleColors.card] 比 [ThemeStyleColors.background] 亮来表达，
  /// 不需要再单独给记录页配一层。
  factory AppSurfaceTokens.fromPalette(ThemeStyleColors colors) =>
      AppSurfaceTokens(
        page: colors.background,
        card: colors.card,
        noteList: colors.background,
        searchBox: Color.lerp(colors.card, colors.background, 0.5)!,
      );

  /// 生成色板（material）：保持迁移前 `ColorUtils` 的算法，逐字搬过来，
  /// 所以 material 风格下这四张表面的像素与迁移前完全一致。
  factory AppSurfaceTokens.fromScheme(
    ColorScheme scheme,
    Brightness brightness,
  ) {
    final surface = scheme.surface;
    final isDark = brightness == Brightness.dark;
    return AppSurfaceTokens(
      page: isDark
          ? surface
          : Color.alphaBlend(surface.withValues(alpha: 0.82), Colors.white),
      card: isDark ? surface : Color.lerp(surface, Colors.white, 0.08)!,
      noteList: isDark
          ? const Color(0xFF2A2A2A)
          : Color.alphaBlend(surface.withValues(alpha: 0.3), Colors.white),
      searchBox: Color.lerp(surface, Colors.white, isDark ? 0.05 : 0.04)!,
    );
  }

  /// 页面通用底色（Scaffold）。
  final Color page;

  /// 自绘卡片底色（首页每日一言卡等）。
  final Color card;

  /// 记录页底色。
  final Color noteList;

  /// 搜索框底色。
  final Color searchBox;

  /// 主题未注册扩展时回退到 material 的取值，避免空断言崩溃。
  static AppSurfaceTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSurfaceTokens>() ??
        AppSurfaceTokens.fromScheme(theme.colorScheme, theme.brightness);
  }

  @override
  AppSurfaceTokens copyWith({
    Color? page,
    Color? card,
    Color? noteList,
    Color? searchBox,
  }) =>
      AppSurfaceTokens(
        page: page ?? this.page,
        card: card ?? this.card,
        noteList: noteList ?? this.noteList,
        searchBox: searchBox ?? this.searchBox,
      );

  @override
  AppSurfaceTokens lerp(ThemeExtension<AppSurfaceTokens>? other, double t) {
    if (other is! AppSurfaceTokens) return this;
    return AppSurfaceTokens(
      page: Color.lerp(page, other.page, t)!,
      card: Color.lerp(card, other.card, t)!,
      noteList: Color.lerp(noteList, other.noteList, t)!,
      searchBox: Color.lerp(searchBox, other.searchBox, t)!,
    );
  }
}

/// 把当前风格的排版令牌下发给 widget。
///
/// 绝大多数排版已经由 `textTheme` 承载，widget 直接读 `theme.textTheme.*` 就够了。
/// 这里只放**够不着 `textTheme` 的那条路**：`flutter_quill` 的 `DefaultStyles`
/// 不继承 `textTheme`，富文本的加粗、标题字重必须单独喂进去
/// （见 `quote_content_widget.dart`）。
///
/// 判据仍然是令牌取值而不是风格身份：widget 里不允许出现 `if (style == ...)`。
@immutable
class AppTypographyTokens extends ThemeExtension<AppTypographyTokens> {
  const AppTypographyTokens({
    required this.variableWeightCompensation,
    required this.readingFontFamily,
  });

  factory AppTypographyTokens.fromForm(ThemeStyleForm form) =>
      AppTypographyTokens(
        variableWeightCompensation: form.variableWeightCompensation,
        readingFontFamily: form.fontFamily,
      );

  /// 见 [ThemeStyleForm.variableWeightCompensation]。
  ///
  /// 富文本里的用法：为 0 时**不能**再把加粗降档。那套降档是给黑体做的，
  /// 而系统中文衬线体常常只有 Regular / Bold 两档，把 w700 降到 w500 会匹配回
  /// Regular——用户标的粗体直接消失，正文里再也分不出重点。
  final double variableWeightCompensation;

  /// 当前风格的阅读字体族，null = 系统默认（[ThemeStyleForm.fontFamily] 的下发）。
  ///
  /// 屏幕上的文字直接读 `textTheme` 就够了，用不着这个。它是给**画到屏幕之外**的
  /// 那条路准备的：PDF 导出走的是 `pdf` 包自己的排版引擎，完全不经过 `textTheme`，
  /// 想让导出的文档和屏幕上是同一种字体，只能把族名单独递过去
  /// （见 `PdfFontService.loadFontSet`）。
  final String? readingFontFamily;

  static AppTypographyTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTypographyTokens>() ??
      AppTypographyTokens.fromForm(ThemeStyleForm.material);

  @override
  AppTypographyTokens copyWith({
    double? variableWeightCompensation,
    String? readingFontFamily,
  }) =>
      AppTypographyTokens(
        variableWeightCompensation:
            variableWeightCompensation ?? this.variableWeightCompensation,
        readingFontFamily: readingFontFamily ?? this.readingFontFamily,
      );

  @override
  AppTypographyTokens lerp(
      ThemeExtension<AppTypographyTokens>? other, double t) {
    if (other is! AppTypographyTokens) return this;
    // 字重降档是个开关而不是连续量，中途插值出来的 0.5 没有意义，
    // 只会让过渡动画里粗体闪一下。跟 ruleSpacing 一样走离散切换。
    return t < 0.5 ? this : other;
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
    required this.secondary,
    required this.tertiary,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.favorite,
    required this.onFavorite,
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
  ///
  /// 取值比「过了 WCAG AA 就行」要保守一档：**四套色板在纸和卡片两种底色上都要
  /// 达到 7:1**，由 `theme_style_contrast_test.dart` 钉死，不是一句口号。
  /// WCAG 只算前景背景两个色值，不看笔画有多宽；同样 6:1 的灰，落在衬线体
  /// 半像素粗的横画上，看到的实际反差要打对折。手工风格用衬线体，
  /// 次要文字就得比黑体的同位色更实一点，读起来才对得上。
  ///
  /// **两种底色都要过**：次要文字大量渲染在卡片上而不是页面底色上，只按底色
  /// 验算会漏。纸墨暗色就是这么漏的——曾取 `0xFFC4B6A8`，底色上 7.66 达标，
  /// 卡片上只有 6.76。
  final Color inkMuted;

  /// 第二、第三辅助色，用于图表和分类标识。
  ///
  /// **不随墨色变**：它们的职责是「在一张图里彼此分得开」，跟着强调色一起转
  /// 会让换墨顺带把图表配色也换掉，而且四支墨各自的第二三色还要再配一遍。
  final Color secondary;
  final Color tertiary;

  /// 危险 / 错误状态。手工色板不能借用 M3 生成的 error，
  /// 否则红色的饱和度会和整套低饱和色板打架。
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  /// 状态语义色（成功 / 警告 / 收藏）。
  ///
  /// 过去这三组是**全局固定**的：`AppTheme` 无论什么风格都注册
  /// `AppSemanticColors.light/dark`，那套值按 M3 的 tonal palette 配，
  /// 落在暖色纸面上就是三块外来色——最扎眼的是笔记卡右下角那颗高饱和红心。
  /// 它们和 [danger] 一样属于色板，不属于 Material。
  ///
  /// 收藏色仍然必须是红的（红心换成主题色就不是红心了），但可以是**这套纸上的**
  /// 那支红：饱和度和明度跟着色板走，而不是照搬 M3 的 tone 40。
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color favorite;
  final Color onFavorite;

  /// 把色板里的状态色下发成主题扩展。material 风格没有色板，仍然用
  /// [AppSemanticColors.light] / [AppSemanticColors.dark]，取值一个不变。
  AppSemanticColors toSemanticColors() => AppSemanticColors(
        success: success,
        successContainer: successContainer,
        onSuccessContainer: onSuccessContainer,
        warning: warning,
        warningContainer: warningContainer,
        onWarningContainer: onWarningContainer,
        favorite: favorite,
        onFavorite: onFavorite,
      );

  /// 映射到 Material 的 [ColorScheme]。
  ///
  /// surfaceContainer 那一族 M3 期望是一条由浅到深的连续梯度，手工色板只给了
  /// 「纸」和「卡片」两档，所以中间档按 [card] → [background] → [outline]
  /// 线性插值补齐，保证组件拿到的层次关系和 M3 一致。
  ColorScheme toColorScheme(Brightness brightness, ThemeAccentColors accent) {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

    return ColorScheme(
      brightness: brightness,
      primary: accent.accent,
      onPrimary: accent.onAccent,
      primaryContainer: accent.container,
      onPrimaryContainer: accent.onContainer,
      secondary: secondary,
      onSecondary: accent.onAccent,
      secondaryContainer: accent.container,
      onSecondaryContainer: accent.onContainer,
      tertiary: tertiary,
      onTertiary: accent.onAccent,
      tertiaryContainer: accent.container,
      onTertiaryContainer: accent.onContainer,
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
      inversePrimary: accent.container,
      surfaceTint: accent.accent,
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
  ///
  /// 页面底色比官网的 `#F9F6F0` 深了一档：那个值和卡片色（近白）只差
  /// 1.06:1，卡片边界在真机上基本看不见，首页那张大卡看着像个空框。
  /// 现在是 1.14:1——仍然是暖白纸，但「纸叠在桌面上」立得住了。
  static const paper = ThemeStylePalette(
    light: ThemeStyleColors(
      background: Color(0xFFF3EEE4),
      card: Color(0xFFFEFDFB),
      outline: Color(0xFFDFD3C2),
      outlineStrong: Color(0xFFCBBBA8),
      ink: Color(0xFF2C2416),
      inkMuted: Color(0xFF5E4C37),
      secondary: Color(0xFF9C5F35),
      tertiary: Color(0xFF4F7355),
      danger: Color(0xFF9B3B3B),
      onDanger: Color(0xFFFEFDFB),
      dangerContainer: Color(0xFFF0DBD5),
      onDangerContainer: Color(0xFF5B1F1F),
      success: Color(0xFF3D6B3F),
      successContainer: Color(0xFFDFE7D5),
      onSuccessContainer: Color(0xFF1E3520),
      warning: Color(0xFF8A5A16),
      warningContainer: Color(0xFFF2E3C8),
      onWarningContainer: Color(0xFF4A2F05),
      // 朱砂红，不是洋红。旧值 0xFFA8324A 的色相是 348°，而这张纸上所有颜色
      // 都在 24–40°（背景 40、赭石 30、次要 24）——差了大半个色环，落在暖纸上
      // 就是一块外来的冷红，也是这套色板里唯一一处这样的。
      // 换成 5° 的朱砂：仍然一眼是红心（这条不能让步），但它是**这张纸上的**
      // 那支红。对比度由 theme_style_contrast_test 逐组合钉死。
      favorite: Color(0xFFA83A31),
      onFavorite: Color(0xFFFEFDFB),
    ),
    dark: ThemeStyleColors(
      background: Color(0xFF231F1A),
      card: Color(0xFF332D27),
      outline: Color(0xFF4A4037),
      outlineStrong: Color(0xFF5D5147),
      ink: Color(0xFFE8DFD5),
      inkMuted: Color(0xFFCBBEB0),
      secondary: Color(0xFFD4895B),
      tertiary: Color(0xFF7CA982),
      danger: Color(0xFFE49595),
      onDanger: Color(0xFF231F1A),
      dangerContainer: Color(0xFF4E2C2C),
      onDangerContainer: Color(0xFFF2C7C7),
      success: Color(0xFF9CC59A),
      successContainer: Color(0xFF2F3A2C),
      onSuccessContainer: Color(0xFFCDE3C7),
      warning: Color(0xFFDFB273),
      warningContainer: Color(0xFF40331E),
      onWarningContainer: Color(0xFFF2DCB8),
      // 同上，暗色下的朱砂。旧值 0xFFE79AA6 是粉色（色相 351°）。
      // 暗色纸要求前景够亮，暖调的亮红必然偏珊瑚，这是色域决定的，不是妥协。
      favorite: Color(0xFFE0998A),
      onFavorite: Color(0xFF231F1A),
    ),
  );

  /// 03 · 素笺（冷）。为避开暖调而专门配的一套。
  static const plain = ThemeStylePalette(
    light: ThemeStyleColors(
      background: Color(0xFFEDEDEA),
      card: Color(0xFFFBFBFA),
      outline: Color(0xFFD8D8D3),
      outlineStrong: Color(0xFFBEBEB8),
      ink: Color(0xFF1F2124),
      inkMuted: Color(0xFF484C50),
      secondary: Color(0xFF56646F),
      tertiary: Color(0xFF6B664F),
      danger: Color(0xFF8F3A3A),
      onDanger: Color(0xFFFBFBFA),
      dangerContainer: Color(0xFFEEDBDB),
      onDangerContainer: Color(0xFF541E1E),
      success: Color(0xFF2F6047),
      successContainer: Color(0xFFD9E6DE),
      onSuccessContainer: Color(0xFF163427),
      warning: Color(0xFF7A5720),
      warningContainer: Color(0xFFEFE2CB),
      onWarningContainer: Color(0xFF42300C),
      favorite: Color(0xFF9C3350),
      onFavorite: Color(0xFFFBFBFA),
    ),
    dark: ThemeStyleColors(
      background: Color(0xFF131516),
      card: Color(0xFF1F2224),
      outline: Color(0xFF313436),
      outlineStrong: Color(0xFF454A4D),
      ink: Color(0xFFE6E7E8),
      inkMuted: Color(0xFFAAB0B5),
      secondary: Color(0xFF9AA8B4),
      tertiary: Color(0xFFB0A98F),
      danger: Color(0xFFE09A9A),
      onDanger: Color(0xFF131516),
      dangerContainer: Color(0xFF452626),
      onDangerContainer: Color(0xFFF0C9C9),
      success: Color(0xFF93C7AC),
      successContainer: Color(0xFF23332B),
      onSuccessContainer: Color(0xFFC6E3D4),
      warning: Color(0xFFD8B57F),
      warningContainer: Color(0xFF38301F),
      onWarningContainer: Color(0xFFEEDCBC),
      favorite: Color(0xFFE39BAA),
      onFavorite: Color(0xFF131516),
    ),
  );
}
