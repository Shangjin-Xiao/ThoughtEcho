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
}
