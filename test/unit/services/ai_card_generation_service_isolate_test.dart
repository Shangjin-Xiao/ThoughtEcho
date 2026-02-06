import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/ai_card_generation_service.dart';

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

      final result = await AICardGenerationService.processSVGTask(data);

      // Verify Markdown cleanup
      expect(result.svg, contains('<svg'));
      expect(result.svg, isNot(contains('```')));

      // Verify Metadata injection
      expect(result.svg, contains('TestBrand'));
      expect(result.svg, contains('2023年1月1日'));

      // Verify Localization (morning -> 晨间 for zh)
      expect(result.svg, contains('晨间'));

      // Verify Logs
      expect(result.logs, isNotEmpty);
      expect(result.logs.any((l) => l.contains('DEBUG:')), isTrue);
    });

    test('processSVGTask rejects unsafe SVG', () async {
      const unsafeSvg = '<svg><script>alert(1)</script></svg>';
      final data = AICardProcessingData(
        svgContent: unsafeSvg,
        brandName: 'TestBrand',
        date: '2023-01-01',
      );

      expect(
        () async => await AICardGenerationService.processSVGTask(data),
        throwsA(isA<Exception>()), // Should throw AICardGenerationException
      );
    });

    test('processSVGTask handles missing metadata gracefully', () async {
      const rawSvg =
          '<svg xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" /></svg>';
      final data = AICardProcessingData(
        svgContent: rawSvg,
        brandName: 'TestBrand',
        date: null, // Missing date
      );

      final result = await AICardGenerationService.processSVGTask(data);

      expect(result.svg, contains('TestBrand'));
      // Should not crash
    });
  });
}
