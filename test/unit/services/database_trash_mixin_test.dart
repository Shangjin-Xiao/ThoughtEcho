import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:uuid/uuid.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseTrashMixin Unit Tests', () {
    late DatabaseService service;
    late Database db;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      service = DatabaseService();

      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // Schema source of truth, so a new quotes column lands here automatically
      // instead of silently drifting away from the production definition.
      await DatabaseSchemaDefinitions().createCurrentSchema(db);

      DatabaseService.setTestDatabase(db);
      await service.init();
    });

    tearDown(() async {
      DatabaseService.clearTestDatabase();
      await db.close();
    });

    group('getDeletedQuotes & getDeletedQuotesCount', () {
      test('returns empty list and zero count when no deleted quotes',
          () async {
        final count = await service.getDeletedQuotesCount();
        expect(count, equals(0));

        final quotes = await service.getDeletedQuotes();
        expect(quotes, isEmpty);
      });

      test('returns deleted quotes with tags and respects limit/offset',
          () async {
        final now = DateTime.now().toUtc();
        final id1 = const Uuid().v4();
        final id2 = const Uuid().v4();

        final quote1 = Quote(
          id: id1,
          content: 'Deleted Note 1',
          date: now.toIso8601String(),
          isDeleted: true,
          deletedAt:
              now.subtract(const Duration(minutes: 10)).toIso8601String(),
        );
        final quote2 = Quote(
          id: id2,
          content: 'Deleted Note 2',
          date: now.toIso8601String(),
          isDeleted: true,
          deletedAt: now.subtract(const Duration(minutes: 5)).toIso8601String(),
        );

        await service.addQuote(quote1);
        await service.addQuote(quote2);

        // Attach tag to quote2
        await db.insert('quote_tags', {'quote_id': id2, 'tag_id': 'tag_test'});

        final count = await service.getDeletedQuotesCount();
        expect(count, equals(2));

        // Order by deleted_at DESC default: quote2 (5 min ago) then quote1 (10 min ago)
        final deletedQuotes =
            await service.getDeletedQuotes(limit: 1, offset: 0);
        expect(deletedQuotes.length, equals(1));
        expect(deletedQuotes.first.id, equals(id2));
        expect(deletedQuotes.first.tagIds, contains('tag_test'));

        final secondPage = await service.getDeletedQuotes(limit: 1, offset: 1);
        expect(secondPage.length, equals(1));
        expect(secondPage.first.id, equals(id1));
      });
    });

    group('getTombstonesForBackup', () {
      test('returns list of tombstones from database', () async {
        final id = const Uuid().v4();
        final deletedAt = DateTime.now().toUtc().toIso8601String();
        await db.insert('quote_tombstones', {
          'quote_id': id,
          'deleted_at': deletedAt,
          'device_id': 'device_123',
        });

        final tombstones = await service.getTombstonesForBackup();
        expect(tombstones.length, equals(1));
        expect(tombstones.first['quote_id'], equals(id));
        expect(tombstones.first['deleted_at'], equals(deletedAt));
        expect(tombstones.first['device_id'], equals('device_123'));
      });
    });

    group('restoreQuote', () {
      test('throws ArgumentError for empty ID', () async {
        expect(() => service.restoreQuote(''), throwsArgumentError);
      });

      test('throws StateError when quote tombstone exists', () async {
        final id = const Uuid().v4();
        await db.insert('quote_tombstones', {
          'quote_id': id,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        });

        expect(
          () => service.restoreQuote(id),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('笔记已被永久删除，无法恢复'),
            ),
          ),
        );
      });

      test('restores a soft-deleted quote', () async {
        final id = const Uuid().v4();
        final quote = Quote(
          id: id,
          content: 'Note to restore',
          date: DateTime.now().toIso8601String(),
          isDeleted: true,
          deletedAt: DateTime.now().toUtc().toIso8601String(),
        );

        await db.insert('quotes', quote.toJson());

        await service.restoreQuote(id);

        final restored = await service.getQuoteById(id);
        expect(restored, isNotNull);
        expect(restored!.isDeleted, isFalse);
        expect(restored.deletedAt, isNull);
      });

      test('restoring a missing or active quote leaves rows untouched',
          () async {
        final activeId = const Uuid().v4();
        await db.insert(
          'quotes',
          Quote(
            id: activeId,
            content: 'Active note',
            date: DateTime.now().toUtc().toIso8601String(),
          ).toJson(),
        );
        final before = await db.query('quotes');

        // Neither id can match `WHERE id = ? AND is_deleted = 1`, so both calls
        // must leave the row byte-identical instead of stamping last_modified.
        await service.restoreQuote(const Uuid().v4());
        await service.restoreQuote(activeId);

        expect(await db.query('quotes'), equals(before));
        final unchanged = (await service.getQuoteById(activeId))!;
        expect(unchanged.lastModified, isNull);
        expect(await service.getTombstonesForBackup(), isEmpty);
      });
    });

    group('permanentlyDeleteQuote', () {
      test('throws ArgumentError for empty ID', () async {
        expect(() => service.permanentlyDeleteQuote(''), throwsArgumentError);
      });

      test('permanently deletes a soft-deleted quote and creates tombstone',
          () async {
        final id = const Uuid().v4();
        final quote = Quote(
          id: id,
          content: 'Note for permanent delete',
          date: DateTime.now().toIso8601String(),
          isDeleted: true,
          deletedAt: DateTime.now().toUtc().toIso8601String(),
        );

        await db.insert('quotes', quote.toJson());

        await service.permanentlyDeleteQuote(id);

        final checkQuote = await service.getQuoteById(id, includeDeleted: true);
        expect(checkQuote, isNull);

        final tombstones = await db.query(
          'quote_tombstones',
          where: 'quote_id = ?',
          whereArgs: [id],
        );
        expect(tombstones.length, equals(1));
      });
    });

    group('emptyTrash', () {
      test('does nothing when trash is empty', () async {
        await service.emptyTrash();
        final tombstones = await service.getTombstonesForBackup();
        expect(tombstones, isEmpty);
      });

      test('permanently deletes all soft-deleted quotes and creates tombstones',
          () async {
        final id1 = const Uuid().v4();
        final id2 = const Uuid().v4();

        final quote1 = Quote(
          id: id1,
          content: 'Trash 1',
          date: DateTime.now().toIso8601String(),
          isDeleted: true,
          deletedAt: DateTime.now().toUtc().toIso8601String(),
        );
        final quote2 = Quote(
          id: id2,
          content: 'Trash 2',
          date: DateTime.now().toIso8601String(),
          isDeleted: true,
          deletedAt: DateTime.now().toUtc().toIso8601String(),
        );

        await db.insert('quotes', quote1.toJson());
        await db.insert('quotes', quote2.toJson());

        await service.emptyTrash();

        final deletedQuotes = await service.getDeletedQuotes();
        expect(deletedQuotes, isEmpty);

        final tombstones = await service.getTombstonesForBackup();
        expect(tombstones.length, equals(2));
      });
    });

    group('autoCleanupExpiredTrash', () {
      test('throws ArgumentError for invalid retention days', () async {
        expect(
          () => service.autoCleanupExpiredTrash(retentionDays: 15),
          throwsArgumentError,
        );
      });

      test('deletes expired quotes and leaves unexpired quotes', () async {
        final expiredId = const Uuid().v4();
        final unexpiredId = const Uuid().v4();

        final now = DateTime.now().toUtc();
        final expiredDate =
            now.subtract(const Duration(days: 35)).toIso8601String();
        final unexpiredDate =
            now.subtract(const Duration(days: 10)).toIso8601String();

        final expiredQuote = Quote(
          id: expiredId,
          content: 'Expired Note',
          date: now.toIso8601String(),
          isDeleted: true,
          deletedAt: expiredDate,
        );

        final unexpiredQuote = Quote(
          id: unexpiredId,
          content: 'Unexpired Note',
          date: now.toIso8601String(),
          isDeleted: true,
          deletedAt: unexpiredDate,
        );

        await db.insert('quotes', expiredQuote.toJson());
        await db.insert('quotes', unexpiredQuote.toJson());

        final cleanedCount =
            await service.autoCleanupExpiredTrash(retentionDays: 30);
        expect(cleanedCount, equals(1));

        final deletedQuotes = await service.getDeletedQuotes();
        expect(deletedQuotes.length, equals(1));
        expect(deletedQuotes.first.id, equals(unexpiredId));

        final tombstones = await service.getTombstonesForBackup();
        expect(tombstones.length, equals(1));
        expect(tombstones.first['quote_id'], equals(expiredId));
      });
    });
  });
}
