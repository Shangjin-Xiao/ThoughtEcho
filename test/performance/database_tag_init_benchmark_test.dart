import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late DatabaseService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> createSchema(Database db) async {
    await db.execute('''
        CREATE TABLE quotes(
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          date TEXT NOT NULL,
          category_id TEXT DEFAULT '',
          last_modified TEXT
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
          PRIMARY KEY (quote_id, tag_id),
          FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
          FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
        )
      ''');
    await db.execute('PRAGMA foreign_keys = ON');
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

  setUp(() async {
    service = DatabaseService();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await createSchema(db);
    DatabaseService.setTestDatabase(db);
    await service.init();
  });

  tearDown(() async {
    await db.close();
  });

  test('Benchmark initDefaultHitokotoTags execution time', () async {
    // 1. Prepare stale / broken categories that trigger updates & repairs for default categories
    await db.delete('categories');
    final now = DateTime.now().toUtc().toIso8601String();

    // Populate categories requiring name or is_default fix
    final defaultCategories = [
      {
        'id': 'default_hitokoto',
        'name': '每日一言_旧',
        'is_default': 0,
        'icon_name': 'format_quote',
        'last_modified': now
      },
      {
        'id': 'default_anime',
        'name': '动画_旧',
        'is_default': 0,
        'icon_name': '🎬',
        'last_modified': now
      },
      {
        'id': 'default_comic',
        'name': '漫画_旧',
        'is_default': 0,
        'icon_name': '📚',
        'last_modified': now
      },
      {
        'id': 'default_game',
        'name': '游戏_旧',
        'is_default': 0,
        'icon_name': '🎮',
        'last_modified': now
      },
      {
        'id': 'default_novel',
        'name': '文学_旧',
        'is_default': 0,
        'icon_name': '📖',
        'last_modified': now
      },
      {
        'id': 'default_original',
        'name': '原创_旧',
        'is_default': 0,
        'icon_name': '✨',
        'last_modified': now
      },
      {
        'id': 'default_internet',
        'name': '来自网络_旧',
        'is_default': 0,
        'icon_name': '🌐',
        'last_modified': now
      },
      {
        'id': 'default_other',
        'name': '其他_旧',
        'is_default': 0,
        'icon_name': '📦',
        'last_modified': now
      },
      {
        'id': 'default_movie',
        'name': '影视_旧',
        'is_default': 0,
        'icon_name': '🎞️',
        'last_modified': now
      },
      {
        'id': 'default_poem',
        'name': '诗词_旧',
        'is_default': 0,
        'icon_name': '🪶',
        'last_modified': now
      },
      {
        'id': 'default_music',
        'name': '网易云_旧',
        'is_default': 0,
        'icon_name': '🎧',
        'last_modified': now
      },
      {
        'id': 'default_philosophy',
        'name': '哲学_旧',
        'is_default': 0,
        'icon_name': '🤔',
        'last_modified': now
      },
    ];

    for (final cat in defaultCategories) {
      await db.insert('categories', cat);
    }

    const iterations = 200;
    final stopwatch = Stopwatch()..start();

    for (int i = 0; i < iterations; i++) {
      // Re-invalidate names to trigger update logic each iteration
      await db.execute(
          "UPDATE categories SET name = name || '_diff', is_default = 0");
      await service.initDefaultHitokotoTags();
    }

    stopwatch.stop();
    debugPrint(
        'Time taken for $iterations iterations of initDefaultHitokotoTags: ${stopwatch.elapsedMilliseconds} ms (${(stopwatch.elapsedMicroseconds / iterations).toStringAsFixed(2)} us/op)');

    // Verify all categories are properly restored
    final categories = await db.query('categories');
    expect(categories.length, defaultCategories.length);
    for (final row in categories) {
      expect(row['is_default'], 1);
      expect((row['name'] as String).endsWith('_diff'), isFalse);
    }
  });
}
