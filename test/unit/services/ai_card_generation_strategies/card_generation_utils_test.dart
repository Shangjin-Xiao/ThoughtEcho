import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/ai_card_generation_strategies/card_generation_utils.dart';

void main() {
  group('CardGenerationUtils', () {
    group('localizeWeather', () {
      test('should localize basic weather to Chinese by default', () {
        expect(CardGenerationUtils.localizeWeather('clear'), '晴');
        expect(CardGenerationUtils.localizeWeather('Clear'), '晴');
        expect(CardGenerationUtils.localizeWeather(' partly cloudy '), '少云');
        expect(CardGenerationUtils.localizeWeather('partly_cloudy'), '少云');
      });

      test('should localize weather to target language', () {
        expect(CardGenerationUtils.localizeWeather('sunny', languageCode: 'en'),
            'Sunny');
        expect(CardGenerationUtils.localizeWeather('sunny', languageCode: 'ja'),
            '晴れ');
        expect(CardGenerationUtils.localizeWeather('sunny', languageCode: 'fr'),
            'Ensoleillé');
      });

      test('should return original if weather not found', () {
        expect(CardGenerationUtils.localizeWeather('unknown_weather'),
            'unknown_weather');
      });

      test('should return null or original for empty/null inputs', () {
        expect(CardGenerationUtils.localizeWeather(null), null);
        expect(CardGenerationUtils.localizeWeather(''), null);
        expect(CardGenerationUtils.localizeWeather('   '), null);
      });
    });

    group('localizeDayPeriod', () {
      test('should localize basic day periods to Chinese by default', () {
        expect(CardGenerationUtils.localizeDayPeriod('morning'), '晨间');
        expect(CardGenerationUtils.localizeDayPeriod('moring'),
            '晨间'); // testing typo handling
        expect(CardGenerationUtils.localizeDayPeriod(' Noon '), '正午');
        expect(CardGenerationUtils.localizeDayPeriod('late night'), '深夜');
      });

      test('should localize day period to target language', () {
        expect(
            CardGenerationUtils.localizeDayPeriod('afternoon',
                languageCode: 'en'),
            'Afternoon');
        expect(
            CardGenerationUtils.localizeDayPeriod('afternoon',
                languageCode: 'ja'),
            '午後');
        expect(
            CardGenerationUtils.localizeDayPeriod('afternoon',
                languageCode: 'fr'),
            'Après-midi');
      });

      test('should return original if day period not found', () {
        expect(CardGenerationUtils.localizeDayPeriod('unknown_period'),
            'unknown_period');
      });

      test('should return null for empty/null inputs', () {
        expect(CardGenerationUtils.localizeDayPeriod(null), null);
        expect(CardGenerationUtils.localizeDayPeriod(''), null);
        expect(CardGenerationUtils.localizeDayPeriod('   '), null);
      });
    });

    group('formatDate', () {
      test('should format valid date to Chinese/Japanese style', () {
        expect(CardGenerationUtils.formatDate('2026-01-22', languageCode: 'zh'),
            '2026年1月22日');
        expect(CardGenerationUtils.formatDate('2026-01-22', languageCode: 'ja'),
            '2026年1月22日');
      });

      test('should format valid date to French style', () {
        expect(CardGenerationUtils.formatDate('2026-01-22', languageCode: 'fr'),
            '22/01/2026');
      });

      test('should format valid date to English style (default)', () {
        expect(CardGenerationUtils.formatDate('2026-01-22', languageCode: 'en'),
            'Jan 22, 2026');
      });

      test('should format valid date to Chinese style by default', () {
        expect(CardGenerationUtils.formatDate('2026-01-22'), '2026年1月22日');
      });

      test('should return original string for invalid date formats', () {
        expect(CardGenerationUtils.formatDate('invalid-date'), 'invalid-date');
        expect(CardGenerationUtils.formatDate('2026/01/22', languageCode: 'zh'),
            '2026/01/22'); // Assuming DateTime.parse fails
      });
    });
  });
}
