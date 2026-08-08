import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/localization_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveAppLocalizations', () {
    test('honours the configured locale code', () {
      expect(resolveAppLocalizations('zh').weatherClear, '晴');
      expect(resolveAppLocalizations('en').weatherClear, 'Clear');
    });

    test('strips the region suffix before matching', () {
      // SettingsService.setLocale 收得下 'zh_CN'，而 supportedLocales 比的是
      // 纯语言子标签——不归一化就会被判成不支持然后掉到英文。
      expect(resolveAppLocalizations('zh_CN').weatherClear, '晴');
      expect(resolveAppLocalizations('zh-Hans').weatherClear, '晴');
      expect(resolveAppLocalizations('EN_US').weatherClear, 'Clear');
    });

    test('falls back to English for unsupported languages', () {
      expect(resolveAppLocalizations('xx').weatherClear, 'Clear');
      expect(resolveAppLocalizations('xx_YY').weatherClear, 'Clear');
    });

    test('follows the platform locale when no code is configured', () {
      // 跟随系统时至少要拿到一份可用的文案，不能抛。
      expect(resolveAppLocalizations(null).weatherClear, isNotEmpty);
      expect(resolveAppLocalizations('').weatherClear, isNotEmpty);
    });
  });
}
