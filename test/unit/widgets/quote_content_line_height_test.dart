import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

/// 折叠判定必须跟着主题风格的行高走。
///
/// 历史背景：富文本的判定曾经读全局 [QuoteContent.estimatedLineHeight]，而这个值
/// 由 `QuoteContent.build` 回填——比**父组件**（`quote_item_widget`）的判定晚一帧。
/// 首帧和刚切换风格的那一帧于是会用上一套风格的行高：纸墨真实行高 17×1.75≈29.75，
/// 初值却是 material 的 24，差 24%，足以让一条实际超过 160px 的笔记被判成
/// 「不需要展开」，展开入口直接不出现。
///
/// 现在判定改成按传入的 style 用 `TextPainter` 实测（见
/// [QuoteContent.exceedsCollapsedHeightForLayout]），行高天然跟着 style 走。全局值
/// 只剩无宽度兜底那条路在用。这里钉住三件事：全局值仍然跟着 style 对齐、
/// **换风格后不会命中上一套风格的缓存**、以及判定确实随行高翻转。
void main() {
  /// 5 个短行的富文本，**末尾带 `\n`**（Quill 的 delta 总是这样收尾，照抄真实数据）。
  ///
  /// 实测口径：5 个非空块各占 1 行（每行都短到不会再折），块间 4 个
  /// `CollapsedRichText.blockGap`，所以高度 = **5 × 行高 + 16**：
  ///
  /// | 风格 | 行高 | 实测高度 | 对 160 的折叠阈值 |
  /// | --- | --- | --- | --- |
  /// | material | 24    | 136.0  | 低 24，不折叠 |
  /// | 纸墨      | 29.75 | 164.75 | 高 4.75，要折叠 |
  ///
  /// 5 行是能卡在阈值两侧的行数。**纸墨那侧 margin 只有 4.75px**，所以改动
  /// `CollapsedRichText.blockGap` 或 `collapsedContentMaxHeight` 会让这里失败——
  /// 那不是误报，是这些常量真的动了折叠行为，需要重新挑行数。
  String fiveShortLinesDelta(String marker) => jsonEncode([
        {'insert': '$marker\n第二行\n第三行\n第四行\n第五行\n'}
      ]);

  Quote richQuote(String marker) => Quote(
        id: 'line-height-$marker',
        content: '$marker\n第二行\n第三行\n第四行\n第五行',
        date: DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        editSource: 'fullscreen',
        deltaContent: fiveShortLinesDelta(marker),
      );

  /// 复刻 `quote_item_widget` 传给判定的正文样式：`textTheme.bodyLarge` 的
  /// 字号与行高。风格令牌是这两项的唯一来源。
  TextStyle bodyLargeFor(ThemeStyle style) {
    final form = style.form;
    return TextStyle(
      fontSize: 16 * form.bodyFontScale,
      height: form.bodyLineHeight,
    );
  }

  bool decideExpansion(Quote quote, ThemeStyle style) {
    return QuoteContent.exceedsCollapsedHeightForLayout(
      quote: quote,
      style: bodyLargeFor(style),
      // 富文本现在按这个宽度实测；400 足够宽，5 个短行都不会再折。
      maxWidth: 400,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    );
  }

  setUp(QuoteContent.resetCaches);

  test('判定入口会把估算行高对齐到传入的正文样式', () {
    decideExpansion(richQuote('material'), ThemeStyle.material);
    expect(QuoteContent.estimatedLineHeight, closeTo(16 * 1.5, 0.001));

    decideExpansion(richQuote('paper'), ThemeStyle.paper);
    expect(QuoteContent.estimatedLineHeight, closeTo(17 * 1.75, 0.001));

    decideExpansion(richQuote('plain'), ThemeStyle.plain);
    expect(QuoteContent.estimatedLineHeight, closeTo(17 * 1.6, 0.001));
  });

  test('同一条笔记换风格后重新判定，不会沿用上一套风格的结果', () {
    // 同一个 quote 实例走两次，缓存键必须把行高的变化算进去。
    final quote = richQuote('same');

    expect(
      decideExpansion(quote, ThemeStyle.material),
      isFalse,
      reason: 'material 下 5×24+16=136，没到 160 的折叠阈值',
    );
    expect(
      decideExpansion(quote, ThemeStyle.paper),
      isTrue,
      reason: '纸墨下 5×29.75+16≈164.75 已经超过阈值，'
          '若仍返回 false 说明命中了 material 那次的缓存，展开入口会消失',
    );
    // 再切回去也要跟着翻，不能被纸墨那次的结果粘住。
    expect(decideExpansion(quote, ThemeStyle.material), isFalse);
  });

  test('判定确实随行高翻转（上面注释里的算式不是拍脑袋）', () {
    // 不靠心算：直接在翻转点两侧各取一个行高，答案必须刚好翻过去。
    // 解 5×行高 + 16 > 160 得翻转点 行高 = 28.8。
    bool decideAtLineHeight(double lineHeight) =>
        QuoteContent.exceedsCollapsedHeightForLayout(
          quote: richQuote('probe-$lineHeight'),
          style: TextStyle(fontSize: 10, height: lineHeight / 10),
          maxWidth: 400,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        );

    expect(decideAtLineHeight(28.0), isFalse, reason: '156 不该超阈值');
    expect(decideAtLineHeight(30.0), isTrue, reason: '166 该超阈值');
  });

  test('无宽度兜底走的仍是估算公式，不是实测', () {
    // maxWidth 非有限 / <= 0 时判定退回 `_estimatePlainTextHeight`。那条公式还活着
    // （末尾空段算 0.5 行、段间距 `_lineSpacing`），但已经没有别的用例覆盖它了，
    // 改动它不会被上面那条实测翻转用例捕获。这里按翻转点两侧各取一个行高钉住。
    bool decideWithoutWidth(double lineHeight) =>
        QuoteContent.exceedsCollapsedHeightForLayout(
          quote: richQuote('nowidth-$lineHeight'),
          style: TextStyle(fontSize: 10, height: lineHeight / 10),
          maxWidth: double.infinity,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        );

    // 兜底口径：5 个非空块各 1 行 + 4 个 blockGap(4px) = 5×行高 + 16。
    // 解 5×行高 + 16 > 160 得翻转点 行高 = 28.8。
    expect(decideWithoutWidth(28.0), isFalse);
    expect(decideWithoutWidth(30.0), isTrue);
  });

  test('style 缺字号或行高时不动全局值，交给 build 回填', () {
    decideExpansion(richQuote('seed'), ThemeStyle.paper);
    final seeded = QuoteContent.estimatedLineHeight;

    QuoteContent.exceedsCollapsedHeightForLayout(
      quote: richQuote('null-style'),
      style: null,
      maxWidth: 400,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    );
    expect(QuoteContent.estimatedLineHeight, seeded);
  });
}
