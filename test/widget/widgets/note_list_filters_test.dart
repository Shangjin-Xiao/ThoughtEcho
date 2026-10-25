library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnimatedFilterChip Unit & Widget Tests', () {
    testWidgets(
      'renders child wrapped in Opacity and Transform during entry animation',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Test Chip'),
              ),
            ),
          ),
        );

        // Initially at t=0ms, value is 0.0, Opacity and Transform wrappers exist under AnimatedFilterChip.
        expect(find.text('Test Chip'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsOneWidget,
        );

        // Pump mid-way through 250ms animation (e.g. 100ms)
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'prunes Opacity and Transform layers after animation completes (value >= 1.0)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Test Chip'),
              ),
            ),
          ),
        );

        // Advance past the 250ms animation duration
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Test Chip'), findsOneWidget);
        // Verify Opacity and Transform are no longer wrapping the child under AnimatedFilterChip
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('NoteListFiltersExtension and AnimatedFilterChip Integration', () {
    testWidgets(
      'renders filter chips with keys and correct localized labels',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: const ['tag-1'],
            selectedWeathers: const ['clear', 'other_weather'],
            selectedDayPeriods: const ['morning'],
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Verify keys
        expect(find.byKey(const ValueKey('tag_tag-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('weather_cat_sunny')), findsOneWidget);
        expect(find.byKey(const ValueKey('weather_other_weather')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('period_morning')), findsOneWidget);

        // Verify AnimatedFilterChip widgets (1 tag + 1 weather cat + 1 other weather + 1 period = 4)
        expect(find.byType(AnimatedFilterChip), findsNWidgets(4));

        // Verify layer pruning after animation completes
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'triggers callbacks correctly on chip deletion and clear all',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        List<String>? updatedTags;
        List<String>? updatedWeathers;
        List<String>? updatedDayPeriods;

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: const ['tag-1'],
            selectedWeathers: const ['clear'],
            selectedDayPeriods: const ['morning'],
            onTagSelectionChanged: (tags) => updatedTags = tags,
            onFilterChanged: (weathers, dayPeriods) {
              updatedWeathers = weathers;
              updatedDayPeriods = dayPeriods;
            },
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap delete on tag-1
        final tagCloseButton = find.descendant(
          of: find.byKey(const ValueKey('tag_tag-1')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(tagCloseButton);
        await tester.pump();

        expect(updatedTags, isEmpty);

        // Tap delete on sunny weather chip
        final weatherCloseButton = find.descendant(
          of: find.byKey(const ValueKey('weather_cat_sunny')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(weatherCloseButton);
        await tester.pump();

        expect(updatedWeathers, isEmpty);
        expect(updatedDayPeriods, ['morning']);

        // Tap clear all button (the last Icons.close button in filter bar)
        updatedTags = null;
        updatedWeathers = null;
        updatedDayPeriods = null;

        final clearAllButton = find.byIcon(Icons.close).last;
        await tester.tap(clearAllButton);
        await tester.pump();

        expect(updatedTags, isEmpty);
        expect(updatedWeathers, isEmpty);
        expect(updatedDayPeriods, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'handles rapid addition and removal of tags with ValueKey element reuse',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        Widget buildApp(List<String> tags) {
          return _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: 'Tag 1', iconName: '🏷️'),
              NoteTag(id: 'tag-2', name: 'Tag 2', iconName: '🏷️'),
            ],
            selectedTagIds: tags,
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          );
        }

        await tester.pumpWidget(buildApp(['tag-1', 'tag-2']));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const ValueKey('tag_tag-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('tag_tag-2')), findsOneWidget);

        // Rapidly remove tag-1 before animation finishes
        await tester.pumpWidget(buildApp(['tag-2']));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const ValueKey('tag_tag-1')), findsNothing);
        expect(find.byKey(const ValueKey('tag_tag-2')), findsOneWidget);

        // Advance past animation
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('tag_tag-2')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'animates filter bar expansion and collapse using SizeTransition with RepaintBoundary layer isolation',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        Widget buildApp(List<String> selectedTags) {
          return _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: selectedTags,
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          );
        }

        // Start with no filters selected
        await tester.pumpWidget(buildApp([]));
        await tester.pump();

        // SizeTransition should exist with sizeFactor 0.0 or SizedBox.shrink when no filters
        expect(find.byType(SizeTransition), findsNothing);

        // Add a tag filter -> expand filter display
        await tester.pumpWidget(buildApp(['tag-1']));
        await tester.pump(); // Start animation (t=0ms)

        expect(find.byType(SizeTransition), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(SizeTransition),
            matching: find.byType(RepaintBoundary),
          ),
          findsAtLeastNWidgets(1),
        );

        final SizeTransition sizeTransition1 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition1.sizeFactor.value, 0.0);

        // Advance 150ms -> sizeFactor ~ 0.5
        await tester.pump(const Duration(milliseconds: 150));
        final SizeTransition sizeTransition2 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition2.sizeFactor.value, greaterThan(0.0));
        expect(sizeTransition2.sizeFactor.value, lessThan(1.0));

        // Advance past 300ms -> sizeFactor = 1.0
        await tester.pump(const Duration(milliseconds: 200));
        final SizeTransition sizeTransition3 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition3.sizeFactor.value, 1.0);

        // Remove tag filter -> reverse animation collapse
        await tester.pumpWidget(buildApp([]));
        await tester.pump(); // t=0ms of reverse

        final SizeTransition sizeTransition4 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition4.sizeFactor.value, 1.0);

        // Mid-way through collapse (150ms)
        await tester.pump(const Duration(milliseconds: 150));
        final SizeTransition sizeTransition5 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition5.sizeFactor.value, lessThan(1.0));
        expect(sizeTransition5.sizeFactor.value, greaterThan(0.0));

        // Finish collapse animation (past 300ms)
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(SizeTransition), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'verifies RepaintBoundary layer isolation on Expanded note list area',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: const ['tag-1'],
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          ),
        );

        await tester.pumpAndSettle();

        // Find RepaintBoundary wrapping the note list animation layer
        final listOpacityFinder = find.byType(AnimatedOpacity);
        expect(listOpacityFinder, findsAtLeastNWidgets(1));

        final repaintBoundaryUnderList = find.ancestor(
          of: listOpacityFinder,
          matching: find.byType(RepaintBoundary),
        );
        expect(repaintBoundaryUnderList, findsAtLeastNWidgets(1));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });
}

