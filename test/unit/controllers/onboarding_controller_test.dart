import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/controllers/onboarding_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_analysis_model.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/services/clipboard_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

class FakeDatabaseServiceWithSafeDbError extends DatabaseService {
  FakeDatabaseServiceWithSafeDbError() : super.forTesting();

  @override
  Future<void> init() async {}

  @override
  Future<void> initDefaultHitokotoTags() async {}

  @override
  Future<Database> get safeDatabase async {
    throw Exception('safeDatabase access failure test');
  }
}

class FakeAIAnalysisDatabaseService extends ChangeNotifier
    implements AIAnalysisDatabaseService {
  @override
  Future<void> init() async {}

  @override
  Stream<List<AIAnalysis>> get analysesStream => const Stream.empty();

  @override
  Future<bool> deleteAllAnalyses() async => true;

  @override
  Future<bool> deleteAnalysis(String id) async => true;

  @override
  Future<String> exportToJson() async => '[]';

  @override
  Future<List<Map<String, dynamic>>> exportAnalysesAsList() async => [];

  @override
  Future<List<Map<String, dynamic>>> exportAnalysesPage(
    int offset,
    int limit,
  ) async =>
      [];

  @override
  Future<List<AIAnalysis>> getAllAnalyses() async => [];

  @override
  Future<AIAnalysis?> getAnalysisById(String id) async => null;

  @override
  Future<int> importAnalysesFromList(List analyses) async => 0;

  @override
  Future<int> restoreFromJson(String jsonStr) async => 0;

  @override
  Future<AIAnalysis> saveAnalysis(AIAnalysis analysis) async => analysis;

  @override
  Future<List<AIAnalysis>> searchAnalyses(String query) async => [];

  @override
  Future<List<AIAnalysis>> searchAnalysesByType(String analysisType) async =>
      [];

  @override
  Future<Database> get database => throw UnimplementedError();

  @override
  Future<void> closeDatabase() async {}
}

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

  group('OnboardingController 异常处理', () {
    late SettingsService settingsService;
    late MMKVService mmkvService;
    late ClipboardService clipboardService;
    void Function<T>(T)? debugCheckInvalidValueTypeBeforeTest;

    setUp(() async {
      await TestHarness.initialize();
      debugCheckInvalidValueTypeBeforeTest =
          Provider.debugCheckInvalidValueType;
      Provider.debugCheckInvalidValueType = null;
      PackageInfo.setMockInitialValues(
        appName: 'ThoughtEcho',
        packageName: 'com.example.thoughtecho',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      settingsService = await SettingsService.create();
      mmkvService = MMKVService();
      await mmkvService.init();
      clipboardService = ClipboardService();
    });

    tearDown(() async {
      Provider.debugCheckInvalidValueType =
          debugCheckInvalidValueTypeBeforeTest;
      await TestHarness.tearDown();
    });

    testWidgets('safeDatabase 抛出异常时能捕获警告并顺利完成引导流程', (tester) async {
      final fakeDbService = FakeDatabaseServiceWithSafeDbError();
      final fakeAiDbService = FakeAIAnalysisDatabaseService();
      final controller = OnboardingController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(value: fakeDbService),
            ChangeNotifierProvider<SettingsService>.value(
              value: settingsService,
            ),
            Provider<MMKVService>.value(value: mmkvService),
            ChangeNotifierProvider<ClipboardService>.value(
              value: clipboardService,
            ),
            ChangeNotifierProvider<AIAnalysisDatabaseService>.value(
              value: fakeAiDbService,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                controller.initialize(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final completeFuture = controller.completeOnboarding();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await completeFuture;

      expect(settingsService.hasCompletedOnboarding(), isTrue);
      controller.dispose();
    });
  });
}
