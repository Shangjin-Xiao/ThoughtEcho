import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
// 仅在 Windows 平台下使用 sqflite_common_ffi，其它平台直接使用 sqflite 默认实现
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    if (dart.library.io) 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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
  // 内存存储分类数据
  final List<NoteCategory> _categoryStore = [];

  // 新增：流式分页加载笔记
  final _quotesController = StreamController<List<Quote>>.broadcast();
  List<Quote> _quotesCache = [];
  List<String>? _watchTagIds;
  String? _watchCategoryId;
  String _watchOrderBy = 'date DESC';
  int _watchLimit = 20;
  int _watchOffset = 0;
  bool _watchHasMore = true;
  String? _watchSearchQuery;

  // 查询缓存，减少重复数据库查询
  final Map<String, List<Quote>> _filterCache = {};
  final int _maxCacheEntries = 10; // 最多缓存10组过滤条件的结果

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
      final oldPath = join(dbPath, 'mind_trace.db');
      final path = join(dbPath, 'thoughtecho.db');

      // 自动迁移旧数据库文件
      final oldFile = File(oldPath);
      final newFile = File(path);
      if (!await newFile.exists() && await oldFile.exists()) {
        try {
          await oldFile.copy(path); // 用copy更安全，保留原文件
          debugPrint('已自动迁移旧数据库文件到新文件名');
        } catch (e) {
          debugPrint('自动迁移旧数据库文件失败: $e');
        }
      }

      _database = await openDatabase(
        path,
        version: 9, // 版本号增加，以支持添加索引
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
              color_hex TEXT,
              location TEXT, -- 从版本 8 开始添加
              weather TEXT, -- 从版本 8 开始添加
              temperature TEXT -- 从版本 8 开始添加
            )
          ''');

          // 创建索引以加速常用查询
          await db.execute(
            'CREATE INDEX idx_quotes_category_id ON quotes(category_id)',
          );
          await db.execute('CREATE INDEX idx_quotes_date ON quotes(date)');
          // 虽然tag_ids是一个文本字段，但我们也可以为它创建索引，以加速LIKE查询
          await db.execute(
            'CREATE INDEX idx_quotes_tag_ids ON quotes(tag_ids)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // 如果数据库版本低于 2，添加 tag_ids 字段（以前可能不存在，但在本版本中创建表时已包含）
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ""',
            );
          }
          // 如果数据库版本低于 3，添加 categories 表中的 icon_name 字段（在本版本中创建表时已包含）
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE categories ADD COLUMN icon_name TEXT',
            );
          }
          // 如果数据库版本低于 4，添加 quotes 表中的 category_id 字段
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE quotes ADD COLUMN category_id TEXT DEFAULT ""',
            );
          }

          // 如果数据库版本低于 5，添加 quotes 表中的 source 字段
          if (oldVersion < 5) {
            await db.execute('ALTER TABLE quotes ADD COLUMN source TEXT');
          }

          // 如果数据库版本低于 6，添加 quotes 表中的 color_hex 字段
          if (oldVersion < 6) {
            await db.execute('ALTER TABLE quotes ADD COLUMN color_hex TEXT');
          }

          // 如果数据库版本低于 7，添加 quotes 表中的 source_author 和 source_work 字段
          if (oldVersion < 7) {
            await db.execute(
              'ALTER TABLE quotes ADD COLUMN source_author TEXT',
            );
            await db.execute('ALTER TABLE quotes ADD COLUMN source_work TEXT');

            // 将现有的 source 字段数据拆分到新字段中
            final quotes = await db.query(
              'quotes',
              where: 'source IS NOT NULL AND source != ""',
            );
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
                  {'source_author': author, 'source_work': work},
                  where: 'id = ?',
                  whereArgs: [quote['id']],
                );
              }
            }
          }

          // 如果数据库版本低于 8，添加位置和天气相关字段
          if (oldVersion < 8) {
            debugPrint(
              '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 location, weather, temperature 字段',
            );
            await db.execute('ALTER TABLE quotes ADD COLUMN location TEXT');
            await db.execute('ALTER TABLE quotes ADD COLUMN weather TEXT');
            await db.execute('ALTER TABLE quotes ADD COLUMN temperature TEXT');
            debugPrint('数据库升级：location, weather, temperature 字段添加完成');
          }

          // 如果数据库版本低于 9，添加索引以提高查询性能
          if (oldVersion < 9) {
            debugPrint('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加索引');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_quotes_tag_ids ON quotes(tag_ids)',
            );
            debugPrint('数据库升级：索引添加完成');
          }
        },
      );

      // 检查并修复数据库结构
      await _checkAndFixDatabaseStructure();

      // 更新分类流数据
      await _updateCategoriesStream();

      // 修复: 初始化完成后，立即预加载笔记数据并触发监听器
      debugPrint('数据库初始化完成，开始预加载笔记数据...');
      // 重置流相关状态
      _watchOffset = 0;
      _quotesCache = [];
      _filterCache.clear();
      _watchHasMore = true;
      // 调用一次 _loadNextQuotesPage 来预加载数据
      await _prefetchInitialQuotes();
      // 通知监听器数据已更新
      notifyListeners();
    } catch (e) {
      debugPrint('数据库初始化错误: $e');
      rethrow;
    }
  }

  /// 在初始化时预加载笔记数据
  Future<void> _prefetchInitialQuotes() async {
    try {
      // 使用默认配置加载第一页数据，包括所有默认筛选条件
      final quotes = await getUserQuotes(
        limit: _watchLimit,
        offset: 0,
        orderBy: _watchOrderBy,
        // 确保预加载不带任何筛选条件的数据，使首页初始状态能命中缓存
        tagIds: null,
        categoryId: null,
        searchQuery: null,
      );

      if (quotes.isNotEmpty) {
        debugPrint('初始预加载了 ${quotes.length} 条笔记');

        // 确保使用完整的缓存键，与watchQuotes保持一致
        final cacheKey = _generateCacheKey(
          tagIds: null,
          categoryId: null,
          searchQuery: null,
          orderBy: _watchOrderBy,
        );

        _addToCache(cacheKey, quotes, 0);

        // 确保笔记流控制器有最新数据
        if (_quotesController.hasListener) {
          _quotesCache = quotes;
          _watchOffset = quotes.length;
          _watchHasMore = quotes.length == _watchLimit;
          _quotesController.add(List.unmodifiable(quotes));
        } else {
          // 即使没有监听器，也将数据添加到流中，确保第一次监听时能立即获取数据
          _quotesCache = quotes;
          _watchOffset = quotes.length;
          _watchHasMore = quotes.length == _watchLimit;
          _quotesController.add(List.unmodifiable(quotes));
        }
      } else {
        debugPrint('数据库中没有笔记数据');
        // 确保流控制器发出空列表而不是等待数据
        _quotesController.add([]);
      }
    } catch (e) {
      debugPrint('预加载笔记时出错: $e');
      // 即使出错也要发出空列表，避免UI一直等待
      _quotesController.add([]);
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
      final requiredColumns = {'location', 'weather', 'temperature'};
      final missingColumns = requiredColumns.difference(columnNames);

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
          await db.insert('categories', {
            'id': category.id,
            'name': category.name,
            'is_default': category.isDefault ? 1 : 0,
            'icon_name': category.iconName,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
          'app': '心迹',
          'version': await db.getVersion(),
          'exportTime': DateTime.now().toIso8601String(),
        },
        'categories':
            categories
                .map(
                  (c) => {
                    'id': c['id'],
                    'name': c['name'],
                    'isDefault': c['is_default'] == 1,
                    'iconName': c['icon_name'],
                  },
                )
                .toList(),
        'quotes':
            quotes
                .map(
                  (q) => {
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
                  },
                )
                .toList(),
      };

      // 转换为格式化的 JSON 字符串
      final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonData);

      String filePath;
      if (customPath != null) {
        // 使用自定义路径
        filePath = customPath;
      } else {
        // 使用默认路径
        final dir = await getApplicationDocumentsDirectory();
        final fileName = '心迹_${DateTime.now().millisecondsSinceEpoch}.json';
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

      // 验证数据格式 (与 validateBackupFile 保持一致)
      if (!data.containsKey('metadata') ||
          !data.containsKey('categories') ||
          !data.containsKey('quotes')) {
        throw Exception('备份文件格式无效，缺少必要的顶层数据结构 (metadata, categories, quotes)');
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
          final existingCategoryIds =
              existingCategories.map((c) => c['id'] as String).toSet();

          // 创建一个映射，用于检查分类名称重复
          final existingCategoryNames = {
            for (var c in existingCategories)
              (c['name'] as String).toLowerCase(): c['id'] as String,
          };

          final existingQuotes = await txn.query('quotes', columns: ['id']);
          final existingQuoteIds =
              existingQuotes.map((q) => q['id'] as String).toSet();

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

  /// 检查是否可以导出数据（检测数据库是否可访问）
  Future<bool> checkCanExport() async {
    try {
      // 尝试执行简单查询以验证数据库可访问
      if (_database == null) {
        debugPrint('数据库未初始化');
        return false;
      }

      // 修正：将'quote'改为正确的表名'quotes'
      await _database!.query('quotes', limit: 1);
      return true;
    } catch (e) {
      debugPrint('数据库访问检查失败: $e');
      return false;
    }
  }

  /// 验证备份文件是否有效
  Future<bool> validateBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在: $filePath');
      }

      final content = await file.readAsString();
      final data = json.decode(content);

      // 确保解码后是 Map 类型
      if (data is! Map<String, dynamic>) {
        throw Exception('备份文件顶层结构不是有效的 JSON 对象');
      }

      // --- 修改处 ---
      // 验证基本结构，应与 exportAllData 导出的结构一致
      final requiredKeys = {'metadata', 'categories', 'quotes'};
      if (!requiredKeys.every((key) => data.containsKey(key))) {
        // 提供更详细的错误信息，指出缺少哪些键
        final missingKeys = requiredKeys.difference(data.keys.toSet());
        throw Exception(
          '备份文件格式无效，缺少必要的顶层数据结构 (需要: metadata, categories, quotes; 缺少: ${missingKeys.join(', ')})',
        );
      }
      // --- 修改结束 ---

      // 可选：进一步验证内部结构，例如 metadata 是否包含 version
      if (data['metadata'] is! Map ||
          !(data['metadata'] as Map).containsKey('version')) {
        debugPrint('警告：备份文件元数据 (metadata) 格式不正确或缺少版本信息');
        // 可以选择是否在这里抛出异常，取决于是否强制要求版本信息
      }

      // 可选：检查 categories 和 quotes 是否为列表类型
      if (data['categories'] is! List) {
        throw Exception('备份文件中的 \'categories\' 必须是一个列表');
      }
      if (data['quotes'] is! List) {
        throw Exception('备份文件中的 \'quotes\' 必须是一个列表');
      }

      // 检查至少需要有quotes或categories (可选，空备份也可能有效)
      final quotes = data['quotes'] as List?;
      final categories = data['categories'] as List?;

      if ((quotes == null || quotes.isEmpty) &&
          (categories == null || categories.isEmpty)) {
        debugPrint('警告：备份文件不包含任何分类或笔记数据');
        // 空备份也是有效的，但可以记录警告
      }

      debugPrint('备份文件验证通过: $filePath');
      return true; // 如果所有检查都通过，返回 true
    } catch (e) {
      debugPrint('验证备份文件失败: $e');
      // 重新抛出更具体的错误信息给上层调用者
      // 保留原始异常类型，以便上层可以根据需要区分处理
      // 例如: throw FormatException('备份文件JSON格式错误');
      // 或: throw FileSystemException('无法读取备份文件', filePath);
      // 这里统一抛出 Exception，包含原始错误信息
      throw Exception('无法验证备份文件： $e');
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
      final exists = _categoryStore.any(
        (c) => c.name.toLowerCase() == name.toLowerCase(),
      );
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
      final quoteMap = quote.toJson(); // 将 toMap 改为 toJson
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
      _refreshQuotesStream(); // 更新流
    } catch (e) {
      debugPrint('保存笔记到数据库时出错: $e');
      rethrow; // 重新抛出异常，让调用者处理
    }
  }

  // 在增删改后刷新分页流数据
  void _refreshQuotesStream() {
    if (_quotesController.hasListener) {
      debugPrint('刷新笔记流数据');
      // 清除缓存，确保获取最新数据
      _filterCache.clear();

      // 重置状态并加载新数据
      _watchOffset = 0;
      _quotesCache = [];
      _watchHasMore = true;

      // 触发重新加载
      _loadNextQuotesPage();
    } else {
      debugPrint('笔记流无监听器，跳过刷新');
    }
  }

  /// 分页获取笔记，支持标签、分类和搜索
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    int limit = 20,
    int offset = 0,
    String orderBy = 'date DESC',
  }) async {
    try {
      if (kIsWeb) {
        // Web 平台内存过滤
        List<Quote> filtered = List.from(_memoryStore);
        if (tagIds != null && tagIds.isNotEmpty) {
          filtered =
              filtered
                  .where((q) => tagIds.any((id) => q.tagIds.contains(id)))
                  .toList();
        } else if (categoryId != null && categoryId.isNotEmpty) {
          filtered = filtered.where((q) => q.categoryId == categoryId).toList();
        }
        if (searchQuery != null && searchQuery.isNotEmpty) {
          filtered =
              filtered
                  .where(
                    (q) =>
                        q.content.toLowerCase().contains(
                          searchQuery.toLowerCase(),
                        ) ||
                        (q.source?.toLowerCase().contains(
                              searchQuery.toLowerCase(),
                            ) ??
                            false),
                  )
                  .toList();
        }
        filtered.sort((a, b) => b.date.compareTo(a.date));
        final start = offset < filtered.length ? offset : filtered.length;
        final end =
            (offset + limit) < filtered.length
                ? (offset + limit)
                : filtered.length;
        return filtered.sublist(start, end);
      }

      final db = database;
      List<String> conditions = [];
      List<dynamic> args = [];
      if (tagIds != null && tagIds.isNotEmpty) {
        conditions.add(tagIds.map((_) => 'tag_ids LIKE ?').join(' OR '));
        args.addAll(tagIds.map((id) => '%$id%'));
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        conditions.add('category_id = ?');
        args.add(categoryId);
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        conditions.add('(content LIKE ? OR source LIKE ?)');
        args.addAll(['%$searchQuery%', '%$searchQuery%']);
      }
      final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;
      final maps = await db.query(
        'quotes',
        where: where,
        whereArgs: args,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
      return maps
          .map((m) => Quote.fromJson(m))
          .toList(); // 将 fromMap 改为 fromJson
    } catch (e) {
      debugPrint('获取引用错误: $e');
      return [];
    }
  }

  /// 获取笔记总数，用于分页
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
  }) async {
    try {
      if (kIsWeb) {
        return (await getUserQuotes(
          tagIds: tagIds,
          categoryId: categoryId,
          searchQuery: searchQuery,
          limit: 1000000,
          offset: 0,
        )).length;
      }
      final db = database;
      List<String> conditions = [];
      List<dynamic> args = [];
      if (tagIds != null && tagIds.isNotEmpty) {
        conditions.add(tagIds.map((_) => 'tag_ids LIKE ?').join(' OR '));
        args.addAll(tagIds.map((id) => '%$id%'));
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        conditions.add('category_id = ?');
        args.add(categoryId);
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        conditions.add('(content LIKE ? OR source LIKE ?)');
        args.addAll(['%$searchQuery%', '%$searchQuery%']);
      }
      final whereClause =
          conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM quotes $whereClause',
        args,
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('获取笔记总数错误: $e');
      return 0;
    }
  }

  /// 删除指定的笔记
  Future<void> deleteQuote(String id) async {
    if (kIsWeb) {
      _memoryStore.removeWhere((quote) => quote.id == id);
      notifyListeners();
      _refreshQuotesStream();
      return;
    }
    final db = database;
    await db.delete('quotes', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
    _refreshQuotesStream();
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
      final quoteMap = quote.toJson(); // 将 toMap 改为 toJson

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
      _refreshQuotesStream(); // 更新流
    } catch (e) {
      debugPrint('更新笔记时出错: $e');
      rethrow; // 重新抛出异常，让调用者处理
    }
  }

  /// 监听笔记列表，支持分页加载和搜索
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
  }) {
    // 检查是否有筛选条件改变
    bool hasFilterChanged = false;

    // 检查标签是否变更
    if (_watchTagIds != null && tagIds != null) {
      if (_watchTagIds!.length != tagIds.length) {
        hasFilterChanged = true;
        debugPrint('标签数量变更: ${_watchTagIds!.length} -> ${tagIds.length}');
      } else {
        // 比较标签内容是否一致
        for (int i = 0; i < _watchTagIds!.length; i++) {
          if (!tagIds.contains(_watchTagIds![i])) {
            hasFilterChanged = true;
            debugPrint('标签内容变更');
            break;
          }
        }
      }
    } else if ((_watchTagIds == null) != (tagIds == null)) {
      hasFilterChanged = true;
      debugPrint(
        '标签筛选条件状态变更: ${_watchTagIds == null ? "无" : "有"} -> ${tagIds == null ? "无" : "有"}',
      );
    }

    // 检查分类是否变更
    if (_watchCategoryId != categoryId) {
      hasFilterChanged = true;
      debugPrint('分类变更: $_watchCategoryId -> $categoryId');
    }

    // 检查排序是否变更
    if (_watchOrderBy != orderBy) {
      hasFilterChanged = true;
      debugPrint('排序变更: $_watchOrderBy -> $orderBy');
    }

    // 检查搜索条件是否变更
    final normalizedSearchQuery =
        (searchQuery != null && searchQuery.isNotEmpty) ? searchQuery : null;
    if (_watchSearchQuery != normalizedSearchQuery) {
      hasFilterChanged = true;
      debugPrint('搜索条件变更: $_watchSearchQuery -> $normalizedSearchQuery');
    }

    // 更新筛选条件
    _watchTagIds = tagIds;
    _watchCategoryId = categoryId;
    _watchOrderBy = orderBy;
    _watchLimit = limit;
    _watchSearchQuery = normalizedSearchQuery;

    // 如果筛选条件变更，清空当前数据和缓存
    if (hasFilterChanged) {
      debugPrint('筛选条件已变更，清空缓存并重新加载数据');
      _watchOffset = 0;
      _watchHasMore = true;
      _quotesCache = [];

      // 清除相关的缓存条目
      final cacheKey = _generateCacheKey(
        tagIds: tagIds,
        categoryId: categoryId,
        searchQuery: searchQuery,
        orderBy: orderBy,
      );
      _filterCache.remove(cacheKey);

      // 立即通知监听器数据已清空，避免显示旧数据
      _quotesController.add([]);
    }

    // 首次加载
    _loadNextQuotesPage();
    return _quotesController.stream;
  }

  /// 公共接口：加载下一页笔记
  Future<void> loadMoreQuotes() async {
    if (!_watchHasMore) return;
    await _loadNextQuotesPage();
  }

  Future<void> _loadNextQuotesPage() async {
    // 如果已经没有更多数据，直接返回
    if (!_watchHasMore) return;

    // 生成当前查询条件的缓存键
    final cacheKey = _generateCacheKey(
      tagIds: _watchTagIds,
      categoryId: _watchCategoryId,
      searchQuery: _watchSearchQuery,
      orderBy: _watchOrderBy,
    );

    // 先尝试从缓存获取数据
    final cachedQuotes = _getFromCache(cacheKey, _watchOffset, _watchLimit);
    if (cachedQuotes != null) {
      debugPrint('从缓存加载 ${cachedQuotes.length} 条笔记 (偏移量: $_watchOffset)');
      _quotesCache.addAll(cachedQuotes);
      _watchOffset += cachedQuotes.length;
      _watchHasMore = cachedQuotes.length == _watchLimit;
      _quotesController.add(List.unmodifiable(_quotesCache));

      // 如果本次加载接近缓存末尾，提前加载下一页
      final cachedData = _filterCache[cacheKey];
      if (cachedData != null &&
          _watchOffset >= cachedData.length - _watchLimit / 2) {
        // 在后台预加载下一页数据
        _prefetchNextPage(cacheKey);
      }

      return;
    }

    // 缓存未命中，从数据库加载
    _loadFromDatabase(cacheKey);
  }

  // 从数据库加载数据
  Future<void> _loadFromDatabase(String cacheKey) async {
    try {
      debugPrint('从数据库加载笔记数据，搜索条件: ${_watchSearchQuery ?? "无"}');

      // 添加超时检测
      bool hasTimedOut = false;
      final timeoutFuture = Future.delayed(const Duration(seconds: 8), () {
        hasTimedOut = true;
        debugPrint('数据库查询超时，返回空结果');
        if (_quotesController.hasListener && _quotesCache.isEmpty) {
          _quotesController.add([]);
          _watchHasMore = false;
        }
        return <Quote>[];
      });

      // 实际数据库查询
      final queryFuture = getUserQuotes(
        tagIds: _watchTagIds,
        categoryId: _watchCategoryId,
        limit: _watchLimit,
        offset: _watchOffset,
        orderBy: _watchOrderBy,
        searchQuery: _watchSearchQuery,
      );

      // 使用Future.any等待最快完成的操作
      final newQuotes = await Future.any([queryFuture, timeoutFuture]);

      // 如果已经超时，不继续处理
      if (hasTimedOut) return;

      debugPrint('从数据库加载 ${newQuotes.length} 条笔记 (偏移量: $_watchOffset)');

      if (newQuotes.isNotEmpty) {
        _quotesCache.addAll(newQuotes);
        _watchOffset += newQuotes.length;
        _watchHasMore = newQuotes.length == _watchLimit;

        // 将新获取的数据添加到缓存中
        _addToCache(cacheKey, newQuotes, _watchOffset - newQuotes.length);

        // 如果加载了满页数据，触发预加载下一页
        if (newQuotes.length == _watchLimit) {
          // 延迟预加载，避免立即发起新请求
          Future.delayed(const Duration(milliseconds: 200), () {
            if (_quotesController.hasListener) {
              _prefetchNextPage(cacheKey);
            }
          });
        }
      } else {
        _watchHasMore = false;
      }

      // 通知监听器
      _quotesController.add(List.unmodifiable(_quotesCache));
    } catch (e) {
      debugPrint('加载笔记时出错: $e');
      // 出错时也需要通知，避免UI一直显示加载状态
      _quotesController.add(List.unmodifiable(_quotesCache));
    }
  }

  // 预加载下一页数据
  Future<void> _prefetchNextPage(String cacheKey) async {
    try {
      // 检查是否已经加载了所有数据
      if (!_watchHasMore) return;

      // 计算下一页的偏移量
      final nextPageOffset = _watchOffset;

      // 避免重复预加载：检查缓存中是否已经有了下一页数据
      final cachedData = _filterCache[cacheKey];
      if (cachedData != null && cachedData.length > nextPageOffset) {
        // 缓存中已有下一页数据，无需预加载
        return;
      }

      debugPrint('预加载下一页数据，偏移量: $nextPageOffset');

      // 预加载下一页数据
      final prefetchedQuotes = await getUserQuotes(
        tagIds: _watchTagIds,
        categoryId: _watchCategoryId,
        limit: _watchLimit,
        offset: nextPageOffset,
        orderBy: _watchOrderBy,
        searchQuery: _watchSearchQuery,
      );

      // 将预加载的数据添加到缓存，但不更新当前显示
      if (prefetchedQuotes.isNotEmpty) {
        _addToCache(cacheKey, prefetchedQuotes, nextPageOffset);
      }
    } catch (e) {
      debugPrint('预加载笔记时出错: $e');
      // 预加载错误可以被忽略，不影响主UI流
    }
  }

  // 生成缓存键，将过滤条件组合成唯一标识
  String _generateCacheKey({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    String orderBy = 'date DESC',
  }) {
    final tagKey = tagIds?.join(',') ?? '';
    final categoryKey = categoryId ?? '';
    final searchKey = searchQuery ?? '';
    return '$tagKey|$categoryKey|$searchKey|$orderBy';
  }

  // 从缓存中获取数据，如果有的话
  List<Quote>? _getFromCache(String cacheKey, int offset, int limit) {
    final cachedData = _filterCache[cacheKey];
    if (cachedData == null) return null;

    // 检查是否缓存了足够的数据
    if (cachedData.length > offset) {
      final end =
          (offset + limit) <= cachedData.length
              ? (offset + limit)
              : cachedData.length;
      return cachedData.sublist(offset, end);
    }

    return null;
  }

  // 向缓存添加数据
  void _addToCache(String cacheKey, List<Quote> quotes, int offset) {
    if (!_filterCache.containsKey(cacheKey)) {
      // 如果缓存已满，移除最旧的条目
      if (_filterCache.length >= _maxCacheEntries) {
        final oldestKey = _filterCache.keys.first;
        _filterCache.remove(oldestKey);
      }
      _filterCache[cacheKey] = [];
    }

    // 如果是第一页，则清空缓存
    if (offset == 0) {
      _filterCache[cacheKey] = List.from(quotes);
    } else {
      // 否则追加到现有缓存
      _filterCache[cacheKey]!.addAll(quotes);
    }
  }
}
