import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/ai_assistant_page.dart';
import 'package:thoughtecho/pages/explore_page.dart';
import 'package:thoughtecho/pages/insights_page.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _FakeStatsDatabase implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql.contains('COUNT(*) as c') && sql.contains('SUM(LENGTH(content))')) {
      return const [
        {'c': 3, 's': 90},
      ];
    }
    if (sql.contains('COUNT(DISTINCT substr(date,1,10)) as d')) {
      return const [
        {'d': 2},
      ];
    }
    if (sql.contains('SELECT day_period')) {
      return const [
        {'day_period': '夜晚'},
      ];
    }
    if (sql.contains('SELECT weather')) {
      return const [
        {'weather': '晴'},
      ];
    }
    if (sql.contains('FROM quote_tags')) {
      return const [
        {'name': '工作'},
      ];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService() : super.forTesting();

  final Database _database = _FakeStatsDatabase();

  @override
  Future<Database> get safeDatabase async => _database;

  @override
  Future<List<Quote>> getMostFavoritedQuotesThisWeek({int limit = 5}) async {
    return const [
      Quote(
        id: 'q1',
        content: '这是最受欢迎的笔记内容，用于生成探索页摘要。',
        date: '2026-04-08T00:00:00.000',
        favoriteCount: 8,
      ),
    ];
  }
}

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAIService extends AIService {
  _FakeAIService({required super.settingsService});

  @override
  bool hasValidApiKey() => false;

  @override
  Future<bool> hasValidApiKeyAsync() async => false;
}

class _TestNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

Widget _buildApp(
  DatabaseService databaseService, {
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(
        value: _FakeSettingsService(),
      ),
      ChangeNotifierProvider<AIService>.value(
        value: _FakeAIService(settingsService: _FakeSettingsService()),
      ),
      ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: navigatorObservers,
      home: const ExplorePage(),
    ),
  );
}

void main() {
  testWidgets('stats card opens InsightsPage when tapped', (tester) async {
    final databaseService = _FakeDatabaseService();
    final navigatorObserver = _TestNavigatorObserver();

    await tester.pumpWidget(
      _buildApp(databaseService, navigatorObservers: [navigatorObserver]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('explore_stats_section_card')));
    await tester.idle();

    expect(navigatorObserver.pushedRoutes, isNotEmpty);
    final route = navigatorObserver.pushedRoutes.last;
    expect(route, isA<MaterialPageRoute<dynamic>>());
    final page = (route as MaterialPageRoute<dynamic>).builder(
      tester.element(find.byType(ExplorePage)),
    );
    expect(page, isA<InsightsPage>());
  });

  testWidgets('AI assistant receives explore summary from stats', (
    tester,
  ) async {
    final databaseService = _FakeDatabaseService();
    final navigatorObserver = _TestNavigatorObserver();

    await tester.pumpWidget(
      _buildApp(databaseService, navigatorObservers: [navigatorObserver]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('explore_ai_chat_entry')));
    await tester.idle();

    expect(navigatorObserver.pushedRoutes, isNotEmpty);
    final route = navigatorObserver.pushedRoutes.last;
    expect(route, isA<MaterialPageRoute<dynamic>>());
    final page = (route as MaterialPageRoute<dynamic>).builder(
      tester.element(find.byType(ExplorePage)),
    ) as AIAssistantPage;
    expect(page.exploreGuideSummary, isNotNull);
    expect(page.exploreGuideSummary, contains('3'));
    expect(page.exploreGuideSummary, contains('90'));
    expect(page.exploreGuideSummary, contains('夜晚'));
    expect(page.exploreGuideSummary, contains('晴'));
    expect(page.exploreGuideSummary, contains('工作'));
  });
}
