import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../utils/app_logger.dart';

class DatabaseHealthService {
  /// 修复：添加查询性能统计
  final Map<String, int> _queryStats = {}; // 查询次数统计
  final Map<String, int> _queryTotalTime = {}; // 查询总耗时统计
  int _totalQueries = 0;
  int _cacheHits = 0;

  void recordQueryStats(String queryType, int elapsedMs) {
    _totalQueries++;
    _queryStats[queryType] = (_queryStats[queryType] ?? 0) + 1;
    _queryTotalTime[queryType] = (_queryTotalTime[queryType] ?? 0) + elapsedMs;
  }

  void recordCacheHit() {
    _cacheHits++;
  }

  /// 修复：获取查询性能报告
  Map<String, dynamic> getQueryPerformanceReport() {
    final report = <String, dynamic>{
      'totalQueries': _totalQueries,
      'cacheHits': _cacheHits,
      'cacheHitRate': _totalQueries > 0
          ? '${(_cacheHits / _totalQueries * 100).toStringAsFixed(2)}%'
          : '0%',
      'queryTypes': <String, dynamic>{},
    };

    for (final entry in _queryStats.entries) {
      final queryType = entry.key;
      final count = entry.value;
      final totalTime = _queryTotalTime[queryType] ?? 0;
      final avgTime = count > 0 ? (totalTime / count).toStringAsFixed(2) : '0';

      report['queryTypes'][queryType] = {
        'count': count,
        'totalTime': '${totalTime}ms',
        'avgTime': '${avgTime}ms',
      };
    }

    return report;
  }

  /// 安全验证：检查标识符（表名、列名、索引名）是否合法，防止 SQL 注入
  bool _isValidIdentifier(String identifier) {
    final regex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    return regex.hasMatch(identifier);
  }

  /// 修复：安全地创建索引，检查列是否存在
  Future<void> createIndexSafely(
    Database db,
    String tableName,
    String columnName,
    String indexName,
  ) async {
    if (!_isValidIdentifier(tableName) ||
        !_isValidIdentifier(columnName) ||
        !_isValidIdentifier(indexName)) {
      logDebug('发现不合法的标识符，跳过索引创建: $tableName, $columnName, $indexName');
      return;
    }
    try {
      // 检查列是否存在
      final columnExists = await checkColumnExists(db, tableName, columnName);
      if (!columnExists) {
        logDebug('列 $columnName 不存在于表 $tableName 中，跳过索引创建');
        return;
      }

      // 创建索引
      await db.execute(
        'CREATE INDEX IF NOT EXISTS $indexName ON $tableName($columnName)',
      );
      logDebug('索引 $indexName 创建成功');
    } catch (e) {
      logDebug('创建索引 $indexName 失败: $e');
    }
  }

