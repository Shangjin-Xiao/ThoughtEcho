import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/string_utils.dart';

void main() {
  group('StringUtils', () {
    group('formatSource', () {
      test('should return empty string when author and source are null', () {
        expect(StringUtils.formatSource(null, null), isEmpty);
      });

      test('should return empty string when author and source are empty', () {
        expect(StringUtils.formatSource('', ''), isEmpty);
      });

      test('should return formatted author when only author is provided', () {
        expect(StringUtils.formatSource('John Doe', null), '——John Doe');
        expect(StringUtils.formatSource('John Doe', ''), '——John Doe');
      });

      test('should return formatted source when only source is provided', () {
        expect(StringUtils.formatSource(null, 'My Book'), '——《My Book》');
        expect(StringUtils.formatSource('', 'My Book'), '——《My Book》');
      });

      test('should return formatted author and source when both are provided',
          () {
        expect(StringUtils.formatSource('John Doe', 'My Book'),
            '——John Doe 《My Book》');
      });

      test('should handle whitespace correctly', () {
        expect(
            StringUtils.formatSource(' John ', ' Book '), '—— John  《 Book 》');
      });
    });

    group('parseSource', () {
      test('should parse author and source correctly', () {
        final result = StringUtils.parseSource('——John Doe 《My Book》');
        expect(result, ['John Doe', 'My Book']);
      });

      test('should parse only author correctly', () {
        final result = StringUtils.parseSource('——John Doe');
        expect(result, ['John Doe', '']);
      });

      test('should parse only source correctly', () {
        final result = StringUtils.parseSource('《My Book》');
        expect(result, ['', 'My Book']);
      });

      test(
          'should parse formatted source with missing author prefix if source is present',
          () {
        final result = StringUtils.parseSource('Author 《Source》');
        expect(result, ['', 'Source']);
      });

      test('should handle empty string', () {
        final result = StringUtils.parseSource('');
        expect(result, ['', '']);
      });

      test('should trim author whitespace', () {
        final result = StringUtils.parseSource('—— John Doe  《My Book》');
        expect(result, ['John Doe', 'My Book']);
      });

      test(
          'should handle source without closing bracket gracefully (or as implemented)',
          () {
        final result = StringUtils.parseSource('《My Book');
        expect(result[1], '');
        expect(result[0], '');
      });
    });

    group('parseSourceToControllers', () {
      test('should update controllers with parsed values', () {
        final authorController = TextEditingController();
        final workController = TextEditingController();

        StringUtils.parseSourceToControllers(
          '——John Doe 《My Book》',
          authorController,
          workController,
        );

        expect(authorController.text, 'John Doe');
        expect(workController.text, 'My Book');
      });

      test('should handle empty source string', () {
        final authorController = TextEditingController();
        final workController = TextEditingController();

        StringUtils.parseSourceToControllers(
          '',
          authorController,
          workController,
        );

        expect(authorController.text, '');
        expect(workController.text, '');
      });
    });

    group('needsExpansion', () {
      test('should return false when text length is less than threshold', () {
        expect(
            StringUtils.needsExpansion('Short text', threshold: 20), isFalse);
      });

      test('should return false when text length equals threshold', () {
        final text = 'a' * 20;
        expect(StringUtils.needsExpansion(text, threshold: 20), isFalse);
      });

      test('should return true when text length is greater than threshold', () {
        final text = 'a' * 21;
        expect(StringUtils.needsExpansion(text, threshold: 20), isTrue);
      });

      test('should use default threshold of 100', () {
        expect(StringUtils.needsExpansion('a' * 100), isFalse);
        expect(StringUtils.needsExpansion('a' * 101), isTrue);
      });
    });

    group('truncateForPreview', () {
      test('should preserve emoji grapheme clusters while truncating', () {
        const text = 'ab👨‍👩‍👧‍👦cd';

        expect(StringUtils.truncateForPreview(text, 3), 'ab👨‍👩‍👧‍👦...');
      });

      test('should return original text when it fits the preview limit', () {
        expect(StringUtils.truncateForPreview('短句😊', 3), '短句😊');
      });

      test('should remove rich-text object placeholders from previews', () {
        expect(StringUtils.truncateForPreview('珍藏\u{FFFC}😊', 20), '珍藏😊');
      });
    });

    group('removeObjectReplacementChar', () {
      test('removes single Object Replacement Character', () {
        final textWithObj = 'Hello \u{FFFC} World';
        expect(StringUtils.removeObjectReplacementChar(textWithObj),
            'Hello  World');
      });

      test('removes multiple Object Replacement Characters', () {
        final textWithObjs = 'Image 1\u{FFFC} and Image 2\u{FFFC}';
        expect(StringUtils.removeObjectReplacementChar(textWithObjs),
            'Image 1 and Image 2');
      });

      test('returns original string if no Object Replacement Character exists',
          () {
        final normalText = 'This is a normal text without any special objects.';
        expect(StringUtils.removeObjectReplacementChar(normalText), normalText);
      });

      test('handles string consisting only of Object Replacement Characters',
          () {
        final onlyObjs = '\u{FFFC}\u{FFFC}\u{FFFC}';
        expect(StringUtils.removeObjectReplacementChar(onlyObjs), '');
      });

      test('handles empty string', () {
        expect(StringUtils.removeObjectReplacementChar(''), '');
      });
    });

    group('forEachLine', () {
      test('handles empty string', () {
        final List<String> lines = [];
        final List<bool> isLastFlags = [];
        StringUtils.forEachLine('', (line, isLast) {
          lines.add(line);
          isLastFlags.add(isLast);
        });
        expect(lines, ['']);
        expect(isLastFlags, [true]);
      });

      test('handles string without newline', () {
        final List<String> lines = [];
        final List<bool> isLastFlags = [];
        StringUtils.forEachLine('single line', (line, isLast) {
          lines.add(line);
          isLastFlags.add(isLast);
        });
        expect(lines, ['single line']);
        expect(isLastFlags, [true]);
      });

      test('handles string with newlines', () {
        final List<String> lines = [];
        final List<bool> isLastFlags = [];
        StringUtils.forEachLine('line 1\nline 2\nline 3', (line, isLast) {
          lines.add(line);
          isLastFlags.add(isLast);
        });
        expect(lines, ['line 1', 'line 2', 'line 3']);
        expect(isLastFlags, [false, false, true]);
      });

      test('handles string ending with newline', () {
        final List<String> lines = [];
        final List<bool> isLastFlags = [];
        StringUtils.forEachLine('line 1\n', (line, isLast) {
          lines.add(line);
          isLastFlags.add(isLast);
        });
        expect(lines, ['line 1', '']);
        expect(isLastFlags, [false, true]);
      });

      test('handles string with consecutive newlines', () {
        final List<String> lines = [];
        final List<bool> isLastFlags = [];
        StringUtils.forEachLine('line 1\n\nline 3', (line, isLast) {
          lines.add(line);
          isLastFlags.add(isLast);
        });
        expect(lines, ['line 1', '', 'line 3']);
        expect(isLastFlags, [false, false, true]);
      });
    });
  });
}
