import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

/// 折叠判定（`exceedsCollapsedHeightForLayout`）是**每张卡片首次布局都要走一遍**的
/// 热路径：它在 `LayoutBuilder` 里跑一次 `TextPainter.layout`。
///
/// 2026-08-13 的诊断点名它"一个计数器都没有"，于是此后每一轮优化都只能猜首滑的
/// 成本落在哪。这个测试钉住计量本身：计数器不动 = 日志里那一栏永远是 0 =
/// 下一轮又要靠猜。
void main() {
  Map<String, dynamic> expansionStats() =>
      QuoteContent.debugCacheStats()['expansion'] as Map<String, dynamic>;

  bool judge(Quote quote) => QuoteContent.exceedsCollapsedHeightForLayout(
        quote: quote,
        style: const TextStyle(fontSize: 16, height: 1.5),
        maxWidth: 300,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      );

  setUp(QuoteContent.clearCacheForTesting);
  tearDown(QuoteContent.clearCacheForTesting);

  test('首次判定记一次 miss，并把实际耗时计进 workMicros', () {
    final quote = Quote(
      id: 'judged-1',
      content: List.filled(40, '折叠判定要真的排一遍版才知道超没超').join('\n'),
      date: DateTime(2026, 8, 18).toIso8601String(),
    );

    expect(expansionStats()['missCount'], 0);

    expect(judge(quote), isTrue);

    expect(expansionStats()['missCount'], 1);
    expect(
      expansionStats()['workMicros'] as int,
      greaterThan(0),
      reason: '真的跑了一次 TextPainter，耗时不该记成 0',
    );
    expect(expansionStats()['worstWorkMicros'] as int, greaterThan(0));
  });

  test('同一条笔记再判定走缓存，只加 hit 不再加 miss', () {
    final quote = Quote(
      id: 'judged-2',
      content: '短到不需要折叠',
      date: DateTime(2026, 8, 18).toIso8601String(),
    );

    judge(quote);
    final workAfterFirst = expansionStats()['workMicros'] as int;

    judge(quote);

    expect(expansionStats()['missCount'], 1);
    expect(expansionStats()['hitCount'], 1);
    expect(
      expansionStats()['workMicros'],
      workAfterFirst,
      reason: '命中缓存不该再累加耗时，否则日志会把命中也算成成本',
    );
  });
}
