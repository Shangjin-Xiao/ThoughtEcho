import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

/// 折叠态的纯文本正文带 `maxLines`，行数由
/// [QuoteContent.collapsedPlainTextMaxLines] 算。它的唯一硬性要求是**只能偏大**：
///
/// - 偏大 → 多排的行落在 160px 折叠盒外面，`ClipRect` 裁掉，用户看不见；
/// - 偏小 → 正文尾巴静悄悄少一截，没有任何提示，而且和「双击展开」的判定对不上。
///
/// 所以这里不断言具体行数（那会随字体和主题漂），只断言
/// `maxLines × 真实行高 ≥ 折叠盒高度`——用真的 `TextPainter` 量出来的真实行高。
void main() {
  const double boxHeight = QuoteContent.collapsedContentMaxHeight;

  /// 用 `TextPainter` 量出这套样式下一行到底多高。
  double realLineHeight(TextStyle style, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: '单行', style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: 1000);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  void expectCoversBox(TextStyle style, TextScaler textScaler) {
    final maxLines = QuoteContent.collapsedPlainTextMaxLines(
      style: style,
      textScaler: textScaler,
    );
    // null 表示放弃截断（整篇都排），永远不会少排内容。
    if (maxLines == null) return;

    final lineHeight = realLineHeight(style, textScaler);
    expect(
      maxLines * lineHeight,
      greaterThanOrEqualTo(boxHeight),
      reason: 'maxLines=$maxLines × 行高=$lineHeight 必须盖满 ${boxHeight}px 的折叠盒，'
          '否则折叠预览会少排内容',
    );
  }

  group('collapsedPlainTextMaxLines 恒偏大', () {
    test('显式行高', () {
      for (final height in [1.0, 1.2, 1.5, 1.8, 2.4]) {
        expectCoversBox(
          TextStyle(fontSize: 16, height: height),
          TextScaler.noScaling,
        );
      }
    });

    test('行高交给字体（height 为 null）', () {
      for (final fontSize in [10.0, 12.0, 14.0, 16.0, 20.0, 28.0]) {
        expectCoversBox(TextStyle(fontSize: fontSize), TextScaler.noScaling);
      }
    });

    test('跟随系统字号缩放', () {
      for (final scale in [0.8, 1.0, 1.3, 2.0, 3.0]) {
        expectCoversBox(
          const TextStyle(fontSize: 16, height: 1.5),
          TextScaler.linear(scale),
        );
      }
    });

    test('样式为 null 时也不能少排', () {
      final maxLines = QuoteContent.collapsedPlainTextMaxLines(
        style: null,
        textScaler: TextScaler.noScaling,
      );
      // 兜底字号 16、行高按 1.0 估，真实行高只会更大，所以 11 行足够盖住 160px。
      expect(maxLines, isNotNull);
      expect(maxLines! * 16.0, greaterThanOrEqualTo(boxHeight));
    });
  });

  group('算不出可信预算时放弃截断，而不是夹一个盖不住盒子的行数', () {
    test('字号和行高同时极小 → 不设 maxLines', () {
      // 预算会超过 64 行的硬上限。夹到 64 的话，64 × 0.0001px 远远盖不住 160px，
      // 正文会被真的截断——放弃截断只是慢，截断是丢内容。
      expect(
        QuoteContent.collapsedPlainTextMaxLines(
          style: const TextStyle(fontSize: 0.01, height: 0.01),
          textScaler: TextScaler.noScaling,
        ),
        isNull,
      );
    });

    test('字号为 0 → 不设 maxLines', () {
      expect(
        QuoteContent.collapsedPlainTextMaxLines(
          style: const TextStyle(fontSize: 0),
          textScaler: TextScaler.noScaling,
        ),
        isNull,
      );
    });

    test('行高非有限 → 不设 maxLines', () {
      expect(
        QuoteContent.collapsedPlainTextMaxLines(
          style: const TextStyle(fontSize: 16, height: double.infinity),
          textScaler: TextScaler.noScaling,
        ),
        isNull,
      );
    });

    test('正常样式仍然给出预算，没有被兜底吞掉', () {
      expect(
        QuoteContent.collapsedPlainTextMaxLines(
          style: const TextStyle(fontSize: 16, height: 1.5),
          textScaler: TextScaler.noScaling,
        ),
        isNotNull,
      );
    });
  });

  group('工作量确实有上界', () {
    test('正文再长，行数预算也不跟着涨', () {
      const style = TextStyle(fontSize: 16, height: 1.5);
      final maxLines = QuoteContent.collapsedPlainTextMaxLines(
        style: style,
        textScaler: TextScaler.noScaling,
      );
      expect(maxLines, isNotNull);

      // 这是整个改动的目的：`RenderParagraph` 不看高度约束，不封顶的话
      // 一条几千字的笔记会把整篇断行整形完，再被 ClipRect 裁到只剩五六行。
      final painter = TextPainter(
        text: TextSpan(text: '很长的正文内容。' * 2000, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
      )..layout(maxWidth: 320);

      expect(painter.didExceedMaxLines, isTrue);
      expect(painter.computeLineMetrics(), hasLength(maxLines));
      // 排出来的高度盖得住折叠盒，裁剪之后的像素和不封顶时一模一样。
      expect(painter.height, greaterThanOrEqualTo(boxHeight));
      painter.dispose();
    });
  });
}
