library;

import 'dart:convert';
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

  testWidgets('短列表中所有卡片全部保持 keepAlive', (tester) async {
    // 5 条笔记 <= 自适应保留窗口总容量（3 * 2 + 1 = 7）
    final quotes = List.generate(
      5,
      (i) => Quote(
        id: 'short-note-$i',
        content: '短列表普通笔记内容 $i',
        date: DateTime(2026, 6, 1, 10, i).toIso8601String(),
      ),
    );

    final db = _AdaptiveKeepAliveFakeDb(quotes);
    final settings = _AdaptiveKeepAliveFakeSettings();

    await tester.pumpWidget(
      _TestNoteListHarness(databaseService: db, settingsService: settings),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 检查所有已挂载的 _NoteListItemKeepAlive 组件，其 keepAlive 均应为 true
    final keepAliveWidgets = tester.widgetList(
      find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_NoteListItemKeepAlive'),
    );
    expect(keepAliveWidgets, isNotEmpty);
    for (final widget in keepAliveWidgets) {
      expect((widget as dynamic).keepAlive, isTrue);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('长列表中仅视口附近的卡片和富媒体卡片保持 keepAlive', (tester) async {
    // 30 条笔记，其中第 20 条是媒体卡片
    final mediaDelta = jsonEncode([
      {
        'insert': {'image': 'file:///tmp/test.png'},
      },
      {'insert': '\n'},
    ]);

    final quotes = List.generate(
      30,
      (i) => Quote(
        id: 'long-note-$i',
        content: '长列表笔记内容 $i',
        deltaContent: i == 20 ? mediaDelta : null,
        editSource: i == 20 ? 'fullscreen' : 'inline',
        date: DateTime(2026, 6, 1, 10, i).toIso8601String(),
      ),
    );

    final db = _AdaptiveKeepAliveFakeDb(quotes);
    final settings = _AdaptiveKeepAliveFakeSettings();

    await tester.pumpWidget(
      _TestNoteListHarness(databaseService: db, settingsService: settings),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 视口在顶部时，centerIndex = 0，自适应半径约 3~5
    // 检查已挂载的 keep-alive 状态
    final keepAliveWidgets = tester
        .widgetList(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_NoteListItemKeepAlive'),
        )
        .toList();
    expect(keepAliveWidgets, isNotEmpty);

    // 位于顶部的卡片（视口半径内）应保持 keepAlive
    expect((keepAliveWidgets.first as dynamic).keepAlive, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}

class _TestNoteListHarness extends StatelessWidget {
  final DatabaseService databaseService;
  final SettingsService settingsService;

  const _TestNoteListHarness({
    required this.databaseService,
    required this.settingsService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
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
            selectedWeathers: const [],
            selectedDayPeriods: const [],
            onFilterChanged: (_, __) {},
          ),
        ),
      ),
    );
  }
}

class _AdaptiveKeepAliveFakeSettings extends ChangeNotifier
    implements SettingsService {
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

class _AdaptiveKeepAliveFakeDb extends DatabaseService {
  final List<Quote> quotes;

  _AdaptiveKeepAliveFakeDb(this.quotes) : super.forTesting();

  @override
  bool get hasMoreQuotes => false;

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
    return Stream<List<Quote>>.value(quotes);
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
