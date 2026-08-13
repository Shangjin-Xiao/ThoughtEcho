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

    test('正文里写了 "image" 这串字的短笔记不保活', () {
      // 判定改走 DeltaMediaCache 之前，这里是 `deltaContent.contains('"image"')`，
      // 于是一条只是在讨论 JSON 字段名的短笔记会被误判成「有媒体」而永久保活——
      // 白白钉在 element 树上，每次 setState 陪着重建一遍。
      final delta = jsonEncode([
        {'insert': '这个 {"image": "..."} 字段该怎么存\n'},
      ]);
      expect(delta.contains('"image"'), isTrue);

      final quote = _quote(
        id: 'talks-about-image',
        content: '这个 {"image": "..."} 字段该怎么存',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isFalse);
    });
  });
}
