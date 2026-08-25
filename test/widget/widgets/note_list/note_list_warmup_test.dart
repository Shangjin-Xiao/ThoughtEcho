import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

/// 空闲预热的全部价值在于它算出来的缓存键和卡片渲染时问的键**一模一样**。
/// 差一个像素、差一档字重，预热就变成静悄悄的空转：日志里只会看到
/// `planMiss+` / `expandMiss+` 没降，而没人知道为什么。
///
/// 这个文件钉的就是这条不变量：先暖，再真的把卡片建出来，未命中数必须一次都不涨。
/// 这个项目已经吃过一次"缓存一次都没命中"的亏（见 beab8ca），不能再吃第二次。
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
  String get noteInsertAnimationType => 'slide';

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  bool get noteListDisableCardShadows => false;

  @override
  bool get noteListDisableBackdropBlur => false;

  @override
  String get exportFormat => 'card';

  @override
  String get noteCardMediaStyle => NoteCardMediaStyle.thumbnail;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

const String _longChunk = '这是一段足够长的正文，用来把折叠盒撑满，好让折叠判定和折叠排版都真的跑起来。';

Quote _plainQuote() => Quote(
      id: 'plain-1',
      content: List.filled(8, _longChunk).join('\n'),
      date: DateTime(2025, 6, 21, 9).toIso8601String(),
      editSource: 'inline',
      dayPeriod: 'morning',
    );

/// 带位置和天气：卡片头部三段文字（日期 / 位置 / 天气）全都要测宽，
/// 只有日期的话，位置和天气那两段的键对不对得上就没人验。
Quote _richQuote() => Quote(
      id: 'rich-1',
      content: List.filled(8, _longChunk).join('\n'),
      deltaContent: jsonEncode([
        for (var i = 0; i < 8; i++) {'insert': '$_longChunk\n'},
      ]),
      date: DateTime(2025, 6, 21, 9).toIso8601String(),
      editSource: 'fullscreen',
      dayPeriod: 'morning',
      location: '浙江省 杭州市 西湖区',
      latitude: 30.2,
      longitude: 120.1,
      weather: 'clear',
      temperature: '21°C',
    );

int _planMisses() => (QuoteContent.debugCacheStats()['plan']
    as Map<String, dynamic>)['missCount'] as int;

int _expansionMisses() => (QuoteContent.debugCacheStats()['expansion']
    as Map<String, dynamic>)['missCount'] as int;

int _expansionCacheSize() => (QuoteContent.debugCacheStats()['expansion']
    as Map<String, dynamic>)['cacheSize'] as int;

