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
