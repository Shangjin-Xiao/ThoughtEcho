import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/config/lottie_config.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10nZh;
  late AppLocalizations l10nEn;

  setUpAll(() async {
    l10nZh = await AppLocalizations.delegate.load(const Locale('zh'));
    l10nEn = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('LottieConfig 预设与向后兼容', () {
    test('presets 包含全部核心预设且默认描述向后兼容', () {
      expect(LottieConfig.presets.containsKey('searchLoading'), isTrue);
      expect(LottieConfig.presets.containsKey('weatherSearchLoading'), isTrue);
      expect(LottieConfig.presets.containsKey('customLoading'), isTrue);
      expect(LottieConfig.presets.containsKey('notFound'), isTrue);

      expect(
        LottieConfig.presets['searchLoading']!.description,
        equals('搜索中...'),
      );
      expect(
        LottieConfig.presets['weatherSearchLoading']!.description,
        equals('天气搜索中...'),
      );
      expect(
        LottieConfig.presets['customLoading']!.description,
        equals('加载中...'),
      );
      expect(
        LottieConfig.presets['notFound']!.description,
        equals('未找到相关内容'),
      );
    });

    test('getAnimationForScene 正确返回各场景的预设对象', () {
      expect(
        LottieConfig.getAnimationForScene(LottieScene.searchLoading),
        same(LottieConfig.presets['searchLoading']),
      );
      expect(
        LottieConfig.getAnimationForScene(LottieScene.weatherSearchLoading),
        same(LottieConfig.presets['weatherSearchLoading']),
      );
      expect(
        LottieConfig.getAnimationForScene(LottieScene.customLoading),
        same(LottieConfig.presets['customLoading']),
      );
      expect(
        LottieConfig.getAnimationForScene(LottieScene.notFound),
        same(LottieConfig.presets['notFound']),
      );
    });
  });

  group('AnimationPreset 国际化解析与回退', () {
    test('中文环境下 descriptionOf 解析中文文案', () {
      final searchPreset =
          LottieConfig.getAnimationForScene(LottieScene.searchLoading);
      final weatherPreset =
          LottieConfig.getAnimationForScene(LottieScene.weatherSearchLoading);
      final customPreset =
          LottieConfig.getAnimationForScene(LottieScene.customLoading);
      final notFoundPreset =
          LottieConfig.getAnimationForScene(LottieScene.notFound);

      expect(searchPreset.descriptionOf(l10nZh), equals('搜索中...'));
      expect(weatherPreset.descriptionOf(l10nZh), equals('天气搜索中...'));
      expect(customPreset.descriptionOf(l10nZh), equals('加载中...'));
      expect(notFoundPreset.descriptionOf(l10nZh), equals('未找到相关内容'));
    });

    test('英文环境下 descriptionOf 解析英文文案', () {
      final searchPreset =
          LottieConfig.getAnimationForScene(LottieScene.searchLoading);
      final weatherPreset =
          LottieConfig.getAnimationForScene(LottieScene.weatherSearchLoading);
      final customPreset =
          LottieConfig.getAnimationForScene(LottieScene.customLoading);
      final notFoundPreset =
          LottieConfig.getAnimationForScene(LottieScene.notFound);

      expect(searchPreset.descriptionOf(l10nEn), equals('Searching...'));
      expect(
        weatherPreset.descriptionOf(l10nEn),
        equals('Searching weather...'),
      );
      expect(customPreset.descriptionOf(l10nEn), equals('Loading...'));
      expect(notFoundPreset.descriptionOf(l10nEn), equals('No content found'));
    });

    test('当 l10n 为 null 时 descriptionOf 优雅回退到默认描述', () {
      for (final scene in LottieScene.values) {
        final preset = LottieConfig.getAnimationForScene(scene);
        expect(preset.descriptionOf(null), equals(preset.description));
        expect(preset.descriptionOf(), equals(preset.description));
      }
    });

    test('自定义无 descriptionBuilder 的预设 descriptionOf 回退至默认描述', () {
      const customPreset = AnimationPreset(
        path: 'assets/lottie/custom.json',
        repeat: true,
        size: 50.0,
        description: '默认自定义文案',
      );

      expect(customPreset.descriptionOf(l10nZh), equals('默认自定义文案'));
      expect(customPreset.descriptionOf(l10nEn), equals('默认自定义文案'));
      expect(customPreset.descriptionOf(null), equals('默认自定义文案'));
    });
  });

  group('LottieConfig 场景静态解析工具方法', () {
    test('getDescriptionForSceneWithL10n 支持多语言及空回退', () {
      expect(
        LottieConfig.getDescriptionForSceneWithL10n(
          LottieScene.searchLoading,
          l10nZh,
        ),
        equals('搜索中...'),
      );
      expect(
        LottieConfig.getDescriptionForSceneWithL10n(
          LottieScene.searchLoading,
          l10nEn,
        ),
        equals('Searching...'),
      );
      expect(
        LottieConfig.getDescriptionForSceneWithL10n(
          LottieScene.searchLoading,
          null,
        ),
        equals('搜索中...'),
      );
    });

    testWidgets('getDescriptionForScene 在具备 AppLocalizations 时返回当前语言文本',
        (WidgetTester tester) async {
      late String resolvedText;

      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en'),
          delegates: AppLocalizations.localizationsDelegates,
          child: Builder(
            builder: (context) {
              resolvedText = LottieConfig.getDescriptionForScene(
                LottieScene.weatherSearchLoading,
                context,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolvedText, equals('Searching weather...'));
    });

    testWidgets('getDescriptionForScene 缺失 AppLocalizations 时优雅回退到默认描述',
        (WidgetTester tester) async {
      late String resolvedText;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            resolvedText = LottieConfig.getDescriptionForScene(
              LottieScene.weatherSearchLoading,
              context,
            );
            return const SizedBox();
          },
        ),
      );

      expect(resolvedText, equals('天气搜索中...'));
    });
  });
}
