import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/delta_media_extractor.dart';

void main() {
  setUp(DeltaMediaCache.clear);

  group('parseDeltaMedia', () {
    test('空输入一律回退到 empty，不抛异常', () {
      expect(parseDeltaMedia(null), DeltaMediaSummary.empty);
      expect(parseDeltaMedia(''), DeltaMediaSummary.empty);
      expect(parseDeltaMedia('[]'), DeltaMediaSummary.empty);
    });

    test('畸形 delta 不该让卡片崩掉', () {
      expect(parseDeltaMedia('这不是 JSON'), DeltaMediaSummary.empty);
      expect(parseDeltaMedia('{"ops": "不是数组"}'), DeltaMediaSummary.empty);
      expect(parseDeltaMedia('null'), DeltaMediaSummary.empty);
    });

    test('纯文本笔记没有媒体', () {
      final delta = jsonEncode([
        {'insert': '只有文字\n'},
      ]);
      final summary = parseDeltaMedia(delta);
      expect(summary.hasMedia, isFalse);
      expect(summary.hasImage, isFalse);
      expect(summary.totalCount, 0);
    });

    test('按出现顺序抽出多张图片', () {
      final delta = jsonEncode([
        {'insert': '前言'},
        {
          'insert': {'image': 'a.png'},
        },
        {'insert': '中间'},
        {
          'insert': {'image': 'b.png'},
        },
        {'insert': '\n'},
      ]);
      final summary = parseDeltaMedia(delta);
      expect(summary.imageSources, ['a.png', 'b.png']);
      expect(summary.firstImageSource, 'a.png');
      expect(summary.totalCount, 2);
    });

    test('视频和音频只计数，不进 imageSources', () {
      final delta = jsonEncode([
        {
          'insert': {'video': 'v.mp4'},
        },
        {
          'insert': {'audio': 'a.m4a'},
        },
        {'insert': '\n'},
      ]);
      final summary = parseDeltaMedia(delta);
      expect(summary.imageSources, isEmpty);
      expect(summary.hasImage, isFalse);
      expect(summary.hasMedia, isTrue);
      expect(summary.videoCount, 1);
      expect(summary.audioCount, 1);
      expect(summary.totalCount, 2);
    });

    test('认 {ops: [...]} 包裹格式', () {
      final delta = jsonEncode({
        'ops': [
          {
            'insert': {'image': 'wrapped.png'},
          },
          {'insert': '\n'},
        ],
      });
      expect(parseDeltaMedia(delta).imageSources, ['wrapped.png']);
    });

    test('image 值是 Map 时按 source/image/url 取', () {
      final delta = jsonEncode([
        {
          'insert': {
            'image': {'source': 'from-source.png'},
          },
        },
        {
          'insert': {
            'image': {'url': 'from-url.png'},
          },
        },
        {'insert': '\n'},
      ]);
      expect(
        parseDeltaMedia(delta).imageSources,
        ['from-source.png', 'from-url.png'],
      );
    });

    test('空 source 的图片被跳过，不产生空字符串条目', () {
      final delta = jsonEncode([
        {
          'insert': {'image': ''},
        },
        {
          'insert': {'image': 'real.png'},
        },
        {'insert': '\n'},
      ]);
      expect(parseDeltaMedia(delta).imageSources, ['real.png']);
    });

    test('imageSources 不可变，调用方改不动缓存里的结果', () {
      final delta = jsonEncode([
        {
          'insert': {'image': 'a.png'},
        },
        {'insert': '\n'},
      ]);
      final summary = parseDeltaMedia(delta);
      expect(() => summary.imageSources.add('b.png'), throwsUnsupportedError);
    });
  });

  group('isDeltaMediaInsert', () {
    test('只有图片/视频/音频三种嵌入算媒体', () {
      expect(isDeltaMediaInsert({'image': 'a.png'}), isTrue);
      expect(isDeltaMediaInsert({'video': 'v.mp4'}), isTrue);
      expect(isDeltaMediaInsert({'audio': 'a.m4a'}), isTrue);
    });

    test('文本和其他嵌入不算媒体', () {
      expect(isDeltaMediaInsert('纯文本'), isFalse);
      expect(isDeltaMediaInsert(null), isFalse);
      expect(isDeltaMediaInsert({'formula': 'x^2'}), isFalse);
    });
  });

  group('DeltaMediaCache', () {
    test('同一份 delta 第二次命中缓存', () {
      final delta = jsonEncode([
        {
          'insert': {'image': 'a.png'},
        },
        {'insert': '\n'},
      ]);

      final first = DeltaMediaCache.of(delta);
      final second = DeltaMediaCache.of(delta);

      expect(identical(first, second), isTrue);
      expect(DeltaMediaCache.stats['hitCount'], 1);
      expect(DeltaMediaCache.stats['missCount'], 1);
    });

    test('内容不同的 delta 各自算一次', () {
      final a = jsonEncode([
        {
          'insert': {'image': 'a.png'},
        },
        {'insert': '\n'},
      ]);
      final b = jsonEncode([
        {
          'insert': {'image': 'b.png'},
        },
        {'insert': '\n'},
      ]);

      expect(DeltaMediaCache.of(a).firstImageSource, 'a.png');
      expect(DeltaMediaCache.of(b).firstImageSource, 'b.png');
      expect(DeltaMediaCache.stats['missCount'], 2);
    });

    test('超出上限后按最久未使用淘汰，缓存不会无界增长', () {
      final maxSize = DeltaMediaCache.stats['maxSize'] as int;
      for (var i = 0; i < maxSize + 60; i++) {
        DeltaMediaCache.of(jsonEncode([
          {
            'insert': {'image': 'img_$i.png'},
          },
          {'insert': '\n'},
        ]));
      }
      expect(DeltaMediaCache.stats['cacheSize'], lessThanOrEqualTo(maxSize));
      // 下界断言：只有上界的话，"of() 因回归完全不写缓存"（cacheSize 恒为 0）
      // 也会让这条测试通过。
      expect(DeltaMediaCache.stats['cacheSize'], greaterThan(0));
    });

    test('空 delta 不进缓存', () {
      DeltaMediaCache.of(null);
      DeltaMediaCache.of('');
      expect(DeltaMediaCache.stats['cacheSize'], 0);
    });
  });
}
