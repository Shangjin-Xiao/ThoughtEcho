import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/config/onboarding_config.dart';
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

/// 引导流程测试用的假数据库服务：把迁移、初始化等重 DB 路径空操作化，
/// safeDatabase 返回内存库。真实 `DatabaseService().init()` 在测试环境会
/// 走完整的建库/迁移/预加载流程，直接导致 completeOnboarding 挂死。
class FakeDatabaseServiceForOnboarding extends DatabaseService {
  FakeDatabaseServiceForOnboarding(this._db) : super.forTesting();

  final Database _db;

  @override
  Future<void> init() async {}

  @override
  bool get isInitialized => true;

  @override
  Future<void> initDefaultHitokotoTags() async {}

  @override
  Future<Database> get safeDatabase async => _db;

  @override
  Future<void> patchQuotesDayPeriod() async {}

  @override
  Future<void> migrateWeatherToKey() async {}

  @override
  Future<void> migrateDayPeriodToKey() async {}
}

/// 让「完成引导」这一步写入失败，用于验证 fatal 时 isCompleting 被复位。
class ThrowingCompleteSettingsService extends SettingsService {
  ThrowingCompleteSettingsService(super.prefs);

  @override
  Future<void> setHasCompletedOnboarding(bool completed) async {
    throw Exception('fatal: cannot persist onboarding completion');
  }
}

