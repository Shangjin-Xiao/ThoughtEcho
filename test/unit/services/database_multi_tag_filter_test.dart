import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:uuid/uuid.dart';

/// 集成测试：验证多标签筛选查询（EXISTS / INNER JOIN 改写）的正确性
///
/// 覆盖场景：
/// - 单标签筛选（列表 + 计数）
/// - 多标签 AND 筛选（列表 + 计数）
/// - 部分匹配（不满足全部标签，不应返回）
/// - 空标签列表（返回全部）
/// - 无匹配标签（返回空）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService Multi-Tag Filter Tests', () {
    late DatabaseService service;
    late Database db;

    setUp(() async {
      service = DatabaseService();

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
      await service.init();
    });

    tearDown(() async {
      await db.close();
    });

    group('Single tag filter', () {
      test('should return only notes with the specified tag', () async {
        final tagA = 'tag-a';
        final tagB = 'tag-b';
        final now = DateTime.now().toUtc().toIso8601String();

        final noteWithA = Quote(
          id: const Uuid().v4(),
          content: 'note with tag A',
          date: now,
          tagIds: [tagA],
        );
        final noteWithB = Quote(
          id: const Uuid().v4(),
          content: 'note with tag B',
          date: now,
          tagIds: [tagB],
        );
        final noteWithBoth = Quote(
          id: const Uuid().v4(),
          content: 'note with both tags',
          date: now,
          tagIds: [tagA, tagB],
        );

        await service.addQuote(noteWithA);
        await service.addQuote(noteWithB);
        await service.addQuote(noteWithBoth);

        final results = await service.getUserQuotes(tagIds: [tagA], limit: 100);
        final ids = results.map((q) => q.id).toSet();

        expect(ids, contains(noteWithA.id));
        expect(ids, contains(noteWithBoth.id));
        expect(ids, isNot(contains(noteWithB.id)));
      });

      test('count should match list results for single tag', () async {
        final tagA = 'tag-a';
        final now = DateTime.now().toUtc().toIso8601String();

        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'note 1',
          date: now,
          tagIds: [tagA],
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'note 2',
          date: now,
          tagIds: [],
        ));

        final count = await service.getQuotesCount(tagIds: [tagA]);
        final list = await service.getUserQuotes(tagIds: [tagA], limit: 100);

        expect(count, equals(1));
        expect(list.length, equals(count));
      });
    });

    group('Multi-tag AND filter', () {
      test('should return only notes with ALL specified tags', () async {
        final tagA = 'tag-a';
        final tagB = 'tag-b';
        final tagC = 'tag-c';
        final now = DateTime.now().toUtc().toIso8601String();

        final noteAOnly = Quote(
          id: const Uuid().v4(),
          content: 'only A',
          date: now,
          tagIds: [tagA],
        );
        final noteAB = Quote(
          id: const Uuid().v4(),
          content: 'A and B',
          date: now,
          tagIds: [tagA, tagB],
        );
        final noteABC = Quote(
          id: const Uuid().v4(),
          content: 'A, B and C',
          date: now,
          tagIds: [tagA, tagB, tagC],
        );
        final noteBC = Quote(
          id: const Uuid().v4(),
          content: 'B and C',
          date: now,
          tagIds: [tagB, tagC],
        );

        await service.addQuote(noteAOnly);
        await service.addQuote(noteAB);
        await service.addQuote(noteABC);
        await service.addQuote(noteBC);

        final results = await service.getUserQuotes(
          tagIds: [tagA, tagB],
          limit: 100,
        );
        final ids = results.map((q) => q.id).toSet();

        expect(ids, contains(noteAB.id));
        expect(ids, contains(noteABC.id));
        expect(ids, isNot(contains(noteAOnly.id)));
        expect(ids, isNot(contains(noteBC.id)));
      });

      test('count should match list results for multi-tag', () async {
        final tagA = 'tag-a';
        final tagB = 'tag-b';
        final now = DateTime.now().toUtc().toIso8601String();

        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'A only',
          date: now,
          tagIds: [tagA],
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'A and B',
          date: now,
          tagIds: [tagA, tagB],
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'A, B and extra',
          date: now,
          tagIds: [tagA, tagB, 'extra'],
        ));

        final count = await service.getQuotesCount(tagIds: [tagA, tagB]);
        final list = await service.getUserQuotes(
          tagIds: [tagA, tagB],
          limit: 100,
        );

        expect(count, equals(2));
        expect(list.length, equals(count));
      });

      test('three tags filter should work correctly', () async {
        final tagA = 'tag-a';
        final tagB = 'tag-b';
        final tagC = 'tag-c';
        final now = DateTime.now().toUtc().toIso8601String();

        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'AB',
          date: now,
          tagIds: [tagA, tagB],
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'ABC',
          date: now,
          tagIds: [tagA, tagB, tagC],
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'AC',
          date: now,
          tagIds: [tagA, tagC],
        ));

        final results = await service.getUserQuotes(
          tagIds: [tagA, tagB, tagC],
          limit: 100,
        );

        expect(results.length, equals(1));
        expect(results.first.content, equals('ABC'));
      });
    });

    group('Edge cases', () {
      test('empty tagIds should return all notes', () async {
        final now = DateTime.now().toUtc().toIso8601String();

        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'note 1',
          date: now,
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'note 2',
          date: now,
          tagIds: ['some-tag'],
        ));

        final countAll = await service.getQuotesCount();
        final listAll = await service.getUserQuotes(limit: 100);
        final countEmptyTags = await service.getQuotesCount(tagIds: []);
        final listEmptyTags =
            await service.getUserQuotes(tagIds: [], limit: 100);

        expect(countEmptyTags, equals(countAll));
        expect(listEmptyTags.length, equals(listAll.length));
      });

      test('non-existent tag should return empty results', () async {
        final now = DateTime.now().toUtc().toIso8601String();

        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'note with tag',
          date: now,
          tagIds: ['existing-tag'],
        ));

        final count = await service.getQuotesCount(tagIds: ['non-existent']);
        final list = await service.getUserQuotes(
          tagIds: ['non-existent'],
          limit: 100,
        );

        expect(count, equals(0));
        expect(list, isEmpty);
      });

      test('count and list should be consistent under combined filters',
          () async {
        final tagA = 'tag-a';
        final categoryId = 'cat-1';
        final now = DateTime.now().toUtc().toIso8601String();

        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'matching both',
          date: now,
          categoryId: categoryId,
          tagIds: [tagA],
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'wrong category',
          date: now,
          categoryId: 'cat-2',
          tagIds: [tagA],
        ));
        await service.addQuote(Quote(
          id: const Uuid().v4(),
          content: 'wrong tag',
          date: now,
          categoryId: categoryId,
          tagIds: ['other-tag'],
        ));

        final count = await service.getQuotesCount(
          tagIds: [tagA],
          categoryId: categoryId,
        );
        final list = await service.getUserQuotes(
          tagIds: [tagA],
          categoryId: categoryId,
          limit: 100,
        );

        expect(count, equals(1));
        expect(list.length, equals(count));
        expect(list.first.content, equals('matching both'));
      });
    });
  });
}
