import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

Quote _quote({
  required String id,
  required String content,
  String? deltaContent,
  String? editSource,
}) {
  return Quote(
    id: id,
    content: content,
    date: DateTime(2026, 6, 9).toIso8601String(),
    deltaContent: deltaContent,
    editSource: editSource,
  );
}

void main() {
  group('NoteListView.shouldKeepAliveQuoteItem', () {
    test('普通文本不永久保活', () {
      final quote = _quote(
        id: 'plain',
        content: List.filled(8, 'plain text').join('\n'),
        editSource: 'inline',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isFalse);
    });

    test('短 fullscreen 富文本不永久保活', () {
      final delta = jsonEncode([
        {'insert': 'short rich text\n'},
      ]);
      final quote = _quote(
        id: 'short-rich',
        content: 'short rich text',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isFalse);
    });

    test('需要折叠的 fullscreen 富文本保活', () {
      final content = List.filled(12, 'long rich text').join('\n');
      final delta = jsonEncode([
        {'insert': '$content\n'},
      ]);
      final quote = _quote(
        id: 'long-rich',
        content: content,
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isTrue);
    });

    test('包含媒体的 fullscreen 富文本保活', () {
      final delta = jsonEncode([
        {
          'insert': {'image': 'file:///tmp/image.jpg'},
        },
        {'insert': '\n'},
      ]);
      final quote = _quote(
        id: 'image-rich',
        content: 'image',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isTrue);
    });

    test('保活口径由媒体解析决定，不由子串扫描决定', () {
      // 判定原本是三次 `deltaContent.contains(...)`，现在走 DeltaMediaCache。
      // 这里钉住「子串出现 ≠ 有媒体」：`image` 只是某个 op 的属性名时，
      // 子串扫描会当成有媒体而永久保活，解析不会。
      final delta = jsonEncode([
        {
          'insert': '短笔记\n',
          'attributes': {'image': 'not-an-embed'},
        },
      ]);
      expect(delta.contains('"image"'), isTrue);

      final quote = _quote(
        id: 'image-attribute-only',
        content: '短笔记',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isFalse);
    });
  });

  group('NoteListView.calculateAdaptiveKeepAliveRadius', () {
    test('下限不低于 3（总计 7 条），防止极速滑动白屏', () {
      final radiusVerySmall = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 100.0,
        averageCardHeight: 180.0,
      );
      expect(radiusVerySmall, equals(NoteListView.minPlainKeepAliveRadius));
      expect(radiusVerySmall, equals(3));
      expect(radiusVerySmall * 2 + 1, equals(7));
    });

    test('上限不超过 5（总计 11 条），控制离屏 Element 树开销', () {
      final radiusVeryLarge = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 3000.0,
        averageCardHeight: 180.0,
      );
      expect(radiusVeryLarge, equals(NoteListView.maxPlainKeepAliveRadius));
      expect(radiusVeryLarge, equals(5));
      expect(radiusVeryLarge * 2 + 1, equals(11));
    });

    test('视口为空、零或异常时回退到默认值 4（总计 9 条）', () {
      expect(
        NoteListView.calculateAdaptiveKeepAliveRadius(viewportDimension: null),
        equals(NoteListView.defaultPlainKeepAliveRadius),
      );
      expect(
        NoteListView.calculateAdaptiveKeepAliveRadius(viewportDimension: 0),
        equals(NoteListView.defaultPlainKeepAliveRadius),
      );
      expect(
        NoteListView.calculateAdaptiveKeepAliveRadius(viewportDimension: -200),
        equals(NoteListView.defaultPlainKeepAliveRadius),
      );
      expect(
        NoteListView.calculateAdaptiveKeepAliveRadius(
          viewportDimension: double.nan,
        ),
        equals(NoteListView.defaultPlainKeepAliveRadius),
      );
      expect(
        NoteListView.calculateAdaptiveKeepAliveRadius(
          viewportDimension: double.infinity,
        ),
        equals(NoteListView.defaultPlainKeepAliveRadius),
      );
    });

    test('根据视口高度自适应单侧保留 3~5 条卡片', () {
      // 常见小屏或横屏 (约 500dp)
      final radiusSmall = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 500.0,
        averageCardHeight: 180.0,
      );
      expect(radiusSmall, equals(3));

      // 常见手机视口 (约 720dp)
      final radiusStandard = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 720.0,
        averageCardHeight: 180.0,
      );
      expect(radiusStandard, equals(4));

      // 常见长屏手机或平板 (约 950dp)
      final radiusTall = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 950.0,
        averageCardHeight: 180.0,
      );
      expect(radiusTall, equals(5));
    });

    test('根据动态卡片平均高度自适应调整保留半径', () {
      // 卡片较高时（例如 300dp），视口 750dp 对应半径应缩小为 3
      final radiusTallCards = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 750.0,
        averageCardHeight: 300.0,
      );
      expect(radiusTallCards, equals(3));

      // 卡片较矮时（例如 130dp），视口 750dp 对应半径应增大为 5
      final radiusShortCards = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 750.0,
        averageCardHeight: 130.0,
      );
      expect(radiusShortCards, equals(5));
    });

    test('异常卡片高度时回退至估计默认平均高度', () {
      final radiusZeroHeight = NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 720.0,
        averageCardHeight: 0,
      );
      expect(radiusZeroHeight, equals(4));

      final radiusNegativeHeight =
          NoteListView.calculateAdaptiveKeepAliveRadius(
        viewportDimension: 720.0,
        averageCardHeight: -100,
      );
      expect(radiusNegativeHeight, equals(4));
    });
  });
}
