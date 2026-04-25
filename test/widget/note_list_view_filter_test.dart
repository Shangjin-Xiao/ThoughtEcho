library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoteListView filter subscription race', () {
    testWidgets(
      'clearing filters resubscribes only once with updated filter params',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final initialCallCount = databaseService.watchCalls.length;
        expect(initialCallCount, greaterThan(0));

        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final newCalls =
            databaseService.watchCalls.skip(initialCallCount).toList();

        expect(newCalls, hasLength(1));
        expect(newCalls.single.tagIds, isNull);
        expect(newCalls.single.selectedWeathers, isNull);
        expect(newCalls.single.selectedDayPeriods, isNull);

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'shows notes even when tag list is still empty',
      (tester) async {
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '通过通知进入后的笔记',
              date: DateTime(2026, 3, 29).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('通过通知进入后的笔记'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'scrollToQuoteById waits for real first batch after placeholder empty list',
      (tester) async {
        final databaseService = _DelayedFakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final noteListKey = GlobalKey<NoteListViewState>();

        await tester.pumpWidget(
          _TestApp(
            key: const ValueKey('delayed-test-app'),
            databaseService: databaseService,
            settingsService: settingsService,
            noteListKey: noteListKey,
          ),
        );

        await tester.pump();
        databaseService.emitPlaceholder();
        await tester.pump();

        final scrollFuture = noteListKey.currentState!.scrollToQuoteById(
          'quote-1',
        );

        await tester.pump(const Duration(milliseconds: 4200));

        databaseService.emitQuotes([
          Quote(
            id: 'quote-1',
            content: '延迟到达的目标笔记',
            date: DateTime(2026, 4, 25, 8, 0).toIso8601String(),
          ),
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(await scrollFuture, isTrue);
        expect(find.text('延迟到达的目标笔记'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );
  });
}

class _TestApp extends StatefulWidget {
  final _FakeDatabaseService databaseService;
  final _FakeSettingsService settingsService;
  final List<NoteCategory> tags;
  final GlobalKey<NoteListViewState>? noteListKey;

  _TestApp({
    super.key,
    required this.databaseService,
    required this.settingsService,
    List<NoteCategory>? tags,
    this.noteListKey,
  }) : tags = tags ?? _defaultTags;

  static final List<NoteCategory> _defaultTags = [
    NoteCategory(id: 'tag-1', name: '标签一', iconName: '🏷️'),
  ];

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  List<String> _selectedTagIds = const ['tag-1'];
  List<String> _selectedWeathers = const ['sunny'];
  List<String> _selectedDayPeriods = const ['morning'];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DatabaseService>.value(
          value: widget.databaseService,
        ),
        ChangeNotifierProvider<SettingsService>.value(
          value: widget.settingsService,
        ),
        ChangeNotifierProvider(create: (_) => NoteSearchController()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Material(
          child: NoteListView(
            key: widget.noteListKey,
            tags: widget.tags,
            selectedTagIds: _selectedTagIds,
            onTagSelectionChanged: (tagIds) {
              setState(() {
                _selectedTagIds = tagIds;
              });
            },
            searchQuery: '',
            sortType: 'time',
            sortAscending: false,
            onSortChanged: (_, __) {},
            onSearchChanged: (_) {},
            onEdit: (_) {},
            onDelete: (_) {},
            onAskAI: (_) {},
            selectedWeathers: _selectedWeathers,
            selectedDayPeriods: _selectedDayPeriods,
            onFilterChanged: (weathers, dayPeriods) {
              setState(() {
                _selectedWeathers = weathers;
                _selectedDayPeriods = dayPeriods;
              });
            },
          ),
        ),
      ),
    );
  }
}

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  AppSettings get appSettings => AppSettings.defaultSettings();

  @override
  LocalAISettings get localAISettings => LocalAISettings.defaultSettings();

  @override
  bool get requireBiometricForHidden => false;

  @override
  bool get showFavoriteButton => true;

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

class _WatchQuotesCall {
  final List<String>? tagIds;
  final List<String>? selectedWeathers;
  final List<String>? selectedDayPeriods;

  const _WatchQuotesCall({
    required this.tagIds,
    required this.selectedWeathers,
    required this.selectedDayPeriods,
  });
}

class _FakeDatabaseService extends DatabaseService {
  final List<_WatchQuotesCall> watchCalls = [];
  List<Quote> quotesToEmit = const [];
  List<NoteCategory> categoriesToReturn = const [];

  _FakeDatabaseService() : super.forTesting();

  @override
  bool get isInitialized => true;

  @override
  bool get hasMoreQuotes => false;

  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) {
    watchCalls.add(
      _WatchQuotesCall(
        tagIds: tagIds == null ? null : List<String>.from(tagIds),
        selectedWeathers: selectedWeathers == null
            ? null
            : List<String>.from(selectedWeathers),
        selectedDayPeriods: selectedDayPeriods == null
            ? null
            : List<String>.from(selectedDayPeriods),
      ),
    );
    return Stream<List<Quote>>.value(quotesToEmit);
  }

  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) async {}

  @override
  Future<List<NoteCategory>> getCategories() async => categoriesToReturn;
}

class _DelayedFakeDatabaseService extends _FakeDatabaseService {
  final StreamController<List<Quote>> _controller =
      StreamController<List<Quote>>.broadcast();
  bool _hasMoreQuotes = true;

  @override
  bool get hasMoreQuotes => _hasMoreQuotes;

  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) {
    watchCalls.add(
      _WatchQuotesCall(
        tagIds: tagIds == null ? null : List<String>.from(tagIds),
        selectedWeathers: selectedWeathers == null
            ? null
            : List<String>.from(selectedWeathers),
        selectedDayPeriods: selectedDayPeriods == null
            ? null
            : List<String>.from(selectedDayPeriods),
      ),
    );
    return _controller.stream;
  }

  void emitPlaceholder() {
    _hasMoreQuotes = true;
    _controller.add(const []);
  }

  void emitQuotes(List<Quote> quotes) {
    quotesToEmit = quotes;
    _hasMoreQuotes = false;
    _controller.add(quotes);
  }

  Future<void> disposeStream() async {
    await _controller.close();
  }
}
