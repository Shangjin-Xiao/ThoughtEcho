import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/ai_card_generation_strategies/svg_processing_isolate.dart';
import 'package:thoughtecho/services/ai_card_generation_strategies/card_generation_utils.dart';

void main() {
  group('AICardGenerationService Isolate Logic', () {
    test('processSVGTask cleans simple SVG and injects metadata', () async {
      const rawSvg =
          '```svg\n<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect /></svg>\n```';
      final data = AICardProcessingData(
        svgContent: rawSvg,
        brandName: 'TestBrand',
        date: '2023年1月1日',
        weather: '晴',
        dayPeriod: 'morning',
      );

      final result = await processSVGTask(data);

      expect(result.svg, contains('<svg'));
      expect(result.svg, isNot(contains('```')));
      expect(result.svg, contains('TestBrand'));
      expect(result.svg, contains('2023年1月1日'));
    });
  });

  group('CardGenerationUtils', () {
    test('localizeWeather works correctly', () {
      expect(CardGenerationUtils.localizeWeather('clear', languageCode: 'zh'), '晴');
      expect(CardGenerationUtils.localizeWeather('clear', languageCode: 'en'), 'Clear');
    });
  });
}
