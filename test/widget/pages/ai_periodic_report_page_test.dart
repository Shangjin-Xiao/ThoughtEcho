import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/ai_periodic_report_page.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _EmptyPeriodDatabaseService extends DatabaseService {
  _EmptyPeriodDatabaseService() : super.forTesting();

  @override
  Future<List<Quote>> getQuotesForPeriod(
    DateTime start,
    DateTime end, {
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    return const [];
  }
}

/// 返回固定一条笔记，并统计查询次数，用于验证数据库通知的合并与静默刷新。
class _CountingPeriodDatabaseService extends DatabaseService {
  _CountingPeriodDatabaseService() : super.forTesting();

  int queryCount = 0;

  @override
  Future<List<Quote>> getQuotesForPeriod(
    DateTime start,
    DateTime end, {
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    queryCount++;
    return [
      Quote(
        id: 'q1',
        content: '一条测试笔记',
        date: DateTime.now().toIso8601String(),
      ),
    ];
  }

  void notifyDataChanged() => notifyListeners();
}

class _ReportSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get reportInsightsUseAI => false;

  @override
  String get localeCode => 'zh';

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  Future<String?> getCustomString(String key) async => null;

  @override
  Future<void> setCustomString(String key, String value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty period still shows zero statistics and AI entry',
      (tester) async {
    final settings = _ReportSettingsService();
    final database = _EmptyPeriodDatabaseService();
    final insights = InsightHistoryService(settingsService: settings);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<DatabaseService>.value(value: database),
          ChangeNotifierProvider<InsightHistoryService>.value(value: insights),
          ChangeNotifierProvider<AIService>(
            create: (_) => AIService(settingsService: settings),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AIPeriodicReportPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(AIPeriodicReportPage));
    final l10n = AppLocalizations.of(context);
    expect(find.text(l10n.dataOverview), findsOneWidget);
    expect(find.text(l10n.aiChat), findsOneWidget);
    // 摘要带保留，四个 0 仍然可见
    expect(find.text('0'), findsWidgets);
    // 但三个「暂无」chip 不再出现——空状态文案已经说过一次了
    expect(find.text(l10n.noDataYet), findsNothing);
    expect(
      find.text(l10n.noNotesInPeriodForPeriod(l10n.periodWeek)),
      findsOneWidget,
    );
  });

  // 回归：入场动画只留一层。之前七到十个 TweenAnimationBuilder 交错到 1.4 秒，
  // 数据早就到了用户还得等动画演完。
  testWidgets('overview uses a single entrance animation', (tester) async {
    final settings = _ReportSettingsService();
    final database = _CountingPeriodDatabaseService();
    final insights = InsightHistoryService(settingsService: settings);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<DatabaseService>.value(value: database),
          ChangeNotifierProvider<InsightHistoryService>.value(value: insights),
          ChangeNotifierProvider<AIService>(
            create: (_) => AIService(settingsService: settings),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AIPeriodicReportPage(),
        ),
      ),
    );
    // 先确认异步查询已完成、概览已经渲染出来，否则下面数的是空树
    await tester.pump();
    await tester.pump();
    final context = tester.element(find.byType(AIPeriodicReportPage));
    final l10n = AppLocalizations.of(context);
    expect(find.text(l10n.dataOverview), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 恰好一层：多了是又退回逐块交错，少了是入场动画被整个删掉
    expect(
      find.byType(TweenAnimationBuilder<double>).evaluate().length,
      equals(1),
    );

    // 300ms 之后必须完全落位
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpAndSettle();
  });

  // 回归：数据库在启动/同步期间会连续 notifyListeners 多次。
  // 若每次都重查并把整页切回转圈，进入探索页时就会来回闪。
  testWidgets('database bursts are debounced and refresh silently',
      (tester) async {
    final settings = _ReportSettingsService();
    final database = _CountingPeriodDatabaseService();
    final insights = InsightHistoryService(settingsService: settings);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<DatabaseService>.value(value: database),
          ChangeNotifierProvider<InsightHistoryService>.value(value: insights),
          ChangeNotifierProvider<AIService>(
            create: (_) => AIService(settingsService: settings),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AIPeriodicReportPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(database.queryCount, 1);

    // 连续 5 次通知只应触发一次重查
    for (var i = 0; i < 5; i++) {
      database.notifyDataChanged();
      await tester.pump(const Duration(milliseconds: 20));
    }

    // 防抖窗口内不应重查，也不应出现整页转圈
    expect(database.queryCount, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(database.queryCount, 2);

    // 静默刷新：内容始终在位，不会被整页 loading 顶掉
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
