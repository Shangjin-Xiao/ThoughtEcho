import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database pagination stream', () {
    late _DuplicatePageDatabaseService service;
    late Database db;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      service = _DuplicatePageDatabaseService();

      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await _createQuoteTables(db);

      DatabaseService.setTestDatabase(db);
      await service.init();
    });

    tearDown(() async {
      DatabaseService.clearTestDatabase();
      await db.close();
    });

    test(
      'advances the raw offset when a full duplicate page adds no new rows',
      () async {
        final events = <List<Quote>>[];
        final sub = service.watchQuotes(limit: 2).listen(events.add);
        addTearDown(sub.cancel);

        await _waitForEvent(
          events,
          (quotes) => quotes.map((quote) => quote.id).toList(),
          equals(['quote-a', 'quote-b']),
        );

        await service.loadMoreQuotes();
        await _waitForEvent(
          events,
          (quotes) => quotes.map((quote) => quote.id).toList(),
          equals(['quote-a', 'quote-b']),
          startIndex: 1,
        );

        await service.loadMoreQuotes();
        await _waitForEvent(
          events,
          (quotes) => quotes.map((quote) => quote.id).toList(),
          equals(['quote-a', 'quote-b', 'quote-c', 'quote-d']),
        );

        expect(service.requestedOffsets, containsAllInOrder([0, 2, 4]));
      },
    );
  });

  group('Database pagination refresh', () {
    late _PagedDatabaseService service;
    late Database db;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      service = _PagedDatabaseService(totalQuotes: 7);

      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await _createQuoteTables(db);
      DatabaseService.setTestDatabase(db);
      await service.init();
    });

    tearDown(() async {
      DatabaseService.clearTestDatabase();
      await db.close();
    });

    Future<StreamSubscription<List<Quote>>> loadThreePages(
      List<List<Quote>> events,
    ) async {
      final sub = service.watchQuotes(limit: 2).listen(events.add);
      await _waitForEvent(events, _ids, equals(['quote-0', 'quote-1']));
      await service.loadMoreQuotes();
      await _waitForEvent(
        events,
        _ids,
        equals(['quote-0', 'quote-1', 'quote-2', 'quote-3']),
      );
      await service.loadMoreQuotes();
      await _waitForEvent(
        events,
        _ids,
        equals([
          'quote-0',
          'quote-1',
          'quote-2',
          'quote-3',
          'quote-4',
          'quote-5',
        ]),
      );
      return sub;
    }

    test(
      '刷新按已加载条数一次性回填，列表不会塌回第一页',
      () async {
        final events = <List<Quote>>[];
        final sub = await loadThreePages(events);
        addTearDown(sub.cancel);

        final eventsBeforeRefresh = events.length;
        service.requestedPages.clear();
        // 内容确实变了，这次刷新应当推送（去重只针对完全没变的刷新）。
        service.contentRevision++;

        service.refreshQuotes();

        await _waitForEvent(
          events,
          (quotes) => quotes.length,
          equals(6),
          startIndex: eventsBeforeRefresh,
        );

        // 关键：刷新期间一条都不能变短。列表在用户滚动途中缩短会让
        // maxScrollExtent 骤减、滚动位置被夹紧，视觉上就是"列表突然飞走"。
        for (var i = eventsBeforeRefresh; i < events.length; i++) {
          expect(
            events[i].length,
            6,
            reason: '刷新过程中第 ${i - eventsBeforeRefresh} 个事件把列表截短了',
          );
        }

        // 回填只查一次，limit 等于原有条数。
        expect(service.requestedPages, hasLength(1));
        expect(service.requestedPages.single.offset, 0);
        expect(service.requestedPages.single.limit, 6);
      },
    );

    test(
      '筛选条件未变时重新订阅不会把分页偏移重置回 0',
      () async {
        final events = <List<Quote>>[];
        final sub = await loadThreePages(events);
        addTearDown(sub.cancel);

        service.requestedPages.clear();

        // 相同筛选条件再次订阅：复用已有流，不应重建分页状态。
        final secondEvents = <List<Quote>>[];
        final secondSub =
            service.watchQuotes(limit: 2).listen(secondEvents.add);
        addTearDown(secondSub.cancel);
        await _waitForEvent(secondEvents, (quotes) => quotes.length, equals(6));

        await service.loadMoreQuotes();
        await _waitForEvent(
          secondEvents,
          (quotes) => quotes.length,
          equals(7),
        );

        // 偏移若被重置为 0，这一页取回的全是重复数据：列表一条都不增长，
        // 底部加载指示器却会一直转。
        expect(
          service.requestedPages.map((page) => page.offset),
          isNot(contains(0)),
        );
        expect(service.requestedPages.single.offset, 6);
      },
    );

    test(
      '第一次刷新还在回填途中又来一次刷新，仍然回填全部条数',
      () async {
        final events = <List<Quote>>[];
        final sub = await loadThreePages(events);
        addTearDown(sub.cancel);

        final eventsBeforeRefresh = events.length;
        service.requestedPages.clear();
        service.contentRevision++;

        // 连续两次刷新：第二次进来时 _currentQuotes 已被第一次清空。
        // 若按"当时的列表长度"算回填目标就会退化成只取一页，
        // 列表塌回第一页——正是这个 PR 要修的 bug。
        service.refreshQuotes();
        service.refreshQuotes();

        await _waitForEvent(
          events,
          (quotes) => quotes.length,
          equals(6),
          startIndex: eventsBeforeRefresh,
        );

        for (var i = eventsBeforeRefresh; i < events.length; i++) {
          expect(
            events[i].length,
            6,
            reason: '并发刷新期间第 ${i - eventsBeforeRefresh} 个事件把列表截短了',
          );
        }
      },
    );

    /// 让一次刷新的回填查询全部失败，返回失败前的事件数。
    ///
    /// 超时只是失败的一种；SQLite 异常等会被 loadMoreQuotes 内部吞掉，
    /// 用非超时异常才能真正验证"所有错误都要交出去"这条契约。
    Future<int> failRefill(List<List<Quote>> events) async {
      final eventsBeforeRefresh = events.length;
      final queriesBeforeRefresh = service.completedQueries;
      service.failQueriesWith = StateError('数据库炸了');

      service.refreshQuotes();
      await _waitUntil(() => service.completedQueries > queriesBeforeRefresh);
      await _drainEventLoop();

      service.failQueriesWith = null;
      return eventsBeforeRefresh;
    }

    test(
      '回填查询失败时不推半成品，列表不会塌缩',
      () async {
        final events = <List<Quote>>[];
        final sub = await loadThreePages(events);
        addTearDown(sub.cancel);

        final eventsBeforeRefresh = await failRefill(events);

        // 回填一条都没取到。此时推送就是把列表从 6 条清成 0 条——
        // 用户正滑到的位置会被 maxScrollExtent 夹紧，正是要修的塌陷。
        for (var i = eventsBeforeRefresh; i < events.length; i++) {
          expect(
            events[i].length,
            greaterThanOrEqualTo(6),
            reason: '回填失败后推出了比刷新前更短的列表',
          );
        }
      },
    );

    test(
      '回填失败回滚后，普通分页从原游标续取而不是塌回第一页',
      () async {
        final events = <List<Quote>>[];
        final sub = await loadThreePages(events);
        addTearDown(sub.cancel);

        final eventsBeforeRefresh = await failRefill(events);

        // 失败后内存状态必须整体回滚，而不只是"跳过推送"。否则 _currentQuotes
        // 已空、_watchOffset 已归零，接下来任何一次普通分页（空闲预取、滚到
        // 底部的兜底加载）都会从 offset=0 取回第一页并正常推给 UI ——
        // 列表照样塌回第一页。
        service.requestedPages.clear();
        await service.loadMoreQuotes();
        await _waitForEvent(
          events,
          (quotes) => quotes.length,
          equals(7),
          startIndex: eventsBeforeRefresh,
        );

        // 续页要从第 6 条之后接着取，而不是回到 offset 0。
        expect(service.requestedPages.single.offset, 6);
      },
    );

    test(
      '回填失败回滚时，已经翻到底的分页状态不会被重新标记为还有下一页',
      () async {
        final events = <List<Quote>>[];
        final sub = await loadThreePages(events);
        addTearDown(sub.cancel);

        // 一路翻到底：第 4 页（offset 6, limit 2）只取到 1 条，不足一页，
        // hasMore 就在这时翻成 false（判据是 quotes.length >= requestLimit，
        // 不需要再多取一次空页）。
        await service.loadMoreQuotes();
        await _waitForEvent(events, (quotes) => quotes.length, equals(7));
        expect(service.hasMoreQuotes, isFalse);

        await failRefill(events);

        // 回滚要把分页游标一起复原。无条件写 true 的话，明明已经没有下一页的
        // 列表会重新显示"还有下一页"，用户滑到底还会看到一次白转的加载指示器。
        expect(
          service.hasMoreQuotes,
          isFalse,
          reason: '回填失败回滚后，已翻到底的列表被错误标记为仍可分页',
        );
      },
    );

    test(
      '刷新结果与刷新前完全一致时不再整表推送',
      () async {
        final events = <List<Quote>>[];
        final sub = await loadThreePages(events);
        addTearDown(sub.cancel);

        final eventsBeforeRefresh = events.length;
        final queriesBeforeRefresh = service.completedQueries;
        service.requestedPages.clear();

        service.refreshQuotes();
        // 等回填查询真正**完成**（而不是刚被记录），再把事件循环排空：
        // 推送若会发生，此时必定已经发生，不需要靠固定延时赌时序。
        await _waitUntil(
          () => service.completedQueries > queriesBeforeRefresh,
        );
        await _drainEventLoop();

        // 整表推送会让列表页重建上百个 item，在滚动帧里就是一次可见卡顿。
        expect(
          events.length,
          eventsBeforeRefresh,
          reason: '可见列表毫无变化的刷新不应触发整表推送',
        );
      },
    );
  });

  group('Database pagination chunked refill', () {
    late _PagedDatabaseService service;
    late Database db;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      service = _PagedDatabaseService(totalQuotes: 600);

      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await _createQuoteTables(db);
      DatabaseService.setTestDatabase(db);
      await service.init();
    });

    tearDown(() async {
      DatabaseService.clearTestDatabase();
      await db.close();
    });

    test(
      '超过单次分块上限时分多次回填，最后一块只取剩余条数',
      () async {
        // 单次查询上限 500：501 条要分成 500 + 1 两次取回。
        final events = <List<Quote>>[];
        final sub = service.watchQuotes(limit: 501).listen(events.add);
        addTearDown(sub.cancel);
        await _waitForEvent(events, (quotes) => quotes.length, equals(501));

        final eventsBeforeRefresh = events.length;
        service.requestedPages.clear();
        service.contentRevision++;

        service.refreshQuotes();

        await _waitForEvent(
          events,
          (quotes) => quotes.length,
          equals(501),
          startIndex: eventsBeforeRefresh,
        );

        // 中途一条都不许推短列表。
        for (var i = eventsBeforeRefresh; i < events.length; i++) {
          expect(events[i].length, 501);
        }

        // 最后一块若退回整页大小，会多取回一整页、列表比刷新前更长。
        expect(
          service.requestedPages.map((page) => (page.offset, page.limit)),
          containsAllInOrder([(0, 500), (500, 1)]),
        );
      },
    );
  });

  group('Database pagination single-flight, timeout & error contracts', () {
    late Database rawDb;
    late _InterceptingDatabase proxyDb;
    late _RealTestDatabaseService service;
    late _RecordingLogService logService;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      logService = _RecordingLogService();
      AppLogger.serviceForTesting = logService;

      rawDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await _createQuoteTables(rawDb);
      proxyDb = _InterceptingDatabase(rawDb);
      DatabaseService.setTestDatabase(proxyDb);

      service = _RealTestDatabaseService();
      await service.init();
    });

    tearDown(() async {
      DatabaseService.setDebugLifecycleStateProvider(service, null);
      DatabaseService.setDebugQueryStageObserver(service, null);
      AppLogger.serviceForTesting = UnifiedLogService.instance;
      DatabaseService.clearTestDatabase();
      service.dispose();
      await rawDb.close();
    });

    Future<void> seedQuotes(int count, {List<String> tagIds = const []}) async {
      for (var i = 0; i < count; i++) {
        final id = 'seed-$i';
        await rawDb.insert('quotes', {
          'id': id,
          'content': '合成测试笔记 $i',
          'date': DateTime(2026, 7, 10, 9)
              .subtract(Duration(minutes: i))
              .toIso8601String(),
          'weather': i.isEven ? 'sunny' : 'rainy',
          'day_period': 'morning',
          'last_modified': '2026-07-10T09:00:00.000Z',
        });
        for (final tagId in tagIds) {
          await rawDb.insert('quote_tags', {
            'quote_id': id,
            'tag_id': tagId,
          });
        }
      }
    }

    test(
      '单层超时权威：5.5 秒慢查询在单层超时窗口内正常完成，不再被 5 秒外层超时腰斩',
      () async {
        await seedQuotes(3);
        final preloadedRows = await rawDb.query(
          'quotes',
          orderBy: 'date DESC',
          limit: 2,
        );

        proxyDb.onQueryQuotes = (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 5500));
          return preloadedRows;
        };
        proxyDb.onCommitBatch = (_) async =>
            <Object?>[<Map<String, Object?>>[], <Map<String, Object?>>[]];

        fakeAsync((async) {
          final events = <List<Quote>>[];
          final errors = <Object>[];
          final sub = service.watchQuotes(limit: 2).listen(
                events.add,
                onError: (Object e, StackTrace _) => errors.add(e),
              );

          async.flushMicrotasks();
          expect(DatabaseService.isPaginationQueryInFlight(service), isTrue);

          // 跨越原先 loadMoreQuotes 硬编码的 5 秒边界。
          async.elapse(const Duration(milliseconds: 5200));
          expect(errors, isEmpty);
          expect(events, isEmpty);

          // 5.5 秒完成查询后正常返回首屏结果。
          async.elapse(const Duration(milliseconds: 500));
          async.flushMicrotasks();

          expect(errors, isEmpty);
          expect(events, hasLength(1));
          expect(_ids(events.single), equals(['seed-0', 'seed-1']));
          expect(DatabaseService.isPaginationQueryInFlight(service), isFalse);

          sub.cancel();
        });
      },
    );

    test(
      '生命周期感知与协作式取消：超时或转入后台后立即中止重试及孤儿标签查询',
      () async {
        await seedQuotes(2, tagIds: const ['tag-alpha']);
        final stages = <String>[];
        var lifecycle = AppLifecycleState.resumed;
        DatabaseService.setDebugLifecycleStateProvider(
          service,
          () => lifecycle,
        );
        DatabaseService.setDebugQueryStageObserver(service, stages.add);

        final delayedRows = await rawDb.query('quotes', orderBy: 'date DESC');
        final queryCompleter = Completer<List<Map<String, Object?>>>();
        proxyDb.onQueryQuotes = (_) => queryCompleter.future;

        fakeAsync((async) {
          final errors = <Object>[];
          final sub = service.watchQuotes(limit: 2).listen(
                (_) {},
                onError: (Object e, StackTrace _) => errors.add(e),
              );

          async.flushMicrotasks();
          expect(stages, equals(['sql_query']));

          // 转入后台并跨越单次查询超时阈值：不进入 retry_wait、不发起第 2 次 sql_query。
          lifecycle = AppLifecycleState.paused;
          async.elapse(
            DatabaseService.optimalQueryTimeout() + const Duration(seconds: 5),
          );
          expect(stages, equals(['sql_query']));

          // 即便底层慢查询随后迟到完成，由于该轮 attempt 已超时作废，
          // 也不会继续提交孤儿 quote_tags 批量查询。
          queryCompleter.complete(delayedRows);
          async.flushMicrotasks();
          expect(stages, isNot(contains('tags_batch')));
          expect(proxyDb.batchCommitCount, 0);

          sub.cancel();
        });
      },
    );

    test(
      '筛选代数切换取消：旧筛选查询失败或超时后不继续重试污染新流',
      () async {
        await seedQuotes(2);
        final stages = <String>[];
        DatabaseService.setDebugQueryStageObserver(service, stages.add);

        final firstQueryCompleter = Completer<List<Map<String, Object?>>>();
        var interceptFirst = true;
        proxyDb.onQueryQuotes = (proceed) {
          if (interceptFirst) {
            interceptFirst = false;
            return firstQueryCompleter.future;
          }
          return proceed();
        };

        final firstErrors = <Object>[];
        final firstSub = service
            .watchQuotes(limit: 2, searchQuery: '旧筛选')
            .listen((_) {}, onError: (Object e, StackTrace _) {
          firstErrors.add(e);
        });
        addTearDown(firstSub.cancel);
        await _drainEventLoop();
        expect(stages, equals(['sql_query']));

        // 用户立即切换到新筛选条件，代数递增并取消旧查询等待者。
        final secondEvents = <List<Quote>>[];
        final secondSub = service
            .watchQuotes(limit: 2, searchQuery: '合成测试')
            .listen(secondEvents.add);
        addTearDown(secondSub.cancel);

        await _waitForEvent(secondEvents, (q) => q.length, equals(2));

        // 让旧查询以异常结束：因为等待者已被取消，不应触发 retry_wait，也不向旧流补发错误。
        firstQueryCompleter.completeError(StateError('旧查询过期失败'));
        await _drainEventLoop();

        expect(stages, isNot(contains('retry_wait')));
        expect(firstErrors, isEmpty);
      },
    );

    test(
      '单航班合并与写入纪元隔离：同签名并发查询只执行一次 SQL，真实写入后不复用旧快照',
      () async {
        await seedQuotes(3, tagIds: const ['t1', 't2']);

        final gate = Completer<void>();
        proxyDb.onQueryQuotes = (proceed) async {
          await gate.future;
          return proceed();
        };

        // 归一化后等价的两组参数（标签顺序/重复项不同）并发请求。
        final futureA = service.getUserQuotes(
          tagIds: const ['t2', 't1', 't2'],
          selectedWeathers: const ['sunny', 'sunny'],
          offset: 0,
          limit: 20,
        );
        final futureB = service.getUserQuotes(
          tagIds: const ['t1', 't2'],
          selectedWeathers: const ['sunny'],
          offset: 0,
          limit: 20,
        );

        await _drainEventLoop();
        expect(proxyDb.quotesQueryCount, 1);

        gate.complete();
        final results = await Future.wait([futureA, futureB]);
        expect(proxyDb.quotesQueryCount, 1);
        expect(_ids(results[0]), _ids(results[1]));
        expect(results[0], isNotEmpty);

        // 真实数据写入推进 mutationEpoch：让写前读请求先读出旧 SQL 行并卡在标签批查阶段，
        // 随后执行真实写入并发起新读请求，验证旧快照不包含新写入数据而新读请求包含新数据。
        final preWriteTagGate = Completer<void>();
        final sqlReadDone = Completer<void>();
        var interceptOnce = true;
        proxyDb.onQueryQuotes = (proceed) async {
          final rows = await proceed();
          if (interceptOnce && !sqlReadDone.isCompleted) {
            sqlReadDone.complete();
          }
          return rows;
        };
        proxyDb.onCommitBatch = (proceed) async {
          if (interceptOnce) {
            interceptOnce = false;
            await preWriteTagGate.future;
          }
          return proceed();
        };
        proxyDb.quotesQueryCount = 0;

        final staleReadFuture = service.getUserQuotes(offset: 0, limit: 20);
        await sqlReadDone.future;
        expect(proxyDb.quotesQueryCount, 1);

        await service.addQuote(
          Quote(
            id: 'fresh-quote',
            content: '写入后的新笔记',
            date: DateTime(2026, 8, 1).toIso8601String(),
          ),
        );

        final freshReadFuture = service.getUserQuotes(offset: 0, limit: 20);
        preWriteTagGate.complete();

        final staleQuotes = await staleReadFuture;
        final freshQuotes = await freshReadFuture;
        proxyDb.onQueryQuotes = null;
        proxyDb.onCommitBatch = null;
        expect(
          proxyDb.quotesQueryCount,
          2,
          reason: '写入推进纪元后，新的分页读取不得复用写前已发出的在飞查询',
        );
        expect(
          _ids(staleQuotes),
          equals(['seed-0', 'seed-1', 'seed-2']),
          reason: '写前已读出的在途快照应完整返回原 3 条数据且不混入写后新记录',
        );
        expect(
          _ids(freshQuotes),
          equals(['fresh-quote', 'seed-0', 'seed-1', 'seed-2']),
        );
      },
    );

    test(
      '多页列表在后台连续触发两次 refreshQuotes 时保留已投递快照与回填深度，回到前台后完整恢复不塌缩',
      () async {
        await seedQuotes(6);
        var lifecycle = AppLifecycleState.resumed;
        DatabaseService.setDebugLifecycleStateProvider(
          service,
          () => lifecycle,
        );

        final events = <List<Quote>>[];
        final errors = <Object>[];
        final sub = service.watchQuotes(limit: 2).listen(
              events.add,
              onError: (Object e, StackTrace _) => errors.add(e),
            );
        addTearDown(sub.cancel);

        // 依次加载满 3 页（共 6 条，触底 hasMoreQuotes == false）。
        await _waitForEvent(events, (q) => q.length, equals(2));
        await service.loadMoreQuotes();
        await _waitForEvent(events, (q) => q.length, equals(4));
        await service.loadMoreQuotes();
        await _waitForEvent(events, (q) => q.length, equals(6));
        await service.loadMoreQuotes();
        await _drainEventLoop();
        expect(service.hasMoreQuotes, isFalse);

        final eventCountBeforeBg = events.length;

        // 切入后台后模拟 WebDAV 合并：导入流程与外层同步服务连续两次调用 refreshQuotes()。
        lifecycle = AppLifecycleState.paused;
        await rawDb.insert('quotes', {
          'id': 'bg-sync-top',
          'content': '后台双次刷新期间合入的笔记',
          'date': DateTime(2026, 8, 5, 12).toIso8601String(),
          'weather': 'sunny',
          'day_period': 'afternoon',
          'last_modified': '2026-08-05T12:00:00.000Z',
        });
        service.refreshQuotes();
        service.refreshQuotes();
        await _drainEventLoop();

        expect(events.length, eventCountBeforeBg);
        expect(errors, isEmpty);
        expect(
          service.hasMoreQuotes,
          isFalse,
          reason: '后台连续刷新回滚后必须复原刷新前的分页游标状态',
        );

        // 回到前台 resumed 并执行恢复刷新：必须回填 6 条深度而非退化成单页 2 条。
        lifecycle = AppLifecycleState.resumed;
        expect(
          DatabaseService.consumeDeferredPaginationRefresh(service),
          isTrue,
        );
        service.refreshQuotes();
        await _waitForEvent(
          events,
          _ids,
          equals([
            'bg-sync-top',
            'seed-0',
            'seed-1',
            'seed-2',
            'seed-3',
            'seed-4',
          ]),
        );
        expect(events.last, hasLength(6));
      },
    );

    test(
      'isPaginationQueryInFlight 隔离非分页查询航班，且在途翻页完成后自动排空挂起的延迟刷新',
      () async {
        await seedQuotes(4);
        var lifecycle = AppLifecycleState.resumed;
        DatabaseService.setDebugLifecycleStateProvider(
          service,
          () => lifecycle,
        );

        // 1. 非分页公开 getUserQuotes 在途时，isPaginationQueryInFlight 必须保持 false。
        final exportGate = Completer<void>();
        proxyDb.onQueryQuotes = (proceed) async {
          await exportGate.future;
          return proceed();
        };
        final exportFuture = service.getUserQuotes(offset: 0, limit: 10);
        await _drainEventLoop();
        expect(
          DatabaseService.isPaginationQueryInFlight(service),
          isFalse,
          reason: '后台备份或媒体扫描发起的 getUserQuotes 不得阻塞 UI 分页恢复判断',
        );
        exportGate.complete();
        expect(await exportFuture, hasLength(4));
        proxyDb.onQueryQuotes = null;

        // 2. 后台同步挂起延迟刷新后回到前台，若此时有翻页查询在途，延迟刷新不会被误清空，且在翻页收尾后自动补刷。
        final events = <List<Quote>>[];
        final sub = service.watchQuotes(limit: 2).listen(events.add);
        addTearDown(sub.cancel);
        await _waitForEvent(events, _ids, equals(['seed-0', 'seed-1']));

        lifecycle = AppLifecycleState.paused;
        await rawDb.insert('quotes', {
          'id': 'synced-during-flight',
          'content': '翻页在途期间后台同步合入的笔记',
          'date': DateTime(2026, 8, 6, 8).toIso8601String(),
          'weather': 'sunny',
          'day_period': 'morning',
          'last_modified': '2026-08-06T08:00:00.000Z',
        });
        service.refreshQuotes();
        await _drainEventLoop();

        lifecycle = AppLifecycleState.resumed;
        final pageTwoGate = Completer<void>();
        var holdPageTwoOnce = true;
        proxyDb.onQueryQuotes = (proceed) async {
          if (holdPageTwoOnce) {
            holdPageTwoOnce = false;
            await pageTwoGate.future;
          }
          return proceed();
        };

        final loadMoreFuture = service.loadMoreQuotes();
        await _drainEventLoop();
        expect(DatabaseService.isPaginationQueryInFlight(service), isTrue);

        pageTwoGate.complete();
        await loadMoreFuture;
        proxyDb.onQueryQuotes = null;
        // 原列表已有 [seed-0, seed-1]（offset=2），后台头插 1 条后该在途翻页读回 [seed-1, seed-2]，
        // 去重后扩充至 3 条，随即由 finally 自动排空挂起的延迟刷新并回填最新前 3 条记录。
        await _waitForEvent(
          events,
          _ids,
          equals([
            'synced-during-flight',
            'seed-0',
            'seed-1',
          ]),
        );
        expect(
          DatabaseService.consumeDeferredPaginationRefresh(service),
          isFalse,
        );
      },
    );

    test(
      '公开 getUserQuotes 在非活跃生命周期下不截断数据，且与分页生命周期门控航班隔离',
      () async {
        await seedQuotes(5, tagIds: const ['t1']);
        var lifecycle = AppLifecycleState.resumed;
        DatabaseService.setDebugLifecycleStateProvider(
          service,
          () => lifecycle,
        );

        // 模拟导出备份或媒体孤儿清理期间用户切换应用（进入 inactive / paused）。
        lifecycle = AppLifecycleState.inactive;
        final pageWhileInactive = await service.getUserQuotes(
          offset: 0,
          limit: 50,
          excludeHiddenNotes: false,
          includeDeleted: true,
        );
        expect(_ids(pageWhileInactive), hasLength(5));

        lifecycle = AppLifecycleState.paused;
        final secondPageCheck = await service.getUserQuotes(
          offset: 0,
          limit: 3,
        );
        expect(
          _ids(secondPageCheck),
          equals(['seed-0', 'seed-1', 'seed-2']),
          reason:
              '非分页公开 getUserQuotes 在后台生命周期下必须完整读取 SQLite，绝不能返回伪空列表截断备份或误删附件',
        );

        // 进一步验证：UI 分页查询（前台门控）与公开 getUserQuotes（非门控）同参数并发时不共享在途航班。
        lifecycle = AppLifecycleState.resumed;
        final gate = Completer<void>();
        proxyDb.quotesQueryCount = 0;
        proxyDb.onQueryQuotes = (proceed) async {
          await gate.future;
          return proceed();
        };

        final watchErrors = <Object>[];
        final sub = service.watchQuotes(limit: 3).listen(
              (_) {},
              onError: (Object e, StackTrace _) => watchErrors.add(e),
            );
        addTearDown(sub.cancel);
        final exportFuture = service.getUserQuotes(offset: 0, limit: 3);

        await _drainEventLoop();
        expect(
          proxyDb.quotesQueryCount,
          2,
          reason: '带生命周期门控的 UI 分页航班与无门控的公开查询航班必须隔离',
        );

        // 切入后台后放行 SQL：UI 分页在标签批查前中止，而公开 getUserQuotes 仍完整返回 3 条数据。
        lifecycle = AppLifecycleState.paused;
        gate.complete();

        final exportedQuotes = await exportFuture;
        await _drainEventLoop();
        expect(_ids(exportedQuotes), equals(['seed-0', 'seed-1', 'seed-2']));
        expect(watchErrors, isNotEmpty);
        proxyDb.onQueryQuotes = null;
      },
    );

    test(
      '已加载列表在后台同步触发 refreshQuotes 时保留可见旧列表并标记待刷新，回到前台后补跑且筛选切换可作废旧标记',
      () async {
        await seedQuotes(2);
        var lifecycle = AppLifecycleState.resumed;
        DatabaseService.setDebugLifecycleStateProvider(
          service,
          () => lifecycle,
        );

        final events = <List<Quote>>[];
        final errors = <Object>[];
        final sub = service.watchQuotes(limit: 2).listen(
              events.add,
              onError: (Object e, StackTrace _) => errors.add(e),
            );
        addTearDown(sub.cancel);

        await _waitForEvent(events, _ids, equals(['seed-0', 'seed-1']));
        final eventCountBeforeBgSync = events.length;

        // 模拟应用处于 inactive 时 WebDAV 合并入库新笔记并调用 refreshQuotes()。
        lifecycle = AppLifecycleState.inactive;
        await rawDb.insert('quotes', {
          'id': 'webdav-merged',
          'content': '后台 WebDAV 合并的新笔记',
          'date': DateTime(2026, 8, 2, 10).toIso8601String(),
          'weather': 'sunny',
          'day_period': 'morning',
          'last_modified': '2026-08-02T10:00:00.000Z',
        });
        service.refreshQuotes();
        await _drainEventLoop();

        // 后台期间回填被生命周期门控挂起：旧列表不塌缩、不报 error 日志，但记录了待刷新标记。
        expect(events.length, eventCountBeforeBgSync);
        expect(errors, isEmpty);
        expect(
          logService.records.where((r) => r['level'] == UnifiedLogLevel.error),
          isEmpty,
        );

        // 回到前台 resumed 后消费待刷新标记并补跑 refreshQuotes，新合并的笔记立即可见。
        lifecycle = AppLifecycleState.resumed;
        expect(
          DatabaseService.consumeDeferredPaginationRefresh(service),
          isTrue,
        );
        expect(
          DatabaseService.consumeDeferredPaginationRefresh(service),
          isFalse,
          reason: '待刷新标记消费一次后即清零，避免重复刷新',
        );
        service.refreshQuotes();
        await _waitForEvent(
          events,
          _ids,
          equals(['webdav-merged', 'seed-0']),
        );

        // 若后台再次挂起刷新，但在消费前切换了筛选条件（新建流控制器），旧控制器的挂起标记自动失效。
        lifecycle = AppLifecycleState.paused;
        service.refreshQuotes();
        await _drainEventLoop();

        lifecycle = AppLifecycleState.resumed;
        final filteredEvents = <List<Quote>>[];
        final filteredSub = service
            .watchQuotes(limit: 10, searchQuery: '后台 WebDAV')
            .listen(filteredEvents.add);
        addTearDown(filteredSub.cancel);

        expect(
          DatabaseService.consumeDeferredPaginationRefresh(service),
          isFalse,
          reason: '筛选切换已重建流并启动新查询，旧控制器的延迟刷新标记必须自动作废',
        );
        await _waitForEvent(filteredEvents, _ids, equals(['webdav-merged']));
      },
    );

    test(
      '显式错误传播与外部调用兜底：首屏/空列表失败下发 addError 不推假空列表，外部 getUserQuotes 仍兜底返回空数组',
      () async {
        proxyDb.onQueryQuotes = (_) async {
          throw StateError('模拟存储读取损坏');
        };

        final events = <List<Quote>>[];
        final errors = <(Object, StackTrace)>[];
        final sub = service.watchQuotes(limit: 20).listen(
              events.add,
              onError: (Object e, StackTrace st) => errors.add((e, st)),
            );
        addTearDown(sub.cancel);

        await _waitUntil(() => errors.isNotEmpty);
        await _drainEventLoop();

        // 首屏失败严禁推送伪装成“无笔记”的空数组。
        expect(events, isEmpty);
        expect(errors, hasLength(1));

        // 首屏为空时触发 refreshQuotes 同样向流下发错误而非空数组。
        service.refreshQuotes();
        await _waitUntil(() => errors.length >= 2);
        expect(events, isEmpty);

        // 非分页外部调用方直接调 getUserQuotes 时保持兼容契约，返回 [] 不抛未捕获异常。
        final fallbackResult = await service.getUserQuotes(limit: 10);
        expect(fallbackResult, isEmpty);
      },
    );

    test(
      '非空列表上拉分页失败保留原列表与游标，并向调用方抛出异常以供 UI 提示',
      () async {
        await seedQuotes(4);

        final events = <List<Quote>>[];
        final sub = service.watchQuotes(limit: 2).listen(events.add);
        addTearDown(sub.cancel);

        await _waitForEvent(events, _ids, equals(['seed-0', 'seed-1']));
        final eventsAfterFirstPage = events.length;

        proxyDb.onQueryQuotes = (_) async {
          throw StateError('翻页时磁盘瞬时繁忙');
        };

        await expectLater(
          service.loadMoreQuotes(),
          throwsA(isA<StateError>()),
        );
        await _drainEventLoop();

        expect(events.length, eventsAfterFirstPage);
        expect(_ids(events.last), equals(['seed-0', 'seed-1']));
        expect(service.hasMoreQuotes, isTrue);

        // 恢复正常后从原游标 offset=2 继续拉取下一页。
        proxyDb.onQueryQuotes = null;
        await service.loadMoreQuotes();
        await _waitForEvent(
          events,
          _ids,
          equals(['seed-0', 'seed-1', 'seed-2', 'seed-3']),
        );
      },
    );

    test(
      '单点错误日志与非空堆栈：单次超时或 SQLite 异常全链路仅产生 1 条 error 日志且携带非空 StackTrace',
      () async {
        proxyDb.onQueryQuotes = (_) =>
            Completer<List<Map<String, Object?>>>().future; // 永不返回，触发单层超时

        fakeAsync((async) {
          final errors = <(Object, StackTrace)>[];
          final sub = service.watchQuotes(limit: 20).listen(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              logErrorOnce(
                'UI 订阅侧收到错误: $error',
                error: error,
                stackTrace: stackTrace,
                source: 'NoteListViewTest',
              );
              errors.add((error, stackTrace));
            },
          );

          async.flushMicrotasks();
          // 推进经过第 1 次单层超时 + 300ms 重试等待 + 第 2 次单层超时。
          final totalTimeoutWindow = DatabaseService.optimalQueryTimeout() * 2 +
              const Duration(seconds: 2);
          async.elapse(totalTimeoutWindow);
          async.flushMicrotasks();

          expect(errors, hasLength(1));
          expect(errors.single.$1, isA<TimeoutException>());
          expect(errors.single.$2.toString(), isNotEmpty);

          final errorLogs = logService.records
              .where((record) => record['level'] == UnifiedLogLevel.error)
              .toList();
          expect(
            errorLogs,
            hasLength(1),
            reason: '同一条超时异常跨越重试/查询/分页/UI 边界只能上报一次 error 日志',
          );
          expect(errorLogs.single['stackTrace'], isNotNull);
          expect(errorLogs.single['stackTrace'].toString(), isNotEmpty);

          sub.cancel();
        });
      },
    );
  });
}

