import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/svg_test_helper.dart';

void main() {
  group('SVGTestHelper', () {
    test('generateTestSVG should generate basic SVG content correctly', () {
      final svg = SVGTestHelper.generateTestSVG(
        content: 'Custom Content',
        title: 'Custom Title',
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('Custom Content'));
      expect(svg, contains('Custom Title'));
      expect(svg, contains('xmlns="http://www.w3.org/2000/svg"'));
    });

    group('validateSVG', () {
      test('should return true for valid SVG', () {
        final validSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
</svg>
''';
        expect(SVGTestHelper.validateSVG(validSvg), isTrue);
      });

      test('should return false for empty content', () {
        expect(SVGTestHelper.validateSVG('   '), isFalse);
        expect(SVGTestHelper.validateSVG(''), isFalse);
      });

      test('should return false when missing <svg> tag', () {
        final missingOpen = '''
  <circle cx="50" cy="50" r="40" />
</svg>
''';
        expect(SVGTestHelper.validateSVG(missingOpen), isFalse);
      });

      test('should return false when missing </svg> tag', () {
        final missingClose = '''
<svg>
  <circle cx="50" cy="50" r="40" />
''';
        expect(SVGTestHelper.validateSVG(missingClose), isFalse);
      });

      test(
          'should still return true but log warnings when missing xmlns or viewBox',
          () {
        final validSvgWithoutAttrs = '<svg></svg>';
        // According to the code, it returns true but logs a warning
        expect(SVGTestHelper.validateSVG(validSvgWithoutAttrs), isTrue);
      });
    });

    group('cleanAndFixSVG', () {
      test('should remove markdown ticks correctly', () {
        final markdownSvg = '''
```svg
<svg><circle r="10"/></svg>
```
''';
        final cleaned = SVGTestHelper.cleanAndFixSVG(markdownSvg);
        expect(cleaned, isNot(contains('```')));
        expect(cleaned, isNot(contains('svg\n')));
        expect(cleaned, startsWith('<svg'));
      });

      test('should add xmlns if missing', () {
        final withoutXmlns = '<svg></svg>';
        final cleaned = SVGTestHelper.cleanAndFixSVG(withoutXmlns);
        expect(cleaned, contains('xmlns="http://www.w3.org/2000/svg"'));
      });

      test('should add viewBox if width, height and viewBox are missing', () {
        final withoutViewBoxOrSize =
            '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
        final cleaned = SVGTestHelper.cleanAndFixSVG(withoutViewBoxOrSize);
        expect(cleaned, contains('viewBox="0 0 400 600"'));
      });

      test('should not add viewBox if width or height exists', () {
        final withWidth = '<svg width="100" height="100"></svg>';
        final cleaned = SVGTestHelper.cleanAndFixSVG(withWidth);
        expect(cleaned, isNot(contains('viewBox="0 0 400 600"')));
      });
    });

    test('generateTestSVGs should return a list of non-empty SVGs', () {
      final list = SVGTestHelper.generateTestSVGs();
      expect(list, isNotEmpty);
      expect(list.length, greaterThan(0));
      for (var svg in list) {
        expect(SVGTestHelper.validateSVG(svg), isTrue);
      }
    });
  });
}
