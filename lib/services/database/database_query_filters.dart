part of '../database_service.dart';

/// DatabaseQueryFilterOperations for DatabaseService.
extension DatabaseQueryFilterOperations on DatabaseService {

  /// 获取笔记列表，支持标签、分类、搜索、天气和时间段筛选
  /// 修复：获取用户笔记，增加初始化状态检查
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers, // 天气筛选
    List<String>? selectedDayPeriods, // 时间段筛选
    bool excludeHiddenNotes = true, // 默认排除隐藏笔记
  }) async {
    try {
      // 修复：确保数据库已完全初始化
      if (!_isInitialized) {
        logDebug('数据库尚未初始化，等待初始化完成...');
        if (_isInitializing && _initCompleter != null) {
          await _initCompleter!.future;
        } else {
          await init();
        }
      }

      // 优化：定期清理缓存而不是每次查询都清理
      _scheduleCacheCleanup();

      // 判断是否正在查询隐藏标签
      final isQueryingHiddenTag =
          tagIds != null && tagIds.contains(hiddenTagId);
      // 如果正在查询隐藏标签，则不排除隐藏笔记
      final shouldExcludeHidden = excludeHiddenNotes && !isQueryingHiddenTag;

      if (kIsWeb) {
        // Web平台的完整筛选逻辑
        var filtered = _memoryStore;

        // 排除隐藏笔记（除非正在查询隐藏标签）
        if (shouldExcludeHidden) {
          filtered =
              filtered.where((q) => !q.tagIds.contains(hiddenTagId)).toList();
        }

        if (tagIds != null && tagIds.isNotEmpty) {
          filtered = filtered
              .where((q) => q.tagIds.any((tag) => tagIds.contains(tag)))
              .toList();
        }
        if (categoryId != null && categoryId.isNotEmpty) {
          filtered = filtered.where((q) => q.categoryId == categoryId).toList();
        }
        if (searchQuery != null && searchQuery.isNotEmpty) {
          final query = searchQuery.toLowerCase();
          filtered = filtered
              .where(
                (q) =>
                    q.content.toLowerCase().contains(query) ||
                    (q.source?.toLowerCase().contains(query) ?? false) ||
                    (q.sourceAuthor?.toLowerCase().contains(query) ?? false) ||
                    (q.sourceWork?.toLowerCase().contains(query) ?? false),
              )
              .toList();
        }
        if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
          filtered = filtered
              .where(
                (q) =>
                    q.weather != null && selectedWeathers.contains(q.weather),
              )
              .toList();
        }
        if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
          filtered = filtered
              .where(
                (q) =>
                    q.dayPeriod != null &&
                    selectedDayPeriods.contains(q.dayPeriod),
              )
              .toList();
        }

        // 排序（支持日期、喜爱度、名称）
        filtered.sort((a, b) {
          if (orderBy.startsWith('date')) {
            final dateA = DateTime.tryParse(a.date) ?? DateTime.now();
            final dateB = DateTime.tryParse(b.date) ?? DateTime.now();
            return orderBy.contains('ASC')
                ? dateA.compareTo(dateB)
                : dateB.compareTo(dateA);
          } else if (orderBy.startsWith('favorite_count')) {
            return orderBy.contains('ASC')
                ? a.favoriteCount.compareTo(b.favoriteCount)
                : b.favoriteCount.compareTo(a.favoriteCount);
          } else {
            return orderBy.contains('ASC')
                ? a.content.compareTo(b.content)
                : b.content.compareTo(a.content);
          }
        });

        // 分页 - 修复：确保正确处理边界情况
        final start = offset.clamp(0, filtered.length);
        final end = (offset + limit).clamp(0, filtered.length);

        logDebug(
          'Web分页：总数据${filtered.length}条，offset=$offset，limit=$limit，start=$start，end=$end',
        );

        // 如果起始位置已经超出数据范围，直接返回空列表
        if (start >= filtered.length) {
          logDebug('起始位置超出范围，返回空列表');
          return [];
        }

        final result = filtered.sublist(start, end);
        logDebug('Web分页返回${result.length}条数据');
        return result;
      }

      // 修复：统一查询超时时间和重试机制
      return await _executeQueryWithRetry(() async {
        final db = await safeDatabase; // 使用安全的数据库访问
        return await _performDatabaseQuery(
          db: db,
          tagIds: tagIds,
          categoryId: categoryId,
          searchQuery: searchQuery,
          selectedWeathers: selectedWeathers,
          selectedDayPeriods: selectedDayPeriods,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
          excludeHiddenNotes: shouldExcludeHidden,
        );
      });
    } catch (e) {
      logError('获取笔记失败: $e', error: e, source: 'DatabaseService');
      return [];
    }
  }

  /// 修复：带重试机制的查询执行


  /// 智能推送专用轻量查询
  ///
  /// 不加载大字段（delta_content, ai_analysis, summary, keywords），
  /// 不 JOIN tag 表，专为后台 isolate 设计，低内存开销。
  Future<List<Quote>> getQuotesForSmartPush({
    String? whereSql,
    List<Object?>? whereArgs,
    int limit = 200,
    String orderBy = 'q.date DESC',
  }) async {
    try {
      if (!_isInitialized) {
        if (_isInitializing && _initCompleter != null) {
          await _initCompleter!.future;
        } else {
          await init();
        }
      }

      if (kIsWeb) {
        // Web 平台降级：使用内存存储
        var filtered = _memoryStore;
        filtered.sort((a, b) {
          final dateA = DateTime.tryParse(a.date) ?? DateTime.now();
          final dateB = DateTime.tryParse(b.date) ?? DateTime.now();
          return dateB.compareTo(dateA);
        });
        return filtered.take(limit).toList();
      }

      final db = await safeDatabase;

      final conditions = <String>[];
      final args = <Object?>[];

      // 排除隐藏笔记
      conditions.add('''
        NOT EXISTS (
          SELECT 1 FROM quote_tags qt_hidden
          WHERE qt_hidden.quote_id = q.id
          AND qt_hidden.tag_id = ?
        )
      ''');
      args.add(hiddenTagId);

      if (whereSql != null && whereSql.isNotEmpty) {
        conditions.add(whereSql);
        if (whereArgs != null) {
          args.addAll(whereArgs);
        }
      }

      final where =
          conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

      // 只取必要列，不取 delta_content/ai_analysis/summary/keywords
      final query = '''
        SELECT q.id, q.content, q.date, q.source, q.source_author, q.source_work,
               q.category_id, q.color_hex, q.location, q.latitude, q.longitude,
               q.weather, q.temperature, q.edit_source, q.day_period,
               q.last_modified, q.favorite_count
        FROM quotes q
        $where
        ORDER BY $orderBy
        LIMIT ?
      ''';
      args.add(limit);

      final maps = await db.rawQuery(query, args.whereType<Object>().toList());
      return maps.map((m) => Quote.fromJson(m)).toList();
    } catch (e) {
      logError(
        'getQuotesForSmartPush 失败: $e',
        error: e,
        source: 'DatabaseService',
      );
      return [];
    }
  }

  /// 智能推送专用：获取笔记创建时间的小时分布（纯聚合，不加载内容）


  /// 智能推送专用：获取笔记创建时间的小时分布（纯聚合，不加载内容）
  Future<List<int>> getHourDistributionForSmartPush() async {
    final distribution = List<int>.filled(24, 0);
    try {
      if (!_isInitialized) {
        if (_isInitializing && _initCompleter != null) {
          await _initCompleter!.future;
        } else {
          await init();
        }
      }

      if (kIsWeb) {
        for (final note in _memoryStore) {
          final d = DateTime.tryParse(note.date);
          if (d != null) distribution[d.hour]++;
        }
        return distribution;
      }

      final db = await safeDatabase;
      final maps = await db.rawQuery('''
        SELECT CAST(substr(date, 12, 2) AS INTEGER) AS h, COUNT(*) AS c
        FROM quotes
        GROUP BY h
      ''');
      for (final row in maps) {
        final h = (row['h'] as int?) ?? 0;
        final c = (row['c'] as int?) ?? 0;
        if (h >= 0 && h < 24) {
          distribution[h] = c;
        }
      }
    } catch (e) {
      logError(
        'getHourDistributionForSmartPush 失败: $e',
        error: e,
        source: 'DatabaseService',
      );
    }
    return distribution;
  }

  /// 修复：获取查询性能报告


  /// 修复：获取查询性能报告
  Map<String, dynamic> getQueryPerformanceReport() {
    return _healthService.getQueryPerformanceReport();
  }

  /// 修复：安全地创建索引，检查列是否存在


  /// 获取笔记总数，用于分页
  /// [excludeHiddenNotes] 是否排除隐藏笔记，默认为 true
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
  }) async {
    // 判断是否正在查询隐藏标签
    final isQueryingHiddenTag = tagIds != null && tagIds.contains(hiddenTagId);
    // 如果正在查询隐藏标签，则不排除隐藏笔记
    final shouldExcludeHidden = excludeHiddenNotes && !isQueryingHiddenTag;

    if (kIsWeb) {
      // 优化：Web平台直接在内存中应用筛选逻辑计算数量，避免加载大量数据
      var filtered = _memoryStore;

      // 排除隐藏笔记
      if (shouldExcludeHidden) {
        filtered =
            filtered.where((q) => !q.tagIds.contains(hiddenTagId)).toList();
      }

      if (tagIds != null && tagIds.isNotEmpty) {
        filtered = filtered
            .where((q) => q.tagIds.any((tag) => tagIds.contains(tag)))
            .toList();
      }

      if (categoryId != null && categoryId.isNotEmpty) {
        filtered = filtered.where((q) => q.categoryId == categoryId).toList();
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        filtered = filtered
            .where(
              (q) =>
                  q.content.toLowerCase().contains(query) ||
                  (q.source?.toLowerCase().contains(query) ?? false) ||
                  (q.sourceAuthor?.toLowerCase().contains(query) ?? false) ||
                  (q.sourceWork?.toLowerCase().contains(query) ?? false),
            )
            .toList();
      }

      if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
        filtered = filtered
            .where(
              (q) => q.weather != null && selectedWeathers.contains(q.weather),
            )
            .toList();
      }

      if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
        filtered = filtered
            .where(
              (q) =>
                  q.dayPeriod != null &&
                  selectedDayPeriods.contains(q.dayPeriod),
            )
            .toList();
      }

      return filtered.length;
    }
    try {
      final db = await safeDatabase;
      List<String> conditions = [];
      List<dynamic> args = [];

      // 排除隐藏笔记（通过 NOT EXISTS 子查询排除带有隐藏标签的笔记）
      if (shouldExcludeHidden) {
        conditions.add('''
          NOT EXISTS (
            SELECT 1 FROM quote_tags ht 
            WHERE ht.quote_id = q.id AND ht.tag_id = ?
          )
        ''');
        args.add(hiddenTagId);
      }

      // 分类筛选
      if (categoryId != null && categoryId.isNotEmpty) {
        conditions.add('q.category_id = ?');
        args.add(categoryId);
      }

      // 搜索查询
      if (searchQuery != null && searchQuery.isNotEmpty) {
        conditions.add(
          '(q.content LIKE ? OR q.source LIKE ? OR q.source_author LIKE ? OR q.source_work LIKE ?)',
        );
        final searchParam = '%$searchQuery%';
        args.addAll([searchParam, searchParam, searchParam, searchParam]);
      }

      // 天气筛选
      if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
        final weatherPlaceholders = selectedWeathers.map((_) => '?').join(',');
        conditions.add('q.weather IN ($weatherPlaceholders)');
        args.addAll(selectedWeathers);
      }

      // 时间段筛选
      if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
        final dayPeriodPlaceholders =
            selectedDayPeriods.map((_) => '?').join(',');
        conditions.add('q.day_period IN ($dayPeriodPlaceholders)');
        args.addAll(selectedDayPeriods);
      }

      String query;
      List<dynamic> finalArgs = List.from(args);

      if (tagIds != null && tagIds.isNotEmpty) {
        // 使用 INNER JOIN 和 GROUP BY 来进行计数
        final tagPlaceholders = tagIds.map((_) => '?').join(',');

        String subQuery = '''
          SELECT 1
          FROM quotes q
          INNER JOIN quote_tags qt ON q.id = qt.quote_id
        ''';

        conditions.add('qt.tag_id IN ($tagPlaceholders)');
        finalArgs.addAll(tagIds);

        final whereClause =
            conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

        String havingClause = 'HAVING COUNT(DISTINCT qt.tag_id) = ?';
        finalArgs.add(tagIds.length);

        query = '''
          SELECT COUNT(*) FROM (
            $subQuery
            $whereClause
            GROUP BY q.id
            $havingClause
          )
        ''';
      } else {
        // 没有标签筛选，使用简单的 COUNT
        final whereClause =
            conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
        query = 'SELECT COUNT(*) as count FROM quotes q $whereClause';
      }

      logDebug('执行计数查询: $query\n参数: $finalArgs');
      final result = await db.rawQuery(query, finalArgs);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      logDebug('获取笔记总数错误: $e');
      return 0;
    }
  }

  /// 修复：删除指定的笔记，增加数据验证和错误处理

}
