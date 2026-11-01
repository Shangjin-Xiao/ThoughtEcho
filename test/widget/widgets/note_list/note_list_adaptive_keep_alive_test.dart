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

    bool? isKeepAliveFor(String quoteId) {
      final finder = find.descendant(
        of: find.byKey(ValueKey('note_item_motion_$quoteId')),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_NoteListItemKeepAlive',
        ),
      );
      if (finder.evaluate().isEmpty) return null;
      return (tester.widget(finder) as dynamic).keepAlive as bool;
    }

    // 滑动跳过前几个普通条目至第 10 项附近
    // 旧半径 18 会将已划出视口的普通第 0 项持续保留在树中；
    // 而自适应半径（3~5）则会及时释放离屏普通卡片，仅富媒体卡片强制常驻。
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 普通卡片第 0 项已滑出保留窗口，不再保留在活动树中
    expect(isKeepAliveFor('long-note-0'), isNull);

    // 滚动至第 20 条富媒体卡片附近
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 富媒体卡片已挂载且始终保持 keepAlive
    expect(isKeepAliveFor('long-note-20'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('变高长列表中滚动时基于实测可视索引保持卡片 keepAlive', (tester) async {
    // 构造变高列表：前 20 条为短卡片（~100dp），后 10 条为高卡片（~400dp）
    // 若仅根据滚动偏移估算中心，当滑动到高卡片时估算中心会严重滞后（停留在短卡片索引），
    // 导致可视区域内的高卡片过早被判定为超出自适应半径而无法保留。
    final quotes = <Quote>[
      ...List.generate(
        20,
        (i) => Quote(
          id: 'var-short-$i',
          content: '短卡片内容 $i',
          date: DateTime(2026, 6, 1, 10, i).toIso8601String(),
        ),
      ),
      ...List.generate(
        10,
        (i) => Quote(
          id: 'var-tall-${20 + i}',
          content: '变高长卡片内容第 ${20 + i} 条：\n'
              '${'这是撑高内容行，用于拉大不同卡片高度差。\n' * 8}'
              '结束标记',
          date: DateTime(2026, 6, 1, 11, i).toIso8601String(),
        ),
      ),
    ];

    final db = _AdaptiveKeepAliveFakeDb(quotes);
    final settings = _AdaptiveKeepAliveFakeSettings();

    await tester.pumpWidget(
      _TestNoteListHarness(databaseService: db, settingsService: settings),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    bool? isKeepAliveFor(String quoteId) {
      final finder = find.descendant(
        of: find.byKey(ValueKey('note_item_motion_$quoteId')),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_NoteListItemKeepAlive',
        ),
      );
      if (finder.evaluate().isEmpty) return null;
      return (tester.widget(finder) as dynamic).keepAlive as bool;
    }

    // 初始状态顶部短卡片保持 keepAlive
    expect(isKeepAliveFor('var-short-0'), isTrue);

    // 滚动至第 20 条高卡片进入视口
    final tallCardFinder = find.byKey(
      const ValueKey('note_item_motion_var-tall-20'),
    );
    await tester.scrollUntilVisible(
      tallCardFinder,
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 实测可视范围内的高卡片（第 20 条）必须保持 keepAlive
    expect(isKeepAliveFor('var-tall-20'), isTrue);

    // 此时远离视口的顶部短卡片已被正常释放
    expect(isKeepAliveFor('var-short-0'), isNull);

    // 稍作微调滚动，确认可视及近邻高卡片依然稳定保持 keepAlive，不发生抖动销毁
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(isKeepAliveFor('var-tall-20'), isTrue);

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
