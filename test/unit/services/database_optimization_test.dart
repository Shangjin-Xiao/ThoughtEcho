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
            favorite_count INTEGER DEFAULT 0
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

      DatabaseService.setTestDatabase(db);

      // Initialize the service (will detect existing DB and set initialized flag)
      await service.init();
    });

    tearDown(() async {
      await db.close();
    });

    test('getUserQuotes should return partial quote (null aiAnalysis)', () async {
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
      expect(fetchedQuote.aiAnalysis, isNull, reason: 'aiAnalysis should be excluded in list view');
    });

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
  });
}
