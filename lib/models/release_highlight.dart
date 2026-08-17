import 'package:flutter/foundation.dart';

/// 更新说明页里的一条内容。
///
/// 内容本身在 `lib/config/release_highlights.dart` 登记，这里只定义形状。
@immutable
class ReleaseHighlight {
  const ReleaseHighlight({
    required this.version,
    required this.lede,
    this.title,
    this.points = const [],
    this.action = ReleaseHighlightAction.none,
    this.isFootnote = false,
  });

  /// 这条内容是**哪个版本加进来的**，也是它唯一的显示判据：用户上次看过的版本
  /// 比它旧，就显示。
  ///
  /// 所以跨版本升级（3.6.5 直接到 4.1.0）不需要任何额外逻辑，区间内所有条目
  /// 自然都会列出来；而 3.7.0 才加的崩溃诊断说明，对 3.7.0 之后升上来的用户
  /// 自然不再出现——**不要为某一条内容写特例判断**。
  final String version;

  /// 导语。整条内容里唯一必填的文字：脚注型条目只有它。
  final String lede;

  /// 标题。脚注型条目（[isFootnote]）没有标题，其余条目都应该给。
  final String? title;

  /// 「核心亮点」下面的分条。为空时整块不渲染。
  ///
  /// 构造后**不要再改这个列表**。类是 `const` 构造的，没法在构造器里换成
  /// `List.unmodifiable` 来强制这一点；实际上也不需要——唯一的生产者
  /// `ReleaseHighlights` 每次调用都现建一份新列表，不对外共享引用。
  final List<ReleaseHighlightPoint> points;

  /// 这条内容附带的行内操作。
  final ReleaseHighlightAction action;

  /// 渲染成页尾的脚注小字，而不是一张卡片。
  ///
  /// 隐私、诊断这类「需要告知但不是卖点」的内容用它：既保证升级路径上一定
  /// 被看到，又不会和真正的新功能抢版面。
  final bool isFootnote;
}

/// 「核心亮点」里的一条：一个短标题加一段说明。
@immutable
class ReleaseHighlightPoint {
  const ReleaseHighlightPoint({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

/// 一条内容可以附带的行内操作。
///
/// 用枚举而不是 `Widget Function()`，是为了让内容登记表保持成纯数据：
/// 交互长什么样属于页面，登记表只声明「这条需要一个主题切换器」。
enum ReleaseHighlightAction {
  /// 没有行内操作。
  none,

  /// 主题风格切换器：当场换、当场看到效果。
  themeStyle,
}
