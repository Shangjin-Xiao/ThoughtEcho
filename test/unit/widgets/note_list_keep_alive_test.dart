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
    test('普通文本也保活以稳定滚动范围', () {
      final quote = _quote(
        id: 'plain',
        content: List.filled(8, 'plain text').join('\n'),
        editSource: 'inline',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isTrue);
    });

    test('短 fullscreen 富文本保活', () {
      final delta = jsonEncode([
        {'insert': 'short rich text\n'},
      ]);
      final quote = _quote(
        id: 'short-rich',
        content: 'short rich text',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      expect(NoteListView.shouldKeepAliveQuoteItem(quote), isTrue);
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
  });
}
