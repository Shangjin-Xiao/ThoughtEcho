// filepath: /workspaces/ThoughtEcho/test/unit/services/clipboard_service_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/clipboard_service.dart';

void main() {
  group('ClipboardService Logic Tests', () {
    late ClipboardService clipboardService;

    setUp(() {
      clipboardService = ClipboardService();
    });

    test('Case 1: Author and Source (——Author《Source》)', () {
      final input = 'Some content ——Author《Source》';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], 'Author');
      expect(result['source'], 'Source');
      expect(result['matched_substring'], contains('——Author《Source》'));
    });

    test('Case 2: Source and Author (《Source》——Author)', () {
      final input = 'Some content 《Source》——Author';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], 'Author');
      expect(result['source'], 'Source');
      expect(result['matched_substring'], contains('《Source》——Author'));
    });

    test('Case 3: Quote ("Content"——Author)', () {
      final input = '"Some Quote"——Author';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], 'Author');
      expect(result['source'], null);
      expect(result['matched_substring'], contains('"Some Quote"——Author'));
    });

    test('Case 4: Author Fallback (——Author)', () {
      final input = 'Some content ——Author';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], 'Author');
      expect(result['source'], null);
      expect(result['matched_substring'], contains('——Author'));
    });

    test('Case 5: Source Fallback (《Source》)', () {
      final input = 'Some content 《Source》';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], null);
      expect(result['source'], 'Source');
      expect(result['matched_substring'], contains('《Source》'));
    });

    test('Case 4 & 5 combination (Fallback logic for Author then Source)', () {
      // This tests the logic where it finds Author, then looks back for Source
      // Case 4 handles: text... 《Source》 ... ——Author
      final input = 'Some content 《Source》 ——Author';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], 'Author');
      expect(result['source'], 'Source');
    });

    test('Case 5 & 4 combination (Fallback logic for Source then Author)', () {
      // This tests the logic where it finds Source, then looks back for Author
      // Case 5 handles: text... ——Author ... 《Source》
      final input = 'Some content ——Author 《Source》';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], 'Author');
      expect(result['source'], 'Source');
    });

    test('No Match', () {
      final input = 'Just some random text without any attribution.';
      final result = clipboardService.extractAuthorAndSource(input);

      expect(result['author'], null);
      expect(result['source'], null);
      expect(result['matched_substring'], null);
    });

    test('Clean function logic check (trimming)', () {
      // Indirectly testing clean via public method
      final input = 'Content ——  Author   ';
      final result = clipboardService.extractAuthorAndSource(input);
      expect(result['author'], 'Author');
    });
  });
}
