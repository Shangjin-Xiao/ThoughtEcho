import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:uuid/uuid.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Trash Flow Tests', () {
    late DatabaseService service;
    late Database db;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      service = DatabaseService();

      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // Create tables required for the test
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
          CREATE TABLE quote_tombstones (
            quote_id TEXT PRIMARY KEY,
            deleted_at TEXT NOT NULL,
            device_id TEXT
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

    test('soft delete -> restore -> permanent delete -> tombstone exists',
        () async {
      final id = const Uuid().v4();
      final quote = Quote(
        id: id,
        content: 'Trash flow test note',
        date: DateTime.now().toIso8601String(),
      );

      // 1. Add quote
      await service.addQuote(quote);
      final beforeDelete = await service.getQuoteById(id);
      expect(beforeDelete, isNotNull);
      expect(beforeDelete!.isDeleted, isFalse);

      // 2. Soft delete
      await service.deleteQuote(id);
      final afterDelete = await service.getQuoteById(id, includeDeleted: true);
      expect(afterDelete, isNotNull);
      expect(afterDelete!.isDeleted, isTrue);
      expect(afterDelete.deletedAt, isNotNull);

      // 3. Verify in trash
      final trashQuotes = await service.getDeletedQuotes();
      expect(trashQuotes.any((q) => q.id == id), isTrue);

      // 4. Restore
      await service.restoreQuote(id);
      final afterRestore = await service.getQuoteById(id);
      expect(afterRestore, isNotNull);
      expect(afterRestore!.isDeleted, isFalse);
      expect(afterRestore.deletedAt, isNull);

      // 5. Verify not in trash
      final trashAfterRestore = await service.getDeletedQuotes();
      expect(trashAfterRestore.any((q) => q.id == id), isFalse);

      // 6. Soft delete again
      await service.deleteQuote(id);

      // 7. Permanently delete
      await service.permanentlyDeleteQuote(id);
      final afterPermanent =
          await service.getQuoteById(id, includeDeleted: true);
      expect(afterPermanent, isNull);

      // 8. Verify tombstone exists
      final tombstones = await db.query('quote_tombstones');
      expect(tombstones.length, 1);
      expect(tombstones.first['quote_id'], id);
      expect(tombstones.first['deleted_at'], isNotNull);
    });

    test('restore refreshes active note list and search streams', () async {
      final id = const Uuid().v4();
      final quote = Quote(
        id: id,
        content: 'Restored searchable note',
        date: DateTime.now().toIso8601String(),
      );

      final listEvents = <List<Quote>>[];
      final listSub = service.watchQuotes(limit: 20).listen(listEvents.add);
      addTearDown(listSub.cancel);

      Future<int> waitForListEvent(
        int startIndex,
        bool Function(List<Quote> quotes) matches,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (DateTime.now().isBefore(deadline)) {
          for (var i = startIndex; i < listEvents.length; i++) {
            if (matches(listEvents[i])) {
              return i + 1;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Timed out waiting for matching list stream event');
      }

      var listCursor = 0;

      await service.addQuote(quote);
      listCursor = await waitForListEvent(
        listCursor,
        (quotes) => quotes.any((quote) => quote.id == id),
      );

      await service.deleteQuote(id);
      listCursor = await waitForListEvent(
        listCursor,
        (quotes) => quotes.every((quote) => quote.id != id),
      );

      await service.restoreQuote(id);
      await waitForListEvent(
        listCursor,
        (quotes) => quotes.any((quote) => quote.id == id),
      );

      await listSub.cancel();

      await expectLater(
        service.watchQuotes(
          limit: 20,
          searchQuery: 'Restored searchable',
        ),
        emits(
          predicate<List<Quote>>(
            (quotes) => quotes.any((quote) => quote.id == id),
          ),
        ),
      );

      expect(
        listEvents.any((quotes) => quotes.any((quote) => quote.id == id)),
        isTrue,
      );
    });

    test(
        'search after restore is not starved by an in-flight default list refresh',
        () async {
      final restoredId = const Uuid().v4();
      final restoredQuote = Quote(
        id: restoredId,
        content: 'Concurrent restored unique note',
        date: DateTime(2020).toIso8601String(),
        isDeleted: true,
        deletedAt: DateTime.now().toUtc().toIso8601String(),
      );

      await db.insert('quotes', restoredQuote.toJson());
      for (var i = 0; i < 25; i++) {
        final quote = Quote(
          id: const Uuid().v4(),
          content: 'Regular visible note $i',
          date: DateTime(2026, 1, 1, 12, i).toIso8601String(),
        );
        await db.insert('quotes', quote.toJson());
      }

      final listEvents = <List<Quote>>[];
      final listSub = service.watchQuotes(limit: 20).listen(listEvents.add);
      addTearDown(listSub.cancel);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline) && listEvents.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(listEvents, isNotEmpty);
      expect(
        listEvents.last.any((quote) => quote.id == restoredId),
        isFalse,
      );

      await service.restoreQuote(restoredId);
      await listSub.cancel();

      await expectLater(
        service
            .watchQuotes(
              limit: 20,
              searchQuery: 'Concurrent restored unique',
            )
            .timeout(const Duration(seconds: 3)),
        emits(
          predicate<List<Quote>>(
            (quotes) => quotes.any((quote) => quote.id == restoredId),
          ),
        ),
      );
    });

    test('autoCleanupExpiredTrash should remove expired soft-deleted quotes',
        () async {
      final id = const Uuid().v4();
      final oldDeletedAt = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();
      final quote = Quote(
        id: id,
        content: 'Expired trash note',
        date: DateTime.now().toIso8601String(),
        isDeleted: true,
        deletedAt: oldDeletedAt,
      );

      await service.addQuote(quote);

      final cleaned = await service.autoCleanupExpiredTrash(
        retentionDays: 30,
      );
      expect(cleaned, 1);

      final afterCleanup = await service.getQuoteById(id);
      expect(afterCleanup, isNull);

      final tombstones = await db.query('quote_tombstones');
      expect(tombstones.length, 1);
      expect(tombstones.first['quote_id'], id);
    });
  });
}
