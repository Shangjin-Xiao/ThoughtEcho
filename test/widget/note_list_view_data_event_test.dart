library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/webdav_sync_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/theme/app_semantic_colors.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/widgets/app_error_view.dart';
import 'package:thoughtecho/widgets/app_loading_view.dart';
import 'package:thoughtecho/widgets/note_list/note_item_motion.dart';
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

/// 探测"列表项有没有被重建"用的是动效层而不是 [QuoteItemWidget]：
/// 后者会被 `_obtainQuoteItem` 记忆化，重建与否都是同一个实例，测不出重建。
/// 动效层每次 itemBuilder 都新建，实例变了就说明这一格真的重建过。
NoteItemMotion _firstItemMotion(WidgetTester tester) =>
    tester.widget<NoteItemMotion>(find.byType(NoteItemMotion).first);

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

        final itemBefore = _firstItemMotion(tester);
        final extentBefore = _noteListScrollPosition(tester).maxScrollExtent;

        // watchQuotes 每次都重发整个累积列表：分页到底、重复通知推来的就是这样
        // 一份逐条同一实例的列表，内容一个字都没变。
        databaseService.emit(quotes, hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          identical(_firstItemMotion(tester), itemBefore),
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
        final afterDataEvent = _firstItemMotion(tester);

        // 帧末回调若又排了一次 setState，下一帧就会再换一批 widget 实例。
        await tester.pump();

        expect(
          identical(_firstItemMotion(tester), afterDataEvent),
          isTrue,
          reason: '可展开性没变时不该再触发一次整列表重建',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      '整列表重建时，入参没变的卡片复用同一个 widget 实例',
      (tester) async {
        // 有些重建躲不掉（这里用 `_hasMore` 翻转触发，父组件重建同理）。躲不掉时
        // 至少要让它便宜：入参没变的卡片返回同一个实例，`Element.updateChild`
        // 会把整棵子树短路掉，连折叠判定和排版计划都不重跑。
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

        final motionBefore = _firstItemMotion(tester);
        final itemBefore = _firstItem(tester);

        databaseService.emit(quotes, hasMore: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          identical(_firstItemMotion(tester), motionBefore),
          isFalse,
          reason: '这次事件确实重建了列表，否则下面那条断言不成立',
        );
        expect(
          identical(_firstItem(tester), itemBefore),
          isTrue,
          reason: '入参没变的卡片应当复用同一个 widget 实例',
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
      '推来内容相同的新实例时不重建列表项',
      (tester) async {
        // 数据库一旦重新查询（回前台刷新、重新订阅），就会造出一批全新的 Quote
        // 对象。内容一个字没改，身份却全变了 —— 按 identical 判断的卡片记忆化
        // 于是整屏失效。2026-08-23 的日志：itemMemo hit+0 / miss+113、
        // worstBuild=74.9ms，113 张卡片在一个滚动帧里重建完。
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

        final itemBefore = _firstItemMotion(tester);

        // 同样的内容、全新的对象。
        final requeried = _makeQuotes(12);
        expect(identical(requeried.first, _firstItem(tester).quote), isFalse);
        databaseService.emit(requeried, hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          identical(_firstItemMotion(tester), itemBefore),
          isTrue,
          reason: '内容没变的行应当沿用旧实例，卡片记忆化才不会整屏落空',
        );

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

        final itemBefore = _firstItemMotion(tester);

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

        expect(identical(_firstItemMotion(tester), itemBefore), isFalse);
        expect(find.text('改过内容的第一条'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );
  });

  group('NoteListView 生命周期门控与错误恢复闭环', () {
    late _WidgetRecordingLogService logService;

    setUp(() {
      logService = _WidgetRecordingLogService();
      AppLogger.serviceForTesting = logService;
    });

    tearDown(() {
      AppLogger.serviceForTesting = UnifiedLogService.instance;
    });

    testWidgets(
      '后台/隐藏生命周期立即取消安全定时器（0 次无效刷新），回到前台仅单次干净恢复',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();
        expect(find.byType(AppLoadingView), findsOneWidget);

        // 首屏尚未返回时按真实系统状态机转入后台：安全定时器立即取消，60 秒后台停留零刷新。
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 60));

        expect(databaseService.refreshQuotesCallCount, 0);
        expect(find.byType(AppLoadingView), findsOneWidget);
        expect(find.byType(AppErrorView), findsNothing);

        // 按真实系统状态机回到前台 resumed：仅触发 1 次恢复刷新，数据到达后正常渲染列表。
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(databaseService.refreshQuotesCallCount, 1);

        databaseService.emit(_makeQuotes(3), hasMore: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('数据事件测试笔记 0'), findsOneWidget);
        expect(find.byType(AppLoadingView), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      '首屏已加载后在非活跃态触发同步刷新：后台保持旧列表，切回 resumed 自动补跑刷新展示新内容',
      (tester) async {
        var lifecycle = AppLifecycleState.resumed;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);

        final databaseService = _LifecycleAwareRealPaginationDbService(
          initialQuotes: _makeQuotes(2),
          readLifecycle: () => lifecycle,
        );
        DatabaseService.setDebugLifecycleStateProvider(
          databaseService,
          () => lifecycle,
        );
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('数据事件测试笔记 0'), findsOneWidget);
        expect(find.text('后台同步合入的新笔记'), findsNothing);

        // 应用切入 inactive / paused 后，模拟 WebDAV 同步合并完成并调用 refreshQuotes()。
        lifecycle = AppLifecycleState.inactive;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.hidden;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.paused;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();

        databaseService.quotes = [
          Quote(
            id: 'synced-quote',
            content: '后台同步合入的新笔记',
            date: DateTime(2026, 8, 18, 9).toIso8601String(),
          ),
          ..._makeQuotes(2),
        ];
        databaseService.refreshQuotes();
        await tester.pump();

        // 后台期间旧列表保持可见且不闪现错误视图。
        expect(find.text('数据事件测试笔记 0'), findsOneWidget);
        expect(find.text('后台同步合入的新笔记'), findsNothing);
        expect(find.byType(AppErrorView), findsNothing);

        // 回到前台 resumed：NoteListView 自动消费挂起的延迟刷新并渲染同步后的新笔记。
        lifecycle = AppLifecycleState.hidden;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.inactive;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.resumed;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('后台同步合入的新笔记'), findsOneWidget);
        expect(find.text('数据事件测试笔记 0'), findsOneWidget);

        DatabaseService.setDebugLifecycleStateProvider(databaseService, null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        databaseService.dispose();
      },
    );

    testWidgets(
      '已加载列表在后台挂起刷新后切回 resumed，同时存在未完成的公开 getUserQuotes(offset: 0, limit: 50) 时仍补跑刷新展示新笔记',
      (tester) async {
        var lifecycle = AppLifecycleState.resumed;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);

        final fakeSqlDb = _InMemoryInterceptingSqfliteDb(
          quotes: _makeQuotes(2),
        );
        DatabaseService.setTestDatabase(fakeSqlDb);
        final databaseService = _FullQueryPipelineTestDbService();
        DatabaseService.setDebugLifecycleStateProvider(
          databaseService,
          () => lifecycle,
        );
        addTearDown(() {
          DatabaseService.setDebugLifecycleStateProvider(databaseService, null);
          DatabaseService.clearTestDatabase();
        });
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('数据事件测试笔记 0'), findsOneWidget);
        expect(find.text('并发巡检期间合入的新笔记'), findsNothing);

        // 切入后台后合入新笔记并连续触发两次 refreshQuotes()，使刷新挂起并记录延迟刷新标记。
        lifecycle = AppLifecycleState.inactive;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.hidden;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.paused;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();

        fakeSqlDb.quotes = [
          Quote(
            id: 'synced-while-public-query-inflight',
            content: '并发巡检期间合入的新笔记',
            date: DateTime(2026, 8, 19, 9).toIso8601String(),
          ),
          ..._makeQuotes(2),
        ];
        databaseService.refreshQuotes();
        databaseService.refreshQuotes();
        await tester.pump();

        // 发起一笔挂起未完成的公开 getUserQuotes(offset: 0, limit: 50)（模拟后台备份/媒体扫描）。
        final publicReadGate = Completer<void>();
        fakeSqlDb.holdLimit50QueryUntil = publicReadGate.future;
        final publicReadFuture = databaseService.getUserQuotes(
          offset: 0,
          limit: 50,
        );
        await tester.pump();

        expect(
          DatabaseService.isPaginationQueryInFlight(databaseService),
          isFalse,
          reason: '公开非门控 getUserQuotes 在途查询不应阻塞 UI 分页恢复判断',
        );

        // 切回 resumed（公开 getUserQuotes 仍处于未完成在途状态）：延迟刷新不被吞没，新笔记正常渲染。
        lifecycle = AppLifecycleState.hidden;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.inactive;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.resumed;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('并发巡检期间合入的新笔记'), findsOneWidget);
        expect(find.text('数据事件测试笔记 0'), findsOneWidget);

        // 放行公开 getUserQuotes，确认其同样完整返回 3 条记录。
        publicReadGate.complete();
        await tester.pump();
        final exportedQuotes = await publicReadFuture;
        expect(exportedQuotes, hasLength(3));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        databaseService.dispose();
      },
    );

    testWidgets(
      '已加载列表在后台挂起刷新后切回 resumed，即使此刻存在真实的 UI 分页查询在途仍不吞没延迟刷新标记',
      (tester) async {
        var lifecycle = AppLifecycleState.resumed;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);

        final fakeSqlDb = _InMemoryInterceptingSqfliteDb(
          quotes: _makeQuotes(55),
        );
        DatabaseService.setTestDatabase(fakeSqlDb);
        final databaseService = _FullQueryPipelineTestDbService();
        DatabaseService.setDebugLifecycleStateProvider(
          databaseService,
          () => lifecycle,
        );
        addTearDown(() {
          DatabaseService.setDebugLifecycleStateProvider(databaseService, null);
          DatabaseService.clearTestDatabase();
        });
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('数据事件测试笔记 0'), findsOneWidget);
        expect(find.text('翻页在途时后台合入的新笔记'), findsNothing);
        expect(databaseService.hasMoreQuotes, isTrue);

        // 切入后台后合入新顶部笔记并触发 refreshQuotes()，使其挂起并记录延迟刷新标记。
        lifecycle = AppLifecycleState.inactive;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.hidden;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        lifecycle = AppLifecycleState.paused;
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();

        fakeSqlDb.quotes = [
          Quote(
            id: 'synced-while-pagination-inflight',
            content: '翻页在途时后台合入的新笔记',
            date: DateTime(2026, 8, 20, 9).toIso8601String(),
          ),
          ..._makeQuotes(55),
        ];
        databaseService.refreshQuotes();
        await tester.pump();

        // 模拟应用即将恢复前台时已有一笔真实的第二页 UI 分页查询（offset > 0）在途：
        // 此时 isPaginationQueryInFlight 为 true，但 NoteListView 收到 resumed 时仍不能吞掉延迟整表刷新。
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        lifecycle = AppLifecycleState.resumed;

        final pageReadGate = Completer<void>();
        fakeSqlDb.holdPositiveOffsetQueryUntil = pageReadGate.future;
        final inFlightLoadMore = databaseService.loadMoreQuotes();
        await tester.pump();

        expect(
          DatabaseService.isPaginationQueryInFlight(databaseService),
          isTrue,
          reason:
              '真实 UI 翻页请求在途时 isPaginationQueryInFlight 必须为 true，以覆盖恢复分支守卫逻辑',
        );

        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.text('翻页在途时后台合入的新笔记'),
          findsOneWidget,
          reason: '即使切回 resumed 时有 UI 翻页在途，已记录的延迟刷新也必须触发整表刷新以展示顶部新笔记',
        );

        pageReadGate.complete();
        await tester.pump();
        await inFlightLoadMore;

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        databaseService.dispose();
      },
    );

    testWidgets(
      '前台连续超时自动恢复最多 2 次后收敛到 AppErrorView，点击重试恢复加载',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final baseTimeout = DatabaseService.optimalQueryTimeout();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();
        expect(find.byType(AppLoadingView), findsOneWidget);

        // 第 1 次安全退避到期（base + 2s）-> 自动触发第 1 次恢复刷新。
        await tester.pump(baseTimeout + const Duration(seconds: 2));
        expect(databaseService.refreshQuotesCallCount, 1);
        expect(find.byType(AppLoadingView), findsOneWidget);

        // 第 2 次安全退避到期（base + 4s）-> 自动触发第 2 次恢复刷新。
        await tester.pump(baseTimeout + const Duration(seconds: 4));
        expect(databaseService.refreshQuotesCallCount, 2);
        expect(find.byType(AppLoadingView), findsOneWidget);

        // 第 3 次安全退避到期（base + 6s）-> 达到上限（<= 2 次），退出转圈展示 AppErrorView。
        await tester.pump(baseTimeout + const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 250));
        expect(databaseService.refreshQuotesCallCount, 2);
        expect(find.byType(AppLoadingView), findsNothing);
        expect(find.byType(AppErrorView), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);

        // 进入错误态后不再有任何后台/前台残余定时器空转。
        await tester.pump(const Duration(seconds: 60));
        expect(databaseService.refreshQuotesCallCount, 2);

        // 用户点击“重试”按钮重新订阅并恢复。
        final watchCountBeforeRetry = databaseService.watchCallCount;
        await tester.tap(find.text('重试'));
        await tester.pump();
        expect(databaseService.watchCallCount, watchCountBeforeRetry + 1);

        databaseService.emit(_makeQuotes(2), hasMore: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(AppErrorView), findsNothing);
        expect(find.text('数据事件测试笔记 0'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      '首屏流式错误立即进入 AppErrorView（仅记录 1 条带堆栈错误日志），修改搜索词或筛选可直接解锁恢复',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            searchQuery: '',
          ),
        );
        await tester.pump();

        final injectedError = StateError('SQLite 首屏查询异常');
        final injectedStack = StackTrace.current;
        databaseService.emitError(injectedError, injectedStack);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(AppErrorView), findsOneWidget);
        expect(find.text('暂时无法读取笔记，请点击重试'), findsOneWidget);
        expect(find.text('还没有笔记，开始记录吧！'), findsNothing);

        final errorLogs = logService.records
            .where((r) => r['level'] == UnifiedLogLevel.error)
            .toList();
        expect(errorLogs, hasLength(1));
        expect(errorLogs.single['stackTrace'], isNotNull);

        // 首屏失败后无需先重启页面，直接修改搜索词即可重建流并恢复。
        final watchBeforeSearch = databaseService.watchCallCount;
        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            searchQuery: '恢复关键词',
          ),
        );
        await tester.pump();
        expect(databaseService.watchCallCount, watchBeforeSearch + 1);
        expect(databaseService.lastSearchQuery, '恢复关键词');

        databaseService.emit(_makeQuotes(1), hasMore: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(AppErrorView), findsNothing);
        expect(find.text('数据事件测试笔记 0'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      '上拉分页加载失败保留已有列表、收起加载态并通过 AppSnackBar.error 提供重试闭环',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final databaseService = _StreamingFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();

        // 先发出首屏短笔记，使列表填满并允许滚动触发下一页。
        databaseService.emit(_makeQuotes(15), hasMore: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('数据事件测试笔记 0'), findsOneWidget);

        // 注入翻页超时异常并向下滚动到底部触发 _loadMore。
        databaseService.loadMoreError = TimeoutException('翻页读取超时');
        await tester.drag(find.byType(ListView), const Offset(0, -2400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // 已有笔记保持不丢，且弹出带“重试”动作的错误 SnackBar。
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('查询超时，请重试'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);

        // 恢复正常后点击 SnackBar 上的“重试”拉取下一页。
        databaseService.loadMoreError = null;
        databaseService.onLoadMoreSuccess = () {
          databaseService.emit(_makeQuotes(17), hasMore: false);
        };
        final retryAction = tester.widget<SnackBarAction>(
          find.byType(SnackBarAction),
        );
        retryAction.onPressed();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(_listItemCount(tester), 17);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      'QuoteListViewByConflict 遇到流错误时展示 AppErrorView 而非假“无冲突”，点击重试可恢复',
      (tester) async {
        final databaseService = _StreamingFakeDatabaseService();

        await tester.pumpWidget(
          ChangeNotifierProvider<DatabaseService>.value(
            value: databaseService,
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                extensions: [
                  AppShapeTokens.fromForm(
                    ThemeStyleForm.material,
                    Brightness.light,
                  ),
                  AppSemanticColors.light,
                ],
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('zh'),
              home: const Scaffold(body: QuoteListViewByConflict()),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(AppLoadingView), findsOneWidget);

        databaseService.emitError(
          TimeoutException('冲突列表查询超时'),
          StackTrace.current,
        );
        await tester.pump();

        expect(find.byType(AppErrorView), findsOneWidget);
        expect(find.text('读取笔记响应较慢，请点击重试'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);

        // 点击重试后重新订阅冲突流并回到加载态，发射冲突笔记后恢复正常渲染。
        await tester.tap(find.text('重试'));
        await tester.pump();
        expect(databaseService.watchCallCount, 2);
        expect(find.byType(AppLoadingView), findsOneWidget);

        databaseService.emit(
          [
            Quote(
              id: 'conflict-1',
              content: '待处理的同步冲突笔记',
              date: DateTime(2026, 8, 20).toIso8601String(),
              lastModified: '2026-08-20T10:00:00.000Z',
            ),
          ],
          hasMore: false,
        );
        await tester.pump();

        expect(find.byType(AppErrorView), findsNothing);
        expect(find.text('待处理的同步冲突笔记'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await databaseService.disposeStream();
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.databaseService,
    required this.settingsService,
    this.searchQuery = '',
  });

  final DatabaseService databaseService;
  final SettingsService settingsService;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider(create: (_) => NoteSearchController()),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: [
            AppShapeTokens.fromForm(ThemeStyleForm.material, Brightness.light),
            AppSemanticColors.light,
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: NoteListView(
            tags: const <NoteTag>[],
            selectedTagIds: const [],
            onTagSelectionChanged: (_) {},
            searchQuery: searchQuery,
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
  int refreshQuotesCallCount = 0;
  int watchCallCount = 0;
  String? lastSearchQuery;
  Object? loadMoreError;
  VoidCallback? onLoadMoreSuccess;

  @override
  bool get isInitialized => true;

  @override
  bool get hasMoreQuotes => _hasMoreQuotes;

  @override
  void refreshQuotes() {
    refreshQuotesCallCount++;
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
    watchCallCount++;
    lastSearchQuery = searchQuery;
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
  }) async {
    final error = loadMoreError;
    if (error != null) {
      throw error;
    }
    onLoadMoreSuccess?.call();
  }

  @override
  Future<List<NoteTag>> getTags() async => const [];

  /// 真实实现推的是 `List.from(_currentQuotes)`：列表对象是新的，元素是原来那批。
  void emit(List<Quote> quotes, {required bool hasMore}) {
    _hasMoreQuotes = hasMore;
    _controller.add(List<Quote>.from(quotes));
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    _controller.addError(error, stackTrace ?? StackTrace.current);
  }

  Future<void> disposeStream() => _controller.close();
}

/// 复用真实 [_DatabasePaginationMixin] 分页与延迟刷新状态机的轻量测试服务。
class _LifecycleAwareRealPaginationDbService extends DatabaseService {
  _LifecycleAwareRealPaginationDbService({
    required List<Quote> initialQuotes,
    required this.readLifecycle,
  })  : quotes = List<Quote>.from(initialQuotes),
        super.forTesting();

  List<Quote> quotes;
  final AppLifecycleState Function() readLifecycle;

  @override
  bool get isInitialized => true;

  @override
  Future<List<NoteTag>> getTags() async => const [];

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async {
    if (readLifecycle() != AppLifecycleState.resumed) {
      Error.throwWithStackTrace(
        TimeoutException('数据库查询在后台态已暂停'),
        StackTrace.current,
      );
    }
    if (offset >= quotes.length) return const [];
    final end = (offset + limit).clamp(0, quotes.length);
    return List<Quote>.from(quotes.sublist(offset, end));
  }
}

/// 走完整 [_DatabaseQueryMixin] 与 [_DatabasePaginationMixin] 单航班管线的测试服务。
class _FullQueryPipelineTestDbService extends DatabaseService {
  _FullQueryPipelineTestDbService() : super.forTesting();

  @override
  bool get isInitialized => true;

  @override
  Future<List<NoteTag>> getTags() async => const [];
}

class _InMemoryInterceptingSqfliteDb implements Database {
  _InMemoryInterceptingSqfliteDb({required List<Quote> quotes})
      : quotes = List<Quote>.from(quotes);

  List<Quote> quotes;
  Future<void>? holdLimit50QueryUntil;
  Future<void>? holdPositiveOffsetQueryUntil;

  @override
  bool get isOpen => true;

  @override
  String get path => ':memory:';

  @override
  Database get database => this;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (table == 'quotes' || table.startsWith('quotes ')) {
      if (limit == 50 && holdLimit50QueryUntil != null) {
        final gate = holdLimit50QueryUntil!;
        holdLimit50QueryUntil = null;
        await gate;
      }
      if ((offset ?? 0) > 0 && holdPositiveOffsetQueryUntil != null) {
        final gate = holdPositiveOffsetQueryUntil!;
        holdPositiveOffsetQueryUntil = null;
        await gate;
      }
      final start = (offset ?? 0).clamp(0, quotes.length);
      final end = limit == null
          ? quotes.length
          : (start + limit).clamp(0, quotes.length);
      return [
        for (final q in quotes.sublist(start, end))
          <String, Object?>{
            'id': q.id,
            'content': q.content,
            'date': q.date,
            'source': q.source,
            'source_author': q.sourceAuthor,
            'source_work': q.sourceWork,
            'category_id': q.categoryId,
            'color_hex': q.colorHex,
            'location': q.location,
            'poi_name': q.poiName,
            'latitude': q.latitude,
            'longitude': q.longitude,
            'weather': q.weather,
            'temperature': q.temperature,
            'edit_source': q.editSource,
            'delta_content': q.deltaContent,
            'day_period': q.dayPeriod,
            'last_modified': q.lastModified,
            'favorite_count': q.favoriteCount,
            'is_deleted': q.isDeleted ? 1 : 0,
            'deleted_at': q.deletedAt,
          },
      ];
    }
    return const <Map<String, Object?>>[];
  }

  @override
  Batch batch() => _EmptyTagSqfliteBatch();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyTagSqfliteBatch implements Batch {
  int _count = 0;

  @override
  int get length => _count;

  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    _count++;
  }

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) async {
    return List<Object?>.filled(_count, const <Map<String, Object?>>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WidgetRecordingLogService implements UnifiedLogService {
  final List<Map<String, dynamic>> records = [];

  @override
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.verbose,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.debug,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.info,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.warning,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.error,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void log(
    UnifiedLogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    records.add({
      'level': level,
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