  /// 修复：检查列是否存在
  Future<bool> checkColumnExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    if (!_isValidIdentifier(tableName) || !_isValidIdentifier(columnName)) {
      logDebug('发现不合法的标识符，跳过列检查: $tableName, $columnName');
      return false;
    }
    try {
      final result = await db.rawQuery(
        'SELECT name FROM pragma_table_info(?)',
        [tableName],
      );
      for (final row in result) {
        if (row['name'] == columnName) {
          return true;
        }
      }
      return false;
    } catch (e) {
      logDebug('检查列 $columnName 是否存在失败: $e');
      return false;
    }
  }

  /// 启动时执行数据库健康检查
  Future<void> performStartupHealthCheck(Database db) async {
    if (kIsWeb) {
      logDebug('Web平台跳过数据库健康检查');
      return;
    }

    try {
      logDebug('开始数据库健康检查...');

      // 1. 验证外键约束状态
      final foreignKeysResult = await db.rawQuery('PRAGMA foreign_keys');
      final foreignKeysEnabled = foreignKeysResult.isNotEmpty &&
          foreignKeysResult.first['foreign_keys'] == 1;

      // 2. 获取数据库版本
      final dbVersion = await db.getVersion();

      // 3. 获取基本统计
      final quoteCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM quotes',
      );
      final quoteCount = quoteCountResult.first['count'] as int;

      final categoryCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM categories',
      );
      final categoryCount = categoryCountResult.first['count'] as int;

      final tagRelationCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM quote_tags',
      );
      final tagRelationCount = tagRelationCountResult.first['count'] as int;

      // 4. 记录健康状态
      logDebug('''
========================================
数据库健康检查报告
========================================
版本: v$dbVersion
外键约束: ${foreignKeysEnabled ? '✅ 已启用' : '⚠️ 未启用'}
笔记数量: $quoteCount
分类数量: $categoryCount
标签关联: $tagRelationCount
========================================
      ''');

      // 5. 如果发现问题，记录警告
      if (!foreignKeysEnabled) {
        logError('⚠️ 警告：外键约束未启用，可能影响数据完整性', source: 'DatabaseHealthCheck');
      }
    } catch (e) {
      logError('数据库健康检查失败: $e', error: e, source: 'DatabaseHealthCheck');
      // 健康检查失败不应阻止应用启动
    }
  }

  /// 修复：标签数据一致性检查
  Future<Map<String, dynamic>> checkTagDataConsistency(Database db) async {
    try {
      final report = <String, dynamic>{
        'orphanedQuoteTags': 0,
        'orphanedCategoryReferences': 0,
        'duplicateTagRelations': 0,
        'issues': <String>[],
      };

      // 1. 检查孤立的quote_tags记录（引用不存在的quote_id）
      final orphanedQuoteTags = await db.rawQuery('''
        SELECT qt.quote_id, qt.tag_id
        FROM quote_tags qt
        LEFT JOIN quotes q ON qt.quote_id = q.id
        WHERE q.id IS NULL
      ''');

      report['orphanedQuoteTags'] = orphanedQuoteTags.length;
      if (orphanedQuoteTags.isNotEmpty) {
        report['issues'].add('发现 ${orphanedQuoteTags.length} 条孤立的标签关联记录');
      }

      // 2. 检查孤立的quote_tags记录（引用不存在的tag_id）
      final orphanedTagRefs = await db.rawQuery('''
        SELECT qt.quote_id, qt.tag_id
        FROM quote_tags qt
        LEFT JOIN categories c ON qt.tag_id = c.id
        WHERE c.id IS NULL
      ''');

      report['orphanedCategoryReferences'] = orphanedTagRefs.length;
      if (orphanedTagRefs.isNotEmpty) {
        report['issues'].add('发现 ${orphanedTagRefs.length} 条引用不存在分类的标签关联');
      }

      // 3. 检查重复的标签关联
      final duplicateRelations = await db.rawQuery('''
        SELECT quote_id, tag_id, COUNT(*) as count
        FROM quote_tags
        GROUP BY quote_id, tag_id
        HAVING COUNT(*) > 1
      ''');

      report['duplicateTagRelations'] = duplicateRelations.length;
      if (duplicateRelations.isNotEmpty) {
        report['issues'].add('发现 ${duplicateRelations.length} 组重复的标签关联');
      }

      // 4. 检查笔记的category_id是否存在对应的分类
      final invalidCategoryRefs = await db.rawQuery('''
        SELECT q.id, q.category_id
        FROM quotes q
        LEFT JOIN categories c ON q.category_id = c.id
        WHERE q.category_id IS NOT NULL AND q.category_id != '' AND c.id IS NULL
      ''');

      if (invalidCategoryRefs.isNotEmpty) {
        report['issues'].add('发现 ${invalidCategoryRefs.length} 条笔记引用了不存在的分类');
      }

      return report;
    } catch (e) {
      logDebug('标签数据一致性检查失败: $e');
      return {
        'error': e.toString(),
        'issues': ['检查过程中发生错误'],
      };
    }
  }

  /// 修复：清理标签数据不一致问题
  Future<bool> cleanupTagDataInconsistencies(Database db) async {
    try {
      int cleanedCount = 0;

      await db.transaction((txn) async {
        // 1. 清理孤立的quote_tags记录（引用不存在的quote_id）
        final orphanedQuoteTagsCount = await txn.rawDelete('''
          DELETE FROM quote_tags
          WHERE quote_id NOT IN (SELECT id FROM quotes)
        ''');
        cleanedCount += orphanedQuoteTagsCount;

        // 2. 清理孤立的quote_tags记录（引用不存在的tag_id）
        final orphanedTagRefsCount = await txn.rawDelete('''
          DELETE FROM quote_tags
          WHERE tag_id NOT IN (SELECT id FROM categories)
        ''');
        cleanedCount += orphanedTagRefsCount;

        // 3. 清理重复的标签关联（保留一条）
        await txn.rawDelete('''
          DELETE FROM quote_tags
          WHERE rowid NOT IN (
            SELECT MIN(rowid)
            FROM quote_tags
            GROUP BY quote_id, tag_id
          )
        ''');

        // 4. 清理笔记中无效的category_id引用
        final invalidCategoryCount = await txn.rawUpdate('''
          UPDATE quotes
          SET category_id = NULL
          WHERE category_id IS NOT NULL
          AND category_id != ''
          AND category_id NOT IN (SELECT id FROM categories)
        ''');
        cleanedCount += invalidCategoryCount;
      });

      logDebug('标签数据清理完成，共处理 $cleanedCount 条记录');

      return true;
    } catch (e) {
      logDebug('标签数据清理失败: $e');
      return false;
    }
  }

  /// 获取适合作为每日一言的本地笔记
  /// 优先选择带有"每日一言"标签的笔记，然后选择较短的笔记
  Future<Map<String, dynamic>?> getLocalDailyQuote(
    Database db, {
    List<Quote>? memoryStore,
    List<NoteCategory>? categoryStore,
  }) async {
    try {
      if (kIsWeb) {
        if (memoryStore == null || categoryStore == null) {
          return null;
        }
        return _getLocalQuoteFromMemory(memoryStore, categoryStore);
      }

      // 首先尝试获取带有"每日一言"标签的笔记
      final dailyQuoteCategory = await _getDailyQuoteCategoryId(db);
      List<Map<String, dynamic>> results = [];

      if (dailyQuoteCategory != null) {
        results = await db.rawQuery(
          '''
          SELECT DISTINCT q.* FROM quotes q
          INNER JOIN quote_tags qt ON q.id = qt.quote_id
          INNER JOIN categories c ON qt.tag_id = c.id
          WHERE c.id = ? AND length(q.content) <= 100
          ORDER BY RANDOM()
          LIMIT 1
        ''',
          [dailyQuoteCategory],
        );
      }

      // 如果没有找到带"每日一言"标签的笔记，选择较短的其他笔记
      if (results.isEmpty) {
        results = await db.rawQuery('''
          SELECT * FROM quotes
          WHERE length(content) <= 80 AND content NOT LIKE '%\n%'
          ORDER BY RANDOM()
          LIMIT 1
        ''');
      }

      if (results.isNotEmpty) {
        final quote = results.first;
        return {
          'content': quote['content'],
          'source': quote['source_work'] ?? '',
          'author': quote['source_author'] ?? '',
          'type': 'local',
          'from_who': quote['source_author'] ?? '',
          'from': quote['source_work'] ?? '',
        };
      }

      return null;
    } catch (e) {
      logDebug('获取本地每日一言失败: $e');
      return null;
    }
  }

  /// 手动触发数据库维护（VACUUM + ANALYZE）
  /// 应在存储管理页面由用户主动触发，带进度提示
  /// 返回维护结果和统计信息
  Future<Map<String, dynamic>> performDatabaseMaintenance(
    Database db, {
    Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return {'success': true, 'message': 'Web平台无需数据库维护', 'skipped': true};
    }

    final stopwatch = Stopwatch()..start();
    final result = <String, dynamic>{
      'success': false,
      'message': '',
      'duration_ms': 0,
      'db_size_before_mb': 0.0,
      'db_size_after_mb': 0.0,
      'space_saved_mb': 0.0,
    };

    try {
      // 获取数据库文件路径
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'thoughtecho.db');
      final dbFile = File(path);

      // 记录维护前的文件大小
      if (await dbFile.exists()) {
        final sizeBefore = await dbFile.length();
        result['db_size_before_mb'] = sizeBefore / (1024 * 1024);
      }

      onProgress?.call('正在更新数据库统计信息...');
      logDebug('开始数据库维护：ANALYZE');

      // 1. 更新统计信息（快速，优先执行）
      await db.execute('ANALYZE');

      onProgress?.call('正在整理数据库碎片...');
      logDebug('开始数据库维护：VACUUM');

      // 2. 清理碎片（可能较慢）
      // VACUUM会自动使用事务保护，中途中断会回滚
      await db.execute('VACUUM');

      onProgress?.call('正在优化索引...');
      logDebug('开始数据库维护：REINDEX');

      // 3. 重建索引
      await db.execute('REINDEX');

      // 记录维护后的文件大小
      if (await dbFile.exists()) {
        final sizeAfter = await dbFile.length();
        result['db_size_after_mb'] = sizeAfter / (1024 * 1024);
        result['space_saved_mb'] =
            result['db_size_before_mb'] - result['db_size_after_mb'];
      }

      result['success'] = true;
      result['message'] = '数据库维护完成';
      onProgress?.call('维护完成！');
    } catch (e) {
      result['message'] = '维护失败: $e';
      logError('数据库维护失败: $e', error: e, source: 'DatabaseService');
    } finally {
      stopwatch.stop();
      result['duration_ms'] = stopwatch.elapsedMilliseconds;
      logDebug(
        '数据库维护结束，耗时${result['duration_ms']}ms，'
        '释放空间${result['space_saved_mb'].toStringAsFixed(2)}MB，状态: ${result['success']}',
      );
    }

    return result;
  }

  /// 获取数据库健康状态信息
  Future<Map<String, dynamic>> getDatabaseHealthInfo(
    Database db, {
    int webQuoteCount = 0,
    int webCategoryCount = 0,
  }) async {
    if (kIsWeb) {
      return {
        'platform': 'web',
        'db_size_mb': 0.0,
        'quote_count': webQuoteCount,
        'category_count': webCategoryCount,
      };
    }

    try {
      // 获取数据库文件大小
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'thoughtecho.db');
      final dbFile = File(path);
      double dbSizeMb = 0.0;

      if (await dbFile.exists()) {
        final size = await dbFile.length();
        dbSizeMb = size / (1024 * 1024);
      }

      // 获取记录数量
      final quoteCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM quotes',
      );
      final quoteCount = quoteCountResult.first['count'] as int;

      final categoryCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM categories',
      );
      final categoryCount = categoryCountResult.first['count'] as int;

      final tagRelationCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM quote_tags',
      );
      final tagRelationCount = tagRelationCountResult.first['count'] as int;

      // 检查外键约束状态
      final foreignKeysResult = await db.rawQuery('PRAGMA foreign_keys');
      final foreignKeysEnabled = foreignKeysResult.first['foreign_keys'] == 1;

      // 获取日志模式
      final journalModeResult = await db.rawQuery('PRAGMA journal_mode');
      final journalMode = journalModeResult.first['journal_mode'];

      return {
        'platform': Platform.operatingSystem,
        'db_size_mb': dbSizeMb,
        'quote_count': quoteCount,
        'category_count': categoryCount,
        'tag_relation_count': tagRelationCount,
        'foreign_keys_enabled': foreignKeysEnabled,
        'journal_mode': journalMode,
        'cache_hit_rate': _totalQueries > 0 ? _cacheHits / _totalQueries : 0.0,
        'total_queries': _totalQueries,
      };
    } catch (e) {
      logError('获取数据库健康信息失败: $e', error: e, source: 'DatabaseService');
      return {'error': e.toString()};
    }
  }

  /// Web平台从内存中获取本地一言
  Map<String, dynamic>? _getLocalQuoteFromMemory(
    List<Quote> memoryStore,
    List<NoteCategory> categoryStore,
  ) {
    try {
      // 首先尝试获取带有"每日一言"标签的笔记
      var candidates = memoryStore
          .where(
            (quote) =>
                quote.tagIds.any(
                  (tagId) => categoryStore.any(
                    (cat) => cat.id == tagId && cat.name == '每日一言',
                  ),
                ) &&
                quote.content.length <= 100,
          )
          .toList();

      // 如果没有找到，选择较短的其他笔记
      if (candidates.isEmpty) {
        candidates = memoryStore
            .where(
              (quote) =>
                  quote.content.length <= 80 && !quote.content.contains('\n'),
            )
            .toList();
      }

      if (candidates.isNotEmpty) {
        final random =
            DateTime.now().millisecondsSinceEpoch % candidates.length;
        final quote = candidates[random];
        return {
          'content': quote.content,
          'source': quote.sourceWork ?? '',
          'author': quote.sourceAuthor ?? '',
          'type': 'local',
          'from_who': quote.sourceAuthor ?? '',
          'from': quote.sourceWork ?? '',
        };
      }

      return null;
    } catch (e) {
      logDebug('从内存获取本地每日一言失败: $e');
      return null;
    }
  }

  /// 获取"每日一言"分类的ID
  Future<String?> _getDailyQuoteCategoryId(Database db) async {
    try {
      final results = await db.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['每日一言'],
        limit: 1,
      );

      return results.isNotEmpty ? results.first['id'] as String : null;
    } catch (e) {
      logDebug('获取每日一言分类ID失败: $e');
      return null;
    }
  }
}