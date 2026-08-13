import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/delta_rich_text_parser.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_rich_text.dart';

/// `CollapsedRichTextMetrics.plan` 的结果缓存。
///
/// 它是在 `LayoutBuilder` 里被调用的：卡片每重建一次，每个可见块就要重新
/// `TextPainter.layout` 一遍。而记录页里有几十张卡片是永久 keepAlive 的，
/// 一次 `setState` 就是几十次全量重量——这是 08-13 日志里 117.8ms / 123.9ms
/// 建帧的主要来源之一。
///
/// 缓存的正确性只有两条：**相同输入必须给出相同计划**（否则测量和渲染会漂开，
/// 折叠盒高度和实际画出来的内容对不上），**任何进键的参数变了都必须重新算**。
void main() {
  const TextStyle baseStyle = TextStyle(fontSize: 16, height: 1.5);
  const double width = 320;

  setUp(() {
    CollapsedRichTextPlanCache.clear();
    DeltaRichTextCache.clear();
  });

  String longDelta() => jsonEncode([
        {'insert': '${'折叠盒只有 160px，正文可以很长。' * 40}\n'},
      ]);

  CollapsedRichTextPlan planFor(
    String delta, {
    double maxWidth = width,
    bool showMedia = false,
    bool boldPrioritized = false,
    TextStyle style = baseStyle,
    String? cacheContent,
  }) {
    return CollapsedRichTextMetrics.plan(
      blocks: DeltaRichTextCache.of(delta),
      baseStyle: style,
      maxWidth: maxWidth,
      limit: 160,
      showMedia: showMedia,
      cacheContent: cacheContent ?? delta,
      cacheBoldPrioritized: boldPrioritized,
    );
  }

  group('命中', () {
    test('同样的输入第二次命中，且计划逐字段相同', () {
      final delta = longDelta();

      final first = planFor(delta);
      expect(CollapsedRichTextPlanCache.stats['missCount'], 1);
      expect(CollapsedRichTextPlanCache.stats['hitCount'], 0);

      final second = planFor(delta);
      expect(CollapsedRichTextPlanCache.stats['hitCount'], 1);
      expect(CollapsedRichTextPlanCache.stats['missCount'], 1);

      expect(identical(first, second), isTrue);
      expect(second.height, first.height);
      expect(second.entries.length, first.entries.length);
      expect(second.showMedia, first.showMedia);
    });

    test('缓存的计划和不带缓存算出来的一致', () {
      final delta = longDelta();

      final cached = planFor(delta);
      final uncached = CollapsedRichTextMetrics.plan(
        blocks: DeltaRichTextCache.of(delta),
        baseStyle: baseStyle,
        maxWidth: width,
        limit: 160,
        showMedia: false,
      );

      expect(cached.height, uncached.height);
      expect(cached.entries.length, uncached.entries.length);
      for (var i = 0; i < cached.entries.length; i++) {
        expect(cached.entries[i].maxLines, uncached.entries[i].maxLines);
      }
    });

    test('不传 cacheContent 就完全不走缓存', () {
      final delta = longDelta();
      CollapsedRichTextMetrics.plan(
        blocks: DeltaRichTextCache.of(delta),
        baseStyle: baseStyle,
        maxWidth: width,
        limit: 160,
        showMedia: false,
      );
      expect(CollapsedRichTextPlanCache.stats['cacheSize'], 0);
      expect(CollapsedRichTextPlanCache.stats['missCount'], 0);
    });
  });

  group('进键的参数变了就必须重算', () {
    test('宽度', () {
      final delta = longDelta();
      planFor(delta);
      planFor(delta, maxWidth: width - 84); // 挂了缩略图之后的正文宽度
      expect(CollapsedRichTextPlanCache.stats['missCount'], 2);
    });

    test('showMedia', () {
      final delta = jsonEncode([
        {'insert': '带图的笔记\n'},
        {
          'insert': {'image': 'a.png'},
        },
        {'insert': '\n'},
      ]);
      planFor(delta, showMedia: false);
      planFor(delta, showMedia: true);
      expect(CollapsedRichTextPlanCache.stats['missCount'], 2);
    });

    test('加粗优先（blocks 被重排过）', () {
      final delta = longDelta();
      planFor(delta, boldPrioritized: false);
      planFor(delta, boldPrioritized: true);
      expect(CollapsedRichTextPlanCache.stats['missCount'], 2);
    });

    test('基准样式（换主题 / 换字号）', () {
      final delta = longDelta();
      planFor(delta);
      planFor(delta, style: const TextStyle(fontSize: 20, height: 1.5));
      expect(CollapsedRichTextPlanCache.stats['missCount'], 2);
    });

    test('不同笔记不会串味', () {
      final short = jsonEncode([
        {'insert': '短\n'},
      ]);
      final long = longDelta();

      final shortPlan = planFor(short);
      final longPlan = planFor(long);

      expect(longPlan.height, greaterThan(shortPlan.height));
      expect(CollapsedRichTextPlanCache.stats['missCount'], 2);
    });
  });

  group('不把 base64 钉在堆上', () {
    test('计划排到了 data: 内嵌媒体就不进缓存', () {
      // DeltaMediaCache / DeltaRichTextCache 跳过这类笔记是同一个理由：
      // 那个 source 就是整段 base64，缓存住等于常驻若干 MB。
      final delta = jsonEncode([
        {
          'insert': {'image': 'data:image/png;base64,AAAABBBBCCCC'},
        },
        {'insert': '\n'},
      ]);

      planFor(delta, showMedia: true);
      planFor(delta, showMedia: true);

      expect(CollapsedRichTextPlanCache.stats['cacheSize'], 0);
    });

    test('正文长到排不着那张 data: 图时照常缓存', () {
      // 折叠盒只有 160px，前面的正文就把预算吃光了，计划里根本没有那个媒体块，
      // 也就不持有 base64——这种照常缓存，否则长笔记白白失去缓存。
      final delta = jsonEncode([
        {'insert': '${'折叠盒只有 160px，正文可以很长。' * 40}\n'},
        {
          'insert': {'image': 'data:image/png;base64,AAAABBBBCCCC'},
        },
        {'insert': '\n'},
      ]);

      final plan = planFor(delta, showMedia: true);

      expect(plan.entries.any((e) => e.block.isMedia), isFalse);
      expect(CollapsedRichTextPlanCache.stats['cacheSize'], 1);
    });
  });

  test('clear 把计数一起清掉', () {
    planFor(longDelta());
    expect(CollapsedRichTextPlanCache.stats['cacheSize'], 1);

    CollapsedRichTextPlanCache.clear();
    expect(CollapsedRichTextPlanCache.stats['cacheSize'], 0);
    expect(CollapsedRichTextPlanCache.stats['missCount'], 0);
    expect(CollapsedRichTextPlanCache.stats['hitCount'], 0);
  });
}
