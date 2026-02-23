/// Basic unit tests for ClipboardService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/clipboard_service.dart';

void main() {
  group('ClipboardService Tests', () {
    late ClipboardService clipboardService;

    setUp(() {
      clipboardService = ClipboardService();
    });

    test('should create ClipboardService instance', () {
      expect(clipboardService, isNotNull);
    });

    test('should have basic functionality', () {
      expect(() => clipboardService.toString(), returnsNormally);
    });

    group('extractAuthorAndSource', () {
      test('should extract author and source from format: ——作者《出处》', () {
        final result = clipboardService.extractAuthorAndSource(
          '这是正文 ——鲁迅《狂人日记》',
        );
        expect(result['author'], '鲁迅');
        expect(result['source'], '狂人日记');
        expect(result['matched_substring'], '——鲁迅《狂人日记》');
      });

      test('should extract author and source from format: 《出处》——作者', () {
        final result = clipboardService.extractAuthorAndSource(
          '这是正文 《狂人日记》——鲁迅',
        );
        expect(result['author'], '鲁迅');
        expect(result['source'], '狂人日记');
        expect(result['matched_substring'], '《狂人日记》——鲁迅');
      });

      test('should extract author from format: "引语"——作者', () {
        final result = clipboardService.extractAuthorAndSource('这是正文 "名言"——鲁迅');
        expect(result['author'], '鲁迅');
        expect(result['source'], isNull);
        expect(result['matched_substring'], '"名言"——鲁迅');
      });

      test('should extract author only from format: ——作者', () {
        final result = clipboardService.extractAuthorAndSource('这是正文 ——鲁迅');
        expect(result['author'], '鲁迅');
        expect(result['source'], isNull);
        expect(result['matched_substring'], '——鲁迅');
      });

      test('should extract source only from format: 《出处》', () {
        final result = clipboardService.extractAuthorAndSource('这是正文 《狂人日记》');
        expect(result['author'], isNull);
        expect(result['source'], '狂人日记');
        expect(result['matched_substring'], '《狂人日记》');
      });

      test('should return nulls when no metadata found', () {
        final result = clipboardService.extractAuthorAndSource('没有元数据的正文');
        expect(result['author'], isNull);
        expect(result['source'], isNull);
        expect(result['matched_substring'], isNull);
      });
    });
  });
}
