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
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE categories(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              is_default BOOLEAN DEFAULT 0,
              icon_name TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE quotes(
              id TEXT PRIMARY KEY,
              content TEXT NOT NULL,
              date TEXT NOT NULL,
              tag_ids TEXT DEFAULT '',
              ai_analysis TEXT,
              sentiment TEXT,
              keywords TEXT,
              summary TEXT
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ""');
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE categories ADD COLUMN icon_name TEXT');
          }
        },
      );
    } catch (e) {
      debugPrint('数据库初始化错误: \$e');
      rethrow;
    }
  }

  Future<void> _ensureDefaultCategories() async {
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

  Future<List<Quote>> getUserQuotes({List<String>? tagIds, String? categoryId}) async {
    try {
      if (kIsWeb) {
        return _memoryStore;
      }

      final db = database; // 删除 await
      List<Map<String, dynamic>> maps;
      if (tagIds != null && tagIds.isNotEmpty) {
        final whereClause = tagIds.map((id) => 'tag_ids LIKE ?').join(' OR '); // 使用 ? 占位符
        maps = await db.query('quotes', where: whereClause, whereArgs: tagIds.map((id) => '%$id%').toList()); // 使用 whereArgs 传递参数
      } else if (categoryId != null && categoryId.isNotEmpty) {
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
          tagIds: (maps[i]['tag_ids']?.toString().split(',') ?? []).cast<String>(),
          sentiment: maps[i]['sentiment'],
          keywords: maps[i]['keywords'],
          summary: maps[i]['summary'],
        );
      });
    } catch (e) {
      debugPrint('获取笔记错误: \$e');
      rethrow;
    }
  }

  Stream<List<NoteCategory>> get categoriesStream { // 替换 tagsStream 为 categoriesStream, 返回类型为 NoteCategory
    if (kIsWeb) {
      return Stream.value(_categoryStore); // 替换 _tagStore 为 _categoryStore
    }

    return watchCategories(); // 替换 loadTags 为 watchCategories
  }

  Stream<List<NoteCategory>> loadCategories() async* {
    final db = database; // 删除 await
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

  Future<void> addCategory(String name, {String? iconName}) async {
    if (kIsWeb) {
      final category = NoteCategory(
        id: _uuid.v4(),
        name: name,
        iconName: iconName,
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
        'icon_name': iconName,
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

    final controller = StreamController<List<NoteCategory>>.broadcast();
    
    Future<void> loadCategories() async {
      try {
        final db = database; // 删除 await
        final maps = await db.query('categories', orderBy: 'name');
        final categories = maps.map((map) => NoteCategory.fromMap(map)).toList();
        if (!controller.isClosed) {
          controller.add(categories);
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    loadCategories();
    
    // 确保控制器在不再需要时关闭
    controller.onCancel = () {
      controller.close();
    };
    
    return controller.stream;
  }

  Future<void> _notifyCategories() async {
  }
}
