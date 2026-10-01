import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/ai_card_generation_service.dart';
import 'package:thoughtecho/services/ai_card_generation_strategies/card_generation_utils.dart';
import 'package:thoughtecho/services/ai_card_generation_strategies/svg_processing_isolate.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/aptabase_helper.dart';

class _FakeAIService extends Fake implements AIService {}

class _FakeSettingsService extends Fake implements SettingsService {
  _FakeSettingsService({required this.aiCardGenerationEnabled});

  @override
  final bool aiCardGenerationEnabled;

  @override
  String? get localeCode => 'zh';
}

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
      expect(CardGenerationUtils.localizeWeather('clear', languageCode: 'zh'),
          '晴');
      expect(CardGenerationUtils.localizeWeather('clear', languageCode: 'en'),
          'Clear');
    });
  });

  group('AICardGenerationService 埋点测试', () {
    test('isEnabled 为 true 且进行 AI 生成时触发 ai_card_generate 埋点', () async {
      final service = AICardGenerationService(
        _FakeAIService(),
        _FakeSettingsService(aiCardGenerationEnabled: true),
      );

      String? trackedEvent;
      Map<String, Object>? trackedProps;
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvent = eventName;
        trackedProps = props;
      };

      try {
        final quote = Quote(id: '1', content: '测试内容', date: '2023-01-01');
        try {
          await service.generateCard(brandName: 'Brand', note: quote);
        } catch (_) {}

        expect(trackedEvent, equals('feature_used'));
        expect(trackedProps, equals({'action': 'ai_card_generate'}));
      } finally {
        AptabaseHelper.onTrackEventForTesting = null;
      }
    });

    test('isEnabled 为 false（关闭 AI 生成）时不触发 ai_card_generate 埋点', () async {
      final service = AICardGenerationService(
        _FakeAIService(),
        _FakeSettingsService(aiCardGenerationEnabled: false),
      );

      var eventFired = false;
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        eventFired = true;
      };

      try {
        final quote = Quote(id: '1', content: '测试内容', date: '2023-01-01');
        await service.generateCard(brandName: 'Brand', note: quote);

        expect(eventFired, isFalse);
      } finally {
        AptabaseHelper.onTrackEventForTesting = null;
      }
    });
  });
}
