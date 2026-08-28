import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/onboarding_controller.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OnboardingController sut;

  group('OnboardingController locale preference linkage', () {
    setUp(() async {
      await TestHarness.initialize();
      sut = OnboardingController();
    });

    tearDown(() {
      sut.dispose();
    });

    test('updates daily quote provider when onboarding language changes', () {
      sut.updatePreference('dailyQuoteProvider', ApiService.hitokotoProvider);

      sut.updatePreference('localeCode', 'ja');
      expect(
        sut.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.meigenProvider,
      );

      sut.updatePreference('localeCode', 'ko');
      expect(
        sut.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.koreanAdviceProvider,
      );

      sut.updatePreference('localeCode', 'en');
      expect(
        sut.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.zenQuotesProvider,
      );
    });
  });

  group('OnboardingController AI 快捷开关', () {
    late SettingsService settingsService;

    setUp(() async {
      await TestHarness.initialize();
      sut = OnboardingController();
      settingsService = await SettingsService.create();
    });

    tearDown(() async {
      sut.dispose();
      await TestHarness.tearDown();
    });

    test('引导页没表过态时，不覆盖今日思考 / 周期报告的现有取值', () async {
      // 新用户在引导里配好 AI 服务后的状态：两个开关都已经开着。
      await settingsService.setTodayThoughtsUseAI(true);
      await settingsService.setReportInsightsUseAI(true);

      // 引导页里根本没有这两个开关，所以 preferences 里不会有它们的取值。
      await sut.applyAiTogglePreferences(settingsService);

      // 曾经这里会被无条件写成 false——新用户装完什么都没开就是这么来的。
      expect(settingsService.todayThoughtsUseAI, isTrue);
      expect(settingsService.reportInsightsUseAI, isTrue);
    });

    test('引导页表过态时，按用户选的写', () async {
      await settingsService.setTodayThoughtsUseAI(true);
      await settingsService.setReportInsightsUseAI(true);

      sut.updatePreference('todayThoughtsUseAI', false);
      sut.updatePreference('reportInsightsUseAI', false);
      await sut.applyAiTogglePreferences(settingsService);

      expect(settingsService.todayThoughtsUseAI, isFalse);
      expect(settingsService.reportInsightsUseAI, isFalse);
    });
  });
}