/// 排空事件循环：用于"某件事不应该发生"的负向断言。
Future<void> _drainEventLoop() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition');
}

List<String?> _ids(List<Quote> quotes) =>
    quotes.map((quote) => quote.id).toList();

Future<void> _createQuoteTables(Database db) async {
  await db.execute('''
      CREATE TABLE quotes(
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        date TEXT NOT NULL,
        source TEXT,
        source_author TEXT,
        source_work TEXT,
        ai_analysis TEXT,
        sentiment TEXT,
        keywords TEXT,
        summary TEXT,
        category_id TEXT DEFAULT '',
        color_hex TEXT,
        location TEXT,
        latitude REAL,
        longitude REAL,
        poi_name TEXT,
        weather TEXT,
        temperature TEXT,
        edit_source TEXT,
        delta_content TEXT,
        day_period TEXT,
        last_modified TEXT,
        favorite_count INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT
      )
    ''');
  await db.execute('''
      CREATE TABLE quote_tags (
        quote_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (quote_id, tag_id)
      )
    ''');
  await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_default BOOLEAN DEFAULT 0,
        icon_name TEXT,
        last_modified TEXT
      )
    ''');
  await db.execute('''
      CREATE TABLE media_references (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        quote_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(file_path, quote_id)
      )
    ''');
  await db.execute('''
      CREATE TABLE quote_tombstones (
        quote_id TEXT PRIMARY KEY,
        deleted_at TEXT NOT NULL,
        device_id TEXT
      )
    ''');
}

class _RealTestDatabaseService extends DatabaseService {
  _RealTestDatabaseService() : super.forTesting();
}

class _RecordingLogService implements UnifiedLogService {
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

class _InterceptingDatabase implements Database {
  _InterceptingDatabase(this._delegate);

  final Database _delegate;
  Future<List<Map<String, Object?>>> Function(
    Future<List<Map<String, Object?>>> Function() proceed,
  )? onQueryQuotes;
  Future<List<Object?>> Function(
    Future<List<Object?>> Function() proceed,
  )? onCommitBatch;

  int quotesQueryCount = 0;
  int batchCommitCount = 0;

  @override
  String get path => _delegate.path;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  Database get database => this;

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _delegate.execute(sql, arguments);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _delegate.rawInsert(sql, arguments);

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) =>
      _delegate.rawQuery(sql, arguments);

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _delegate.rawUpdate(sql, arguments);

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _delegate.rawDelete(sql, arguments);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _delegate.insert(
        table,
        values,
        nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm,
      );

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
  }) {
    Future<List<Map<String, Object?>>> proceed() => _delegate.query(
          table,
          distinct: distinct,
          columns: columns,
          where: where,
          whereArgs: whereArgs,
          groupBy: groupBy,
          having: having,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
        );
    if (table == 'quotes' || table.startsWith('quotes ')) {
      quotesQueryCount++;
      final interceptor = onQueryQuotes;
      if (interceptor != null) {
        return interceptor(proceed);
      }
    }
    return proceed();
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _delegate.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) =>
      _delegate.delete(table, where: where, whereArgs: whereArgs);

  @override
  Batch batch() => _InterceptingBatch(_delegate.batch(), this);

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) =>
      _delegate.transaction(action, exclusive: exclusive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InterceptingBatch implements Batch {
  _InterceptingBatch(this._delegate, this._owner);

  final Batch _delegate;
  final _InterceptingDatabase _owner;

  @override
  int get length => _delegate.length;

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
    _delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) {
    _delegate.rawQuery(sql, arguments);
  }

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _delegate.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _delegate.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) {
    _delegate.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  void execute(String sql, [List<Object?>? arguments]) {
    _delegate.execute(sql, arguments);
  }

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) {
    _owner.batchCommitCount++;
    Future<List<Object?>> proceed() => _delegate.commit(
          exclusive: exclusive,
          noResult: noResult,
          continueOnError: continueOnError,
        );
    final interceptor = _owner.onCommitBatch;
    if (interceptor != null) {
      return interceptor(proceed);
    }
    return proceed();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 按 offset/limit 老实分页的假数据源，用于观察真实的取页请求。
class _PagedDatabaseService extends DatabaseService {
  _PagedDatabaseService({required this.totalQuotes}) : super.forTesting();

  final int totalQuotes;
  final requestedPages = <({int offset, int limit})>[];

  /// 已经**返回结果**的查询数。负向断言要等查询真的跑完，
  /// 只看 requestedPages 会在查询还在飞的时候就放行。
  int completedQueries = 0;

  /// 模拟"笔记内容真的变了"：改这个值，刷新回填就会拿到不同的数据。
  int contentRevision = 0;

  /// 令查询在返回前抛出异常，用于验证回填失败时的保护。
  /// 一经设置，**此后所有**查询都会失败，直到调用方把它置回 null。
  Object? failQueriesWith;

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    String? dateStart,
    String? dateEnd,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    requestedPages.add((offset: offset, limit: limit));
    final failure = failQueriesWith;
    if (failure != null) {
      completedQueries++;
      throw failure;
    }
    final end = (offset + limit) < totalQuotes ? offset + limit : totalQuotes;
    final quotes = [
      for (var i = offset; i < end; i++)
        Quote(
          id: 'quote-$i',
          content: '分页测试 quote-$i rev$contentRevision',
          date: DateTime(2026, 6, 29).toIso8601String(),
          lastModified: '2026-06-29T00:00:00.000Z',
        ),
    ];
    completedQueries++;
    return quotes;
  }
}

Future<void> _waitForEvent<T>(
  List<List<Quote>> events,
  T Function(List<Quote> quotes) readValue,
  Matcher matcher, {
  int startIndex = 0,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    for (var i = startIndex; i < events.length; i++) {
      final value = readValue(events[i]);
      if (matcher.matches(value, <dynamic, dynamic>{})) {
        return;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail(
    'Timed out waiting for matching pagination event. '
    'Saw: ${events.map(readValue).toList()}',
  );
}

class _DuplicatePageDatabaseService extends DatabaseService {
  final requestedOffsets = <int>[];

  _DuplicatePageDatabaseService() : super.forTesting();

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    String? dateStart,
    String? dateEnd,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    requestedOffsets.add(offset);
    return switch (offset) {
      0 => [_quote('quote-a'), _quote('quote-b')],
      2 => [_quote('quote-a'), _quote('quote-b')],
      4 => [_quote('quote-c'), _quote('quote-d')],
      _ => const <Quote>[],
    };
  }

  Quote _quote(String id) {
    return Quote(
      id: id,
      content: '分页测试 $id',
      date: DateTime(2026, 6, 29).toIso8601String(),
    );
  }
}
