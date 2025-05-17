// ignore_for_file: unused_element, unused_field
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
import '../services/weather_service.dart';
import '../utils/time_utils.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _database;
  final _categoriesController =
      StreamController<List<NoteCategory>>.broadcast();
  final _uuid = const Uuid();
  // 内存存储，用于 Web 平台或调试存储，与原有业务流程保持一致
  final List<Quote> _memoryStore = [];
  // 内存存储分类数据
  final List<NoteCategory> _categoryStore = [];

  // 定义默认一言分类的固定 ID
  static const String defaultCategoryIdHitokoto = 'default_hitokoto';
  static const String defaultCategoryIdAnime = 'default_anime';
  static const String defaultCategoryIdComic = 'default_comic';
  static const String defaultCategoryIdGame = 'default_game';
  static const String defaultCategoryIdNovel = 'default_novel';
  static const String defaultCategoryIdOriginal = 'default_original';
  static const String defaultCategoryIdInternet = 'default_internet';
  static const String defaultCategoryIdOther = 'default_other';
  static const String defaultCategoryIdMovie = 'default_movie';
  static const String defaultCategoryIdPoem = 'default_poem';
  static const String defaultCategoryIdMusic = 'default_music';
  static const String defaultCategoryIdPhilosophy = 'default_philosophy';
  static const String defaultCategoryIdJoke = 'default_joke';

  // 新增：流式分页加载笔记
  StreamController<List<Quote>>? _quotesController;
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

  // 添加存储天气筛选条件的变量
  List<String>? _watchSelectedWeathers;

  // 添加存储时间段筛选条件的变量
  List<String>? _watchSelectedDayPeriods;

  // 添加初始化状态标志
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

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
      _isInitialized = true; // 标记为已初始化
      notifyListeners();
      return;
    }

    if (_database != null) {
      _isInitialized = true; // 如果数据库已经存在，标记为已初始化
      return;
    }

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

      // 数据库初始化核心逻辑
      _database = await _initDatabase(path);

      // 检查并修复数据库结构
      await _checkAndFixDatabaseStructure();

      // 初始化默认分类/标签
      await initDefaultHitokotoCategories();
      debugPrint('默认分类初始化检查完成');

      // 更新分类流数据
      await _updateCategoriesStream();
      // 初始化完成后，预加载笔记数据
      debugPrint('数据库初始化完成，开始预加载笔记数据...');
      // 重置流相关状态
      _watchOffset = 0;
      _quotesCache = [];
      _filterCache.clear();
      _watchHasMore = true;
      // 预加载数据
      await _prefetchInitialQuotes();

      _isInitialized = true; // 数据库初始化完成
      notifyListeners();
    } catch (e) {
      debugPrint('数据库初始化失败: $e');
      rethrow;
    }
  }

  // 抽取数据库初始化逻辑到单独方法，便于复用
  Future<Database> _initDatabase(String path) async {
    return await openDatabase(
      path,
      version: 11, // 版本号升级至11，以支持添加edit_source和delta_content字段
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
        // 创建引用（笔记）表，新增 category_id、source、source_author、source_work、color_hex、edit_source、delta_content 字段
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
            location TEXT,
            weather TEXT,
            temperature TEXT,
            edit_source TEXT,
            delta_content TEXT
          )
        ''');

        // 创建索引以加速常用查询
        await db.execute(
          'CREATE INDEX idx_quotes_category_id ON quotes(category_id)',
        );
        await db.execute('CREATE INDEX idx_quotes_date ON quotes(date)');
        // 虽然tag_ids是一个文本字段，但我们也可以为它创建索引，以加速LIKE查询
        await db.execute('CREATE INDEX idx_quotes_tag_ids ON quotes(tag_ids)');
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
          await db.execute('ALTER TABLE categories ADD COLUMN icon_name TEXT');
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
          await db.execute('ALTER TABLE quotes ADD COLUMN source_author TEXT');
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

        // 如果数据库版本低于 10，添加 edit_source 字段用于记录编辑来源
        if (oldVersion < 10) {
          debugPrint(
            '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 edit_source 字段',
          );
          await db.execute('ALTER TABLE quotes ADD COLUMN edit_source TEXT');
          debugPrint('数据库升级：edit_source 字段添加完成');
        }
        // 如果数据库版本低于 11，添加 delta_content 字段用于存储富文本Delta JSON
        if (oldVersion < 11) {
          debugPrint(
            '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 delta_content 字段',
          );
          await db.execute('ALTER TABLE quotes ADD COLUMN delta_content TEXT');
          debugPrint('数据库升级：delta_content 字段添加完成');
        }
      },
    );
  }

  // 新增初始化新数据库方法，用于在迁移失败时创建新的数据库
  Future<void> initializeNewDatabase() async {
    if (_isInitialized) return;

    try {
      // 确保数据库目录存在
      if (Platform.isWindows) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'thoughtecho.db');

      // 如果文件已存在但可能损坏，先备份再删除
      final file = File(path);
      if (await file.exists()) {
        try {
          final backupPath = join(
            dbPath,
            'thoughtecho_backup_${DateTime.now().millisecondsSinceEpoch}.db',
          );
          await file.copy(backupPath);
          debugPrint('已将可能损坏的数据库备份到 $backupPath');
          await file.delete();
          debugPrint('已删除可能损坏的数据库文件');
        } catch (e) {
          debugPrint('备份或删除损坏数据库失败: $e');
        }
      }

      // 初始化新数据库
      _database = await _initDatabase(path);

      // 创建默认分类
      await initDefaultHitokotoCategories();

      _isInitialized = true;
      notifyListeners();
      debugPrint('成功初始化新数据库');
    } catch (e) {
      debugPrint('初始化新数据库失败: $e');
      rethrow;
    }
  }

  /// 在初始化时预加载笔记数据
  Future<void> _prefetchInitialQuotes() async {
    try {
      // 将当前查询状态重置为默认值
      _currentQuotes = [];
      _watchHasMore = true;
      _isLoading = false;

      // 使用loadMoreQuotes加载第一页数据
      await loadMoreQuotes(tagIds: null, categoryId: null, searchQuery: null);

      // 通知初始化完成
      if (_currentQuotes.isEmpty) {
        debugPrint('数据库中没有笔记数据');
        // 确保流控制器发出空列表而不是等待数据
        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add([]);
        }
      }
    } catch (e) {
      debugPrint('预加载笔记时出错: $e');
      // 即使出错也要发出空列表，避免UI一直等待
      if (_quotesController != null && !_quotesController!.isClosed) {
        _quotesController!.add([]);
      }
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

      // 检查是否缺少必要的字段
      final requiredColumns = {
        'location',
        'weather',
        'temperature',
        'edit_source',
        'delta_content',
        'day_period', // 添加时间段字段
      };
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
      // Web 平台逻辑：检查内存中的 _categoryStore
      final defaultCategories = _getDefaultHitokotoCategories();
      final existingNamesLower =
          _categoryStore.map((c) => c.name.toLowerCase()).toSet();
      for (final category in defaultCategories) {
        if (!existingNamesLower.contains(category.name.toLowerCase())) {
          _categoryStore.add(category);
        }
      }
      // 确保流更新
      if (!_categoriesController.isClosed) {
        _categoriesController.add(List.unmodifiable(_categoryStore));
      }
      return;
    }

    try {
      // 首先确保数据库已初始化
      if (_database == null) {
        debugPrint('数据库尚未初始化，尝试先进行初始化');
        try {
          await init();
        } catch (e) {
          debugPrint('数据库初始化失败，但仍将尝试创建默认标签: $e');
        }
      }

      // 即使init()失败，也尝试获取数据库，如果還是null則提前返回
      if (_database == null) {
        debugPrint('数据库仍为null，无法创建默认标签');
        return;
      }

      final db = database;
      final defaultCategories = _getDefaultHitokotoCategories();

      // 1. 一次性查询所有现有分类名称（小写）
      final existingCategories = await db.query(
        'categories',
        columns: ['name', 'id'],
      );
      final existingNamesLower =
          existingCategories
              .map((row) => (row['name'] as String?)?.toLowerCase())
              .where((name) => name != null)
              .toSet();

      // 同时创建ID到名称的映射，用于检查默认ID是否已被其它名称使用
      final existingIdToName = {
        for (var row in existingCategories)
          row['id'] as String: row['name'] as String,
      };

      // 2. 筛选出数据库中尚不存在的默认分类
      final categoriesToAdd =
          defaultCategories
              .where(
                (category) =>
                    !existingNamesLower.contains(category.name.toLowerCase()),
              )
              .toList();

      // 3. 检查默认ID是否已被其他名称使用，如果是，需要更新名称
      final idsToUpdate = <String, String>{};
      for (final category in defaultCategories) {
        if (existingIdToName.containsKey(category.id) &&
            existingIdToName[category.id]!.toLowerCase() !=
                category.name.toLowerCase()) {
          // 已存在此ID但名称不同，需要更新
          idsToUpdate[category.id] = category.name;
        }
      }

      // 4. 如果有需要添加的分类，则使用批处理插入
      final batch = db.batch();

      // 先处理更新
      for (final entry in idsToUpdate.entries) {
        batch.update(
          'categories',
          {'name': entry.value, 'is_default': 1},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        debugPrint('更新ID为${entry.key}的分类名称为: ${entry.value}');
      }

      // 再处理新增
      for (final category in categoriesToAdd) {
        // 跳过ID已经存在但名称不同的情况（已在上面处理）
        if (idsToUpdate.containsKey(category.id)) {
          continue;
        }
        batch.insert('categories', {
          'id': category.id,
          'name': category.name,
          'is_default': category.isDefault ? 1 : 0,
          'icon_name': category.iconName,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        debugPrint('添加默认一言分类: ${category.name}');
      }

      // 提交批处理
      if (categoriesToAdd.isNotEmpty || idsToUpdate.isNotEmpty) {
        await batch.commit(noResult: true);
        debugPrint(
          '批量处理了 ${categoriesToAdd.length} 个新分类和 ${idsToUpdate.length} 个更新',
        );
      } else {
        debugPrint('所有默认分类已存在，无需添加');
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
        id: defaultCategoryIdHitokoto, // 使用固定 ID
        name: '每日一言',
        isDefault: true,
        iconName: 'format_quote',
      ),
      NoteCategory(
        id: defaultCategoryIdAnime, // 使用固定 ID
        name: '动画',
        isDefault: true,
        iconName: 'movie',
      ),
      NoteCategory(
        id: defaultCategoryIdComic, // 使用固定 ID
        name: '漫画',
        isDefault: true,
        iconName: 'menu_book',
      ),
      NoteCategory(
        id: defaultCategoryIdGame, // 使用固定 ID
        name: '游戏',
        isDefault: true,
        iconName: 'sports_esports',
      ),
      NoteCategory(
        id: defaultCategoryIdNovel, // 使用固定 ID
        name: '文学',
        isDefault: true,
        iconName: 'auto_stories',
      ),
      NoteCategory(
        id: defaultCategoryIdOriginal, // 使用固定 ID
        name: '原创',
        isDefault: true,
        iconName: 'create',
      ),
      NoteCategory(
        id: defaultCategoryIdInternet, // 使用固定 ID
        name: '来自网络',
        isDefault: true,
        iconName: 'public',
      ),
      NoteCategory(
        id: defaultCategoryIdOther, // 使用固定 ID
        name: '其他',
        isDefault: true,
        iconName: 'category',
      ),
      NoteCategory(
        id: defaultCategoryIdMovie, // 使用固定 ID
        name: '影视',
        isDefault: true,
        iconName: 'theaters',
      ),
      NoteCategory(
        id: defaultCategoryIdPoem, // 使用固定 ID
        name: '诗词',
        isDefault: true,
        iconName: 'brush',
      ),
      NoteCategory(
        id: defaultCategoryIdMusic, // 使用固定 ID
        name: '网易云',
        isDefault: true,
        iconName: 'music_note',
      ),
      NoteCategory(
        id: defaultCategoryIdPhilosophy, // 使用固定 ID
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
              'summary': q['summary'],              'category_id': q['categoryId'],
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

      // 导入后自动补全字段
      await patchQuotesDayPeriod();
      await migrateWeatherToKey();
      await migrateDayPeriodToKey();
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

  /// 添加一条分类（使用指定ID）
  Future<void> addCategoryWithId(
    String id,
    String name, {
    String? iconName,
  }) async {
    // 检查参数
    if (name.trim().isEmpty) {
      throw Exception('分类名称不能为空');
    }
    if (id.trim().isEmpty) {
      throw Exception('分类ID不能为空');
    }

    if (kIsWeb) {
      // 检查是否已存在同名分类
      final exists = _categoryStore.any(
        (c) => c.name.toLowerCase() == name.toLowerCase(),
      );
      if (exists) {
        debugPrint('Web平台: 已存在相同名称的分类 "$name"，但将继续使用');
      }

      // 检查ID是否已被占用
      final idExists = _categoryStore.any((c) => c.id == id);
      if (idExists) {
        // 如果ID已存在，不报错，静默更新此分类
        final index = _categoryStore.indexWhere((c) => c.id == id);
        if (index != -1) {
          _categoryStore[index] = NoteCategory(
            id: id,
            name: name,
            isDefault: _categoryStore[index].isDefault,
            iconName: iconName ?? _categoryStore[index].iconName,
          );
        }
      } else {
        // 创建新分类
        final newCategory = NoteCategory(
          id: id,
          name: name,
          isDefault: false,
          iconName: iconName ?? "",
        );
        _categoryStore.add(newCategory);
      }

      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }

    // 确保数据库已初始化
    if (_database == null) {
      try {
        await init();
      } catch (e) {
        debugPrint('添加分类前初始化数据库失败: $e');
        throw Exception('数据库未初始化，无法添加分类');
      }
    }

    final db = database;

    try {
      // 使用事务确保操作的原子性
      await db.transaction((txn) async {
        // 检查是否已存在同名分类
        final existing = await txn.query(
          'categories',
          where: 'LOWER(name) = ?',
          whereArgs: [name.toLowerCase()],
        );

        if (existing.isNotEmpty) {
          // 如果存在同名分类但ID不同，记录警告但继续
          final existingId = existing.first['id'] as String;
          if (existingId != id) {
            debugPrint('警告: 已存在相同名称的分类 "$name"，但将继续使用指定ID创建');
          }
        }

        // 检查ID是否已被占用
        final existingById = await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: [id],
        );

        if (existingById.isNotEmpty) {
          // 如果ID已存在，更新此分类
          final categoryMap = {'name': name, 'icon_name': iconName ?? ""};
          await txn.update(
            'categories',
            categoryMap,
            where: 'id = ?',
            whereArgs: [id],
          );
          debugPrint('更新ID为 $id 的现有分类为 "$name"');
        } else {
          // 创建新分类，使用指定的ID
          final categoryMap = {
            'id': id,
            'name': name,
            'is_default': 0,
            'icon_name': iconName ?? "",
          };
          await txn.insert(
            'categories',
            categoryMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          debugPrint('使用ID $id 创建新分类 "$name"');
        }
      });

      // 操作成功后更新流和通知侦听器
      await _updateCategoriesStream();
      notifyListeners();
    } catch (e) {
      debugPrint('添加指定ID分类失败: $e');
      // 重试一次作为回退方案
      try {
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
        debugPrint('通过回退方式成功添加分类');
      } catch (retryError) {
        debugPrint('重试添加分类也失败: $retryError');
        throw Exception('无法添加分类: $e');
      }
    }
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

      // 自动补全 day_period 字段
      if (quoteMap['date'] != null) {
        final dt = DateTime.tryParse(quoteMap['date']);
        if (dt != null) {
          final hour = dt.hour;
          String dayPeriodKey;
          if (hour >= 5 && hour < 8) {
            dayPeriodKey = 'dawn';
          } else if (hour >= 8 && hour < 12) {
            dayPeriodKey = 'morning';
          } else if (hour >= 12 && hour < 17) {
            dayPeriodKey = 'afternoon';
          } else if (hour >= 17 && hour < 20) {
            dayPeriodKey = 'dusk';
          } else if (hour >= 20 && hour < 23) {
            dayPeriodKey = 'evening';
          } else {
            dayPeriodKey = 'midnight';
          }
          quoteMap['day_period'] = dayPeriodKey;
        }
      }

      // 确保所有必需的字段都存在
      if (!quoteMap.containsKey('content') || quoteMap['content'] == null) {
        throw Exception('笔记内容不能为空');
      }

      if (!quoteMap.containsKey('date') || quoteMap['date'] == null) {
        quoteMap['date'] = DateTime.now().toIso8601String();
      }

      // 检查数据库中是否存在location、weather、temperature、edit_source、delta_content列
      final tableInfo = await db.rawQuery("PRAGMA table_info(quotes)");
      final columnNames = tableInfo.map((col) => col['name'] as String).toSet();

      // 如果列不存在，从Map中移除相应的键，避免SQL错误
      if (!columnNames.contains('location')) quoteMap.remove('location');
      if (!columnNames.contains('weather')) quoteMap.remove('weather');
      if (!columnNames.contains('temperature')) quoteMap.remove('temperature');
      if (!columnNames.contains('edit_source')) quoteMap.remove('edit_source');
      if (!columnNames.contains('delta_content')) {
        quoteMap.remove('delta_content');
      }

      debugPrint('保存笔记，使用列: ${quoteMap.keys.join(', ')}');

      await db.insert(
        'quotes',
        quoteMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('笔记已成功保存到数据库，ID: ${quoteMap['id']}');

      // 清除缓存，确保数据刷新
      _quotesCache.clear();
      _currentQuotes.clear();
      _filterCache.clear();

      notifyListeners();

      // 确保刷新流和UI
      _refreshQuotesStream();

      // 延迟再次通知以确保UI更新
      Future.delayed(const Duration(milliseconds: 200), () {
        notifyListeners();
      });
    } catch (e) {
      debugPrint('保存笔记到数据库时出错: $e');
      rethrow; // 重新抛出异常，让调用者处理
    }
  }

  // 在增删改后刷新分页流数据
  void _refreshQuotesStream() {
    if (_quotesController != null && !_quotesController!.isClosed) {
      debugPrint('刷新笔记流数据');
      // 清除缓存，确保获取最新数据

      // 重置状态并加载新数据
      _watchOffset = 0;
      _quotesCache = [];
      _watchHasMore = true;
      _currentQuotes = [];

      // 触发重新加载
      loadMoreQuotes();
    } else {
      debugPrint('笔记流无监听器或已关闭，跳过刷新');
    }
  }

  /// 获取笔记列表，支持标签、分类、搜索、天气和时间段筛选
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers, // 天气筛选
    List<String>? selectedDayPeriods, // 时间段筛选
  }) async {
    try {
      if (kIsWeb) {
        var filtered = _memoryStore;
        if (tagIds != null && tagIds.isNotEmpty) {
          filtered =
              filtered
                  .where((q) => q.tagIds.any((tag) => tagIds.contains(tag)))
                  .toList();
        }
        if (categoryId != null && categoryId.isNotEmpty) {
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
        // 天气筛选条件
        if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
          filtered =
              filtered
                  .where(
                    (q) =>
                        q.weather != null &&
                        selectedWeathers.any(
                          (weather) => q.weather!.contains(weather),
                        ),
                  )
                  .toList();
        }
        // 时间段筛选条件
        if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
          filtered =
              filtered
                  .where(
                    (q) =>
                        q.dayPeriod != null &&
                        selectedDayPeriods.contains(q.dayPeriod),
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
      // 天气筛选条件
      if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
        // 考虑null值的情况，使用COALESCE确保null值也能被正确处理
        final weatherConditions = selectedWeathers
            .map((_) => 'COALESCE(weather, "") = ?')
            .join(' OR ');
        conditions.add('($weatherConditions)');
        args.addAll(selectedWeathers);
      }
      // 时间段筛选条件
      if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
        // 考虑null值的情况，使用COALESCE确保null值也能被正确处理
        final dayPeriodConditions = selectedDayPeriods
            .map((_) => 'COALESCE(day_period, "") = ?')
            .join(' OR ');
        conditions.add('($dayPeriodConditions)');
        args.addAll(selectedDayPeriods);
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
      return maps.map((m) => Quote.fromJson(m)).toList();
    } catch (e) {
      debugPrint('获取引用错误: $e');
      return [];
    }
  }

  /// 获取用户笔记总数
  Future<int> getUserQuotesCount() async {
    return getQuotesCount();
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
      // 自动补全 day_period 字段
      if (quoteMap['date'] != null) {
        final dt = DateTime.tryParse(quoteMap['date']);
        if (dt != null) {
          final hour = dt.hour;
          String dayPeriodKey;
          if (hour >= 5 && hour < 8) {
            dayPeriodKey = 'dawn';
          } else if (hour >= 8 && hour < 12) {
            dayPeriodKey = 'morning';
          } else if (hour >= 12 && hour < 17) {
            dayPeriodKey = 'afternoon';
          } else if (hour >= 17 && hour < 20) {
            dayPeriodKey = 'dusk';
          } else if (hour >= 20 && hour < 23) {
            dayPeriodKey = 'evening';
          } else {
            dayPeriodKey = 'midnight';
          }
          quoteMap['day_period'] = dayPeriodKey;
        }
      }

      // 确保所有必需的字段都存在
      if (!quoteMap.containsKey('content') || quoteMap['content'] == null) {
        throw Exception('笔记内容不能为空');
      }

      if (!quoteMap.containsKey('date') || quoteMap['date'] == null) {
        quoteMap['date'] = DateTime.now().toIso8601String();
      }

      // 检查数据库中是否存在location、weather、temperature、edit_source、delta_content列
      final tableInfo = await db.rawQuery("PRAGMA table_info(quotes)");
      final columnNames = tableInfo.map((col) => col['name'] as String).toSet();

      // 如果列不存在，从Map中移除相应的键，避免SQL错误
      if (!columnNames.contains('location')) quoteMap.remove('location');
      if (!columnNames.contains('weather')) quoteMap.remove('weather');
      if (!columnNames.contains('temperature')) quoteMap.remove('temperature');
      if (!columnNames.contains('edit_source')) quoteMap.remove('edit_source');
      if (!columnNames.contains('delta_content')) {
        quoteMap.remove('delta_content');
      }

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

  /// 监听笔记列表，支持分页加载和筛选
  /// 检查并迁移天气数据
  Future<void> _checkAndMigrateWeatherData() async {
    try {
      final db = database;
      final weatherCheck = await db.query(
        'quotes',
        where: 'weather IS NOT NULL AND weather != ""',
        limit: 1,
      );

      if (weatherCheck.isNotEmpty) {
        final weather = weatherCheck.first['weather'] as String?;
        if (weather != null &&
            WeatherService.weatherKeyToLabel.values.contains(weather)) {
          debugPrint('检测到未迁移的weather数据，开始迁移...');
          await migrateWeatherToKey();
        }
      }
    } catch (e) {
      debugPrint('天气数据迁移检查失败: $e');
    }
  }

  /// 检查并迁移时间段数据
  Future<void> _checkAndMigrateDayPeriodData() async {
    try {
      final db = database;
      final dayPeriodCheck = await db.query(
        'quotes',
        where: 'day_period IS NOT NULL AND day_period != ""',
        limit: 1,
      );

      if (dayPeriodCheck.isNotEmpty) {
        final dayPeriod = dayPeriodCheck.first['day_period'] as String?;
        final labelToKey = TimeUtils.dayPeriodKeyToLabel.map(
          (k, v) => MapEntry(v, k),
        );
        if (dayPeriod != null && labelToKey.containsKey(dayPeriod)) {
          debugPrint('检测到未迁移的day_period数据，开始迁移...');
          await migrateDayPeriodToKey();
        }
      }
    } catch (e) {
      debugPrint('时间段数据迁移检查失败: $e');
    }
  }

  /// 监听笔记列表，支持分页加载和筛选
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers, // 天气筛选
    List<String>? selectedDayPeriods, // 时间段筛选
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

    // 检查天气筛选条件是否变更
    if (_watchSelectedWeathers != null && selectedWeathers != null) {
      if (_watchSelectedWeathers!.length != selectedWeathers.length) {
        hasFilterChanged = true;
        debugPrint(
          '天气筛选数量变更: ${_watchSelectedWeathers!.length} -> ${selectedWeathers.length}',
        );
      } else {
        // 比较天气筛选内容是否一致
        for (int i = 0; i < _watchSelectedWeathers!.length; i++) {
          if (!selectedWeathers.contains(_watchSelectedWeathers![i])) {
            hasFilterChanged = true;
            debugPrint('天气筛选内容变更');
            break;
          }
        }
      }
    } else if ((_watchSelectedWeathers == null) != (selectedWeathers == null)) {
      hasFilterChanged = true;
      debugPrint('天气筛选条件状态变更');
    }

    // 检查时间段筛选条件是否变更
    if (_watchSelectedDayPeriods != null && selectedDayPeriods != null) {
      if (_watchSelectedDayPeriods!.length != selectedDayPeriods.length) {
        hasFilterChanged = true;
        debugPrint(
          '时间段筛选数量变更: ${_watchSelectedDayPeriods!.length} -> ${selectedDayPeriods.length}',
        );
      } else {
        // 比较时间段筛选内容是否一致
        for (int i = 0; i < _watchSelectedDayPeriods!.length; i++) {
          if (!selectedDayPeriods.contains(_watchSelectedDayPeriods![i])) {
            hasFilterChanged = true;
            debugPrint('时间段筛选内容变更');
            break;
          }
        }
      }
    } else if ((_watchSelectedDayPeriods == null) !=
        (selectedDayPeriods == null)) {
      hasFilterChanged = true;
      debugPrint('时间段筛选条件状态变更');
    }

    // 更新当前的筛选参数
    _watchOffset = 0;
    _watchLimit = limit;
    _watchTagIds = tagIds;
    _watchCategoryId = categoryId;
    _watchOrderBy = orderBy;
    _watchSearchQuery = normalizedSearchQuery;
    _watchSelectedWeathers = selectedWeathers; // 保存天气筛选条件
    _watchSelectedDayPeriods = selectedDayPeriods; // 保存时间段筛选条件

    // 如果有筛选条件变更或未初始化，重新创建流
    if (hasFilterChanged || _quotesController == null) {
      _quotesController?.close();
      _quotesController = StreamController<List<Quote>>.broadcast();
      _currentQuotes = [];
      _isLoading = false;

      // 在新的异步上下文中执行初始化
      Future(() async {
        try {
          if (!kIsWeb) {
            // 检查并迁移天气数据
            await _checkAndMigrateWeatherData();
            // 检查并迁移时间段数据
            await _checkAndMigrateDayPeriodData();
            // 补全缺失的时间段数据
            await patchQuotesDayPeriod();
          }

          // 加载第一页数据
          await loadMoreQuotes(
            tagIds: tagIds,
            categoryId: categoryId,
            searchQuery: searchQuery,
            selectedWeathers: selectedWeathers,
            selectedDayPeriods: selectedDayPeriods,
          );
        } catch (e) {
          debugPrint('数据初始化或加载失败: $e');
          // 即使失败也发送空列表，避免UI挂起
          _quotesController?.add([]);
        }
      });
    }

    return _quotesController!.stream;
  }

  /// 加载更多笔记数据（用于分页）
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) async {
    // 使用当前观察的参数作为默认值
    tagIds ??= _watchTagIds;
    categoryId ??= _watchCategoryId;
    searchQuery ??= _watchSearchQuery;
    selectedWeathers ??= _watchSelectedWeathers;
    selectedDayPeriods ??= _watchSelectedDayPeriods;

    // 如果正在加载，则忽略这次请求
    if (_isLoading) return;
    _isLoading = true;

    try {
      final quotes = await getUserQuotes(
        tagIds: tagIds,
        categoryId: categoryId,
        offset: _currentQuotes.length,
        limit: _watchLimit,
        orderBy: _watchOrderBy,
        searchQuery: searchQuery,
        selectedWeathers: selectedWeathers,
        selectedDayPeriods: selectedDayPeriods,
      );

      if (quotes.isEmpty) {
        // 没有更多数据了
        _watchHasMore = false;
      } else {
        _currentQuotes.addAll(quotes);
        _watchHasMore = quotes.length >= _watchLimit;
      }

      // 通知订阅者
      if (_quotesController != null && !_quotesController!.isClosed) {
        _quotesController!.add(List.from(_currentQuotes));
      }
    } catch (e) {
      debugPrint('加载更多笔记失败: $e');
    } finally {
      _isLoading = false;
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

  // 添加存储加载状态的变量
  bool _isLoading = false;

  // 添加存储当前加载的笔记列表的变量
  List<Quote> _currentQuotes = [];

  /// 更新分类信息
  Future<void> updateCategory(
    String id,
    String name, {
    String? iconName,
  }) async {
    // 检查参数
    if (name.trim().isEmpty) {
      throw Exception('分类名称不能为空');
    }    
    // 查找是否是默认分类 - 注释掉未使用的变量
    // final List<NoteCategory> defaultCats = _getDefaultHitokotoCategories();
    
    // // 如果是默认分类，不允许修改名称？(或者只允许修改图标) - 根据产品决定
    // if (_defaultCats.any((cat) => cat.id == id)) {
    //   // 暂时允许修改默认分类的名称和图标，但ID不变
    //   // 如果不允许修改名称，可以在这里抛出异常或只更新图标
    //   // throw Exception('不允许修改默认分类的名称');
    // }

    if (kIsWeb) {
      // Web 平台逻辑
      final index = _categoryStore.indexWhere((c) => c.id == id);
      if (index == -1) {
        throw Exception('找不到指定的分类');
      }
      // 检查新名称是否与 *其他* 分类冲突
      final newNameLower = name.toLowerCase();
      final conflict = _categoryStore.any(
        (c) => c.id != id && c.name.toLowerCase() == newNameLower,
      );
      if (conflict) {
        throw Exception('已存在相同名称的分类');
      }
      final updatedCategory = NoteCategory(
        id: id, // ID 保持不变
        name: name,
        isDefault: _categoryStore[index].isDefault, // isDefault 状态保持不变
        iconName: iconName ?? _categoryStore[index].iconName,
      );
      _categoryStore[index] = updatedCategory;
      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }

    final db = database;

    // 检查要更新的分类是否存在
    final currentCategories = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (currentCategories.isEmpty) {
      throw Exception('找不到指定的分类');
    }

    final currentCategory = NoteCategory.fromMap(currentCategories.first);
    final currentNameLower = currentCategory.name.toLowerCase();
    final newNameLower = name.toLowerCase();

    // 只有当新名称与当前名称不同时，才检查重复 (检查除自身以外的分类)
    if (newNameLower != currentNameLower) {
      final existing = await db.query(
        'categories',
        where: 'LOWER(name) = ? AND id != ?', // 排除自身
        whereArgs: [newNameLower, id],
      );
      if (existing.isNotEmpty) {
        throw Exception('已存在相同名称的分类');
      }
    }

    final categoryMap = {
      'name': name,
      'icon_name': iconName ?? currentCategory.iconName, // 如果未提供新图标，则保留旧图标
      // 'is_default' 字段不应在此处更新，它在创建时确定
    };

    await db.update(
      'categories',
      categoryMap,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _updateCategoriesStream();
    notifyListeners();
  }

  /// 批量为旧笔记补全 dayPeriod 字段（根据 date 字段推算并写入）
  Future<void> patchQuotesDayPeriod() async {
    final db = database;
    final List<Map<String, dynamic>> maps = await db.query('quotes');
    for (final map in maps) {
      if (map['day_period'] == null || (map['day_period'] as String).isEmpty) {
        // 解析时间
        String? dateStr = map['date'];
        if (dateStr == null || dateStr.isEmpty) continue;
        DateTime? dt;
        try {
          dt = DateTime.parse(dateStr);
        } catch (_) {
          continue;
        }
        // 推算时间段key
        final hour = dt.hour;
        String dayPeriodKey;
        if (hour >= 5 && hour < 8) {
          dayPeriodKey = 'dawn';
        } else if (hour >= 8 && hour < 12) {
          dayPeriodKey = 'morning';
        } else if (hour >= 12 && hour < 17) {
          dayPeriodKey = 'afternoon';
        } else if (hour >= 17 && hour < 20) {
          dayPeriodKey = 'dusk';
        } else if (hour >= 20 && hour < 23) {
          dayPeriodKey = 'evening';
        } else {
          dayPeriodKey = 'midnight';
        }
        // 更新数据库
        await db.update(
          'quotes',
          {'day_period': dayPeriodKey},
          where: 'id = ?',
          whereArgs: [map['id']],
        );
      }
    }
  }

  /// 迁移旧数据dayPeriod字段为英文key
  Future<void> migrateDayPeriodToKey() async {
    final db = database;
    final List<Map<String, dynamic>> maps = await db.query(
      'quotes',
      columns: ['id', 'day_period'],
    );
    final labelToKey = TimeUtils.dayPeriodKeyToLabel.map(
      (k, v) => MapEntry(v, k),
    );
    for (final map in maps) {
      final id = map['id'] as String?;
      final dayPeriod = map['day_period'] as String?;
      if (id != null &&
          dayPeriod != null &&
          labelToKey.containsKey(dayPeriod)) {
        final key = labelToKey[dayPeriod]!;
        await db.update(
          'quotes',
          {'day_period': key},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    debugPrint('已完成旧数据dayPeriod字段的key迁移');
  }

  /// 迁移旧数据weather字段为英文key
  Future<void> migrateWeatherToKey() async {
    if (kIsWeb) {
      for (var i = 0; i < _memoryStore.length; i++) {
        final q = _memoryStore[i];
        if (q.weather != null &&
            WeatherService.weatherKeyToLabel.values.contains(q.weather)) {
          final key =
              WeatherService.weatherKeyToLabel.entries
                  .firstWhere((e) => e.value == q.weather)
                  .key;
          _memoryStore[i] = q.copyWith(weather: key);
        }
      }
      notifyListeners();
      return;
    }

    final db = database;
    final maps = await db.query('quotes', columns: ['id', 'weather']);
    for (final m in maps) {
      final id = m['id'] as String?;
      final weather = m['weather'] as String?;
      if (id != null &&
          weather != null &&
          WeatherService.weatherKeyToLabel.values.contains(weather)) {
        final key =
            WeatherService.weatherKeyToLabel.entries
                .firstWhere((e) => e.value == weather)
                .key;
        await db.update(
          'quotes',
          {'weather': key},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    debugPrint('已完成旧数据weather字段的key迁移');
  }

  /// 根据 ID 获取分类
  Future<NoteCategory?> getCategoryById(String id) async {
    if (kIsWeb) {
      try {
        return _categoryStore.firstWhere((cat) => cat.id == id);
      } catch (e) {
        debugPrint('在内存中找不到 ID 为 $id 的分类: $e');
        return null;
      }
    }

    try {
      final db = database;
      final maps = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isEmpty) {
        return null;
      }

      return NoteCategory.fromMap(maps.first);
    } catch (e) {
      debugPrint('根据 ID 获取分类失败: $e');
      return null;
    }
  }
}
