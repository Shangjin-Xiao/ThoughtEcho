// ignore_for_file: unused_element
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/quote_model.dart';
import '../services/weather_service.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';
import 'media_reference_service.dart';

class DatabaseSchemaManager {
  @visibleForTesting
  static String poiNameSelectExpressionFromTableInfo(
    List<Map<String, Object?>> tableInfo,
  ) {
    final hasPoiNameColumn = tableInfo.any((col) => col['name'] == 'poi_name');
    return hasPoiNameColumn ? 'poi_name' : 'NULL AS poi_name';
  }

  // 抽取数据库初始化逻辑到单独方法，便于复用
  Future<Database> _initDatabase(String path) async {
    return await openDatabase(
      path,
      version: 20, // 版本号升级至20，添加poi_name + chat_sessions + chat_messages
      onCreate: (db, version) async {
        await createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await upgradeDatabase(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        // 关键：确保外键约束已启用（必须在事务外执行）
        await db.rawQuery('PRAGMA foreign_keys = ON');

        // 每次打开数据库时配置PRAGMA参数
        await configureDatabasePragmas(db);

        // 验证外键约束状态
        await verifyForeignKeysEnabled(db);
      },
    );
  }

  Future<void> createTables(Database db) async {
    // 创建分类表：包含 id、名称、是否为默认、图标名称等字段
    await db.execute('''
      CREATE TABLE categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_default BOOLEAN DEFAULT 0,
        icon_name TEXT,
        last_modified TEXT
      )
    ''');
    // 创建引用（笔记）表，新增 category_id、source、source_author、source_work、color_hex、edit_source、delta_content、day_period、last_modified 字段
    await db.execute('''
      CREATE TABLE quotes(
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        date TEXT NOT NULL,
        source TEXT,
        source_author TEXT,
        source_work TEXT,
        ai_analysis TEXT,
        sentiment TEXT,
        keywords TEXT,
        summary TEXT,
        category_id TEXT DEFAULT '',
        color_hex TEXT,
        location TEXT,
        latitude REAL,
        longitude REAL,
        poi_name TEXT,
        weather TEXT,
        temperature TEXT,
        edit_source TEXT,
        delta_content TEXT,
        day_period TEXT,
        last_modified TEXT,
        favorite_count INTEGER DEFAULT 0
      )
    ''');

    /// 修复：创建优化的索引以加速常用查询
    // 基础索引
    await db.execute(
      'CREATE INDEX idx_quotes_category_id ON quotes(category_id)',
    );
    await db.execute('CREATE INDEX idx_quotes_date ON quotes(date)');

    // 复合索引优化复杂查询
    await db.execute(
      'CREATE INDEX idx_quotes_date_category ON quotes(date DESC, category_id)',
    );
    await db.execute(
      'CREATE INDEX idx_quotes_category_date ON quotes(category_id, date DESC)',
    );

    // 搜索优化索引
    await db.execute(
      'CREATE INDEX idx_quotes_content_fts ON quotes(content)',
    );

    // 天气和时间段查询索引
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_weather ON quotes(weather)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
    );
    // 新增：last_modified 索引用于同步增量查询
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_last_modified ON quotes(last_modified)',
    );
    // 新增：favorite_count 索引用于按喜爱度排序
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_favorite_count ON quotes(favorite_count)',
    );

    // 创建新的 quote_tags 关联表
    await db.execute('''
      CREATE TABLE quote_tags(
        quote_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (quote_id, tag_id),
        FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
      )
    ''');

    /// 修复：优化quote_tags表的索引
    await db.execute(
      'CREATE INDEX idx_quote_tags_quote_id ON quote_tags(quote_id)',
    );
    await db.execute(
      'CREATE INDEX idx_quote_tags_tag_id ON quote_tags(tag_id)',
    );
    // 复合索引优化JOIN查询
    await db.execute(
      'CREATE INDEX idx_quote_tags_composite ON quote_tags(tag_id, quote_id)',
    );

    // poi_name 索引
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_poi_name ON quotes(poi_name)',
    );

    // 创建聊天会话表
    await db.execute('''
      CREATE TABLE chat_sessions(
        id TEXT PRIMARY KEY,
        session_type TEXT NOT NULL DEFAULT 'note',
        note_id TEXT,
        title TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        last_active_at TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (note_id) REFERENCES quotes(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_chat_sessions_note_id ON chat_sessions(note_id)',
    );
    await db.execute(
      'CREATE INDEX idx_chat_sessions_last_active ON chat_sessions(last_active_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_chat_sessions_type ON chat_sessions(session_type)',
    );

    // 创建聊天消息表
    await db.execute('''
      CREATE TABLE chat_messages(
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'user',
        content TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        included_in_context INTEGER NOT NULL DEFAULT 1,
        meta_json TEXT,
        FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_chat_messages_session_id ON chat_messages(session_id)',
    );
    await db.execute(
      'CREATE INDEX idx_chat_messages_created_at ON chat_messages(session_id, created_at ASC)',
    );

    // 创建媒体文件引用表
    await MediaReferenceService.initializeTable(db);

    // 配置数据库安全和性能参数（在事务内）
    await configureDatabasePragmas(db, inTransaction: true);
  }

  Future<void> upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    logDebug('开始数据库升级: $oldVersion -> $newVersion');

    try {
      // 修复：使用事务保护整个升级过程
      await db.transaction((txn) async {
        // 创建升级备份
        await _createUpgradeBackup(txn, oldVersion);

        // 按版本顺序执行升级
        await _performVersionUpgrades(txn, oldVersion, newVersion);

        // 验证升级结果
        await _validateUpgradeResult(txn);
      });

      logDebug('数据库升级成功完成');
    } catch (e) {
      logError('数据库升级失败: $e', error: e, source: 'DatabaseUpgrade');
      rethrow;
    }
  }

  /// 验证外键约束是否已启用
  Future<void> verifyForeignKeysEnabled(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA foreign_keys');
      final isEnabled = result.isNotEmpty && result.first['foreign_keys'] == 1;

      if (isEnabled) {
        logDebug('✅ 外键约束已启用，数据完整性受保护');
      } else {
        logError('⚠️ 警告：外键约束未启用，可能影响数据完整性', source: 'DatabaseService');
      }
    } catch (e) {
      logError('验证外键约束状态失败: $e', error: e, source: 'DatabaseService');
    }
  }

  /// 配置数据库安全和性能PRAGMA参数
  /// [inTransaction] 是否在事务内执行（onCreate/onUpgrade为true，onOpen为false）
  Future<void> configureDatabasePragmas(
    Database db, {
    bool inTransaction = false,
  }) async {
    try {
      // 启用外键约束（防止数据孤立）
      await db.rawQuery('PRAGMA foreign_keys = ON');

      // 设置繁忙超时（5秒），防止并发冲突
      await db.rawQuery('PRAGMA busy_timeout = 5000');

      // 设置缓存大小为8MB（负数表示KB）
      await db.rawQuery('PRAGMA cache_size = -8000');

      // 临时表使用内存存储
      await db.rawQuery('PRAGMA temp_store = MEMORY');

      // 只在事务外执行的配置（onCreate/onUpgrade在事务内，onOpen在事务外）
      if (!inTransaction) {
        // 使用WAL模式提升并发性能（必须在事务外）
        await db.rawQuery('PRAGMA journal_mode = WAL');

        // 正常同步模式（必须在事务外，否则报错 SQLITE_ERROR）
        await db.rawQuery('PRAGMA synchronous = NORMAL');
      }

      // 验证关键配置
      final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
      final journalMode = await db.rawQuery('PRAGMA journal_mode');

      logDebug(
        '数据库PRAGMA配置完成 (inTransaction=$inTransaction): foreign_keys=${foreignKeys.first['foreign_keys']}, journal_mode=${journalMode.first['journal_mode']}',
      );
    } catch (e) {
      logError('配置数据库PRAGMA失败: $e', error: e, source: 'DatabaseService');
      // 配置失败不应阻止数据库使用，只记录错误
    }
  }

  /// 修复：创建升级备份

  /// 修复：创建升级备份
  Future<void> _createUpgradeBackup(Transaction txn, int oldVersion) async {
    try {
      logDebug('创建数据库升级备份...');

      // 备份quotes表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS quotes_backup_v$oldVersion AS 
        SELECT * FROM quotes
      ''');

      // 备份categories表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS categories_backup_v$oldVersion AS 
        SELECT * FROM categories
      ''');

      // 如果quote_tags表存在，也备份
      final tables = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='quote_tags'",
      );
      if (tables.isNotEmpty) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS quote_tags_backup_v$oldVersion AS 
          SELECT * FROM quote_tags
        ''');
      }

      logDebug('升级备份创建完成');
    } catch (e) {
      logDebug('创建升级备份失败: $e');
      // 备份失败不应阻止升级，但要记录警告
    }
  }

  /// 修复：执行版本升级
  Future<void> _performVersionUpgrades(
    Transaction txn,
    int oldVersion,
    int newVersion,
  ) async {
    logDebug('在事务中执行版本升级...');

    // 如果数据库版本低于 2，添加 tag_ids 字段（以前可能不存在，但在本版本中创建表时已包含）
    if (oldVersion < 2) {
      await txn.execute(
        'ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ""',
      );
    }
    // 如果数据库版本低于 3，添加 categories 表中的 icon_name 字段（在本版本中创建表时已包含）
    if (oldVersion < 3) {
      await txn.execute('ALTER TABLE categories ADD COLUMN icon_name TEXT');
    }
    // 如果数据库版本低于 4，添加 quotes 表中的 category_id 字段
    if (oldVersion < 4) {
      await txn.execute(
        'ALTER TABLE quotes ADD COLUMN category_id TEXT DEFAULT ""',
      );
    }

    // 如果数据库版本低于 5，添加 quotes 表中的 source 字段
    if (oldVersion < 5) {
      await txn.execute('ALTER TABLE quotes ADD COLUMN source TEXT');
    }

    // 如果数据库版本低于 6，添加 quotes 表中的 color_hex 字段
    if (oldVersion < 6) {
      await txn.execute('ALTER TABLE quotes ADD COLUMN color_hex TEXT');
    }

    // 如果数据库版本低于 7，添加 quotes 表中的 source_author 和 source_work 字段
    if (oldVersion < 7) {
      await txn.execute('ALTER TABLE quotes ADD COLUMN source_author TEXT');
      await txn.execute('ALTER TABLE quotes ADD COLUMN source_work TEXT');

      // 将现有的 source 字段数据拆分到新字段中
      final quotes = await txn.query(
        'quotes',
        where: 'source IS NOT NULL AND source != ""',
      );

      for (final quote in quotes) {
        final source = quote['source'] as String?;
        if (source != null && source.isNotEmpty) {
          String? sourceAuthor;
          String? sourceWork;

          // 尝试解析 source 字段
          if (source.contains('《') && source.contains('》')) {
            // 格式：作者《作品》
            final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
            if (workMatch != null) {
              sourceWork = workMatch.group(1);
              sourceAuthor = source.replaceAll(RegExp(r'《.+?》'), '').trim();
              if (sourceAuthor.isEmpty) sourceAuthor = null;
            }
          } else if (source.contains(' - ')) {
            // 格式：作者 - 作品
            final parts = source.split(' - ');
            if (parts.length >= 2) {
              sourceAuthor = parts[0].trim();
              sourceWork = parts.sublist(1).join(' - ').trim();
            }
          } else {
            // 默认作为作者
            sourceAuthor = source.trim();
          }

          // 更新记录
          await txn.update(
            'quotes',
            {'source_author': sourceAuthor, 'source_work': sourceWork},
            where: 'id = ?',
            whereArgs: [quote['id']],
          );
        }
      }
    }

    // 如果数据库版本低于 8，添加位置和天气相关字段
    if (oldVersion < 8) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 location, weather, temperature 字段',
      );
      await txn.execute('ALTER TABLE quotes ADD COLUMN location TEXT');
      await txn.execute('ALTER TABLE quotes ADD COLUMN weather TEXT');
      await txn.execute('ALTER TABLE quotes ADD COLUMN temperature TEXT');
      logDebug('数据库升级：location, weather, temperature 字段添加完成');
    }

    // 如果数据库版本低于 9，添加索引以提高查询性能
    if (oldVersion < 9) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加索引');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
      );
      // 修复：不再为tag_ids列创建索引，因为该列已被quote_tags表替代
      // await txn.execute(
      //   'CREATE INDEX IF NOT EXISTS idx_quotes_tag_ids ON quotes(tag_ids)',
      // );
      logDebug('数据库升级：索引添加完成');
    }

    // 如果数据库版本低于 10，添加 edit_source 字段用于记录编辑来源
    if (oldVersion < 10) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 edit_source 字段');
      await txn.execute('ALTER TABLE quotes ADD COLUMN edit_source TEXT');
      logDebug('数据库升级：edit_source 字段添加完成');
    }
    // 如果数据库版本低于 11，添加 delta_content 字段用于存储富文本Delta JSON
    if (oldVersion < 11) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 delta_content 字段');
      try {
        // 先检查字段是否已存在
        final columns = await txn.rawQuery('PRAGMA table_info(quotes)');
        final hasColumn = columns.any((col) => col['name'] == 'delta_content');

        if (!hasColumn) {
          await txn.execute('ALTER TABLE quotes ADD COLUMN delta_content TEXT');
          logDebug('数据库升级：delta_content 字段添加完成');
        } else {
          logDebug('数据库升级：delta_content 字段已存在，跳过添加');
        }
      } catch (e) {
        logError('delta_content 字段升级失败: $e',
            error: e, source: 'DatabaseUpgrade');
      }
    }

    // 修复：如果数据库版本低于 12，安全地创建 quote_tags 表并迁移数据
    if (oldVersion < 12) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，创建 quote_tags 表并迁移数据');

      await _upgradeToVersion12SafelyInTransaction(txn);
    }

    // 如果数据库版本低于 13，创建媒体文件引用表
    if (oldVersion < 13) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，创建媒体文件引用表');

      await _initializeMediaReferenceTableInTransaction(txn);
      logDebug('数据库升级：媒体文件引用表创建完成');
    }

    // 修复：如果数据库版本低于 14，安全地添加 day_period 字段
    if (oldVersion < 14) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 day_period 字段');

      try {
        // 先检查字段是否已存在
        final columns = await txn.rawQuery('PRAGMA table_info(quotes)');
        final hasColumn = columns.any((col) => col['name'] == 'day_period');

        if (!hasColumn) {
          await txn.execute('ALTER TABLE quotes ADD COLUMN day_period TEXT');
          logDebug('数据库升级：day_period 字段添加完成');
        } else {
          logDebug('数据库升级：day_period 字段已存在，跳过添加');
        }

        // 为新添加的字段创建索引（使用 IF NOT EXISTS 确保安全）
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
        );
        logDebug('数据库升级：day_period 索引创建完成');
      } catch (e) {
        logError('day_period 字段升级失败: $e', error: e, source: 'DatabaseUpgrade');
        // 不要重新抛出异常，允许升级继续
      }
    }

    // 如果数据库版本低于15，添加 last_modified 字段（用于同步与更新追踪）
    if (oldVersion < 15) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 last_modified 字段');
      try {
        final columns = await txn.rawQuery('PRAGMA table_info(quotes)');
        final hasColumn = columns.any((col) => col['name'] == 'last_modified');
        if (!hasColumn) {
          await txn.execute('ALTER TABLE quotes ADD COLUMN last_modified TEXT');
          logDebug('数据库升级：last_modified 字段添加完成');
          // 回填已有数据的last_modified，使用其date或当前时间
          final nowIso = DateTime.now().toIso8601String();
          // 使用COALESCE保证date为空时写入当前时间
          await txn.execute(
            'UPDATE quotes SET last_modified = COALESCE(date, ?)',
            [nowIso],
          );
        } else {
          logDebug('数据库升级：last_modified 字段已存在，跳过添加');
        }
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_last_modified ON quotes(last_modified)',
        );
      } catch (e) {
        logError(
          'last_modified 字段升级失败: $e',
          error: e,
          source: 'DatabaseUpgrade',
        );
      }
    }

    // 版本16：为分类表添加last_modified字段
    if (oldVersion < 16) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，为分类表添加 last_modified 字段',
      );
      try {
        final columns = await txn.rawQuery('PRAGMA table_info(categories)');
        final hasColumn = columns.any((col) => col['name'] == 'last_modified');
        if (!hasColumn) {
          await txn.execute(
            'ALTER TABLE categories ADD COLUMN last_modified TEXT',
          );
          logDebug('数据库升级：categories表 last_modified 字段添加完成');
          // 回填已有分类数据的last_modified
          final nowIso = DateTime.now().toIso8601String();
          await txn.execute('UPDATE categories SET last_modified = ?', [
            nowIso,
          ]);
        } else {
          logDebug('数据库升级：categories表 last_modified 字段已存在，跳过添加');
        }
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_categories_last_modified ON categories(last_modified)',
        );
      } catch (e) {
        logError(
          'categories表 last_modified 字段升级失败: $e',
          error: e,
          source: 'DatabaseUpgrade',
        );
      }
    }

    // 版本17：为笔记表添加favorite_count字段
    if (oldVersion < 17) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，为笔记表添加 favorite_count 字段',
      );
      try {
        final columns = await txn.rawQuery('PRAGMA table_info(quotes)');
        final hasColumn = columns.any((col) => col['name'] == 'favorite_count');
        if (!hasColumn) {
          await txn.execute(
            'ALTER TABLE quotes ADD COLUMN favorite_count INTEGER DEFAULT 0',
          );
          logDebug('数据库升级：quotes表 favorite_count 字段添加完成');
        } else {
          logDebug('数据库升级：quotes表 favorite_count 字段已存在，跳过添加');
        }
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_favorite_count ON quotes(favorite_count)',
        );
      } catch (e) {
        logError(
          'quotes表 favorite_count 字段升级失败: $e',
          error: e,
          source: 'DatabaseUpgrade',
        );
      }
    }

    // 版本18：更新默认标签图标为emoji
    if (oldVersion < 18) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，更新默认标签图标为emoji');
      try {
        // 定义图标映射：旧图标 -> 新emoji
        final Map<String, String> iconMigration = {
          // 历史值 -> 目标值（将旧的 emoji 或临时名统一回到 format_quote）
          'flutter_dash': 'format_quote',
          '💭': 'format_quote',
          'format_quote': 'format_quote',
          'movie': '🎬', // 动画
          'menu_book': '📚', // 漫画
          'sports_esports': '🎮', // 游戏
          'auto_stories': '📖', // 文学
          'create': '✨', // 原创
          'public': '🌐', // 来自网络
          'category': '📦', // 其他
          '📝': '📦', // 历史 emoji -> 新 emoji
          'theaters': '🎞️', // 影视 -> 随机 emoji
          'brush': '🪶', // 诗词 -> 随机 emoji
          'music_note': '🎧', // 网易云 -> 🎧
          '🎶': '🎧', // 历史 emoji -> 🎧
          'psychology': '🤔', // 哲学
        };

        // 注意：这里会更新所有默认标签的图标，包括用户可能自定义过的
        // 但由于是从旧版本升级（oldVersion < 18），通常是首次迁移
        // 如果用户在v18之前已经自定义了图标，这里会被覆盖
        // 考虑到这是首次引入emoji图标，这个行为是可接受的
        // 未来版本如需更新图标，应检查 last_modified 字段避免覆盖用户修改
        for (final entry in iconMigration.entries) {
          final oldIcon = entry.key;
          final newIcon = entry.value;

          await txn.execute(
            'UPDATE categories SET icon_name = ? WHERE icon_name = ? AND is_default = 1',
            [newIcon, oldIcon],
          );
        }

        logDebug('数据库升级：默认标签图标更新完成');
      } catch (e) {
        logError('默认标签图标更新失败: $e', error: e, source: 'DatabaseUpgrade');
      }
    }

    // 版本19：为笔记表添加latitude/longitude字段，支持离线位置存储
    if (oldVersion < 19) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 latitude/longitude 字段',
      );
      try {
        final columns = await txn.rawQuery('PRAGMA table_info(quotes)');

        // 检查并添加 latitude 字段
        final hasLatitude = columns.any((col) => col['name'] == 'latitude');
        if (!hasLatitude) {
          await txn.execute('ALTER TABLE quotes ADD COLUMN latitude REAL');
          logDebug('数据库升级：latitude 字段添加完成');
        }

        // 检查并添加 longitude 字段
        final hasLongitude = columns.any((col) => col['name'] == 'longitude');
        if (!hasLongitude) {
          await txn.execute('ALTER TABLE quotes ADD COLUMN longitude REAL');
          logDebug('数据库升级：longitude 字段添加完成');
        }

        // 为经纬度创建复合索引，便于地理位置查询
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_coordinates ON quotes(latitude, longitude)',
        );
        logDebug('数据库升级：coordinates 索引创建完成');
      } catch (e) {
        logError(
          'latitude/longitude 字段升级失败: $e',
          error: e,
          source: 'DatabaseUpgrade',
        );
      }
    }

    // 版本20：添加 poi_name 字段 + 聊天会话/消息表
    if (oldVersion < 20) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 poi_name + 聊天表',
      );
      final columns = await txn.rawQuery('PRAGMA table_info(quotes)');
      final hasPoiName = columns.any((col) => col['name'] == 'poi_name');
      if (!hasPoiName) {
        await txn.execute('ALTER TABLE quotes ADD COLUMN poi_name TEXT');
        logDebug('数据库升级：poi_name 字段添加完成');
      }

      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_poi_name ON quotes(poi_name)',
      );

      await txn.execute('''
        CREATE TABLE IF NOT EXISTS chat_sessions(
          id TEXT PRIMARY KEY,
          session_type TEXT NOT NULL DEFAULT 'note',
          note_id TEXT,
          title TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          last_active_at TEXT NOT NULL,
          is_pinned INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (note_id) REFERENCES quotes(id) ON DELETE CASCADE
        )
      ''');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_chat_sessions_note_id ON chat_sessions(note_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_chat_sessions_last_active ON chat_sessions(last_active_at DESC)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_chat_sessions_type ON chat_sessions(session_type)',
      );

      await txn.execute('''
        CREATE TABLE IF NOT EXISTS chat_messages(
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'user',
          content TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          included_in_context INTEGER NOT NULL DEFAULT 1,
          meta_json TEXT,
          FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
        )
      ''');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_chat_messages_session_id ON chat_messages(session_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(session_id, created_at ASC)',
      );

      logDebug('数据库升级：v20 完成');
    }
  }

  /// 修复：验证升级结果
  Future<void> _validateUpgradeResult(Transaction txn) async {
    try {
      // 验证关键表是否存在
      final tables = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      final requiredTables = {
        'quotes',
        'categories',
        'quote_tags',
        'chat_sessions',
        'chat_messages',
      };
      final missingTables = requiredTables.difference(tableNames);

      if (missingTables.isNotEmpty) {
        throw Exception('升级后缺少必要的表: $missingTables');
      }

      logDebug('数据库升级验证通过');
    } catch (e) {
      logError('数据库升级验证失败: $e', error: e, source: 'DatabaseUpgrade');
      rethrow;
    }
  }

  /// 修复：安全的版本12升级
  Future<void> _upgradeToVersion12Safely(Database db) async {
    await db.transaction((txn) async {
      try {
        // 1. 创建新的关联表
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS quote_tags(
            quote_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            PRIMARY KEY (quote_id, tag_id),
            FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
          )
        ''');

        // 2. 创建索引
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quote_tags_quote_id ON quote_tags(quote_id)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quote_tags_tag_id ON quote_tags(tag_id)',
        );

        // 3. 安全迁移数据
        await _migrateTagDataSafely(txn);

        logDebug('版本12升级安全完成');
      } catch (e) {
        logError('版本12升级失败: $e', error: e, source: 'DatabaseUpgrade');
        rethrow;
      }
    });
  }

  /// 修复：安全的标签数据迁移
  Future<void> _migrateTagDataSafely(Transaction txn) async {
    // 首先检查tag_ids列是否存在
    final tableInfo = await txn.rawQuery('PRAGMA table_info(quotes)');
    final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

    if (!hasTagIdsColumn) {
      logDebug('tag_ids列不存在，跳过标签数据迁移');
      return;
    }

    // 获取所有有标签的笔记
    final quotesWithTags = await txn.query(
      'quotes',
      columns: ['id', 'tag_ids'],
      where: 'tag_ids IS NOT NULL AND tag_ids != ""',
    );

    if (quotesWithTags.isEmpty) {
      logDebug('没有需要迁移的标签数据');
      return;
    }

    // 优化：一次性获取所有分类ID，避免在循环中进行N+1查询
    final allCategories = await txn.query('categories', columns: ['id']);
    final allCategoryIds = allCategories.map((c) => c['id'] as String).toSet();

    int migratedCount = 0;
    int errorCount = 0;

    // 优化：使用batch进行批量插入
    final batch = txn.batch();

    for (final quote in quotesWithTags) {
      try {
        final quoteId = quote['id'] as String;
        final tagIdsString = quote['tag_ids'] as String?;

        if (tagIdsString == null || tagIdsString.isEmpty) continue;

        // 解析标签ID
        final tagIds = tagIdsString
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();

        if (tagIds.isEmpty) continue;

        // 验证标签ID是否存在（在内存中检查）
        final validTagIds = <String>[];
        for (final tagId in tagIds) {
          if (allCategoryIds.contains(tagId)) {
            validTagIds.add(tagId);
          } else {
            logDebug('警告：标签ID $tagId 不存在，跳过');
          }
        }

        // 插入有效的标签关联（添加到batch）
        for (final tagId in validTagIds) {
          batch.insert(
              'quote_tags',
              {
                'quote_id': quoteId,
                'tag_id': tagId,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        migratedCount++;
      } catch (e) {
        errorCount++;
        logDebug('迁移笔记 ${quote['id']} 的标签时出错: $e');
      }
    }

    // 提交批量操作
    try {
      await batch.commit(noResult: true);
    } catch (e) {
      logError('批量插入标签关联失败: $e', error: e, source: 'TagMigration');
      // 重新抛出异常以确保迁移事务整体失败，避免在迁移未完成时删除 tag_ids 列导致数据丢失
      rethrow;
    }

    logDebug('标签数据迁移完成：成功 $migratedCount 条，错误 $errorCount 条');
  }

  /// 安全地删除tag_ids列（通过重建表）
  Future<void> _removeTagIdsColumnSafely(Transaction txn) async {
    try {
      // 首先检查tag_ids列是否存在
      final tableInfo = await txn.rawQuery('PRAGMA table_info(quotes)');
      final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

      if (!hasTagIdsColumn) {
        logDebug('tag_ids列已不存在，跳过删除');
        return;
      }

      // 上次异常中断时可能残留临时表，先清理
      await txn.execute('DROP TABLE IF EXISTS quotes_new');

      final poiNameSelectFragment = poiNameSelectExpressionFromTableInfo(
        tableInfo.cast<Map<String, Object?>>(),
      );

      logDebug('开始删除tag_ids列...');

      // 1. 创建新的quotes表（不包含tag_ids列，但包含favorite_count和latitude/longitude）
      await txn.execute('''
        CREATE TABLE quotes_new(
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          date TEXT NOT NULL,
          source TEXT,
          source_author TEXT,
          source_work TEXT,
          ai_analysis TEXT,
          sentiment TEXT,
          keywords TEXT,
          summary TEXT,
          category_id TEXT DEFAULT '',
          color_hex TEXT,
          location TEXT,
          latitude REAL,
          longitude REAL,
          poi_name TEXT,
          weather TEXT,
          temperature TEXT,
          edit_source TEXT,
          delta_content TEXT,
          day_period TEXT,
          last_modified TEXT,
          favorite_count INTEGER DEFAULT 0
        )
      ''');

      // 2. 复制数据（排除tag_ids列，保留favorite_count和latitude/longitude）
      await txn.execute('''
        INSERT INTO quotes_new (
          id, content, date, source, source_author, source_work,
          ai_analysis, sentiment, keywords, summary, category_id,
          color_hex, location, latitude, longitude, poi_name, weather, temperature, edit_source,
          delta_content, day_period, last_modified, favorite_count
        )
        SELECT
          id, content, date, source, source_author, source_work,
          ai_analysis, sentiment, keywords, summary, category_id,
          color_hex, location, latitude, longitude, $poiNameSelectFragment, weather, temperature, edit_source,
          delta_content, day_period, last_modified,
          COALESCE(favorite_count, 0) as favorite_count
        FROM quotes
      ''');

      // 3. 删除旧表
      await txn.execute('DROP TABLE quotes');

      // 4. 重命名新表
      await txn.execute('ALTER TABLE quotes_new RENAME TO quotes');

      // 5. 重新创建索引
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_date_category ON quotes(date DESC, category_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_category_date ON quotes(category_id, date DESC)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_content_fts ON quotes(content)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_weather ON quotes(weather)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_favorite_count ON quotes(favorite_count)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_last_modified ON quotes(last_modified)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_coordinates ON quotes(latitude, longitude)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_poi_name ON quotes(poi_name)',
      );

      logDebug('tag_ids列删除完成，favorite_count字段已保留');
    } catch (e) {
      logError('删除tag_ids列失败: $e', error: e, source: 'DatabaseUpgrade');
      rethrow;
    }
  }

  /// 清理遗留的tag_ids列
  Future<void> cleanupLegacyTagIdsColumn(Database db) async {
    try {
      // 检查quotes表是否还有tag_ids列
      final tableInfo = await db.rawQuery('PRAGMA table_info(quotes)');
      final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

      if (!hasTagIdsColumn) {
        logDebug('tag_ids列已不存在，无需清理');
        return;
      }

      logDebug('检测到遗留的tag_ids列，开始清理...');

      // 在事务中执行清理
      await db.transaction((txn) async {
        // 首先确保数据已迁移到quote_tags表
        await _migrateTagDataSafely(txn);

        // 然后删除tag_ids列
        await _removeTagIdsColumnSafely(txn);
      });

      logDebug('遗留tag_ids列清理完成');
    } catch (e) {
      logError('清理遗留tag_ids列失败: $e', error: e, source: 'DatabaseService');
      // 不重新抛出异常，避免影响应用启动
    }
  }

  /// 修复：在事务中安全地执行版本12升级
  Future<void> _upgradeToVersion12SafelyInTransaction(Transaction txn) async {
    try {
      // 1. 创建新的关联表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS quote_tags(
          quote_id TEXT NOT NULL,
          tag_id TEXT NOT NULL,
          PRIMARY KEY (quote_id, tag_id),
          FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
          FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
        )
      ''');

      // 2. 创建索引
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quote_tags_quote_id ON quote_tags(quote_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quote_tags_tag_id ON quote_tags(tag_id)',
      );

      // 3. 安全迁移数据
      await _migrateTagDataSafely(txn);

      // 4. 迁移完成后，删除旧的tag_ids列（SQLite不支持直接删除列，需要重建表）
      await _removeTagIdsColumnSafely(txn);

      logDebug('版本12升级在事务中安全完成');
    } catch (e) {
      logError('版本12升级失败: $e', error: e, source: 'DatabaseUpgrade');
      rethrow;
    }
  }

  /// 修复：在事务中初始化媒体引用表
  Future<void> _initializeMediaReferenceTableInTransaction(
    Transaction txn,
  ) async {
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS media_references (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        quote_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (quote_id) REFERENCES quotes (id) ON DELETE CASCADE,
        UNIQUE(file_path, quote_id)
      )
    ''');

    // 创建索引以提高查询性能
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_references_file_path
      ON media_references (file_path)
    ''');

    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_references_quote_id
      ON media_references (quote_id)
    ''');

    logDebug('媒体引用表在事务中初始化完成');
  }

  /// 检查并修复数据库结构，确保所有必要的列都存在
  /// 修复：检查并修复数据库结构，包括字段和索引
  Future<void> checkAndFixDatabaseStructure(Database db) async {
    try {
      // 获取quotes表的列信息
      final tableInfo = await db.rawQuery('PRAGMA table_info(quotes)');
      final columnNames = tableInfo.map((col) => col['name'] as String).toSet();

      logDebug('当前quotes表列: $columnNames');

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
        logDebug('检测到缺少列: $missingColumns，正在添加...');

        // 添加缺少的列
        for (final column in missingColumns) {
          try {
            await db.execute('ALTER TABLE quotes ADD COLUMN $column TEXT');
            logDebug('成功添加列: $column');
          } catch (e) {
            logDebug('添加列 $column 时出错: $e');
          }
        }
      } else {
        logDebug('数据库结构完整，无需修复');
      }

      // 修复：检查并创建必要的索引
      await _ensureRequiredIndexes(db);
    } catch (e) {
      logDebug('检查数据库结构时出错: $e');
    }
  }

  /// 修复：确保必要的索引存在
  Future<void> _ensureRequiredIndexes(Database db) async {
    try {
      final requiredIndexes = {
        'idx_quotes_category_id':
            'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
        'idx_quotes_date':
            'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
        'idx_quotes_weather':
            'CREATE INDEX IF NOT EXISTS idx_quotes_weather ON quotes(weather)',
        'idx_quotes_day_period':
            'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
      };

      // 获取当前存在的索引
      final existingIndexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='quotes'",
      );
      final existingIndexNames = existingIndexes
          .map((idx) => idx['name'] as String)
          .where((name) => !name.startsWith('sqlite_')) // 排除系统索引
          .toSet();

      logDebug('当前存在的索引: $existingIndexNames');

      // 创建缺失的索引
      for (final entry in requiredIndexes.entries) {
        if (!existingIndexNames.contains(entry.key)) {
          try {
            await db.execute(entry.value);
            logDebug('成功创建索引: ${entry.key}');
          } catch (e) {
            logDebug('创建索引 ${entry.key} 失败: $e');
          }
        }
      }
    } catch (e) {
      logError('检查索引时出错: $e', error: e, source: 'DatabaseStructureCheck');
    }
  }

  /// 监听笔记列表，支持分页加载和筛选
  /// 检查并迁移天气数据
  Future<void> _checkAndMigrateWeatherData(Database db) async {
    try {
      final weatherCheck = await db.query(
        'quotes',
        where: 'weather IS NOT NULL AND weather != ""',
        limit: 1,
      );

      if (weatherCheck.isNotEmpty) {
        final weather = weatherCheck.first['weather'] as String?;
        if (weather != null &&
            WeatherService.legacyWeatherKeyToLabel.values.contains(weather)) {
          logDebug('检测到未迁移的weather数据，开始迁移...');
          await migrateWeatherToKey(db);
        }
      }
    } catch (e) {
      logDebug('天气数据迁移检查失败: $e');
    }
  }

  /// 检查并迁移时间段数据
  Future<void> _checkAndMigrateDayPeriodData(Database db) async {
    try {
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
          logDebug('检测到未迁移的day_period数据，开始迁移...');
          await migrateDayPeriodToKey(db);
        }
      }
    } catch (e) {
      logDebug('时间段数据迁移检查失败: $e');
    }
  }

  /// 批量为旧笔记补全 dayPeriod 字段（根据 date 字段推算并写入）
  Future<void> patchQuotesDayPeriod(Database? db) async {
    try {
      // 检查数据库是否已初始化 - 在初始化过程中允许执行
      if (db == null) {
        throw Exception('数据库未初始化，无法执行 day_period 字段补全');
      }

      // 优化：使用原生 SQL 批量更新，避免 Dart 层面的大量数据传输和循环处理
      // 逻辑与 TimeUtils 及 Dart 实现保持一致：
      // 05-07: dawn, 08-11: morning, 12-16: afternoon,
      // 17-19: dusk, 20-22: evening, 其他: midnight
      final count = await db.rawUpdate('''
        UPDATE quotes
        SET day_period = CASE
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 5 AND CAST(strftime('%H', date) AS INTEGER) < 8 THEN 'dawn'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 8 AND CAST(strftime('%H', date) AS INTEGER) < 12 THEN 'morning'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 12 AND CAST(strftime('%H', date) AS INTEGER) < 17 THEN 'afternoon'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 17 AND CAST(strftime('%H', date) AS INTEGER) < 20 THEN 'dusk'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 20 AND CAST(strftime('%H', date) AS INTEGER) < 23 THEN 'evening'
          ELSE 'midnight'
        END
        WHERE (day_period IS NULL OR day_period = '')
          AND date IS NOT NULL
          AND date != ''
          AND strftime('%H', date) IS NOT NULL
      ''');

      if (count > 0) {
        logDebug('已批量补全 $count 条记录的 day_period 字段');
      } else {
        logDebug('没有需要补全 day_period 字段的记录');
      }
    } catch (e) {
      logDebug('补全 day_period 字段失败: $e');
      rethrow;
    }
  }

  /// 修复：安全迁移旧数据dayPeriod字段为英文key
  Future<void> migrateDayPeriodToKey(Database? db) async {
    try {
      // 检查数据库是否已初始化 - 在初始化过程中允许执行
      if (db == null) {
        throw Exception('数据库未初始化，无法执行 dayPeriod 字段迁移');
      }

      // 修复：使用事务保护迁移过程
      await db.transaction((txn) async {
        // 1. 创建备份列
        try {
          await txn.execute(
            'ALTER TABLE quotes ADD COLUMN day_period_backup TEXT',
          );

          // 2. 备份原始数据
          await txn.execute(
            'UPDATE quotes SET day_period_backup = day_period WHERE day_period IS NOT NULL',
          );

          logDebug('day_period字段备份完成');
        } catch (e) {
          // 如果列已存在，继续执行
          logDebug('day_period_backup列可能已存在: $e');
        }

        final labelToKey = TimeUtils.dayPeriodKeyToLabel.map(
          (k, v) => MapEntry(v, k),
        );

        // 3. 查询需要迁移的数据
        // 性能优化：仅查询值为中文标签的记录
        final legacyLabels = labelToKey.keys.toList();
        final placeholders = List.filled(legacyLabels.length, '?').join(',');
        final List<Map<String, dynamic>> maps = await txn.query(
          'quotes',
          columns: ['id', 'day_period'],
          where: 'day_period IN ($placeholders)',
          whereArgs: legacyLabels,
        );

        if (maps.isEmpty) {
          logDebug('没有需要迁移 dayPeriod 字段的记录');
          return;
        }

        int migratedCount = 0;
        int skippedCount = 0;

        // 使用 Batch 批量更新
        final batch = txn.batch();

        for (final map in maps) {
          final id = map['id'] as String?;
          final dayPeriod = map['day_period'] as String?;

          if (id == null || dayPeriod == null || dayPeriod.isEmpty) continue;

          if (labelToKey.containsKey(dayPeriod)) {
            final key = labelToKey[dayPeriod]!;
            batch.update(
              'quotes',
              {'day_period': key},
              where: 'id = ?',
              whereArgs: [id],
            );
            migratedCount++;
          } else {
            skippedCount++;
          }
        }

        if (migratedCount > 0) {
          await batch.commit(noResult: true);
        }

        logDebug('dayPeriod字段迁移完成：转换 $migratedCount 条，跳过 $skippedCount 条');

        // 4. 验证迁移结果
        final verifyCount = await txn.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE day_period IS NOT NULL',
        );
        final totalAfter = verifyCount.first['count'] as int;

        if (totalAfter >= migratedCount) {
          logDebug('dayPeriod字段迁移验证通过');
        } else {
          throw Exception('dayPeriod字段迁移验证失败');
        }
      });
    } catch (e) {
      logError('迁移 dayPeriod 字段失败: $e', error: e, source: 'DatabaseService');
      rethrow;
    }
  }

  /// 修复：安全迁移旧数据weather字段为英文key
  Future<void> migrateWeatherToKey(
    Database? db, {
    List<Quote> memoryStore = const [],
  }) async {
    try {
      if (kIsWeb) {
        int migratedCount = 0;
        for (var i = 0; i < memoryStore.length; i++) {
          final q = memoryStore[i];
          if (q.weather != null &&
              WeatherService.legacyWeatherKeyToLabel.values.contains(
                q.weather,
              )) {
            final key = WeatherService.legacyWeatherKeyToLabel.entries
                .firstWhere((e) => e.value == q.weather)
                .key;
            memoryStore[i] = q.copyWith(weather: key);
            migratedCount++;
          }
        }
        // 注意：notifyListeners 由调用方 DatabaseService 负责
        logDebug('Web平台已完成 $migratedCount 条记录的 weather 字段 key 迁移');
        return;
      }

      // 检查数据库是否已初始化 - 在初始化过程中允许执行
      if (db == null) {
        throw Exception('数据库未初始化，无法执行 weather 字段迁移');
      }

      // 修复：使用事务保护迁移过程
      await db.transaction((txn) async {
        // 1. 创建备份列
        try {
          await txn.execute(
            'ALTER TABLE quotes ADD COLUMN weather_backup TEXT',
          );

          // 2. 备份原始数据
          await txn.execute(
            'UPDATE quotes SET weather_backup = weather WHERE weather IS NOT NULL',
          );

          logDebug('weather字段备份完成');
        } catch (e) {
          // 如果列已存在，继续执行
          logDebug('weather_backup列可能已存在: $e');
        }

        // 3. 查询需要迁移的数据
        // 性能优化：仅查询值为中文标签的记录
        // 使用参数化查询而不是字符串拼接，防止潜在的 SQL 注入问题
        final weatherLabels =
            WeatherService.legacyWeatherKeyToLabel.values.toList();
        if (weatherLabels.isEmpty) {
          logDebug('没有需要迁移的 weather 标签');
          return;
        }
        final placeholders = List.filled(weatherLabels.length, '?').join(',');
        final maps = await txn.query(
          'quotes',
          columns: ['id', 'weather'],
          where: 'weather IN ($placeholders)',
          whereArgs: weatherLabels,
        );

        if (maps.isEmpty) {
          logDebug('没有需要迁移 weather 字段的记录');
          return;
        }

        int migratedCount = 0;
        int skippedCount = 0;

        // 使用 Batch 批量更新
        final batch = txn.batch();

        for (final m in maps) {
          final id = m['id'] as String?;
          final weather = m['weather'] as String?;

          if (id == null || weather == null || weather.isEmpty) continue;

          // 检查是否需要迁移（是否为中文标签）
          if (WeatherService.legacyWeatherKeyToLabel.values.contains(weather)) {
            final key = WeatherService.legacyWeatherKeyToLabel.entries
                .firstWhere((e) => e.value == weather)
                .key;

            batch.update(
              'quotes',
              {'weather': key},
              where: 'id = ?',
              whereArgs: [id],
            );
            migratedCount++;
          } else {
            skippedCount++;
          }
        }

        if (migratedCount > 0) {
          await batch.commit(noResult: true);
        }

        logDebug('weather字段迁移完成：转换 $migratedCount 条，跳过 $skippedCount 条');

        // 4. 验证迁移结果
        final verifyCount = await txn.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE weather IS NOT NULL',
        );
        final totalAfter = verifyCount.first['count'] as int;

        if (totalAfter >= migratedCount) {
          logDebug('weather字段迁移验证通过');
        } else {
          throw Exception('weather字段迁移验证失败');
        }
      });
    } catch (e) {
      logError('迁移 weather 字段失败: $e', error: e, source: 'DatabaseService');
      rethrow;
    }
  }

  /// 优化：在初始化阶段执行所有数据迁移
  /// 兼容性保证：所有迁移都是向后兼容的，不会破坏现有数据
  Future<void> performAllDataMigrations(Database? db) async {
    if (kIsWeb) return; // Web平台无需数据迁移

    try {
      // 首先检查数据库是否可用
      if (db == null) {
        logError('数据库不可用，跳过数据迁移操作', source: 'DatabaseService');
        return;
      }

      logDebug('开始执行数据迁移...');

      // 兼容性检查：验证数据库结构完整性（仅在非新建数据库时执行）
      try {
        await _validateDatabaseCompatibility(db);
      } catch (e) {
        logDebug('数据库兼容性验证跳过: $e');
        // 如果验证失败，可能是新数据库，继续执行其他迁移
      }

      // 检查并迁移天气数据
      await _checkAndMigrateWeatherData(db);

      // 检查并迁移时间段数据
      await _checkAndMigrateDayPeriodData(db);

      // 补全缺失的时间段数据
      await patchQuotesDayPeriod(db);

      // 修复：检查并清理遗留的tag_ids列
      await cleanupLegacyTagIdsColumn(db);

      logDebug('所有数据迁移完成');
    } catch (e) {
      logError('数据迁移失败: $e', error: e, source: 'DatabaseService');
      // 不重新抛出异常，避免影响应用启动
    }
  }

  /// 兼容性验证：检查数据库结构完整性
  Future<void> _validateDatabaseCompatibility(Database db) async {
    try {
      // 检查关键表是否存在
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      final requiredTables = {'quotes', 'categories', 'quote_tags'};
      final missingTables = requiredTables.difference(tableNames);

      if (missingTables.isNotEmpty) {
        logError('缺少必要的数据库表: $missingTables', source: 'DatabaseService');
        throw Exception('数据库结构不完整，缺少表: $missingTables');
      }

      // 检查quote_tags表的数据完整性
      final quoteTagsCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM quote_tags',
      );

      // 修复：检查quotes表中是否还有tag_ids列，如果有则说明迁移未完成
      final tableInfo = await db.rawQuery('PRAGMA table_info(quotes)');
      final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

      if (hasTagIdsColumn) {
        // 如果还有tag_ids列，检查是否有数据需要迁移
        final quotesWithTagsCount = await db.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE tag_ids IS NOT NULL AND tag_ids != ""',
        );
        logDebug(
          '兼容性检查完成 - quote_tags表记录数: ${quoteTagsCount.first['count']}, '
          '有tag_ids列的quotes记录数: ${quotesWithTagsCount.first['count']}',
        );
      } else {
        logDebug(
          '兼容性检查完成 - quote_tags表记录数: ${quoteTagsCount.first['count']}, '
          'tag_ids列已迁移完成',
        );
      }
    } catch (e) {
      logError('数据库兼容性验证失败: $e', error: e, source: 'DatabaseService');
      // 不抛出异常，让应用继续运行
    }
  }
}
