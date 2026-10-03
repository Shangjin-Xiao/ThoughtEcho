import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/config/onboarding_config.dart';
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

  group('OnboardingController page navigation', () {
    setUp(() async {
      await TestHarness.initialize();
      sut = OnboardingController();
    });

    tearDown(() {
      sut.dispose();
    });

    test('onPageChanged updates state correctly', () {
      int notified = 0;
      sut.addListener(() => notified++);

      expect(sut.state.currentPageIndex, 0);
      expect(sut.state.canGoPrevious, isFalse);
      expect(sut.state.canGoNext, isTrue);

      sut.onPageChanged(1);

      expect(sut.state.currentPageIndex, 1);
      expect(sut.state.canGoPrevious, isTrue);
      expect(sut.state.canGoNext, isTrue);
      expect(notified, 1);

      sut.onPageChanged(OnboardingConfig.totalPages - 1);

      expect(sut.state.currentPageIndex, OnboardingConfig.totalPages - 1);
      expect(sut.state.canGoPrevious, isTrue);
      expect(sut.state.canGoNext, isTrue);
    });
  });

  group('OnboardingController preferences state', () {
    setUp(() async {
      await TestHarness.initialize();
      sut = OnboardingController();
    });

    tearDown(() {
      sut.dispose();
    });

    test('updatePreference updates preferences in state and notifies listeners',
        () {
      int notifications = 0;
      sut.addListener(() => notifications++);

      sut.updatePreference('telemetryEnabled', true);
      expect(sut.state.getPreference<bool>('telemetryEnabled'), isTrue);

      sut.updatePreference('sentryEnabled', false);
      expect(sut.state.getPreference<bool>('sentryEnabled'), isFalse);

      sut.updatePreference('defaultStartPage', 2);
      expect(sut.state.getPreference<int>('defaultStartPage'), 2);

      expect(notifications, 3);
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
      settingsService.dispose();
      await TestHarness.tearDown();
    });

    test('引导页没表过态时，不覆盖今日思考 / 周期报告的现有取值', () async {
      await settingsService.setTodayThoughtsUseAI(true);
      await settingsService.setReportInsightsUseAI(true);

      await sut.applyAiTogglePreferences(settingsService);

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
