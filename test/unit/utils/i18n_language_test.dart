import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/i18n_language.dart';

void main() {
  group('I18nLanguage', () {
    group('base', () {
      test('should extract base language from standard locale strings', () {
        expect(I18nLanguage.base('zh_CN'), 'zh');
        expect(I18nLanguage.base('en-US'), 'en');
        expect(I18nLanguage.base('fr_FR'), 'fr');
      });

      test(
        'should handle uppercase language codes by converting to lowercase',
        () {
          expect(I18nLanguage.base('ZH_cn'), 'zh');
          expect(I18nLanguage.base('EN-US'), 'en');
        },
      );

      test('should return "en" for null or empty strings', () {
        expect(I18nLanguage.base(null), 'en');
        expect(I18nLanguage.base(''), 'en');
        expect(I18nLanguage.base('   '), 'en');
      });

      test('should return the original string if no separator is found', () {
        expect(I18nLanguage.base('zh'), 'zh');
        expect(I18nLanguage.base('ko'), 'ko');
      });
    });

    group('appLanguage', () {
      test('should return the base language if it is supported', () {
        expect(I18nLanguage.appLanguage('zh_CN'), 'zh');
        expect(I18nLanguage.appLanguage('en-US'), 'en');
        expect(I18nLanguage.appLanguage('ja_JP'), 'ja');
        expect(I18nLanguage.appLanguage('ko_KR'), 'ko');
        expect(I18nLanguage.appLanguage('fr_FR'), 'fr');
      });

      test('should fallback to "en" if the language is not supported', () {
        expect(I18nLanguage.appLanguage('es_ES'), 'en');
        expect(I18nLanguage.appLanguage('de_DE'), 'en');
        expect(I18nLanguage.appLanguage('ru'), 'en');
      });

      test('should handle null or empty inputs by returning "en"', () {
        expect(I18nLanguage.appLanguage(null), 'en');
        expect(I18nLanguage.appLanguage(''), 'en');
      });
    });

    group('appLanguageOrSystem', () {
      test('should use provided localeCode if it is valid', () {
        expect(I18nLanguage.appLanguageOrSystem('zh_CN'), 'zh');
        expect(I18nLanguage.appLanguageOrSystem('ja'), 'ja');
      });

      test('should fallback to system locale if provided localeCode is null', () {
        // Since we can't easily mock Platform.localeName without a wrapper,
        // we'll just verify it doesn't crash and returns a valid supported language or 'en'
        final result = I18nLanguage.appLanguageOrSystem(null);
        expect(['zh', 'en', 'ja', 'ko', 'fr'].contains(result), isTrue);
      });

      test(
        'should fallback to system locale if provided localeCode is empty whitespace',
        () {
          final result = I18nLanguage.appLanguageOrSystem('   ');
          expect(['zh', 'en', 'ja', 'ko', 'fr'].contains(result), isTrue);
        },
      );
    });

    group('buildAcceptLanguage', () {
      test('should build correct header for "en"', () {
        expect(I18nLanguage.buildAcceptLanguage('en'), 'en-US,en;q=0.9');
      });

      test('should build correct header for "zh"', () {
        expect(
          I18nLanguage.buildAcceptLanguage('zh'),
          'zh-CN,zh;q=0.9,en;q=0.8',
        );
      });

      test('should build correct header for "ja"', () {
        expect(
          I18nLanguage.buildAcceptLanguage('ja'),
          'ja-JP,ja;q=0.9,en;q=0.8',
        );
      });

      test('should build correct header for "ko"', () {
        expect(
          I18nLanguage.buildAcceptLanguage('ko'),
          'ko-KR,ko;q=0.9,en;q=0.8',
        );
      });

      test('should build correct header for "fr"', () {
        expect(
          I18nLanguage.buildAcceptLanguage('fr'),
          'fr-FR,fr;q=0.9,en;q=0.8',
        );
      });

      test(
        'should handle unsupported languages gracefully by using them as primary',
        () {
          // Even though appLanguage filters out unsupported ones, if this method is called directly:
          expect(
            I18nLanguage.buildAcceptLanguage('es'),
            'es,es;q=0.9,en;q=0.8',
          );
        },
      );
    });
  });
}