class _FilterTestApp extends StatefulWidget {
  final _FakeDatabaseService databaseService;
  final _FakeSettingsService settingsService;
  final List<NoteTag> tags;
  final List<String> selectedTagIds;
  final List<String> selectedWeathers;
  final List<String> selectedDayPeriods;
  final ValueChanged<List<String>>? onTagSelectionChanged;
  final void Function(List<String> weathers, List<String> dayPeriods)?
      onFilterChanged;

  const _FilterTestApp({
    required this.databaseService,
    required this.settingsService,
    required this.tags,
    required this.selectedTagIds,
    required this.selectedWeathers,
    required this.selectedDayPeriods,
    this.onTagSelectionChanged,
    this.onFilterChanged,
  });

  @override
  State<_FilterTestApp> createState() => _FilterTestAppState();
}

class _FilterTestAppState extends State<_FilterTestApp> {
  late List<String> _selectedTagIds;
  late List<String> _selectedWeathers;
  late List<String> _selectedDayPeriods;

  @override
  void initState() {
    super.initState();
    _selectedTagIds = widget.selectedTagIds;
    _selectedWeathers = widget.selectedWeathers;
    _selectedDayPeriods = widget.selectedDayPeriods;
  }

  @override
  void didUpdateWidget(covariant _FilterTestApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedTagIds = widget.selectedTagIds;
    _selectedWeathers = widget.selectedWeathers;
    _selectedDayPeriods = widget.selectedDayPeriods;
  }

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
            tags: widget.tags,
            selectedTagIds: _selectedTagIds,
            onTagSelectionChanged: (tagIds) {
              setState(() {
                _selectedTagIds = tagIds;
              });
              widget.onTagSelectionChanged?.call(tagIds);
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
              widget.onFilterChanged?.call(weathers, dayPeriods);
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
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

class _FakeDatabaseService extends DatabaseService {
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
    bool includeDeleted = false,
  }) {
    return Stream<List<Quote>>.value(const []);
  }

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

  @override
  Future<List<NoteTag>> getTags() async => const [];
}
