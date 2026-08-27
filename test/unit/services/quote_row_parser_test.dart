import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';

import '../../test_harness.dart';

/// 一条读不出来的坏行，不能连累整批查询。
///
/// `Quote.fromJson` 对正文为空、日期不可解析的行会抛异常。原来七处读取都是裸调用
/// `maps.map((m) => Quote.fromJson(m))`，一条坏行就能让**整页笔记加载失败**——用户
/// 看到的不是「有一条笔记怪怪的」，而是列表整个打不开。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseService service;
  late Database db;

  setUp(() async {
    await TestHarness.initialize();
    DatabaseService.clearTestDatabase();
    service = DatabaseService();

    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await _createQuoteTables(db);

    DatabaseService.setTestDatabase(db);
    await service.init();
  });

  tearDown(() async {
    DatabaseService.clearTestDatabase();
    await db.close();
  });

  Future<void> insertRow(String id, String content, String date) async {
    await db.insert('quotes', {
      'id': id,
      'content': content,
      'date': date,
      'last_modified': '2026-08-22T17:40:00.000Z',
    });
  }

  test('正文为空的坏行被跳过，同批的好笔记照常返回', () async {
    await insertRow('good-1', '正常的笔记', '2026-08-22T17:40:00.000Z');
    await insertRow('bad-empty', '', '2026-08-21T17:40:00.000Z');
    await insertRow('good-2', '另一条正常的笔记', '2026-08-20T17:40:00.000Z');

    final quotes = await service.getUserQuotes();

    expect(
      quotes.map((q) => q.id),
      containsAll(<String>['good-1', 'good-2']),
    );
    expect(quotes.map((q) => q.id), isNot(contains('bad-empty')));
  });

  test('日期无法解析的坏行同样只丢自己', () async {
    await insertRow('good-1', '正常的笔记', '2026-08-22T17:40:00.000Z');
    await insertRow('bad-date', '日期是坏的', '不是日期');

    final quotes = await service.getUserQuotes();

    expect(quotes.map((q) => q.id), contains('good-1'));
    expect(quotes.map((q) => q.id), isNot(contains('bad-date')));
  });

  test('整批都是坏行时返回空列表而不是抛异常', () async {
    await insertRow('bad-1', '', '2026-08-22T17:40:00.000Z');
    await insertRow('bad-2', '坏日期', '不是日期');

    // 关键是「不抛」：抛出去的话调用方拿不到任何数据，列表整个打不开。
    expect(await service.getUserQuotes(), isEmpty);
  });

  test('id 是 BLOB 的行也只丢自己：预处理阶段的强转不能绕过逐行兜底', () async {
    // 构建 quoteIds / 标签映射那几步原来硬转 `as String`，会在 _parseQuoteRows
    // 还没轮到之前就抛出来，把整批查询带走。
    //
    // 必须用 BLOB 才复现得了：TEXT 列有 TEXT 亲和性，塞进去的整数会被 SQLite 转成
    // 字符串读回来，只有 BLOB 原样保留（读出来是 Uint8List）。
    await insertRow('good-1', '正常的笔记', '2026-08-22T17:40:00.000Z');
    await db.rawInsert(
      "INSERT INTO quotes (id, content, date, last_modified) "
      "VALUES (x'DEADBEEF', ?, ?, ?)",
      [
        '这一行的 id 是 BLOB',
        '2026-08-21T17:40:00.000Z',
        '2026-08-21T17:40:00.000Z',
      ],
    );

    final quotes = await service.getUserQuotes();

    expect(quotes.map((q) => q.id), contains('good-1'));
  });

  test('关联表里的坏 tag_id 同样不能带走整批查询', () async {
    // 坏的 quote_id 会被 `IN (...)` 直接筛掉，真正能进到映射构建里的是「quote_id
    // 正常、tag_id 是 BLOB」这种行——原来那句 `tagMap['tag_id'] as String` 会在
    // 这里抛出来。
    await insertRow('good-1', '正常的笔记', '2026-08-22T17:40:00.000Z');
    await db.rawInsert(
      "INSERT INTO quote_tags (quote_id, tag_id) VALUES (?, x'DEADBEEF')",
      ['good-1'],
    );

    final quotes = await service.getUserQuotes();

    expect(quotes.map((q) => q.id), contains('good-1'));
  });

  test('按内容搜索也走同一个兜底', () async {
    await insertRow('good-1', '找得到的笔记', '2026-08-22T17:40:00.000Z');
    await insertRow('bad-date', '找得到的笔记但日期坏了', '不是日期');

    final results = await service.searchQuotesByContent('找得到的笔记');

    expect(results.map((q) => q.id), contains('good-1'));
    expect(results.map((q) => q.id), isNot(contains('bad-date')));
  });
}

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
      CREATE TABLE categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_default INTEGER DEFAULT 0,
        icon_name TEXT,
        last_modified TEXT
      )
    ''');
  await db.execute('''
      CREATE TABLE quote_tombstones(
        quote_id TEXT PRIMARY KEY,
        deleted_at TEXT
      )
    ''');
}
