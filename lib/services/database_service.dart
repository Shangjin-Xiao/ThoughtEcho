import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../models/note_category.dart';
import '../models/note_tag.dart';
import '../models/quote_model.dart';
import 'package:uuid/uuid.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _database;
  final _categoriesController =
      StreamController<List<NoteCategory>>.broadcast();
  final _tagsController = StreamController<List<NoteTag>>.broadcast();
  final _uuid = const Uuid();
  // 内存存储，用于 Web 平台或调试存储，与原有业务流程保持一致
  final List<Quote> _memoryStore = [];
  // 内存存储分类数据
  final List<NoteCategory> _categoryStore = [];
  // 内存存储标签数据
  final List<NoteTag> _tagStore = [];

  Database get database {
    if (_database == null) {
      throw Exception('数据库未初始化');
    }
    return _database!;
  }

  Future<void> init() async {
    if (kIsWeb) {
      // Web平台特定的初始化
      debugPrint('在Web平台初始化内存存储');
      // 添加一些示例数据以便Web平台测试
      if (_memoryStore.isEmpty) {
        _memoryStore.add(
          Quote(
            id: _uuid.v4(),
            content: '欢迎使用心迹 - Web版',
            date: DateTime.now().toIso8601String(),
            source: '示例来源',
            aiAnalysis: '这是Web平台示例笔记',
          ),
        );
      }

      if (_categoryStore.isEmpty) {
        _categoryStore.add(
          NoteCategory(
            id: _uuid.v4(),
            name: '默认分类',
            isDefault: true,
            iconName: 'bookmark',
          ),
        );
      }

      if (_tagStore.isEmpty) {
        _tagStore.add(NoteTag(id: _uuid.v4(), name: '默认标签', iconName: 'tag'));
      }

      // 触发更新
      _categoriesController.add(_categoryStore);
      _tagsController.add(_tagStore);
      notifyListeners();
      return;
    }

    if (_database != null) return;

    debugPrint('初始化数据库...');

    try {
      // 仅在 Windows 平台下使用 FFI，其它平台（如 Android）直接使用 sqflite 默认实现
      if (Platform.isWindows) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      // 获取数据库存储路径，由 main.dart 已设置好路径
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'thoughtecho.db');

      _database = await openDatabase(
        path,
        version: 8,
        onCreate: (db, version) async {
          await db.transaction((txn) async {
            // 创建分类表
            await txn.execute('''
              CREATE TABLE categories(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                is_default BOOLEAN DEFAULT 0,
                icon_name TEXT
              )
            ''');
            // 创建标签表
            await txn.execute('''
              CREATE TABLE tags(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                is_default BOOLEAN DEFAULT 0,
                icon_name TEXT
              )
            ''');
            // 创建引用表
            await txn.execute('''
              CREATE TABLE quotes(
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                date TEXT NOT NULL,
                source TEXT,
                source_author TEXT,
                source_work TEXT,
                tag_ids TEXT DEFAULT '',
                ai_analysis TEXT,
                sentiment TEXT,
                keywords TEXT,
                summary TEXT,
                category_id TEXT DEFAULT '',
                color_hex TEXT,
                location TEXT,
                weather TEXT,
                temperature TEXT
              )
            ''');
          });
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await db.transaction((txn) async {
            try {
              if (oldVersion < 2) {
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ""',
                );
              }
              if (oldVersion < 3) {
                await txn.execute(
                  'ALTER TABLE categories ADD COLUMN icon_name TEXT',
                );
              }
              if (oldVersion < 4) {
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN category_id TEXT DEFAULT ""',
                );
              }
              if (oldVersion < 5) {
                await txn.execute('ALTER TABLE quotes ADD COLUMN source TEXT');
              }
              if (oldVersion < 6) {
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN color_hex TEXT',
                );
              }
              if (oldVersion < 7) {
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN source_author TEXT',
                );
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN source_work TEXT',
                );

                // 迁移现有数据
                final quotes = await txn.query(
                  'quotes',
                  where: 'source IS NOT NULL AND source != ""',
                );
                for (final quote in quotes) {
                  final String? source = quote['source'] as String?;
                  if (source != null && source.isNotEmpty) {
                    String? author;
                    String? work;

                    if (source.contains('——') && source.contains('「')) {
                      final parts = source.split('——');
                      if (parts.length > 1) {
                        author = parts[0].trim();
                        final workMatch = RegExp(
                          r'「(.+?)」',
                        ).firstMatch(parts[1]);
                        if (workMatch != null) {
                          work = workMatch.group(1);
                        }
                      }
                    } else if (source.contains('——')) {
                      final parts = source.split('——');
                      if (parts.length > 1) {
                        author = parts[0].trim();
                        work = parts[1].trim();
                      }
                    }

                    await txn.update(
                      'quotes',
                      {'source_author': author, 'source_work': work},
                      where: 'id = ?',
                      whereArgs: [quote['id']],
                    );
                  }
                }
              }
              if (oldVersion < 8) {
                debugPrint('数据库升级：从版本 $oldVersion 升级到版本 $newVersion');
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN location TEXT',
                );
                await txn.execute('ALTER TABLE quotes ADD COLUMN weather TEXT');
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN temperature TEXT',
                );
                debugPrint('数据库升级：新字段添加完成');
              }
            } catch (e) {
              debugPrint('数据库升级失败: $e');
              rethrow;
            }
          });
        },
      );

      // 检查并修复数据库结构
      await _checkAndFixDatabaseStructure();

      // 更新分类流数据
      await _updateCategoriesStream();
      await _updateTagsStream();
    } catch (e) {
      debugPrint('数据库初始化错误: $e');
      rethrow;
    }
  }

  /// 检查并修复数据库结构，确保所有必要的列都存在
  Future<void> _checkAndFixDatabaseStructure() async {
    try {
      final db = database;

      await db.transaction((txn) async {
        try {
          // 获取quotes表的列信息
          final tableInfo = await txn.rawQuery("PRAGMA table_info(quotes)");
          final columnNames =
              tableInfo.map((col) => col['name'] as String).toSet();

          debugPrint('当前quotes表列: $columnNames');

          // 检查是否缺少必要的列
          final requiredColumns = {
            'id': 'TEXT PRIMARY KEY',
            'content': 'TEXT NOT NULL',
            'date': 'TEXT NOT NULL',
            'source': 'TEXT',
            'source_author': 'TEXT',
            'source_work': 'TEXT',
            'tag_ids': 'TEXT DEFAULT ""',
            'ai_analysis': 'TEXT',
            'sentiment': 'TEXT',
            'keywords': 'TEXT',
            'summary': 'TEXT',
            'category_id': 'TEXT DEFAULT ""',
            'color_hex': 'TEXT',
            'location': 'TEXT',
            'weather': 'TEXT',
            'temperature': 'TEXT',
          };

          final missingColumns = <String, String>{};
          for (final entry in requiredColumns.entries) {
            if (!columnNames.contains(entry.key)) {
              missingColumns[entry.key] = entry.value;
            }
          }

          if (missingColumns.isNotEmpty) {
            debugPrint('检测到缺少列: ${missingColumns.keys.join(', ')}，正在添加...');

            // 在事务中添加缺少的列
            for (final entry in missingColumns.entries) {
              try {
                await txn.execute(
                  'ALTER TABLE quotes ADD COLUMN ${entry.key} ${entry.value}',
                );
                debugPrint('成功添加列: ${entry.key}');
              } catch (e) {
                debugPrint('添加列 ${entry.key} 时出错: $e');
                rethrow; // 在事务中抛出异常将触发回滚
              }
            }
            debugPrint('所有缺失列添加完成');
          } else {
            debugPrint('数据库结构完整，无需修复');
          }

          // 检查tags表是否存在
          final tables = await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='tags'",
          );

          if (tables.isEmpty) {
            debugPrint('创建缺失的tags表');
            await txn.execute('''
              CREATE TABLE IF NOT EXISTS tags(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                is_default BOOLEAN DEFAULT 0,
                icon_name TEXT
              )
            ''');
          }

          // 验证quotes表的完整性
          final rows = await txn.rawQuery('PRAGMA integrity_check');
          if (rows.isNotEmpty &&
              rows[0].values.first.toString().toLowerCase() != 'ok') {
            throw Exception('数据库完整性检查失败: ${rows[0].values.first}');
          }
          debugPrint('数据库完整性检查通过');
        } catch (e) {
          debugPrint('数据库结构检查/修复过程中出错: $e');
          rethrow; // 确保事务回滚
        }
      });
    } catch (e) {
      debugPrint('数据库结构检查/修复失败: $e');
      // 此处可以添加重试逻辑或者其他错误恢复机制
      rethrow;
    }
  }

  Future<List<NoteCategory>> getCategories() async {
    if (kIsWeb) {
      return _categoryStore;
    }
    try {
      final db = database;
      final maps = await db.query('categories');
      final categories = maps.map((map) => NoteCategory.fromMap(map)).toList();
      return categories;
    } catch (e) {
      debugPrint('获取分类错误: $e');
      return [];
    }
  }

  /// 添加一条分类
  Future<void> addCategory(String name, {String? iconName}) async {
    if (kIsWeb) {
      final newCategory = NoteCategory(
        id: _uuid.v4(),
        name: name,
        isDefault: false,
        iconName: iconName ?? "",
      );
      _categoryStore.add(newCategory);
      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }
    final db = database;
    final id = _uuid.v4();
    final categoryMap = {
      'id': id,
      'name': name,
      'is_default': 0,
      'icon_name': iconName ?? "",
    };
    await db.insert(
      'categories',
      categoryMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _updateCategoriesStream();
    notifyListeners();
  }

  /// 监听分类流
  Stream<List<NoteCategory>> watchCategories() {
    _updateCategoriesStream();
    return _categoriesController.stream;
  }

  /// 删除指定分类
  Future<void> deleteCategory(String id) async {
    if (kIsWeb) {
      _categoryStore.removeWhere((category) => category.id == id);
      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }
    final db = database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    await _updateCategoriesStream();
    notifyListeners();
  }

  Future<void> _updateCategoriesStream() async {
    final categories = await getCategories();
    _categoriesController.add(categories);
  }

  /// 添加一条引用（笔记）
  Future<void> addQuote(Quote quote) async {
    if (kIsWeb) {
      _memoryStore.add(quote);
      notifyListeners();
      return;
    }
    try {
      final db = database;
      // 如果笔记中不包含 categoryId, 则设为空字符串
      final id = quote.id ?? _uuid.v4();
      final quoteMap = quote.toMap();
      quoteMap['id'] = id;
      if (!quoteMap.containsKey('category_id')) {
        quoteMap['category_id'] = "";
      }

      // 确保所有必需的字段都存在
      if (!quoteMap.containsKey('content') || quoteMap['content'] == null) {
        throw Exception('笔记内容不能为空');
      }

      if (!quoteMap.containsKey('date') || quoteMap['date'] == null) {
        quoteMap['date'] = DateTime.now().toIso8601String();
      }

      // 检查数据库中是否存在location、weather、temperature列
      final tableInfo = await db.rawQuery("PRAGMA table_info(quotes)");
      final columnNames = tableInfo.map((col) => col['name'] as String).toSet();

      // 如果列不存在，从Map中移除相应的键，避免SQL错误
      if (!columnNames.contains('location')) quoteMap.remove('location');
      if (!columnNames.contains('weather')) quoteMap.remove('weather');
      if (!columnNames.contains('temperature')) quoteMap.remove('temperature');

      debugPrint('保存笔记，使用列: ${quoteMap.keys.join(', ')}');

      await db.insert(
        'quotes',
        quoteMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('笔记已成功保存到数据库，ID: ${quoteMap['id']}');
      notifyListeners();
    } catch (e) {
      debugPrint('保存笔记到数据库时出错: $e');
      rethrow; // 重新抛出异常，让调用者处理
    }
  }

  /// 获取用户的所有引用（支持通过标签 tagIds 或分类 categoryId 查询）
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
  }) async {
    try {
      if (kIsWeb) {
        // Web平台特定逻辑
        if (tagIds != null && tagIds.isNotEmpty) {
          return _memoryStore
              .where(
                (quote) => tagIds.any((tagId) => quote.tagIds.contains(tagId)),
              )
              .toList();
        } else if (categoryId != null && categoryId.isNotEmpty) {
          return _memoryStore
              .where((quote) => quote.categoryId == categoryId)
              .toList();
        }
        return List.from(_memoryStore);
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

  /// 删除指定的笔记
  Future<void> deleteQuote(String id) async {
    if (kIsWeb) {
      _memoryStore.removeWhere((quote) => quote.id == id);
      notifyListeners();
      return;
    }
    final db = database;
    await db.delete('quotes', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  /// 更新笔记内容
  Future<void> updateQuote(Quote quote) async {
    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quote.id);
      if (index != -1) {
        _memoryStore[index] = quote;
        notifyListeners();
      }
      return;
    }

    try {
      if (quote.id == null) {
        throw Exception('更新笔记时ID不能为空');
      }

      final db = database;
      final quoteMap = quote.toMap();

      // 确保所有必需的字段都存在
      if (!quoteMap.containsKey('content') || quoteMap['content'] == null) {
        throw Exception('笔记内容不能为空');
      }

      if (!quoteMap.containsKey('date') || quoteMap['date'] == null) {
        quoteMap['date'] = DateTime.now().toIso8601String();
      }

      // 检查数据库中是否存在location、weather、temperature列
      final tableInfo = await db.rawQuery("PRAGMA table_info(quotes)");
      final columnNames = tableInfo.map((col) => col['name'] as String).toSet();

      // 如果列不存在，从Map中移除相应的键，避免SQL错误
      if (!columnNames.contains('location')) quoteMap.remove('location');
      if (!columnNames.contains('weather')) quoteMap.remove('weather');
      if (!columnNames.contains('temperature')) quoteMap.remove('temperature');

      debugPrint('更新笔记，使用列: ${quoteMap.keys.join(', ')}');

      await db.update(
        'quotes',
        quoteMap,
        where: 'id = ?',
        whereArgs: [quote.id],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('笔记已成功更新，ID: ${quote.id}');
      notifyListeners();
    } catch (e) {
      debugPrint('更新笔记时出错: $e');
      rethrow; // 重新抛出异常，让调用者处理
    }
  }

  // 标签相关方法
  Future<void> addTag(String name, {String? iconName}) async {
    if (kIsWeb) {
      final tag = NoteTag(id: _uuid.v4(), name: name, iconName: iconName);
      _tagStore.add(tag);
      _tagsController.add(_tagStore);
      notifyListeners();
      return;
    }

    final db = database;
    final tag = NoteTag(id: _uuid.v4(), name: name, iconName: iconName);

    await db.insert(
      'tags',
      tag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _updateTagsStream();
    notifyListeners();
  }

  Stream<List<NoteTag>> watchTags() {
    if (kIsWeb) {
      return _tagsController.stream;
    }
    return Stream.fromFuture(getTags());
  }

  Future<void> deleteTag(String id) async {
    if (kIsWeb) {
      _tagStore.removeWhere((tag) => tag.id == id);
      _tagsController.add(_tagStore);
      notifyListeners();
      return;
    }

    final db = database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
    await _updateTagsStream();
    notifyListeners();
  }

  Future<void> _updateTagsStream() async {
    if (kIsWeb) {
      _tagsController.add(_tagStore);
      return;
    }
    final tags = await getTags();
    _tagsController.add(tags);
  }

  Future<List<NoteTag>> getTags() async {
    if (kIsWeb) {
      return _tagStore;
    }
    try {
      final db = database;
      final maps = await db.query('tags');
      return maps.map((map) => NoteTag.fromMap(map)).toList();
    } catch (e) {
      debugPrint('获取标签错误: $e');
      return [];
    }
  }

  /// 导出所有数据
  Future<String> exportAllData({String? customPath}) async {
    try {
      final data = {
        'metadata': {
          'app': '心迹',
          'version': 8, // 当前数据库版本
          'exportTime': DateTime.now().toIso8601String(),
        },
        'quotes': await _exportQuotes(),
        'categories': await _exportCategories(),
        'tags': await _exportTags(),
      };

      final jsonStr = json.encode(data);

      final String path;
      if (customPath != null) {
        path = customPath;
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        path =
            '${docDir.path}/thoughtecho_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      }

      final file = File(path);
      await file.writeAsString(jsonStr);
      return path;
    } catch (e) {
      debugPrint('导出数据失败: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _exportQuotes() async {
    if (kIsWeb) {
      return _memoryStore.map((q) => q.toMap()).toList();
    }
    try {
      final db = database;
      return await db.query('quotes');
    } catch (e) {
      debugPrint('导出笔记数据失败: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _exportCategories() async {
    if (kIsWeb) {
      return _categoryStore.map((c) => c.toMap()).toList();
    }
    try {
      final db = database;
      return await db.query('categories');
    } catch (e) {
      debugPrint('导出分类数据失败: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _exportTags() async {
    if (kIsWeb) {
      return _tagStore.map((t) => t.toMap()).toList();
    }
    try {
      final db = database;
      return await db.query('tags');
    } catch (e) {
      debugPrint('导出标签数据失败: $e');
      return [];
    }
  }

  /// 从备份文件导入数据
  Future<void> importData(String filePath, {bool clearExisting = true}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('导入文件不存在');
      }

      final jsonStr = await file.readAsString();
      final data = json.decode(jsonStr) as Map<String, dynamic>;

      // 验证数据格式
      if (!_validateImportData(data)) {
        throw Exception('无效的备份文件格式');
      }

      final importVersion = data['metadata']['version'] as int;
      if (kIsWeb) {
        // Web平台特殊处理
        if (clearExisting) {
          _memoryStore.clear();
          _categoryStore.clear();
          _tagStore.clear();
        }

        // 导入数据
        await _importWebData(data);
      } else {
        final db = database;
        await db.transaction((txn) async {
          try {
            if (clearExisting) {
              // 在删除前创建临时备份
              final backupPath = await _createBackup();
              debugPrint('已创建数据备份: $backupPath');

              await txn.delete('categories');
              await txn.delete('quotes');
              await txn.delete('tags');
            }

            // 导入数据
            await _importData(txn, data);
          } catch (e) {
            debugPrint('导入过程中出错: $e');
            rethrow;
          }
        });
      }

      notifyListeners();
    } catch (e) {
      debugPrint('导入数据失败: $e');
      rethrow;
    }
  }

  bool _validateImportData(Map<String, dynamic> data) {
    try {
      if (!data.containsKey('metadata') ||
          !data.containsKey('quotes') ||
          !data.containsKey('categories')) {
        return false;
      }

      final metadata = data['metadata'] as Map<String, dynamic>?;
      if (metadata == null ||
          !metadata.containsKey('app') ||
          !metadata.containsKey('version') ||
          !metadata.containsKey('exportTime')) {
        return false;
      }

      if (metadata['app'] != '心迹') {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _importData(Transaction txn, Map<String, dynamic> data) async {
    // 导入分类
    final categories = data['categories'] as List;
    for (final c in categories) {
      if (c is! Map<String, dynamic>) continue;
      await txn.insert(
        'categories',
        c,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // 导入标签
    if (data.containsKey('tags')) {
      final tags = data['tags'] as List;
      for (final t in tags) {
        if (t is! Map<String, dynamic>) continue;
        await txn.insert(
          'tags',
          t,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    // 导入笔记
    final quotes = data['quotes'] as List;
    for (final q in quotes) {
      if (q is! Map<String, dynamic>) continue;
      await txn.insert(
        'quotes',
        q,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _importWebData(Map<String, dynamic> data) async {
    // 导入分类
    final categories = data['categories'] as List;
    for (final c in categories) {
      if (c is! Map<String, dynamic>) continue;
      _categoryStore.add(NoteCategory.fromMap(c));
    }

    // 导入标签
    if (data.containsKey('tags')) {
      final tags = data['tags'] as List;
      for (final t in tags) {
        if (t is! Map<String, dynamic>) continue;
        _tagStore.add(NoteTag.fromMap(t));
      }
    }

    // 导入笔记
    final quotes = data['quotes'] as List;
    for (final q in quotes) {
      if (q is! Map<String, dynamic>) continue;
      _memoryStore.add(Quote.fromMap(q));
    }
  }

  Future<String> _createBackup() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final docDir = await getApplicationDocumentsDirectory();
    final backupPath = '${docDir.path}/backup_before_import_$timestamp.json';
    await exportAllData(customPath: backupPath);
    return backupPath;
  }
}
