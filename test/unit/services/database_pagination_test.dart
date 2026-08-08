import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';

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