/// 头部测宽（日期 / 位置 / 天气）的未命中次数。标签估宽走同一张缓存表但
/// `countAsHeader: false`，不会混进这个数。
int _headerMisses() =>
    QuoteItemWidget.getHeaderTextWidthCacheStats()['cacheMisses']!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    QuoteContent.clearCacheForTesting();
    QuoteItemWidget.clearExpansionCacheForTest();
    QuoteItemWidget.lastCollapsedContentWidth = null;
  });

  Future<BuildContext> pumpCard(
    WidgetTester tester,
    Quote quote, {
    required Key key,
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: _FakeSettingsService(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return QuoteItemWidget(
                  key: key,
                  quote: quote,
                  tagMap: const {},
                  isExpanded: false,
                  onToggleExpanded: (_) {},
                  onEdit: () {},
                  onDelete: () {},
                  onAskAI: () {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 折叠盒对超长富文本会溢出几个像素再被 ClipRect 裁掉（改动前后一致，
    // 见 docs/note-list-first-paint-cost-2026-08-19.md 的遗留项），
    // 这里只关心缓存命中，不让它把测试带偏。
    tester.takeException();
    return captured;
  }

  for (final entry in <String, ({Quote Function() build, bool warmsPlan})>{
    '纯文本': (build: _plainQuote, warmsPlan: false),
    '富文本': (build: _richQuote, warmsPlan: true),
  }.entries) {
    testWidgets('预热过的${entry.key}卡片建出来时一次未命中都不再产生', (tester) async {
      final quote = entry.value.build();

      // 先真的建一次，拿到卡片正文区的实际布局宽度。
      final context = await pumpCard(tester, quote, key: const ValueKey('a'));
      final width = QuoteItemWidget.lastCollapsedContentWidth;
      expect(width, isNotNull, reason: '卡片建出来后必须回填正文布局宽度');
      expect(width, greaterThan(0));

      // 清空所有测量缓存，模拟"这条笔记还没被任何卡片量过"。
      QuoteContent.clearCacheForTesting();
      QuoteItemWidget.clearExpansionCacheForTest();

      QuoteItemWidget.warmCollapsedMeasurements(
        context: context,
        quote: quote,
        contentMaxWidth: width!,
        mediaStyle: NoteCardMediaStyle.thumbnail,
        prioritizeBoldContent: false,
        showExactTime: false,
      );

      final planMissesAfterWarmup = _planMisses();
      final expansionMissesAfterWarmup = _expansionMisses();
      final headerMissesAfterWarmup = _headerMisses();
      expect(
        headerMissesAfterWarmup,
        greaterThan(0),
        reason: '预热必须真的量过头部那几段文字',
      );
      expect(
        expansionMissesAfterWarmup,
        greaterThan(0),
        reason: '预热必须真的算过折叠判定，否则这个测试什么都没验证',
      );
      if (entry.value.warmsPlan) {
        expect(
          planMissesAfterWarmup,
          greaterThan(0),
          reason: '富文本的预热必须真的跑过折叠排版',
        );
      }

      // 换 key 强制整棵子树重建：折叠判定和折叠排版都会重新问一次缓存。
      await pumpCard(tester, quote, key: const ValueKey('b'));

      expect(
        _expansionMisses(),
        expansionMissesAfterWarmup,
        reason: '折叠判定的键和预热对不上',
      );
      expect(
        _planMisses(),
        planMissesAfterWarmup,
        reason: '折叠排版的键和预热对不上',
      );
      expect(
        _headerMisses(),
        headerMissesAfterWarmup,
        reason: '头部测宽的键和预热对不上',
      );
    });
  }

  testWidgets('测量缓存被清空后，回到前台必须重新预热', (tester) async {
    // App 进后台时 `main.dart` 会把 QuoteContent 的测量缓存整排清掉（省内存）。
    // 预热的游标停在列表末尾不动，只比对宽度和版式的话，回到前台后这一轮直接判定
    // 「暖完了」—— 缓存是空的、游标是满的，接下来每张卡片滑进来都要现算一遍折叠
    // 判定和折叠排版。线上日志里这条路径长这样：`warmup={items=121,cursor=121/121}`
    // 看着很美，`expand=` 却恰好等于「一共建出来过几张卡」。
    final databaseService = _StreamingFakeDatabaseService();
    final quotes = [
      for (var i = 0; i < 120; i++)
        Quote(
          id: 'rewarm-$i',
          content: '缓存清空后重新预热测试笔记 $i',
          date: DateTime(2026, 8, 22, 9)
              .subtract(Duration(minutes: i))
              .toIso8601String(),
          editSource: 'inline',
          dayPeriod: 'morning',
        ),
    ];

    await tester.pumpWidget(
      _TestApp(
        databaseService: databaseService,
        settingsService: _FakeSettingsService(),
      ),
    );
    await tester.pump();
    databaseService.emit(quotes, hasMore: false);
    await tester.pump();

    Future<void> settleIdleWork() async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    int builtCards() =>
        find.byType(QuoteItemWidget, skipOffstage: false).evaluate().length;

    await settleIdleWork();

    expect(
      _expansionCacheSize(),
      greaterThanOrEqualTo(quotes.length),
      reason: '静止期预热应当把整张列表的折叠判定都暖好',
    );
    // 缓存里的量必须是预热做的，不能是「卡片全建出来了」这种平凡解，
    // 否则下面那条断言换成什么实现都能过。
    expect(
      builtCards(),
      lessThan(quotes.length),
      reason: '这个用例要证明的是预热覆盖了没建出来的条目',
    );

    // 模拟 main.dart 在 AppLifecycleState.paused 里做的事。
    QuoteContent.resetCaches();
    expect(_expansionCacheSize(), 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleIdleWork();

    expect(
      _expansionCacheSize(),
      greaterThanOrEqualTo(quotes.length),
      reason: '缓存被清空后预热没有重跑：游标停在列表末尾，'
          '下一次滑动每张卡片都要重算一遍折叠判定',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    await databaseService.disposeStream();
  });

  testWidgets('缓存清空后先暖视口附近的，而不是从第 0 条开始', (tester) async {
    // 2026-08-23 的日志：用户停在第 45~72 条往回滑，预热进度却是 `cursor=23/121`
    // —— 功夫全花在了屏幕外面的头 23 条，滑到的每一张还是要现算。
    final databaseService = _StreamingFakeDatabaseService();
    final quotes = [
      for (var i = 0; i < 120; i++)
        Quote(
          id: 'order-$i',
          content: '预热顺序测试笔记 $i',
          date: DateTime(2026, 8, 23, 9)
              .subtract(Duration(minutes: i))
              .toIso8601String(),
          editSource: 'inline',
          dayPeriod: 'morning',
        ),
    ];

    await tester.pumpWidget(
      _TestApp(
        databaseService: databaseService,
        settingsService: _FakeSettingsService(),
      ),
    );
    await tester.pump();
    databaseService.emit(quotes, hasMore: false);
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 滚到列表中段，让视口锚点明确地离 0 很远。
    final position = tester
        .state<ScrollableState>(
          find
              .ancestor(
                of: find.byType(QuoteItemWidget).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.text('预热顺序测试笔记 0'),
      findsNothing,
      reason: '列表要真的滚离开头，否则这个用例什么都没验证',
    );

    final context = tester.element(find.byType(QuoteItemWidget).first);
    final width = QuoteItemWidget.lastCollapsedContentWidth!;
    int missesWhenWarming(Quote quote) {
      final before = _expansionMisses();
      QuoteItemWidget.warmCollapsedMeasurements(
        context: context,
        quote: quote,
        contentMaxWidth: width,
        mediaStyle: NoteCardMediaStyle.thumbnail,
        prioritizeBoldContent: false,
        showExactTime: false,
      );
      return _expansionMisses() - before;
    }

    // 模拟系统内存压力清掉全部测量缓存，然后只放一轮预热过去。
    QuoteContent.resetCaches();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 420));

    // 屏幕上这一条必须已经暖好；列表最开头那条这一轮还轮不到。
    final visibleQuote = quotes.firstWhere(
      (quote) => find.text(quote.content).evaluate().isNotEmpty,
    );
    expect(
      missesWhenWarming(visibleQuote),
      0,
      reason: '视口里的这一条应当在第一轮就暖好',
    );
    expect(
      missesWhenWarming(quotes.first),
      1,
      reason: '预热还在从第 0 条开始往下走，屏幕上的卡片要等它走完才轮得到',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    await databaseService.disposeStream();
  });

  testWidgets('静止期把缓存区一级一级撑大，提前建出下一屏的卡片', (tester) async {
    final databaseService = _StreamingFakeDatabaseService();
    final quotes = [
      for (var i = 0; i < 40; i++)
        Quote(
          id: 'warm-$i',
          content: '缓存区预建测试笔记 $i',
          date: DateTime(2026, 8, 19, 9)
              .subtract(Duration(minutes: i))
              .toIso8601String(),
          editSource: 'inline',
          dayPeriod: 'morning',
        ),
    ];

    await tester.pumpWidget(
      _TestApp(
        databaseService: databaseService,
        settingsService: _FakeSettingsService(),
      ),
    );
    await tester.pump();
    databaseService.emit(quotes, hasMore: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 缓存区里的卡片是**建好但不绘制**的，默认的 finder 会把它们当 offstage 跳过 ——
    // 这里要数的恰恰是它们，所以必须 skipOffstage: false。
    int builtCards() =>
        find.byType(QuoteItemWidget, skipOffstage: false).evaluate().length;

    final builtBefore = builtCards();
    expect(builtBefore, greaterThan(0), reason: '首屏应当已经建出卡片');

    // 静止期：预热跑完测量之后开始一级一级撑缓存区，每级 16ms。
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      builtCards(),
      greaterThan(builtBefore),
      reason: '静止期应当提前把下一屏的卡片建出来，否则这批挂载还会落在滚动帧里',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    await databaseService.disposeStream();
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

  void emit(List<Quote> quotes, {required bool hasMore}) {
    _hasMoreQuotes = hasMore;
    _controller.add(List<Quote>.from(quotes));
  }

  Future<void> disposeStream() => _controller.close();
}
