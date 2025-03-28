import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
// 仅在 Windows 平台下使用 sqflite_common_ffi，其它平台直接使用 sqflite 默认实现
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import 'package:uuid/uuid.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _database;
  final _categoriesController =
      StreamController<List<NoteCategory>>.broadcast();
  final _uuid = const Uuid();
  // 内存存储，用于 Web 平台或调试存储，与原有业务流程保持一致
  final List<Quote> _memoryStore = [];
  // 存储分类数据
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
      // 仅在 Windows 平台下使用 FFI，其它平台（如 Android）直接使用 sqflite 默认实现
      if (Platform.isWindows) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      // 获取数据库存储路径，由 main.dart 已设置好路径
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'mind_trace.db');
      
      // 打开数据库，并在 onCreate 方法中创建 categories 与 quotes 两个数据表
      _database = await openDatabase(
        path,
        version: 3,
        onCreate: (db, version) async {
          // 创建分类表：包含 id、名称、是否为默认、图标名称等字段
          await db.execute('''
            CREATE TABLE categories(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              is_default BOOLEAN DEFAULT 0,
              icon_name TEXT
            )
          ''');
          // 创建引用（笔记）表：包含 id、内容、日期、标签、AI 分析、情感、关键词、摘要等字段
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
          // 如果数据库版本低于 2，添加 tag_ids 字段
          if (oldVersion < 2) {
            await db.execute(
                'ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ""');
          }
          // 如果数据库版本低于 3，添加 categories 表中的 icon_name 字段
          if (oldVersion < 3) {
            await db.execute(
                'ALTER TABLE categories ADD COLUMN icon_name TEXT');
          }
        },
      );
    } catch (e) {
      debugPrint('数据库初始化错误: $e');
      rethrow;
    }
  }

  // 如果需要，在此处完善默认分类初始化逻辑
  Future<void> _ensureDefaultCategories() async {
    // 添加默认分类示例，可根据实际需求进行调整
    // 例如：检查 _categoryStore 是否为空，如果为空则插入默认分类
  }

  /// 添加一条引用（笔记）
  Future<void> addQuote(Quote quote) async {
    if (kIsWeb) {
      _memoryStore.add(quote);
      notifyListeners();
      return;
    }
    final db = database;
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

  /// 获取用户的所有引用（支持通过标签 tagIds 或分类 categoryId 查询）
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
  }) async {
    try {
      if (kIsWeb) {
        return _memoryStore;
      }
      final db = database;
      List<Map<String, dynamic>> maps;
      if (tagIds != null && tagIds.isNotEmpty) {
        // 根据 tag_ids 字段进行模糊匹配查询
        final whereClause = tagIds.map((id) => 'tag_ids LIKE ?').join(' OR ');
        maps = await db.query(
          'quotes',
          where: whereClause,
          whereArgs: tagIds.map((id) => '%$id%').toList(),
        );
      } else if (categoryId != null && categoryId.isNotEmpty) {
        maps = await db.query(
          'quotes',
          where: 'category_id = ?',
          whereArgs: [categoryId],
        );
      } else {
        maps = await db.query('quotes');
      }
      return maps.map((map) => Quote.fromMap(map)).toList();
    } catch (e) {
      debugPrint('获取引用错误: $e');
      return [];
    }
  }
}
