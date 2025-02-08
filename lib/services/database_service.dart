import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import 'package:uuid/uuid.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _database;
  final _categoriesController = StreamController<List<NoteCategory>>.broadcast();
  final _uuid = const Uuid();
  final List<Quote> _memoryStore = [];
  final List<NoteCategory> _categoryStore = [];

  Database get database {
    if (_database == null) {
      throw Exception('数据库未初始化');
    }
    return _database!;
  }

  Future<void> init() async {
    if (kIsWeb) return;
    if (_database != null) return;

    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final path = await getDatabasesPath();
      _database = await openDatabase(
        join(path, 'mind_trace.db'),
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE categories(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              is_default BOOLEAN DEFAULT 0
            )
          ''');

          await db.execute('''
            CREATE TABLE quotes(
              id TEXT PRIMARY KEY,
              content TEXT NOT NULL,
              date TEXT NOT NULL,
              category_id TEXT DEFAULT 'general',
              ai_analysis TEXT,
              sentiment TEXT,
              keywords TEXT,
              summary TEXT,
              FOREIGN KEY (category_id) REFERENCES categories (id)
            )
          ''');

          // 添加默认分类
          final defaultCategories = [
            {'id': 'general', 'name': '随记', 'is_default': 1},
            {'id': 'movie', 'name': '影视', 'is_default': 1},
            {'id': 'book', 'name': '书籍', 'is_default': 1},
            {'id': 'poetry', 'name': '古诗词', 'is_default': 1},
          ];

          for (var category in defaultCategories) {
            await db.insert('categories', category);
          }
        },
      );

      // 检查并添加缺失的默认分类
      await _ensureDefaultCategories();
    } catch (e) {
      debugPrint('数据库初始化错误: $e');
      rethrow;
    }
  }

  Future<void> _ensureDefaultCategories() async {
    if (kIsWeb) return;

    final defaultCategories = {
      'general': '随记',
      'movie': '影视',
      'book': '书籍',
      'poetry': '古诗词',
    };

    final db = await database;
    final existingCategories = await db.query('categories', where: 'is_default = 1');
    final existingIds = existingCategories.map((c) => c['id'] as String).toSet();

    for (var entry in defaultCategories.entries) {
      if (!existingIds.contains(entry.key)) {
        await db.insert('categories', {
          'id': entry.key,
          'name': entry.value,
          'is_default': 1,
        });
      }
    }
  }

  Future<void> addQuote(Quote quote) async {
    if (kIsWeb) {
      _memoryStore.add(quote);
      notifyListeners();
      return;
    }

    final db = await database;
    final id = quote.id ?? _uuid.v4();
    final quoteMap = quote.toMap();
    quoteMap['id'] = id;
    
    await db.insert(
      'quotes',
      quoteMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<List<Quote>> getUserQuotes({String? categoryId}) async {
    try {
      if (kIsWeb) {
        if (categoryId != null) {
          return _memoryStore.where((quote) => quote.categoryId == categoryId).toList();
        }
        return _memoryStore;
      }

      final db = await database;
      final List<Map<String, dynamic>> maps;
      if (categoryId != null) {
        maps = await db.query('quotes', where: 'category_id = ?', whereArgs: [categoryId]);
      } else {
        maps = await db.query('quotes');
      }

      return List.generate(maps.length, (i) {
        return Quote(
          id: maps[i]['id'],
          date: maps[i]['date'],
          content: maps[i]['content'],
          aiAnalysis: maps[i]['ai_analysis'],
          categoryId: maps[i]['category_id'],
          sentiment: maps[i]['sentiment'],
          keywords: maps[i]['keywords'],
          summary: maps[i]['summary'],
        );
      });
    } catch (e) {
      debugPrint('获取笔记错误: $e');
      rethrow;
    }
  }

  Stream<List<NoteCategory>> get categoriesStream {
    if (kIsWeb) {
      return Stream.value(_categoryStore);
    }

    return loadCategories();
  }

  Stream<List<NoteCategory>> loadCategories() async* {
    final db = await database;
    final maps = await db.query('categories', orderBy: 'name');
    final categories = maps.map((map) => NoteCategory.fromMap(map)).toList();
    yield categories;
  }

  Future<List<NoteCategory>> getCategories() async {
    if (kIsWeb) {
      return _categoryStore;
    }

    final db = await database;
    final maps = await db.query('categories', orderBy: 'name');
    return maps.map((map) => NoteCategory.fromMap(map)).toList();
  }

  Future<void> addCategory(String name) async {
    if (kIsWeb) {
      final category = NoteCategory(
        id: _uuid.v4(),
        name: name,
      );
      _categoryStore.add(category);
      notifyListeners();
      return;
    }

    final db = await database;
    final id = _uuid.v4();
    await db.insert(
      'categories',
      {
        'id': id,
        'name': name,
        'is_default': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> deleteCategory(String id) async {
    // 检查是否为默认分类
    final defaultIds = {'general', 'movie', 'book', 'poetry'};
    if (defaultIds.contains(id)) {
      throw Exception('默认分类不能删除');
    }

    if (kIsWeb) {
      _categoryStore.removeWhere((c) => c.id == id);
      notifyListeners();
      return;
    }

    final db = await database;
    // 将该分类下的笔记移动到默认分类
    await db.update(
      'quotes',
      {'category_id': 'general'},
      where: 'category_id = ?',
      whereArgs: [id],
    );
    
    // 删除分类
    await db.delete(
      'categories',
      where: 'id = ? AND is_default = 0',
      whereArgs: [id],
    );
    notifyListeners();
  }

  Stream<List<NoteCategory>> watchCategories() {
    if (kIsWeb) {
      return Stream.value(_categoryStore);
    }

    final controller = StreamController<List<NoteCategory>>();
    
    Future<void> loadCategories() async {
      try {
        final db = await database;
        final maps = await db.query('categories', orderBy: 'name');
        final categories = maps.map((map) => NoteCategory.fromMap(map)).toList();
        controller.add(categories);
      } catch (e) {
        controller.addError(e);
      }
    }

    loadCategories();
    return controller.stream;
  }

  Future<void> _notifyCategories() async {
    final categories = await getCategories();
    _categoriesController.add(categories);
  }
}