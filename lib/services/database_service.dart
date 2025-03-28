import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mind_trace/models/quote_model.dart';

class DatabaseService with ChangeNotifier {
  static const _dbVersion = 2;  // 版本号升级
  static const _dbName = 'mind_trace_v2.db';
  Database? _database;

  // 单例模式
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, _dbName);

      debugPrint('数据库路径: $dbPath');

      return await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA foreign_keys=ON');  // 启用外键约束
        },
      );
    } catch (e) {
      debugPrint('数据库初始化失败: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 主表：笔记
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

    // 标签表
    await db.execute('''
      CREATE TABLE tags(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER
      )
    ''');

    // 分类表
    await db.execute('''
      CREATE TABLE categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_code INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE quotes ADD COLUMN created_at INTEGER');
    }
  }

  /// 笔记操作 ---------------------------------------------------
  
  Future<String> addQuote(Quote quote) async {
    final db = await database;
    final id = quote.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.insert(
      'quotes',
      {
        ...quote.toMap(),
        'id': id,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    notifyListeners();
    return id;
  }

  Future<List<Quote>> getQuotes({
    String? searchQuery,
    String? tagId,
    String? categoryId,
  }) async {
    final db = await database;
    
    String? where;
    List<dynamic>? whereArgs;
    
    if (searchQuery != null) {
      where = 'content LIKE ?';
      whereArgs = ['%$searchQuery%'];
    }
    
    if (tagId != null) {
      where = 'tag_ids LIKE ?';
      whereArgs = ['%$tagId%'];
    }
    
    if (categoryId != null) {
      where = 'category_id = ?';
      whereArgs = [categoryId];
    }

    final maps = await db.query(
      'quotes',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    return maps.map(Quote.fromMap).toList();
  }

  Future<int> updateQuote(Quote quote) async {
    final db = await database;
    final count = await db.update(
      'quotes',
      quote.toMap(),
      where: 'id = ?',
      whereArgs: [quote.id],
    );
    notifyListeners();
    return count;
  }

  Future<int> deleteQuote(String id) async {
    final db = await database;
    final count = await db.delete(
      'quotes',
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
    return count;
  }

  /// 标签操作 ---------------------------------------------------
  
  Future<void> addTag(Map<String, dynamic> tag) async {
    final db = await database;
    await db.insert(
      'tags',
      tag,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getTags() async {
    final db = await database;
    return await db.query('tags');
  }

  /// 分类操作 ---------------------------------------------------
  
  Future<void> addCategory(Map<String, dynamic> category) async {
    final db = await database;
    await db.insert(
      'categories',
      category,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    return await db.query('categories');
  }

  /// 维护操作 ---------------------------------------------------
  
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> clearDatabase() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('quotes');
      await txn.delete('tags');
      await txn.delete('categories');
    });
    notifyListeners();
  }
}
