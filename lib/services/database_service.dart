import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mind_trace/models/quote_model.dart';

class DatabaseService with ChangeNotifier {
  static const _dbVersion = 3;
  static const _dbName = 'mind_trace_v3.db';
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, _dbName);

    return await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        // 笔记表（与您的Quote模型完全匹配）
        await db.execute('''
          CREATE TABLE quotes(
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            content TEXT NOT NULL,
            ai_analysis TEXT,
            sentiment TEXT,
            keywords TEXT,
            summary TEXT,
            tag_ids TEXT,
            category_id TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now'))
          )
        ''');

        // 分类表
        await db.execute('''
          CREATE TABLE categories(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color INTEGER,
            icon_code INTEGER
          )
        ''');

        // 标签表
        await db.execute('''
          CREATE TABLE tags(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE quotes ADD COLUMN created_at INTEGER');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS tags(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL UNIQUE,
              color INTEGER
            )
          ''');
        }
      },
    );
  }

  // =============== 笔记操作 ===============
  Future<String> saveQuote(Quote quote) async {
    final db = await database;
    final id = quote.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.insert(
      'quotes',
      {
        ...quote.toMap(),
        'id': id,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    notifyListeners();
    return id;
  }

  Future<List<Quote>> getQuotes({
    String? categoryId,
    String? tagId,
    String? searchQuery,
  }) async {
    final db = await database;
    
    String? where;
    List<dynamic>? whereArgs;
    
    if (categoryId != null) {
      where = 'category_id = ?';
      whereArgs = [categoryId];
    }
    
    if (tagId != null) {
      where = 'tag_ids LIKE ?';
      whereArgs = ['%$tagId%'];
    }
    
    if (searchQuery != null) {
      where = where != null ? '$where AND content LIKE ?' : 'content LIKE ?';
      whereArgs = whereArgs != null 
          ? [...whereArgs, '%$searchQuery%']
          : ['%$searchQuery%'];
    }

    final maps = await db.query(
      'quotes',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    return maps.map(Quote.fromMap).toList();
  }

  // =============== 分类操作 ===============
  Future<String> saveCategory(Map<String, dynamic> category) async {
    final db = await database;
    final id = category['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.insert(
      'categories',
      {
        ...category,
        'id': id,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    notifyListeners();
    return id;
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    return await db.query('categories', orderBy: 'name ASC');
  }

  // =============== 标签操作 ===============
  Future<String> saveTag(Map<String, dynamic> tag) async {
    final db = await database;
    final id = tag['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.insert(
      'tags',
      {
        ...tag,
        'id': id,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    notifyListeners();
    return id;
  }

  Future<List<Map<String, dynamic>>> getTags() async {
    final db = await database;
    return await db.query('tags', orderBy: 'name ASC');
  }

  // =============== 实用方法 ===============
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('quotes');
      await txn.delete('categories');
      await txn.delete('tags');
    });
    notifyListeners();
  }
}
