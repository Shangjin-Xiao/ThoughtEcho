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

  group('NoteListView search transition scroll preservation', () {
    testWidgets(
      'deleting a search character keeps the scroll offset across the '
      'results crossfade instead of flashing the scrolled old list at top',
      (tester) async {
        final databaseService = _SearchFakeDatabase();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 输入“你们”，等待防抖与查询完成
        await tester.enterText(find.byType(TextField), '你们');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 500));
        expect(databaseService.lastQuery, '你们');

        // 滚动搜索结果，使列表停在中间位置
        _noteListScrollPositions(tester).single.jumpTo(600);
        await tester.pump();
        expect(_noteListScrollPositions(tester).single.pixels, 600);

        // 删掉一个字 -> “你”（单字立即触发）
        await tester.enterText(find.byType(TextField), '你');

        // 交叉淡化期间（200ms）新列表应与旧列表对齐到同一滚动偏移，
        // 而不是从顶部开始让旧的已滚动列表在搜索栏下方淡出闪烁。
        var sawIncomingAlignedDuringFade = false;
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final positions = _noteListScrollPositions(tester);
          if (positions.length > 1 &&
              positions.every(
                (position) => (position.pixels - 600).abs() <= 1,
              )) {
            sawIncomingAlignedDuringFade = true;
          }
        }

        expect(sawIncomingAlignedDuringFade, isTrue);

        await tester.pump(const Duration(milliseconds: 300));

        // 淡化结束后列表保持删除前的滚动位置，而不是跳回顶部
        final positions = _noteListScrollPositions(tester);
        expect(positions, hasLength(1));
        expect(positions.single.pixels, closeTo(600, 1));

        await tester.pumpWidget(const SizedBox.shrink());
        // 冲刷 NoteListView 的 4 秒搜索超时保护定时器
        await tester.pump(const Duration(seconds: 5));
        await databaseService.disposeStream();
      },
    );
  });
}

/// 收集所有笔记 ListView（交叉淡化期间会有两个）自身 Scrollable 的 position，
/// 通过 controller 同一性匹配，跳过条目内容和搜索框里的其它 Scrollable。
List<ScrollPosition> _noteListScrollPositions(WidgetTester tester) {
  final positions = <ScrollPosition>[];
  for (final listViewElement in find.byType(ListView).evaluate()) {
    final listView = listViewElement.widget as ListView;
    for (final element in find
        .descendant(
          of: find.byWidget(listView),
          matching: find.byType(Scrollable),
        )
        .evaluate()) {
      final scrollable = element.widget as Scrollable;
      if (identical(scrollable.controller, listView.controller)) {
        final state = (element as StatefulElement).state as ScrollableState;
        positions.add(state.position);
      }
    }
  }
  return positions;
}

class _TestApp extends StatefulWidget {
  final _SearchFakeDatabase databaseService;
  final _FakeSettingsService settingsService;

  const _TestApp({
    required this.databaseService,
    required this.settingsService,
  });

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  final NoteSearchController _searchController = NoteSearchController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        ChangeNotifierProvider<NoteSearchController>.value(
          value: _searchController,
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Material(
          child: AnimatedBuilder(
            animation: _searchController,
            builder: (context, _) {
              return NoteListView(
                tags: [NoteCategory(id: 'tag-1', name: '标签一', iconName: '🏷️')],
                selectedTagIds: const [],
                onTagSelectionChanged: (_) {},
                searchQuery: _searchController.searchQuery,
                sortType: 'time',
                sortAscending: false,
                onSortChanged: (_, __) {},
                onSearchChanged: _searchController.updateSearch,
                onEdit: (_) {},
                onDelete: (_) {},
                onAskAI: (_) {},
                selectedWeathers: const [],
                selectedDayPeriods: const [],
                onFilterChanged: (_, __) {},
              );
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

class _SearchFakeDatabase extends DatabaseService {
  final StreamController<List<Quote>> _controller =
      StreamController<List<Quote>>.broadcast();
  final List<Timer> _pendingTimers = [];
  String? lastQuery;

  _SearchFakeDatabase() : super.forTesting();

  @override
  bool get isInitialized => true;

  @override
  bool get hasMoreQuotes => false;

  List<Quote> _resultsFor(String query) {
    final count = switch (query) {
      '你们' => 12,
      '你' => 15,
      _ => 30,
    };
    return List<Quote>.generate(
      count,
      (index) => Quote(
        id: '$query-quote-$index',
        content: '包含$query的笔记 $index\n第二行内容，让卡片有一定高度',
        date: DateTime(2026, 7, 1, 10, index).toIso8601String(),
        tagIds: const ['tag-1'],
      ),
    );
  }

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
    lastQuery = searchQuery;
    final query = searchQuery ?? '';
    // 模拟真实查询延迟
    final timer = Timer(const Duration(milliseconds: 60), () {
      if (!_controller.isClosed) {
        _controller.add(_resultsFor(query));
      }
    });
    _pendingTimers.add(timer);
    return _controller.stream;
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

  Future<void> disposeStream() async {
    for (final timer in _pendingTimers) {
      timer.cancel();
    }
    await _controller.close();
  }
}