class FakeAIAnalysisDatabaseService extends ChangeNotifier
    implements AIAnalysisDatabaseService {
  bool initCalled = false;
  bool shouldThrow = false;

  @override
  Future<void> init() async {
    initCalled = true;
    if (shouldThrow) {
      throw Exception('AI Analysis DB init error');
    }
  }

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

  group('OnboardingController initialize', () {
    setUp(() async {
      await TestHarness.initialize();
      sut = OnboardingController();
    });

    tearDown(() {
      sut.dispose();
    });

    testWidgets(
        'throws ProviderNotFoundException when required providers are missing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(key: Key('init-host')),
        ),
      );

      final context = tester.element(find.byKey(const Key('init-host')));
      expect(() => sut.initialize(context),
          throwsA(isA<ProviderNotFoundException>()));
    });

    testWidgets(
        'initializes successfully when all required providers exist in context',
        (tester) async {
      final databaseService = DatabaseService();
      final settingsService = await SettingsService.create();
      final mmkvService = MMKVService();
      final clipboardService = ClipboardService();
      // 用 Fake 而非进程级单例：单例在测试间共享，dispose 会毒化后续用例
      final aiAnalysisDbService = FakeAIAnalysisDatabaseService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(
                value: databaseService),
            ChangeNotifierProvider<SettingsService>.value(
                value: settingsService),
            Provider<MMKVService>.value(value: mmkvService),
            ChangeNotifierProvider<ClipboardService>.value(
                value: clipboardService),
            ChangeNotifierProvider<AIAnalysisDatabaseService>.value(
                value: aiAnalysisDbService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SizedBox(key: Key('init-host')),
          ),
        ),
      );

      final context = tester.element(find.byKey(const Key('init-host')));
      sut.initialize(context);

      expect(sut.state.preferences, isNotEmpty);
      await tester.pumpAndSettle();

      databaseService.dispose();
      settingsService.dispose();
      clipboardService.dispose();
      aiAnalysisDbService.dispose();
    });
  });

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

    testWidgets(
        'falls back to system locale when localeCode preference is empty',
        (tester) async {
      final databaseService = DatabaseService();
      final settingsService = await SettingsService.create();
      final mmkvService = MMKVService();
      final clipboardService = ClipboardService();
      // 用 Fake 而非进程级单例：单例在测试间共享，dispose 会毒化后续用例
      final aiAnalysisDbService = FakeAIAnalysisDatabaseService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(
                value: databaseService),
            ChangeNotifierProvider<SettingsService>.value(
                value: settingsService),
            Provider<MMKVService>.value(value: mmkvService),
            ChangeNotifierProvider<ClipboardService>.value(
                value: clipboardService),
            ChangeNotifierProvider<AIAnalysisDatabaseService>.value(
              value: aiAnalysisDbService,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                sut.initialize(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      sut.updatePreference('localeCode', '');
      expect(
        sut.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.zenQuotesProvider,
      );

      // UnifiedLogService 首次初始化会并发等 SafeMMKV，其 50ms 轮询 timer
      // 挂在 FakeAsync 里，teardown 前推进假时钟让它走完
      await tester.pump(const Duration(milliseconds: 500));

      databaseService.dispose();
      settingsService.dispose();
      clipboardService.dispose();
      aiAnalysisDbService.dispose();
    });
  });

  group('OnboardingController page navigation', () {
    late SettingsService settingsService;
    late DatabaseService databaseService;
    late MMKVService mmkvService;
    late ClipboardService clipboardService;
    late FakeAIAnalysisDatabaseService aiAnalysisDbService;

    setUp(() async {
      await TestHarness.initialize();
      sut = OnboardingController();
      databaseService = DatabaseService();
      settingsService = await SettingsService.create();
      mmkvService = MMKVService();
      clipboardService = ClipboardService();
      aiAnalysisDbService = FakeAIAnalysisDatabaseService();
    });

    tearDown(() {
      sut.dispose();
      databaseService.dispose();
      settingsService.dispose();
      clipboardService.dispose();
      aiAnalysisDbService.dispose();
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

    testWidgets(
        'goToPage, nextPage, and previousPage navigate correctly when attached to PageView',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(
                value: databaseService),
            ChangeNotifierProvider<SettingsService>.value(
                value: settingsService),
            Provider<MMKVService>.value(value: mmkvService),
            ChangeNotifierProvider<ClipboardService>.value(
                value: clipboardService),
            ChangeNotifierProvider<AIAnalysisDatabaseService>.value(
              value: aiAnalysisDbService,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                sut.initialize(context);
                return PageView(
                  controller: sut.pageController,
                  onPageChanged: sut.onPageChanged,
                  children: const [
                    Text('Page 0'),
                    Text('Page 1'),
                    Text('Page 2'),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Invalid page indices are ignored (return early, no animation)
      await sut.goToPage(-1);
      expect(sut.state.currentPageIndex, 0);

      await sut.goToPage(100);
      expect(sut.state.currentPageIndex, 0);

      // 动画 Future 只能靠 pump 推进：先启动、pump 完再 await，直接 await 会死锁
      final nextFuture = sut.nextPage();
      await tester.pumpAndSettle();
      await nextFuture;
      expect(sut.state.currentPageIndex, 1);

      final prevFuture = sut.previousPage();
      await tester.pumpAndSettle();
      await prevFuture;
      expect(sut.state.currentPageIndex, 0);

      // Go to last page
      final gotoFuture = sut.goToPage(OnboardingConfig.totalPages - 1);
      await tester.pumpAndSettle();
      await gotoFuture;
      expect(sut.state.currentPageIndex, OnboardingConfig.totalPages - 1);
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

  group('OnboardingController completeOnboarding and skipOnboarding workflows',
      () {
    late SettingsService settingsService;
    late FakeDatabaseServiceForOnboarding databaseService;
    late MMKVService mmkvService;
    late ClipboardService clipboardService;
    late FakeAIAnalysisDatabaseService aiAnalysisDbService;
    late ValueNotifier<bool> initializedNotifier;
    late Database inMemoryDb;

    setUp(() async {
      await TestHarness.initialize();
      PackageInfo.setMockInitialValues(
        appName: 'ThoughtEcho',
        packageName: 'com.example.thoughtecho',
        version: '1.2.3',
        buildNumber: '1',
        buildSignature: '',
      );
      sqfliteFfiInit();
      inMemoryDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      databaseService = FakeDatabaseServiceForOnboarding(inMemoryDb);
      settingsService = await SettingsService.create();
      mmkvService = MMKVService();
      await mmkvService.init();
      clipboardService = ClipboardService();
      aiAnalysisDbService = FakeAIAnalysisDatabaseService();
      initializedNotifier = ValueNotifier<bool>(false);
      sut = OnboardingController(
        servicesInitializedNotifier: initializedNotifier,
      );
    });

    tearDown(() async {
      sut.dispose();
      initializedNotifier.dispose();
      databaseService.dispose();
      settingsService.dispose();
      clipboardService.dispose();
      aiAnalysisDbService.dispose();
      await inMemoryDb.close();
      await TestHarness.tearDown();
    });

    testWidgets(
        'completeOnboarding saves preferences and completes successfully',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(
                value: databaseService),
            ChangeNotifierProvider<SettingsService>.value(
                value: settingsService),
            Provider<MMKVService>.value(value: mmkvService),
            ChangeNotifierProvider<ClipboardService>.value(
                value: clipboardService),
            ChangeNotifierProvider<AIAnalysisDatabaseService>.value(
              value: aiAnalysisDbService,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                sut.initialize(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      sut.updatePreference('defaultStartPage', 1);
      sut.updatePreference('clipboardMonitoring', true);
      sut.updatePreference('locationService', true);
      sut.updatePreference('sentryEnabled', true);

      final completeFuture = sut.completeOnboarding();
      expect(sut.state.isCompleting, isTrue);

      // Subsequent call to completeOnboarding during isCompleting does nothing
      await sut.completeOnboarding();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await completeFuture;

      expect(settingsService.hasCompletedOnboarding(), isTrue);
      expect(settingsService.appSettings.defaultStartPage, 1);
      expect(settingsService.appSettings.clipboardMonitoringEnabled, isTrue);
      expect(settingsService.sentryEnabled, isTrue);
      expect(initializedNotifier.value, isTrue);
      expect(aiAnalysisDbService.initCalled, isTrue);
    });

    testWidgets(
        'skipOnboarding executes default migration and completes workflow',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(
                value: databaseService),
            ChangeNotifierProvider<SettingsService>.value(
                value: settingsService),
            Provider<MMKVService>.value(value: mmkvService),
            ChangeNotifierProvider<ClipboardService>.value(
                value: clipboardService),
            ChangeNotifierProvider<AIAnalysisDatabaseService>.value(
              value: aiAnalysisDbService,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                sut.initialize(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final skipFuture = sut.skipOnboarding();
      expect(sut.state.isCompleting, isTrue);

      // Re-entrant call is ignored
      await sut.skipOnboarding();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await skipFuture;

      expect(settingsService.hasCompletedOnboarding(), isTrue);
      expect(initializedNotifier.value, isTrue);
    });

    testWidgets(
        'completeOnboarding resets isCompleting when a fatal exception occurs',
        (tester) async {
      // AI 初始化失败在生产里被吞掉（仅记日志），构不成 fatal；
      // fatal 源用「完成引导」这一步的 settings 写入失败
      final throwingSettings = ThrowingCompleteSettingsService(
        await SharedPreferences.getInstance(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(
                value: databaseService),
            ChangeNotifierProvider<SettingsService>.value(
                value: throwingSettings),
            Provider<MMKVService>.value(value: mmkvService),
            ChangeNotifierProvider<ClipboardService>.value(
                value: clipboardService),
            ChangeNotifierProvider<AIAnalysisDatabaseService>.value(
              value: aiAnalysisDbService,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                sut.initialize(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // 同步挂载 onError，异常在 future 链内被消化，不会逃逸到 test zone
      final completeFuture = sut.completeOnboarding();
      final fatalObserved = completeFuture.then(
        (_) => false,
        onError: (Object e) => true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(await fatalObserved, isTrue);
      expect(sut.state.isCompleting, isFalse);
      throwingSettings.dispose();
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
      fakeAiDbService.dispose();
    });
  });
}
