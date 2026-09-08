import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/anniversary_digit_glyphs.dart';

void main() {
  group('AnniversaryDigitGlyphs', () {
    test('anniversaryDigitPath returns correct path for valid digits', () {
      expect(anniversaryDigitPath('1'), anniversaryDigitPaths['1']);
      expect(anniversaryDigitPath('5'), anniversaryDigitPaths['5']);
      expect(anniversaryDigitPath('9'), anniversaryDigitPaths['9']);
    });

    test('anniversaryDigitPath fallbacks to 0 for invalid input', () {
      expect(anniversaryDigitPath('a'), anniversaryDigitPaths['0']);
      expect(anniversaryDigitPath(''), anniversaryDigitPaths['0']);
      expect(anniversaryDigitPath('-1'), anniversaryDigitPaths['0']);
    });

    test('anniversaryDigitsWidth calculates width correctly', () {
      expect(anniversaryDigitsWidth(1), 56.0);
      expect(anniversaryDigitsWidth(2), 56.0 * 2 + 14.0);
      expect(anniversaryDigitsWidth(3), 56.0 * 3 + 14.0 * 2);
    });

    test('formatSvgNumber formats numbers correctly', () {
      expect(formatSvgNumber(12.0), '12');
      expect(formatSvgNumber(12.5), '12.5');
      expect(formatSvgNumber(12.55), '12.55');
      expect(formatSvgNumber(12.555), '12.56'); // rounds to 2 decimal places
    });
  });
}
