import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService Optimization Tests', () {
    late DatabaseService service;
    late Database db;

    setUp(() async {
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
          CREATE TABLE categories(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_default BOOLEAN DEFAULT 0,
            icon_name TEXT,
            last_modified TEXT
          )
        ''');
      await db.execute('''
          CREATE TABLE quote_tags(
            quote_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            PRIMARY KEY (quote_id, tag_id)
          )
        ''');

      // Mock media_references table if needed, though not used in these tests
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

      DatabaseService.setTestDatabase(db);

      // Initialize the service (will detect existing DB and set initialized flag)
      await service.init();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'getUserQuotes should return partial quote (null aiAnalysis)',
      () async {
        final id = const Uuid().v4();
        final fullQuote = Quote(
          id: id,
          content: 'Test content',
          date: DateTime.now().toIso8601String(),
          aiAnalysis: 'Huge AI Analysis Text',
        );

        await service.addQuote(fullQuote);

        final quotes = await service.getUserQuotes();
        final fetchedQuote = quotes.firstWhere((q) => q.id == id);

        expect(fetchedQuote.content, equals('Test content'));
        expect(
          fetchedQuote.aiAnalysis,
          isNull,
          reason: 'aiAnalysis should be excluded in list view',
        );
      },
    );

    test('getQuoteById should return full quote', () async {
      final id = const Uuid().v4();
      final fullQuote = Quote(
        id: id,
        content: 'Test content',
        date: DateTime.now().toIso8601String(),
        aiAnalysis: 'Huge AI Analysis Text',
      );

      await service.addQuote(fullQuote);

      final fetchedQuote = await service.getQuoteById(id);
      expect(fetchedQuote, isNotNull);
      expect(fetchedQuote!.content, equals('Test content'));
      expect(fetchedQuote.aiAnalysis, equals('Huge AI Analysis Text'));
    });

    test('searchQuotesByContent excludes deleted notes by default', () async {
      final activeId = const Uuid().v4();
      final deletedId = const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();

      await service.addQuote(
        Quote(id: activeId, content: 'shared-search-keyword active', date: now),
      );
      await service.addQuote(
        Quote(
          id: deletedId,
          content: 'shared-search-keyword deleted',
          date: now,
          isDeleted: true,
          deletedAt: now,
        ),
      );

      final defaultResults = await service.searchQuotesByContent(
        'shared-search-keyword',
      );
      final defaultIds = defaultResults.map((quote) => quote.id).toSet();
      expect(defaultIds.contains(activeId), isTrue);
      expect(defaultIds.contains(deletedId), isFalse);

      final includeDeletedResults = await service.searchQuotesByContent(
        'shared-search-keyword',
        includeDeleted: true,
      );
      final includeDeletedIds = includeDeletedResults
          .map((quote) => quote.id)
          .toSet();
      expect(includeDeletedIds.contains(activeId), isTrue);
      expect(includeDeletedIds.contains(deletedId), isTrue);
    });

    test('getUserQuotes includeDeleted keeps deleted metadata', () async {
      final deletedId = const Uuid().v4();
      final deletedAt = DateTime.now().toUtc().toIso8601String();

      await service.addQuote(
        Quote(
          id: deletedId,
          content: 'deleted-quote-for-backup',
          date: deletedAt,
          isDeleted: true,
          deletedAt: deletedAt,
        ),
      );

      final withDeleted = await service.getUserQuotes(
        includeDeleted: true,
        limit: 100,
      );
      final deletedQuote = withDeleted.firstWhere(
        (quote) => quote.id == deletedId,
      );
      expect(deletedQuote.isDeleted, isTrue);
      expect(deletedQuote.deletedAt, deletedAt);
    });

    test('updateQuote on deleted note should return skippedDeleted', () async {
      final deletedId = const Uuid().v4();
      final deletedAt = DateTime.now().toUtc().toIso8601String();

      await service.addQuote(
        Quote(
          id: deletedId,
          content: 'deleted-before-update',
          date: deletedAt,
          isDeleted: true,
          deletedAt: deletedAt,
        ),
      );

      final result = await service.updateQuote(
        Quote(
          id: deletedId,
          content: 'attempted-update-content',
          date: deletedAt,
          isDeleted: true,
          deletedAt: deletedAt,
        ),
      );

      expect(result, QuoteUpdateResult.skippedDeleted);
      final deletedQuote = await service.getQuoteById(
        deletedId,
        includeDeleted: true,
      );
      expect(deletedQuote, isNotNull);
      expect(deletedQuote!.isDeleted, isTrue);
      expect(deletedQuote.content, 'deleted-before-update');
    });

    test(
      'permanentlyDeleteQuote should not create tombstone for active note',
      () async {
        final activeId = const Uuid().v4();
        final now = DateTime.now().toUtc().toIso8601String();

        await service.addQuote(
          Quote(id: activeId, content: 'active-quote', date: now),
        );

        await service.permanentlyDeleteQuote(activeId);

        final activeQuote = await service.getQuoteById(activeId);
        expect(activeQuote, isNotNull);
        expect(activeQuote!.isDeleted, isFalse);

        final tombstones = await db.query(
          'quote_tombstones',
          where: 'quote_id = ?',
          whereArgs: [activeId],
        );
        expect(tombstones, isEmpty);
      },
    );
  });
}
