import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/i18n_language.dart';

void main() {
  group('I18nLanguage', () {
    group('base()', () {
      test('should extract base language from standard locales', () {
        expect(I18nLanguage.base('zh_CN'), 'zh');
        expect(I18nLanguage.base('en-US'), 'en');
        expect(I18nLanguage.base('fr_FR'), 'fr');
        expect(I18nLanguage.base('ja-JP'), 'ja');
      });

      test('should handle locale with only language code', () {
        expect(I18nLanguage.base('zh'), 'zh');
        expect(I18nLanguage.base('en'), 'en');
      });

      test('should return en for null or empty input', () {
        expect(I18nLanguage.base(null), 'en');
        expect(I18nLanguage.base(''), 'en');
        expect(I18nLanguage.base('   '), 'en');
      });

      test('should convert to lowercase', () {
        expect(I18nLanguage.base('ZH_cn'), 'zh');
        expect(I18nLanguage.base('EN-us'), 'en');
      });
    });

    group('appLanguage()', () {
      test('should return supported language', () {
        expect(I18nLanguage.appLanguage('zh_CN'), 'zh');
        expect(I18nLanguage.appLanguage('en-US'), 'en');
        expect(I18nLanguage.appLanguage('ja_JP'), 'ja');
        expect(I18nLanguage.appLanguage('ko_KR'), 'ko');
        expect(I18nLanguage.appLanguage('fr_FR'), 'fr');
      });

      test('should fallback to en for unsupported language', () {
        expect(I18nLanguage.appLanguage('es_ES'), 'en');
        expect(I18nLanguage.appLanguage('de_DE'), 'en');
        expect(I18nLanguage.appLanguage('ru_RU'), 'en');
      });

      test('should handle null or empty input', () {
        expect(I18nLanguage.appLanguage(null), 'en');
        expect(I18nLanguage.appLanguage(''), 'en');
      });
    });

    group('appLanguageOrSystem()', () {
      test('should use provided locale if valid', () {
        expect(I18nLanguage.appLanguageOrSystem('zh_CN'), 'zh');
        expect(I18nLanguage.appLanguageOrSystem('fr_FR'), 'fr');
        expect(I18nLanguage.appLanguageOrSystem('es_ES'), 'en'); // unsupported fallback
      });

      test('should fallback to system locale if input is null or empty', () {
        // Platform.localeName behavior might vary in test environments,
        // but it should resolve to either a supported language or 'en'.
        final result = I18nLanguage.appLanguageOrSystem(null);
        expect(I18nLanguage.supported.contains(result) || result == 'en', isTrue);

        final resultEmpty = I18nLanguage.appLanguageOrSystem('  ');
        expect(I18nLanguage.supported.contains(resultEmpty) || resultEmpty == 'en', isTrue);
      });
    });

    group('buildAcceptLanguage()', () {
      test('should build correct header for en', () {
        expect(I18nLanguage.buildAcceptLanguage('en'), 'en-US,en;q=0.9');
      });

      test('should build correct header for specific mapped languages', () {
        expect(I18nLanguage.buildAcceptLanguage('zh'), 'zh-CN,zh;q=0.9,en;q=0.8');
        expect(I18nLanguage.buildAcceptLanguage('ja'), 'ja-JP,ja;q=0.9,en;q=0.8');
        expect(I18nLanguage.buildAcceptLanguage('ko'), 'ko-KR,ko;q=0.9,en;q=0.8');
        expect(I18nLanguage.buildAcceptLanguage('fr'), 'fr-FR,fr;q=0.9,en;q=0.8');
      });

      test('should handle language without specific mapping', () {
        // Even if not in regionMap, it builds a valid fallback structure
        expect(I18nLanguage.buildAcceptLanguage('es'), 'es,es;q=0.9,en;q=0.8');
      });
    });
  });
}
