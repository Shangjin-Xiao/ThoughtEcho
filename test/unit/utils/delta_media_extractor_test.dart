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

    test('多图只保留首图 source，其余计数', () {
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
      expect(summary.firstImageSource, 'a.png');
      expect(summary.imageCount, 2);
      expect(summary.totalCount, 2);
    });

    test('视频和音频只计数，不占 firstImageSource', () {
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
      expect(summary.firstImageSource, isNull);
      expect(summary.hasImage, isFalse);
      expect(summary.hasMedia, isTrue);
      expect(summary.videoCount, 1);
      expect(summary.audioCount, 1);
      expect(summary.totalCount, 2);
    });

    test('音频走 custom 嵌入也要认出来', () {
      // 本项目的音频是 CustomBlockEmbed，序列化成 insert.custom.audio，
      // 不在顶层。只认顶层会让折叠态漏掉音频：既不计角标，也不会被剥离，
      // 于是滚动列表里照旧实例化 MediaPlayerWidget。
      final delta = jsonEncode([
        {
          'insert': {
            'custom': {'audio': '/path/rec.m4a'},
          },
        },
        {'insert': '\n'},
      ]);
      final summary = parseDeltaMedia(delta);
      expect(summary.audioCount, 1);
      expect(summary.hasMedia, isTrue);
      expect(summary.totalCount, 1);
    });

    test('custom 被序列化成 JSON 字符串时同样认', () {
      final delta = jsonEncode([
        {
          'insert': {'custom': '{"audio":"/path/rec.m4a"}'},
        },
        {'insert': '\n'},
      ]);
      expect(parseDeltaMedia(delta).audioCount, 1);
    });

    test('custom 里放的不是媒体则不计入', () {
      final delta = jsonEncode([
        {
          'insert': {
            'custom': {'formula': 'x^2'},
          },
        },
        {'insert': '\n'},
      ]);
      expect(parseDeltaMedia(delta).hasMedia, isFalse);
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
      expect(parseDeltaMedia(delta).firstImageSource, 'wrapped.png');
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
      final summary = parseDeltaMedia(delta);
      expect(summary.firstImageSource, 'from-source.png');
      expect(summary.imageCount, 2);
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
      final summary = parseDeltaMedia(delta);
      expect(summary.firstImageSource, 'real.png');
      expect(summary.imageCount, 1);
    });
  });

  group('isDeltaMediaInsert', () {
    test('只有图片/视频/音频三种嵌入算媒体', () {
      expect(isDeltaMediaInsert({'image': 'a.png'}), isTrue);
      expect(isDeltaMediaInsert({'video': 'v.mp4'}), isTrue);
      expect(isDeltaMediaInsert({'audio': 'a.m4a'}), isTrue);
    });

    test('custom 下的音频同样算媒体（本项目音频的真实形状）', () {
      expect(
        isDeltaMediaInsert({
          'custom': {'audio': '/path/rec.m4a'},
        }),
        isTrue,
      );
      expect(
        isDeltaMediaInsert({'custom': '{"audio":"/path/rec.m4a"}'}),
        isTrue,
      );
    });

    test('文本和其他嵌入不算媒体', () {
      expect(isDeltaMediaInsert('纯文本'), isFalse);
      expect(isDeltaMediaInsert(null), isFalse);
      expect(isDeltaMediaInsert({'formula': 'x^2'}), isFalse);
      expect(
        isDeltaMediaInsert({
          'custom': {'formula': 'x^2'},
        }),
        isFalse,
      );
      expect(isDeltaMediaInsert({'custom': '不是 JSON'}), isFalse);
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

    test('首图是 data: URL 时不进缓存，避免把整段 base64 长期钉在堆上', () {
      final delta = jsonEncode([
        {
          'insert': {'image': 'data:image/png;base64,AAAABBBBCCCC'},
        },
        {'insert': '\n'},
      ]);

      final summary = DeltaMediaCache.of(delta);
      // 结果照常返回，只是不留在缓存里。
      expect(summary.imageCount, 1);
      expect(DeltaMediaCache.stats['cacheSize'], 0);

      DeltaMediaCache.of(delta);
      expect(DeltaMediaCache.stats['missCount'], 2);
      expect(DeltaMediaCache.stats['hitCount'], 0);
    });

    test('内容不同但长度相同的 delta 不会串味', () {
      // 键除了整串 hashCode 和长度，还带首尾切片的哈希，
      // 单靠前两者相等已不足以命中。
      final a = jsonEncode([
        {
          'insert': {'image': 'aaa.png'},
        },
        {'insert': '\n'},
      ]);
      final b = jsonEncode([
        {
          'insert': {'image': 'bbb.png'},
        },
        {'insert': '\n'},
      ]);
      expect(a.length, b.length);
      expect(DeltaMediaCache.of(a).firstImageSource, 'aaa.png');
      expect(DeltaMediaCache.of(b).firstImageSource, 'bbb.png');
    });
  });
}
