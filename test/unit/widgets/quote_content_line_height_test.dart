import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

/// 富文本的折叠判定读的是全局 [QuoteContent.estimatedLineHeight]，而这个值由
/// `QuoteContent.build` 回填——比**父组件**（`quote_item_widget`）的折叠判定晚一帧。
///
/// 结果就是首帧、以及刚切换主题风格的那一帧，判定会用上一套风格的行高：
/// 纸墨真实行高 17×1.75≈29.75，初值却是 material 的 24，差 24%，足以让一条实际
/// 超过 160px 的笔记被判成「不需要展开」，展开入口直接不出现。
///
/// 修法是在判定入口前先按传入的 style 对齐行高。这里钉住两件事：对齐本身，
/// 以及**换风格后不会命中上一套风格的缓存**。
void main() {
  /// 5 个短行的富文本。估算高度 = 5×行高 + 4×行间距(4)：
  /// material 24 → 136，不超过 160 的折叠阈值；
  /// 纸墨 29.75 → 168.75，超过。刚好卡在阈值两侧，风格一换答案就得翻。
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
      // 富文本不看宽度，走静态估算；给个有限值让它不提前短路。
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
      reason: '纸墨下 5×29.75+16≈165 已经超过阈值，'
          '若仍返回 false 说明命中了 material 那次的缓存，展开入口会消失',
    );
    // 再切回去也要跟着翻，不能被纸墨那次的结果粘住。
    expect(decideExpansion(quote, ThemeStyle.material), isFalse);
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
