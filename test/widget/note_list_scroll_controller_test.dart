library;

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

  testWidgets(
    'does not read ScrollController offset while results are switching',
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

      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump();

      expect(find.byType(ListView), findsAtLeastNWidgets(1));

      await tester.drag(
        find.byType(ListView).first,
        const Offset(0, -120),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    },
  );
}

class _TestApp extends StatefulWidget {
  final _FakeDatabaseService databaseService;
  final _FakeSettingsService settingsService;

  const _TestApp({
    required this.databaseService,
    required this.settingsService,
  });

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
            tags: const [],
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
    return Stream<List<Quote>>.value(_makeQuotes(60));
  }

  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
  }) async {}

  @override
  Future<List<NoteCategory>> getCategories() async => const [];
}

List<Quote> _makeQuotes(int count) {
  return List<Quote>.generate(
    count,
    (index) => Quote(
      id: 'quote-$index',
      content: '滚动测试笔记 $index\n${'较长内容 ' * 20}',
      date: DateTime(2026, 5, 10, 8, index).toIso8601String(),
    ),
  );
}
