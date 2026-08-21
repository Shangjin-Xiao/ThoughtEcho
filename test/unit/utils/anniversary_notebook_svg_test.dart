import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/anniversary_digit_glyphs.dart';
import 'package:thoughtecho/utils/anniversary_notebook_svg.dart';

void main() {
  group('buildAnniversaryNotebookSvg', () {
    test('生成完整且不含非法数值的 SVG', () {
      for (var year = 1; year <= 12; year++) {
        final svg = buildAnniversaryNotebookSvg(year);
        expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
        expect(svg, endsWith('</svg>'));
        expect(svg.contains('viewBox="0 0 100 100"'), isTrue);
        expect(svg.contains('coverGradient'), isTrue);
        expect(svg.contains('NaN'), isFalse);
        expect(svg.contains('Infinity'), isFalse);
      }
    });

    test('封面数字跟着届数走', () {
      final first = buildAnniversaryNotebookSvg(1);
      final second = buildAnniversaryNotebookSvg(2);

      expect(first.contains(anniversaryDigitPath('1')), isTrue);
      expect(first.contains(anniversaryDigitPath('2')), isFalse);
      expect(second.contains(anniversaryDigitPath('2')), isTrue);
      expect(first == second, isFalse);
    });

    test('两位数届数画两个字形', () {
      final svg = buildAnniversaryNotebookSvg(10);
      expect(svg.contains(anniversaryDigitPath('1')), isTrue);
      expect(svg.contains(anniversaryDigitPath('0')), isTrue);
      // 只有数字用圆头描边，借此数出画了几个字形。
      expect(RegExp(r'stroke-linecap="round"').allMatches(svg).length, 2);
    });

    test('非正数届数回退到一周年', () {
      expect(buildAnniversaryNotebookSvg(0), buildAnniversaryNotebookSvg(1));
      expect(buildAnniversaryNotebookSvg(-3), buildAnniversaryNotebookSvg(1));
    });
  });
}
