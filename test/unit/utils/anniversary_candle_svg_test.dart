import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/anniversary_candle_svg.dart';

void main() {
  group('buildAnniversaryCandleSvg', () {
    test('生成有效且包含完整 SVG 标签的字符串', () {
      final svg = buildAnniversaryCandleSvg(1);
      expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, endsWith('</svg>'));
      expect(svg.contains('viewBox="0 0 400 400"'), isTrue);
      expect(svg.contains('<defs>'), isTrue);
      expect(svg.contains('candleBodyGrad'), isTrue);
    });

    test('支持 1 到 10 及更高周年届数', () {
      for (int y = 1; y <= maxSimulatedAnniversaryYear; y++) {
        final svg = buildAnniversaryCandleSvg(y);
        expect(svg.isNotEmpty, isTrue);
        expect(svg.contains('NaN'), isFalse);
        expect(svg.contains('Infinity'), isFalse);
        expect(svg.contains('stroke="#374151"'), isTrue, reason: '必须包含烛芯');
        expect(svg.contains('fill="#FF7A00"'), isTrue, reason: '必须包含火苗');
      }
    });

    test('多位数年份每个数字都独立生成烛芯和火苗', () {
      final singleDigitSvg = buildAnniversaryCandleSvg(1);
      final doubleDigitSvg = buildAnniversaryCandleSvg(10);

      // 烛芯路径特征
      final singleWickCount =
          RegExp(r'stroke="#374151"').allMatches(singleDigitSvg).length;
      final doubleWickCount =
          RegExp(r'stroke="#374151"').allMatches(doubleDigitSvg).length;

      expect(singleWickCount, 1);
      expect(doubleWickCount, 2);

      // 火苗数量
      final singleFlameCount =
          RegExp(r'fill="#FF7A00"').allMatches(singleDigitSvg).length;
      final doubleFlameCount =
          RegExp(r'fill="#FF7A00"').allMatches(doubleDigitSvg).length;

      expect(singleFlameCount, 1);
      expect(doubleFlameCount, 2);
    });

    test('非正数或 0 届回退到 1 周年', () {
      final svg0 = buildAnniversaryCandleSvg(0);
      final svgNeg = buildAnniversaryCandleSvg(-5);
      final svg1 = buildAnniversaryCandleSvg(1);

      expect(svg0, svg1);
      expect(svgNeg, svg1);
    });
  });
}
