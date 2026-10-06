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
    return [
      ChatSession(
        id: 's1',
        title: 'Session 1',
        sessionType: 'explore',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      ),
    ];
  }

  @override
  Future<Map<String, ChatSessionOverview>> getSessionOverviews(
    List<String> sessionIds,
  ) async {
    return {
      's1': ChatSessionOverview(messageCount: 2, snippet: 'Hello world'),
    };
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
    return Stream<List<Quote>>.value([
      Quote(
        id: 'q1',
        content: 'Test quote 1',
        date: DateTime.now().toIso8601String(),
      ),
    ]);
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
}
