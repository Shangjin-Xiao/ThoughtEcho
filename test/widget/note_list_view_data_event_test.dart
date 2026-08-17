library;

import 'dart:async';

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
import 'package:thoughtecho/widgets/quote_item_widget.dart';

int? _listItemCount(WidgetTester tester) {
  final listView = tester.widget<ListView>(find.byType(ListView));
  return (listView.childrenDelegate as SliverChildBuilderDelegate)
      .estimatedChildCount;
}

/// [expandable] 为真时正文长到超过折叠盒高度，笔记因此带展开入口。
List<Quote> _makeQuotes(int count, {bool expandable = false}) => [
      for (var i = 0; i < count; i++)
        Quote(
          id: 'quote-$i',
          content: expandable
              ? List.filled(30, '数据事件测试笔记 $i 的正文').join('\n')
              : '数据事件测试笔记 $i',
          date: DateTime(2026, 8, 17, 9)
              .subtract(Duration(minutes: i))
              .toIso8601String(),
        ),
    ];

QuoteItemWidget _firstItem(WidgetTester tester) =>
    tester.widget<QuoteItemWidget>(find.byType(QuoteItemWidget).first);

ScrollPosition _noteListScrollPosition(WidgetTester tester) {
  final listView = tester.widget<ListView>(find.byType(ListView));
  for (final element in find
      .descendant(
        of: find.byWidget(listView),
        matching: find.byType(Scrollable),
      )
      .evaluate()) {
    final scrollable = element.widget as Scrollable;
    if (identical(scrollable.controller, listView.controller)) {
      return ((element as StatefulElement).state as ScrollableState).position;
    }
  }
  throw StateError('未找到笔记列表的 ScrollPosition');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoteListView 数据事件', () {
    testWidgets(
      '重复推来同一批笔记实例时不重建列表项',
      (tester) async {
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final quotes = _makeQuotes(12);

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();

        databaseService.emit(quotes, hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final itemBefore = _firstItem(tester);
        final extentBefore = _noteListScrollPosition(tester).maxScrollExtent;

        // watchQuotes 每次都重发整个累积列表：分页到底、重复通知推来的就是这样
        // 一份逐条同一实例的列表，内容一个字都没变。
        databaseService.emit(quotes, hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          identical(_firstItem(tester), itemBefore),
          isTrue,
          reason: '内容没变的数据事件不应触发整列表重建',
        );
        expect(
          _noteListScrollPosition(tester).maxScrollExtent,
          closeTo(extentBefore, 0.5),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      '"有没有可展开笔记"的回填不再多排一次整列表重建',
      (tester) async {
        // 数据事件本身重建一次是应该的；此前帧末的可展开性回填会**再**重建一次，
        // 因为它先把缓存清成 false，再拿新答案和刚清掉的值比。
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();

        databaseService.emit(_makeQuotes(6, expandable: true), hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 换一批新实例，模拟一次真实的数据变更：这次事件本身必须重建。
        databaseService.emit(_makeQuotes(6, expandable: true), hasMore: true);
        await tester.pump();
        final afterDataEvent = _firstItem(tester);

        // 帧末回调若又排了一次 setState，下一帧就会再换一批 widget 实例。
        await tester.pump();

        expect(
          identical(_firstItem(tester), afterDataEvent),
          isTrue,
          reason: '可展开性没变时不该再触发一次整列表重建',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      '翻到最后一页仍然要重建，尾部占位跟着收起',
      (tester) async {
        // `_hasMore` 参与 itemCount，所以这次事件必须走 setState。尾部那一格
        // 不能常驻：常驻会让 maxScrollExtent 长期多估一张卡片的高度。
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final quotes = _makeQuotes(12);

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();

        databaseService.emit(quotes, hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(_listItemCount(tester), quotes.length + 1);

        databaseService.emit(quotes, hasMore: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(_listItemCount(tester), quotes.length);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      '推来新的笔记实例时照常重建列表项',
      (tester) async {
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();

        databaseService.emit(_makeQuotes(12), hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final itemBefore = _firstItem(tester);

        // 笔记被编辑过：重新查询出来的是新对象，必须重建。
        databaseService.emit(
          [
            Quote(
              id: 'quote-0',
              content: '改过内容的第一条',
              date: DateTime(2026, 8, 17, 9).toIso8601String(),
            ),
            ..._makeQuotes(12).skip(1),
          ],
          hasMore: true,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(identical(_firstItem(tester), itemBefore), isFalse);
        expect(find.text('改过内容的第一条'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.databaseService,
    required this.settingsService,
  });

  final DatabaseService databaseService;
  final SettingsService settingsService;

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
            tags: const <NoteTag>[],
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

class _StreamingFakeDatabaseService extends DatabaseService {
  _StreamingFakeDatabaseService() : super.forTesting();

  final StreamController<List<Quote>> _controller =
      StreamController<List<Quote>>.broadcast();
  bool _hasMoreQuotes = true;

  @override
  bool get isInitialized => true;

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
    bool includeDeleted = false,
  }) {
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
    int? refillCount,
    bool suppressNotify = false,
  }) async {}

  @override
  Future<List<NoteTag>> getTags() async => const [];

  /// 真实实现推的是 `List.from(_currentQuotes)`：列表对象是新的，元素是原来那批。
  void emit(List<Quote> quotes, {required bool hasMore}) {
    _hasMoreQuotes = hasMore;
    _controller.add(List<Quote>.from(quotes));
  }

  Future<void> disposeStream() => _controller.close();
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
