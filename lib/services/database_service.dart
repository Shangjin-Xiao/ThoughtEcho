import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
// 仅在 Windows 平台下使用 sqflite_common_ffi，其它平台直接使用 sqflite 默认实现
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import 'package:uuid/uuid.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _database;
  final _categoriesController = StreamController<List<NoteCategory>>.broadcast();
  final _uuid = const Uuid();
  // 内存存储，用于 Web 平台或调试存储，与原有业务流程保持一致
  final List<Quote> _memoryStore = [];
  // 内存存储分类数据
  final List<NoteCategory> _categoryStore = [];

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
            content: '欢迎使用心记 - Web版',
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
      
      // 触发更新
      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }

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

      _database = await openDatabase(
        path,
        version: 7,
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
          // 创建引用（笔记）表，新增 category_id、source、source_author、source_work 和 color_hex 字段
          await db.execute('''
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
              color_hex TEXT
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // 如果数据库版本低于 2，添加 tag_ids 字段（以前可能不存在，但在本版本中创建表时已包含）
          if (oldVersion < 2) {
            await db.execute(
                'ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ""');
          }
          // 如果数据库版本低于 3，添加 categories 表中的 icon_name 字段（在本版本中创建表时已包含）
          if (oldVersion < 3) {
            await db.execute(
                'ALTER TABLE categories ADD COLUMN icon_name TEXT');
          }
          // 如果数据库版本低于 4，添加 quotes 表中的 category_id 字段
          if (oldVersion < 4) {
            await db.execute(
                'ALTER TABLE quotes ADD COLUMN category_id TEXT DEFAULT ""');
          }
          
          // 如果数据库版本低于 5，添加 quotes 表中的 source 字段
          if (oldVersion < 5) {
            await db.execute(
                'ALTER TABLE quotes ADD COLUMN source TEXT');
          }
          
          // 如果数据库版本低于 6，添加 quotes 表中的 color_hex 字段
          if (oldVersion < 6) {
            await db.execute(
                'ALTER TABLE quotes ADD COLUMN color_hex TEXT');
          }
          
          // 如果数据库版本低于 7，添加 quotes 表中的 source_author 和 source_work 字段
          if (oldVersion < 7) {
            await db.execute(
                'ALTER TABLE quotes ADD COLUMN source_author TEXT');
            await db.execute(
                'ALTER TABLE quotes ADD COLUMN source_work TEXT');
            
            // 将现有的 source 字段数据拆分到新字段中
            final quotes = await db.query('quotes', where: 'source IS NOT NULL AND source != ""');
            for (final quote in quotes) {
              final String? source = quote['source'] as String?;
              if (source != null && source.isNotEmpty) {
                String? author;
                String? work;
                
                // 尝试分析现有source格式，提取author和work
                if (source.contains('——') && source.contains('「')) {
                  // 格式为"作者——「作品」"
                  final parts = source.split('——');
                  if (parts.length > 1) {
                    author = parts[0].trim();
                    final workMatch = RegExp(r'「(.+?)」').firstMatch(parts[1]);
                    if (workMatch != null) {
                      work = workMatch.group(1);
                    }
                  }
                } else if (source.contains('——')) {
                  // 格式为"作者——作品"
                  final parts = source.split('——');
                  if (parts.length > 1) {
                    author = parts[0].trim();
                    work = parts[1].trim();
                  }
                }
                
                // 更新数据库条目
                await db.update(
                  'quotes',
                  {
                    'source_author': author,
                    'source_work': work,
                  },
                  where: 'id = ?',
                  whereArgs: [quote['id']],
                );
              }
            }
          }
        },
      );
      // 更新分类流数据
      await _updateCategoriesStream();
    } catch (e) {
      debugPrint('数据库初始化错误: $e');
      rethrow;
    }
  }

  /// 导出全部数据到 JSON 格式
  Future<String> exportAllData() async {
    try {
      final db = database;
      
      // 查询所有数据并转换为 JSON 友好的格式
      final categories = await db.query('categories');
      final quotes = await db.query('quotes');
      
      final jsonData = {
        'metadata': {
          'app': '心记',
          'version': await db.getVersion(),
          'exportTime': DateTime.now().toIso8601String(),
        },
        'categories': categories.map((c) => {
          'id': c['id'],
          'name': c['name'],
          'isDefault': c['is_default'] == 1,
          'iconName': c['icon_name'],
        }).toList(),
        'quotes': quotes.map((q) => {
          'id': q['id'],
          'content': q['content'],
          'date': q['date'],
          'source': q['source'],
          'sourceAuthor': q['source_author'],
          'sourceWork': q['source_work'],
          'tagIds': q['tag_ids'],
          'aiAnalysis': q['ai_analysis'],
          'sentiment': q['sentiment'],
          'keywords': q['keywords'],
          'summary': q['summary'],
          'categoryId': q['category_id'],
          'colorHex': q['color_hex'],
        }).toList(),
      };
      
      // 转换为格式化的 JSON 字符串
      final jsonStr = JsonEncoder.withIndent('  ').convert(jsonData);
      final dir = await getApplicationDocumentsDirectory();
      final fileName = '心记_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonStr);
      return file.path;
    } catch (e) {
      debugPrint('数据导出失败: $e');
      rethrow;
    }
  }

  /// 从 JSON 文件导入数据
  Future<void> importData(String filePath) async {
    try {
      final db = database;
      final file = File(filePath);
      final jsonStr = await file.readAsString();
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      
      // 验证数据格式
      if (!data.containsKey('metadata') || !data.containsKey('categories') || !data.containsKey('quotes')) {
        throw Exception('无效的备份文件格式');
      }
      
      // 开始事务
      await db.transaction((txn) async {
        // 清空现有数据
        await txn.delete('categories');
        await txn.delete('quotes');
        
        // 恢复分类数据
        final categories = data['categories'] as List;
        for (final c in categories) {
          await txn.insert('categories', {
            'id': c['id'],
            'name': c['name'],
            'is_default': c['isDefault'] ? 1 : 0,
            'icon_name': c['iconName'],
          });
        }
        
        // 恢复笔记数据
        final quotes = data['quotes'] as List;
        for (final q in quotes) {
          await txn.insert('quotes', {
            'id': q['id'],
            'content': q['content'],
            'date': q['date'],
            'source': q['source'],
            'source_author': q['sourceAuthor'],
            'source_work': q['sourceWork'],
            'tag_ids': q['tagIds'],
            'ai_analysis': q['aiAnalysis'],
            'sentiment': q['sentiment'],
            'keywords': q['keywords'],
            'summary': q['summary'],
            'category_id': q['categoryId'],
            'color_hex': q['colorHex'],
          });
        }
      });
      
      await _updateCategoriesStream();
      notifyListeners();
    } catch (e) {
      debugPrint('数据导入失败: $e');
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
      'icon_name': iconName ?? ""
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
    final db = database;
    // 如果笔记中不包含 categoryId, 则设为空字符串
    final id = quote.id ?? _uuid.v4();
    final quoteMap = quote.toMap();
    quoteMap['id'] = id;
    if (!quoteMap.containsKey('category_id')) {
      quoteMap['category_id'] = "";
    }
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
          // Web平台特定逻辑
          if (tagIds != null && tagIds.isNotEmpty) {
            return _memoryStore.where((quote) => 
              tagIds.any((tagId) => quote.tagIds.contains(tagId))).toList();
          } else if (categoryId != null && categoryId.isNotEmpty) {
            return _memoryStore.where((quote) => 
              quote.categoryId == categoryId).toList();
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
      final db = database;
      final quoteMap = quote.toMap();
      await db.update(
        'quotes',
        quoteMap,
        where: 'id = ?',
        whereArgs: [quote.id],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      notifyListeners();
    }
}
