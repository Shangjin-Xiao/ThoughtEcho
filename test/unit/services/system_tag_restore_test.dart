import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';

/// 回归测试：清空并导入后系统标签必须能自愈
///
/// 覆盖 initDefaultHitokotoTags 的各条路径：
/// - 固定 ID 缺失且无同名占位 -> 新建系统标签
/// - 固定 ID 存在但被写成普通标签 -> 修回 is_default=1
/// - 固定 ID 缺失但同名普通标签占位 -> 收编，并迁移笔记关联
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('系统标签恢复', () {
    late DatabaseService service;
    late Database db;

    Future<void> createSchema() async {
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
    }

    Future<Map<String, Object?>?> categoryById(String id) async {
      final rows = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
      );
      return rows.isEmpty ? null : rows.first;
    }

    setUp(() async {
      service = DatabaseService();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await createSchema();
      DatabaseService.setTestDatabase(db);
      await service.init();
    });

    tearDown(() async {
      await db.close();
    });

    test('categories 被清空后应重新建出系统标签', () async {
      await db.delete('categories');
      expect(await categoryById(DatabaseService.defaultTagIdHitokoto), isNull);

      await service.initDefaultHitokotoTags();

      final row = await categoryById(DatabaseService.defaultTagIdHitokoto);
      expect(row, isNotNull);
      expect(row!['name'], '每日一言');
      expect(row['is_default'], 1);
    });

    test('被降级为普通标签的系统标签应修回系统属性', () async {
      await db.delete('categories');
      await db.insert('categories', {
        'id': DatabaseService.defaultTagIdHitokoto,
        'name': '每日一言',
        'is_default': 0,
        'icon_name': 'format_quote',
        'last_modified': '2020-01-01T00:00:00.000Z',
      });

      await service.initDefaultHitokotoTags();

      final row = await categoryById(DatabaseService.defaultTagIdHitokoto);
      expect(row!['is_default'], 1);
      // last_modified 必须前进，否则修复会被后续 LWW 合并用旧值盖回去
      expect(
        DateTime.parse(row['last_modified'] as String)
            .isAfter(DateTime.parse('2020-01-01T00:00:00.000Z')),
        isTrue,
      );
    });

    test('同名普通标签占位时应被收编，且笔记关联不丢失', () async {
      await db.delete('categories');
      await db.delete('quote_tags');
      const impostorId = 'imported-tag-id';
      await db.insert('categories', {
        'id': impostorId,
        'name': '每日一言',
        'is_default': 0,
        'icon_name': '',
        'last_modified': '2020-01-01T00:00:00.000Z',
      });
      await db.insert('quotes', {
        'id': 'quote-1',
        'content': '导入进来的笔记',
        'date': DateTime.now().toUtc().toIso8601String(),
        'category_id': impostorId,
      });
      await db.insert('quote_tags', {
        'quote_id': 'quote-1',
        'tag_id': impostorId,
      });

      await service.initDefaultHitokotoTags();

      // 占位行已被移除，系统标签以固定 ID 存在
      expect(await categoryById(impostorId), isNull);
      final row = await categoryById(DatabaseService.defaultTagIdHitokoto);
      expect(row, isNotNull);
      expect(row!['is_default'], 1);

      // 笔记的标签关联迁移到了固定 ID 上
      final relations = await db.query(
        'quote_tags',
        where: 'quote_id = ?',
        whereArgs: ['quote-1'],
      );
      expect(relations.length, 1);
      expect(relations.first['tag_id'], DatabaseService.defaultTagIdHitokoto);

      final quote = await db.query(
        'quotes',
        where: 'id = ?',
        whereArgs: ['quote-1'],
      );
      expect(quote.first['category_id'], DatabaseService.defaultTagIdHitokoto);
    });

    test('系统标签顶着另一个系统标签的名字时，不应被收编走笔记', () async {
      await db.delete('categories');
      await db.delete('quote_tags');
      // default_anime 的名称被写坏成"每日一言"，而 default_hitokoto 缺失
      await db.insert('categories', {
        'id': DatabaseService.defaultTagIdAnime,
        'name': '每日一言',
        'is_default': 1,
        'icon_name': '🎬',
        'last_modified': '2020-01-01T00:00:00.000Z',
      });
      await db.insert('quotes', {
        'id': 'quote-anime',
        'content': '一条动画笔记',
        'date': DateTime.now().toUtc().toIso8601String(),
        'category_id': DatabaseService.defaultTagIdAnime,
      });
      await db.insert('quote_tags', {
        'quote_id': 'quote-anime',
        'tag_id': DatabaseService.defaultTagIdAnime,
      });

      await service.initDefaultHitokotoTags();

      // 动画标签被改回正确名称，且没有被删除
      final anime = await categoryById(DatabaseService.defaultTagIdAnime);
      expect(anime, isNotNull);
      expect(anime!['name'], '动画');

      // 笔记仍然归在动画标签下，没有被迁到"每日一言"
      final relations = await db.query(
        'quote_tags',
        where: 'quote_id = ?',
        whereArgs: ['quote-anime'],
      );
      expect(relations.length, 1);
      expect(relations.first['tag_id'], DatabaseService.defaultTagIdAnime);

      // 每日一言以自己的固定 ID 另行建出
      final hitokoto = await categoryById(DatabaseService.defaultTagIdHitokoto);
      expect(hitokoto, isNotNull);
      expect(hitokoto!['name'], '每日一言');
    });

    test('按固定 ID 重建的一言标签应是系统标签', () async {
      await db.delete('categories');

      await service.addTagWithId(
        DatabaseService.defaultTagIdHitokoto,
        '每日一言',
        iconName: '💭',
      );

      final row = await categoryById(DatabaseService.defaultTagIdHitokoto);
      expect(row!['is_default'], 1);
    });
  });
}
