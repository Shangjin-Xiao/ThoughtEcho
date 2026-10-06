import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/settings_page.dart';
import 'package:thoughtecho/pages/thoughter/session_history_page.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/utils/app_scroll_behavior.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

import '../test_harness.dart';

class _FakeChatSessionService extends ChatSessionService {
  @override
  Future<List<ChatSession>> getAllSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    return List.generate(
      20,
      (i) => ChatSession(
        id: 's$i',
        title: 'Session $i',
        sessionType: 'explore',
        createdAt: DateTime.now().subtract(Duration(days: i)),
        lastActiveAt: DateTime.now().subtract(Duration(days: i)),
      ),
    );
  }

  @override
  Future<Map<String, ChatSessionOverview>> getSessionOverviews(
    List<String> sessionIds,
  ) async {
    return {
      for (final id in sessionIds)
        id: ChatSessionOverview(messageCount: 2, snippet: 'Snippet for $id'),
    };
  }

  @override
  Future<List<ChatSessionSearchResult>> searchSessions(
    String query, {
    int limit = 20,
  }) async {
    return [
      ChatSessionSearchResult(
        session: ChatSession(
          id: 's0',
          title: 'Session 0',
          sessionType: 'explore',
          createdAt: DateTime.now(),
          lastActiveAt: DateTime.now(),
        ),
        snippet: 'Search snippet for $query',
        isTruncated: false,
        matchStart: 0,
        matchEnd: query.length,
      ),
    ];
  }
}

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService() : super.forTesting();

  @override
  bool get isInitialized => true;

  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool includeDeleted = false,
  }) {
    return Stream<List<Quote>>.value(
      List.generate(
        30,
        (i) => Quote(
          id: 'q$i',
          content: 'Test quote $i content for mouse scroll tests',
          date: DateTime.now().subtract(Duration(days: i)).toIso8601String(),
        ),
      ),
    );
  }

  @override
  Future<List<NoteTag>> getTags() async => [];

  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
    int? refillCount,
    bool suppressNotify = false,
  }) async {}
}

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  AppSettings get appSettings => AppSettings.defaultSettings();

  @override
  LocalAISettings get localAISettings => LocalAISettings.defaultSettings();

  @override
  bool get requireBiometricForHidden => false;

  @override
  String get noteCardMediaStyle => NoteCardMediaStyle.thumbnail;

  @override
  bool get showFavoriteButton => true;

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  bool get noteListDisableCardShadows => false;

  @override
  bool get noteListDisableBackdropBlur => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  String get exportFormat => 'pdf';

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  String get noteInsertAnimationType => 'slide';

  @override
  int get anniversarySimulatedYear => 0;

  @override
  List<int> get anniversaryShownYears => const [];

  @override
  String? get localeCode => null;

  @override
  bool get excerptIntentEnabled => true;

  @override
  ThemeMode get themeMode => ThemeMode.system;

  @override
  bool get todayThoughtsUseAI => false;

  @override
  bool get sentryDisclosureShown => true;

  @override
  String get lastSeenReleaseVersion => '';

  @override
  bool get skipNonFullscreenEditor => false;

  @override
  bool get reportInsightsUseAI => false;

  @override
  String get offlineQuoteSource => 'all';

  @override
  String get dailyQuoteProvider => 'hitokoto';

  @override
  List<String> get apiNinjasCategories => const [];

  @override
  MultiAISettings get multiAISettings => const MultiAISettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  test('AppScrollBehavior allows mouse drag in dragDevices', () {
    const behavior = AppScrollBehavior();
    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
  });

  testWidgets('NoteListView contains a Scrollbar widget', (tester) async {
    final databaseService = _FakeDatabaseService();
    final settingsService = _FakeSettingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider(create: (_) => NoteSearchController()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Material(
            child: NoteListView(
              tags: const [],
              selectedTagIds: const [],
              onTagSelectionChanged: (_) {},
              searchQuery: '',
              sortType: 'time',
              sortAscending: false,
              onSortChanged: (_, __) {},
              onSearchChanged: (_) {},
              onEdit: (_) {},
              onDelete: (_) {},
              onAskAI: (_) {},
              onFilterChanged: (_, __) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(Scrollbar), findsAtLeastNWidgets(1));
  });

  testWidgets('SettingsPage contains a Scrollbar widget', (tester) async {
    final appTheme = AppTheme();
    final settingsService = _FakeSettingsService();
    final locationService = LocationService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppTheme>.value(value: appTheme),
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<LocationService>.value(value: locationService),
          ChangeNotifierProvider<UnifiedLogService>.value(
              value: UnifiedLogService.instance),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const SettingsPage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Scrollbar), findsAtLeastNWidgets(1));
  });

  testWidgets('SessionHistoryPage contains a Scrollbar widget', (tester) async {
    final fakeService = _FakeChatSessionService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: fakeService,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsAtLeastNWidgets(1));
  });

  testWidgets(
      'Mouse drag gesture with PointerDeviceKind.mouse successfully scrolls list under AppScrollBehavior',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 50,
            itemExtent: 80.0,
            itemBuilder: (context, index) => ListTile(
              title: Text('Item $index'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(controller.offset, equals(0.0));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0.0));
  });

  testWidgets(
      'Mouse drag gesture with PointerDeviceKind.mouse does NOT scroll list under standard behavior without mouse in dragDevices',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MaterialScrollBehavior(),
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 50,
            itemExtent: 80.0,
            itemBuilder: (context, index) => ListTile(
              title: Text('Item $index'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(controller.offset, equals(0.0));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.offset, equals(0.0));
  });

  testWidgets('NoteListView allows mouse drag scrolling on populated list',
      (tester) async {
    final databaseService = _FakeDatabaseService();
    final settingsService = _FakeSettingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider(create: (_) => NoteSearchController()),
        ],
        child: MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Material(
            child: NoteListView(
              tags: const [],
              selectedTagIds: const [],
              onTagSelectionChanged: (_) {},
              searchQuery: '',
              sortType: 'time',
              sortAscending: false,
              onSortChanged: (_, __) {},
              onSearchChanged: (_) {},
              onEdit: (_) {},
              onDelete: (_) {},
              onAskAI: (_) {},
              onFilterChanged: (_, __) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final listViewFinder = find.byType(ListView).first;
    final scrollableState = tester.state<ScrollableState>(
      find
          .descendant(of: listViewFinder, matching: find.byType(Scrollable))
          .first,
    );
    expect(scrollableState.position.pixels, equals(0.0));

    final gesture = await tester.startGesture(
      tester.getCenter(listViewFinder),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, greaterThan(0.0));
  });

  testWidgets(
      'SessionHistoryPage resets scroll position when search query is entered',
      (tester) async {
    final fakeService = _FakeChatSessionService();

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: fakeService,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final listViewFinder = find.byType(ListView).first;
    final scrollableState = tester.state<ScrollableState>(
      find
          .descendant(of: listViewFinder, matching: find.byType(Scrollable))
          .first,
    );

    // Drag down to scroll
    await tester.drag(listViewFinder, const Offset(0, -300),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, greaterThan(0.0));

    await tester.enterText(find.byType(SearchBar), 'Session');
    await tester.pumpAndSettle();

    final searchListViewFinder = find.byType(ListView).first;
    final searchScrollableState = tester.state<ScrollableState>(
      find
          .descendant(
              of: searchListViewFinder, matching: find.byType(Scrollable))
          .first,
    );
    expect(searchScrollableState.position.pixels, equals(0.0));
  });
}
