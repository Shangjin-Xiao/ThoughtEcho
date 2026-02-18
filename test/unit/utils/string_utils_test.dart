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
        // The regex for author expects "——" prefix.
        // If the string is just "Author 《Source》" (without ——), author extraction might fail based on implementation.
        // Let's check implementation behavior: RegExp(r'——([^《]+)').firstMatch(source);
        // So "Author 《Source》" -> no match for author.
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
        // Regex: RegExp(r'《(.+?)》')
        // If "《My Book", it won't match.
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
  });
}
