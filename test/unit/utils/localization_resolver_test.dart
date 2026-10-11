import 'dart:ui' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/localization_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseLocale', () {
    test('parses single language tags', () {
      expect(parseLocale('zh'), const Locale('zh'));
      expect(parseLocale('en'), const Locale('en'));
      expect(parseLocale('ja'), const Locale('ja'));
    });

    test('parses script subtags', () {
      expect(
        parseLocale('zh-Hant'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(
        parseLocale('zh_Hant'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    });

    test('parses country subtags', () {
      expect(parseLocale('zh_CN'), const Locale('zh', 'CN'));
      expect(parseLocale('zh-TW'), const Locale('zh', 'TW'));
      expect(parseLocale('en_US'), const Locale('en', 'US'));
    });

    test('returns null for empty or null strings', () {
      expect(parseLocale(null), isNull);
      expect(parseLocale(''), isNull);
      expect(parseLocale('   '), isNull);
    });
  });

  group('resolveZhLocale', () {
    test('resolves explicit scriptCode before countryCode', () {
      // 显式 Hans 即使地区是 TW 也必须是简体
      expect(
        resolveZhLocale(const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'TW',
        )),
        const Locale('zh'),
      );
      expect(
        resolveZhLocale(const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'CN',
        )),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    });

    test('infers traditional chinese from TW/HK/MO when scriptCode is absent',
        () {
      expect(
        resolveZhLocale(const Locale('zh', 'TW')),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(
        resolveZhLocale(const Locale('zh', 'HK')),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(
        resolveZhLocale(const Locale('zh', 'MO')),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(
        resolveZhLocale(const Locale('zh', 'CN')),
        const Locale('zh'),
      );
    });
  });

  group('resolveEffectiveLocale', () {
    test('favors preferred locale if provided', () {
      expect(
        resolveEffectiveLocale(preferredLocale: const Locale('ja')),
        const Locale('ja'),
      );
      expect(
        resolveEffectiveLocale(
          preferredLocale: const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'TW',
          ),
        ),
        const Locale('zh'),
      );
    });

    test('iterates system locales until a supported match is found', () {
      final effective = resolveEffectiveLocale(
        systemLocales: const [Locale('it'), Locale('ja')],
      );
      expect(effective, const Locale('ja'));
    });

    test('falls back to English when no candidate is supported', () {
      final effective = resolveEffectiveLocale(
        systemLocales: const [Locale('it'), Locale('ru')],
      );
      expect(effective, const Locale('en'));
    });
  });

  group('resolveAppLocalizations', () {
    test('honours the configured locale code', () {
      expect(resolveAppLocalizations('zh').weatherClear, '晴');
      expect(resolveAppLocalizations('en').weatherClear, 'Clear');
    });

    test('resolves traditional chinese codes to zh-Hant', () {
      expect(resolveAppLocalizations('zh-Hant').appTitle, '心跡');
      expect(resolveAppLocalizations('zh_Hant').appTitle, '心跡');
      expect(resolveAppLocalizations('zh_TW').appTitle, '心跡');
      expect(resolveAppLocalizations('zh-HK').appTitle, '心跡');
      expect(resolveAppLocalizations('zh_MO').appTitle, '心跡');
      expect(resolveAppLocalizations('zh').appTitle, '心迹');
      expect(resolveAppLocalizations('zh_CN').appTitle, '心迹');
    });

    test('strips the region suffix before matching', () {
      expect(resolveAppLocalizations('zh_CN').weatherClear, '晴');
      expect(resolveAppLocalizations('zh-Hans').weatherClear, '晴');
      expect(resolveAppLocalizations('EN_US').weatherClear, 'Clear');
    });

    test('falls back to English for unsupported languages', () {
      expect(resolveAppLocalizations('xx').weatherClear, 'Clear');
      expect(resolveAppLocalizations('xx_YY').weatherClear, 'Clear');
    });

    test('follows the platform locale when no code is configured', () {
      expect(resolveAppLocalizations(null).weatherClear, isNotEmpty);
      expect(resolveAppLocalizations('').weatherClear, isNotEmpty);
    });
  });
}
