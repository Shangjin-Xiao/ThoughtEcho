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
    
    debugPrint('初始化数据库...');

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
        version: 8,
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
          
          // 如果数据库版本低于 8，添加位置和天气相关字段
          if (oldVersion < 8) {
            debugPrint('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 location, weather, temperature 字段');
            await db.execute('ALTER TABLE quotes ADD COLUMN location TEXT');
            await db.execute('ALTER TABLE quotes ADD COLUMN weather TEXT');
            await db.execute('ALTER TABLE quotes ADD COLUMN temperature TEXT');
            debugPrint('数据库升级：location, weather, temperature 字段添加完成');
          } else {
            debugPrint('数据库版本 $oldVersion >= 8，无需添加 location, weather, temperature 字段');
          }
        },
      );
      
      // 检查并修复数据库结构
      await _checkAndFixDatabaseStructure();
      
      // 更新分类流数据
      await _updateCategoriesStream();
    } catch (e) {
      debugPrint('数据库初始化错误: $e');
      rethrow;
    }
  }
  
  /// 检查并修复数据库结构，确保所有必要的列都存在
  Future<void> _checkAndFixDatabaseStructure() async {
    try {
      final db = database;
      
      // 获取quotes表的列信息
      final tableInfo = await db.rawQuery("PRAGMA table_info(quotes)");
      final columnNames = tableInfo.map((col) => col['name'] as String).toSet();
      
      debugPrint('当前quotes表列: $columnNames');
      
      // 检查是否缺少location、weather、temperature列
      final missingColumns = <String>[];
      if (!columnNames.contains('location')) missingColumns.add('location');
      if (!columnNames.contains('weather')) missingColumns.add('weather');
      if (!columnNames.contains('temperature')) missingColumns.add('temperature');
      
      if (missingColumns.isNotEmpty) {
        debugPrint('检测到缺少列: $missingColumns，正在添加...');
        
        // 添加缺少的列
        for (final column in missingColumns) {
          try {
            await db.execute('ALTER TABLE quotes ADD COLUMN $column TEXT');
            debugPrint('成功添加列: $column');
          } catch (e) {
            debugPrint('添加列 $column 时出错: $e');
          }
        }
      } else {
        debugPrint('数据库结构完整，无需修复');
      }
    } catch (e) {
      debugPrint('检查数据库结构时出错: $e');
    }
  }

  /// 初始化默认一言分类标签
  Future<void> initDefaultHitokotoCategories() async {
    if (kIsWeb) {
      // 为Web平台添加默认一言分类
      final defaultCategories = _getDefaultHitokotoCategories();
      for (final category in defaultCategories) {
        final exists = _categoryStore.any((c) => c.name == category.name);
        if (!exists) {
          _categoryStore.add(category);
        }
      }
      _categoriesController.add(_categoryStore);
      return;
    }

    try {
      final db = database;
      final defaultCategories = _getDefaultHitokotoCategories();
      
      // 检查每个默认分类是否已存在
      for (final category in defaultCategories) {
        final existing = await db.query(
          'categories',
          where: 'name = ?',
          whereArgs: [category.name],
        );
        
        // 如果不存在，则添加
        if (existing.isEmpty) {
          await db.insert(
            'categories',
            {
              'id': category.id,
              'name': category.name,
              'is_default': category.isDefault ? 1 : 0,
              'icon_name': category.iconName,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          debugPrint('添加默认一言分类: ${category.name}');
        }
      }
      
      // 更新分类流
      await _updateCategoriesStream();
    } catch (e) {
      debugPrint('初始化默认一言分类出错: $e');
    }
  }
  
  /// 获取默认一言分类列表
  List<NoteCategory> _getDefaultHitokotoCategories() {
    return [
      NoteCategory(
        id: _uuid.v4(),
        name: '每日一言',
        isDefault: true,
        iconName: 'format_quote',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '动画',
        isDefault: true,
        iconName: 'movie',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '漫画',
        isDefault: true,
        iconName: 'menu_book',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '游戏',
        isDefault: true,
        iconName: 'sports_esports',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '文学',
        isDefault: true,
        iconName: 'auto_stories',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '原创',
        isDefault: true,
        iconName: 'create',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '来自网络',
        isDefault: true,
        iconName: 'public',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '其他',
        isDefault: true,
        iconName: 'category',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '影视',
        isDefault: true,
        iconName: 'theaters',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '诗词',
        isDefault: true,
        iconName: 'brush', // 修改为毛笔图标，更符合诗词主题
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '网易云',
        isDefault: true,
        iconName: 'music_note',
      ),
      NoteCategory(
        id: _uuid.v4(),
        name: '哲学',
        isDefault: true,
        iconName: 'psychology',
      ),
    ];
  }

  /// 导出全部数据到 JSON 格式
  ///
  /// [customPath] - 可选的自定义保存路径。如果提供，将保存到指定路径；否则保存到应用文档目录
  /// 返回保存的文件路径
  Future<String> exportAllData({String? customPath}) async {
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
          'location': q['location'],
          'weather': q['weather'],
          'temperature': q['temperature'],
        }).toList(),
      };
      
      // 转换为格式化的 JSON 字符串
      final jsonStr = JsonEncoder.withIndent('  ').convert(jsonData);
      
      String filePath;
      if (customPath != null) {
        // 使用自定义路径
        filePath = customPath;
      } else {
        // 使用默认路径
        final dir = await getApplicationDocumentsDirectory();
        final fileName = '心记_${DateTime.now().millisecondsSinceEpoch}.json';
        filePath = '${dir.path}/$fileName';
      }
      
      final file = File(filePath);
      await file.writeAsString(jsonStr);
      return file.path;
    } catch (e) {
      debugPrint('数据导出失败: $e');
      rethrow;
    }
  }

  /// 从 JSON 文件导入数据
  ///
  /// [filePath] - 导入文件的路径
  /// [clearExisting] - 是否清空现有数据，默认为 true
  Future<void> importData(String filePath, {bool clearExisting = true}) async {
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
        // 如果选择清空现有数据
        if (clearExisting) {
          debugPrint('清空现有数据并导入新数据');
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
              'location': q['location'],
              'weather': q['weather'],
              'temperature': q['temperature'],
            });
          }
        } else {
          debugPrint('合并数据');
          
          // 获取现有分类和笔记的ID列表，用于检查是否存在
          final existingCategories = await txn.query('categories');
          final existingCategoryIds = existingCategories.map((c) => c['id'] as String).toSet();
          
          // 创建一个映射，用于检查分类名称重复
          final existingCategoryNames = {
            for (var c in existingCategories) 
              (c['name'] as String).toLowerCase(): c['id'] as String
          };
          
          final existingQuotes = await txn.query('quotes', columns: ['id']);
          final existingQuoteIds = existingQuotes.map((q) => q['id'] as String).toSet();
          
          // 合并分类数据
          final categories = data['categories'] as List;
          for (final c in categories) {
            final categoryId = c['id'] as String;
            final categoryName = (c['name'] as String).toLowerCase();
            
            // 检查是否已存在同名分类
            if (existingCategoryNames.containsKey(categoryName)) {
              // 如果存在同名分类，使用现有的ID
              final existingId = existingCategoryNames[categoryName];
              debugPrint('发现同名分类: $categoryName，使用现有ID: $existingId');
              
              // 更新引用新导入分类的笔记，让它们引用现有的同名分类
              final quotes = data['quotes'] as List;
              for (final q in quotes) {
                if (q['categoryId'] == categoryId) {
                  q['categoryId'] = existingId;
                }
              }
              
              // 跳过此分类的导入
              continue;
            }
            
            final categoryData = {
              'id': categoryId,
              'name': c['name'],
              'is_default': c['isDefault'] ? 1 : 0,
              'icon_name': c['iconName'],
            };
            
            if (existingCategoryIds.contains(categoryId)) {
              // 更新现有分类
              await txn.update(
                'categories',
                categoryData,
                where: 'id = ?',
                whereArgs: [categoryId],
              );
            } else {
              // 插入新分类
              await txn.insert('categories', categoryData);
              // 更新映射以包含新添加的分类
              existingCategoryNames[categoryName] = categoryId;
              existingCategoryIds.add(categoryId);
            }
          }
          
          // 合并笔记数据
          final quotes = data['quotes'] as List;
          for (final q in quotes) {
            final quoteId = q['id'] as String;
            final quoteData = {
              'id': quoteId,
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
              'location': q['location'],
              'weather': q['weather'],
              'temperature': q['temperature'],
            };
            
            if (existingQuoteIds.contains(quoteId)) {
              // 更新现有笔记
              await txn.update(
                'quotes',
                quoteData,
                where: 'id = ?',
                whereArgs: [quoteId],
              );
            } else {
              // 插入新笔记
              await txn.insert('quotes', quoteData);
            }
          }
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
    // 检查参数
    if (name.trim().isEmpty) {
      throw Exception('分类名称不能为空');
    }
    
    if (kIsWeb) {
      // 检查是否已存在同名分类
      final exists = _categoryStore.any((c) => c.name.toLowerCase() == name.toLowerCase());
      if (exists) {
        throw Exception('已存在相同名称的分类');
      }
      
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
    
    // 检查是否已存在同名分类
    final existing = await db.query(
      'categories',
      where: 'LOWER(name) = ?',
      whereArgs: [name.toLowerCase()],
    );
    
    if (existing.isNotEmpty) {
      throw Exception('已存在相同名称的分类');
    }
    
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
}
