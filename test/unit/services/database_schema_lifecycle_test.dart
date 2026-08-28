import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await database.close();
  });

  group('Database schema lifecycle', () {
    test('creates and validates the current schema from one definition',
        () async {
      final manager = DatabaseSchemaManager();

      await manager.createTables(database);
      await manager.validateSchema(database);

      final quotesColumns =
          await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames =
          quotesColumns.map((column) => column['name'] as String).toSet();

      expect(
          columnNames,
          containsAll(<String>[
            'latitude',
            'longitude',
            'poi_name',
            'is_deleted',
            'deleted_at',
          ]));
    });

    test('weather / day_period 的二次迁移也要留底，不能只靠建列那一次快照', () async {
      // _ensureBackupColumn 只在建列那一次整列快照，列已存在就早退。而这两个迁移
      // 是可以再跑的（同步/导入之后又带进标签形态的值），只靠它的话，第二轮的原值
      // 就没有任何地方留底——原值一旦被覆盖，回滚代码也找不回来。
      //
      // 这里直接调迁移本身而不走 performAllDataMigrations：触发它的
      // _checkAndMigrateWeatherData 只用 `limit: 1` 抽一行做判断，抽到的那行已经是
      // key 时整体跳过（那是另一个独立问题），会让这条用例测不到想测的东西。
      final manager = DatabaseSchemaManager();
      await manager.createTables(database);

      Future<void> insert(String id, String weather, String dayPeriod) async {
        await database.insert('quotes', {
          'id': id,
          'content': '正文 $id',
          'date': '2026-08-22T17:40:00.000Z',
          'weather': weather,
          'day_period': dayPeriod,
        });
      }

      Future<void> runMigrations() async {
        await manager.migrateWeatherToKey(database);
        await manager.migrateDayPeriodToKey(database);
      }

      // 第一轮：建快照列的那一次。
      await insert('first-round', '晴', '晨曦');
      await runMigrations();

      // 第二轮：快照列此时已经存在，_ensureBackupColumn 的早退分支生效。
      await insert('second-round', '多云', '黄昏');
      await runMigrations();

      Future<Map<String, Object?>> rowOf(String id) async =>
          (await database.query('quotes', where: 'id = ?', whereArgs: [id]))
              .first;

      final first = await rowOf('first-round');
      expect(first['weather'], 'clear');
      expect(first['day_period'], 'dawn');
      expect(first['weather_backup'], '晴');
      expect(first['day_period_backup'], '晨曦');

      final second = await rowOf('second-round');
      expect(second['weather'], 'cloudy');
      expect(second['day_period'], 'dusk');
      // 回归点：第二轮的原值同样要留得下来。
      expect(second['weather_backup'], '多云');
      expect(second['day_period_backup'], '黄昏');
    });

    test('upgrades a version 11 database through every remaining adapter',
        () async {
      await _createVersion11Schema(database);
      await database.insert('categories', <String, Object?>{
        'id': 'tag-1',
        'name': 'Existing tag',
        'is_default': 0,
        'icon_name': 'format_quote',
      });
      await database.insert('quotes', <String, Object?>{
        'id': 'quote-1',
        'content': 'Legacy content',
        'date': '2024-01-01T12:00:00.000',
        'source': 'Author - Work',
        'source_author': 'Author',
        'source_work': 'Work',
        'tag_ids': 'tag-1',
      });

      final manager = DatabaseSchemaManager();
      await manager.upgradeDatabase(
        database,
        11,
        DatabaseSchemaManager.schemaVersion,
      );
      await manager.validateSchema(database);

      final migratedQuote = (await database.query('quotes')).single;
      expect(migratedQuote['content'], 'Legacy content');
      expect(migratedQuote['source_author'], 'Author');
      expect(migratedQuote['source_work'], 'Work');
      expect(migratedQuote['poi_name'], isNull);

      final quoteTags = await database.query('quote_tags');
      expect(quoteTags, <Map<String, Object?>>[
        <String, Object?>{'quote_id': 'quote-1', 'tag_id': 'tag-1'},
      ]);

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      expect(
          columns.map((column) => column['name']), isNot(contains('tag_ids')));
    });

    test('upgrades the earliest supported schema through all adapters',
        () async {
      await _createVersion1Schema(database);
      await database.insert('quotes', <String, Object?>{
        'id': 'quote-1',
        'content': 'Oldest content',
        'date': '2021-01-01T12:00:00.000',
      });

      final manager = DatabaseSchemaManager();
      await manager.upgradeDatabase(
        database,
        1,
        DatabaseSchemaManager.schemaVersion,
      );
      await manager.validateSchema(database);

      final quote = (await database.query('quotes')).single;
      expect(quote['content'], 'Oldest content');
      expect(quote['favorite_count'], 0);
      expect(quote['is_deleted'], 0);
    });

    test('restores the coordinate index when upgrading a version 20 database',
        () async {
      final manager = DatabaseSchemaManager();
      await manager.createTables(database);
      await database.execute('DROP INDEX idx_quotes_coordinates');

      await manager.upgradeDatabase(database, 20, 21);
      await manager.validateSchema(database);

      final indexes = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_quotes_coordinates'",
      );
      expect(indexes, isNotEmpty);
    });

    test('heals structure no adapter in range recreates during upgrade',
        () async {
      final manager = DatabaseSchemaManager();
      await manager.createTables(database);
      // 记录版本为 20，但结构缺少 v16 才建的分类索引和附属表：旧构建建库、
      // 升级中断或从备份恢复都会出现这种“版本号比结构新”的库。
      await database.execute('DROP INDEX idx_categories_last_modified');
      await database.execute('DROP TABLE media_references');
      await database.execute('DROP TABLE quote_tombstones');

      await manager.upgradeDatabase(database, 20, 21);
      await manager.validateSchema(database);

      final indexes = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_categories_last_modified'",
      );
      expect(indexes, isNotEmpty);
    });

    test('keeps existing rows while healing during upgrade', () async {
      final manager = DatabaseSchemaManager();
      await manager.createTables(database);
      await database.insert('categories', <String, Object?>{
        'id': 'tag-1',
        'name': 'Existing tag',
        'is_default': 0,
      });
      await database.insert('quotes', <String, Object?>{
        'id': 'quote-1',
        'content': 'Existing content',
        'date': '2025-01-01T12:00:00.000',
      });
      await database.execute('DROP INDEX idx_categories_last_modified');

      await manager.upgradeDatabase(database, 20, 21);
      await manager.validateSchema(database);

      expect((await database.query('quotes')).single['content'],
          'Existing content');
      expect(
          (await database.query('categories')).single['name'], 'Existing tag');
    });

    test('repairs missing current structure from the shared definition',
        () async {
      final manager = DatabaseSchemaManager();
      await manager.createTables(database);
      await database.execute('DROP INDEX idx_quotes_poi_name');
      await database.execute('DROP TABLE quote_tombstones');

      await manager.checkAndFixDatabaseStructure(database);
      await manager.validateSchema(database);
    });

    test('rolls back and stops when a version adapter fails', () async {
      var followingAdapterRan = false;
      final policy = SchemaMigrationPolicy(<SchemaVersionAdapter>[
        SchemaVersionAdapter(
          version: 2,
          description: 'failing migration',
          apply: (transaction) async {
            await transaction
                .execute('CREATE TABLE migration_marker(id INTEGER)');
            throw StateError('simulated migration failure');
          },
        ),
        SchemaVersionAdapter(
          version: 3,
          description: 'must not run',
          apply: (_) async {
            followingAdapterRan = true;
          },
        ),
      ]);

      await expectLater(
        () => database.transaction(
          (transaction) =>
              policy.apply(transaction, fromVersion: 1, toVersion: 3),
        ),
        throwsA(isA<SchemaMigrationException>()),
      );

      expect(followingAdapterRan, isFalse);
      final marker = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'migration_marker'",
      );
      expect(marker, isEmpty);
    });

    test('遗留列清理排在建快照列的迁移之前，快照不会被表重建抹掉', () async {
      // performAllDataMigrations 是真实入口。它里面 cleanupLegacyTagIdsColumn 会靠
      // **重建 quotes 表**来去掉遗留的 tag_ids 列，而重建用的是写死的列清单，不含任何
      // *_backup 列。所以只要它排在 repairOutOfDomainSentiment 后面，前脚存下的原值
      // 后脚就被整张表抹掉——修复变成了不可逆的删除。
      final manager = DatabaseSchemaManager();
      await manager.createTables(database);

      // 造一个还带着遗留 tag_ids 列的库，触发那次表重建。
      await database.execute('ALTER TABLE quotes ADD COLUMN tag_ids TEXT');
      await database.insert('quotes', {
        'id': 'demo-quote-zh-001',
        'content': '我常以为是丑女造就了美人。',
        'date': '2026-08-22T17:40:00.000Z',
        'sentiment': 'thoughtful', // 不在词汇表里，会被修复置空
      });

      await manager.performAllDataMigrations(database);

      final columns = (await database.rawQuery('PRAGMA table_info(quotes)'))
          .map((column) => column['name'] as String)
          .toSet();
      expect(columns, isNot(contains('tag_ids')), reason: '遗留列清理应当执行过');
      expect(columns, contains('sentiment_backup'), reason: '快照列不能被表重建抹掉');

      final row = (await database.query(
        'quotes',
        where: 'id = ?',
        whereArgs: ['demo-quote-zh-001'],
      ))
          .first;
      expect(row['sentiment'], isNull);
      expect(row['sentiment_backup'], 'thoughtful');
    });
  });
}

Future<void> _createVersion11Schema(Database database) async {
  await database.execute('''
    CREATE TABLE categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      is_default BOOLEAN DEFAULT 0,
      icon_name TEXT
    )
  ''');
  await database.execute('''
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
      weather TEXT,
      temperature TEXT,
      edit_source TEXT,
      delta_content TEXT,
      tag_ids TEXT DEFAULT ''
    )
  ''');
}

Future<void> _createVersion1Schema(Database database) async {
  await database.execute('''
    CREATE TABLE categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      is_default BOOLEAN DEFAULT 0
    )
  ''');
  await database.execute('''
    CREATE TABLE quotes(
      id TEXT PRIMARY KEY,
      content TEXT NOT NULL,
      date TEXT NOT NULL,
      ai_analysis TEXT,
      sentiment TEXT,
      keywords TEXT,
      summary TEXT
    )
  ''');
}
