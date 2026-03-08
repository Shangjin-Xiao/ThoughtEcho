part of '../database_service.dart';

/// DatabaseQueryOperations for DatabaseService.
extension DatabaseQueryOperations on DatabaseService {

  /// 修复：直接查询数据库，不进行初始化状态检查，用于内部调用
  Future<List<Quote>> _directGetQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) async {
    if (kIsWeb) {
      // Web平台的完整筛选逻辑
      var filtered = _memoryStore;
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

      // 排序
      if (orderBy.contains('date')) {
        filtered.sort((a, b) {
          final aDate = DateTime.tryParse(a.date) ?? DateTime.now();
          final bDate = DateTime.tryParse(b.date) ?? DateTime.now();
          return orderBy.contains('DESC')
              ? bDate.compareTo(aDate)
              : aDate.compareTo(bDate);
        });
      } else if (orderBy.contains('content')) {
        filtered.sort((a, b) {
          return orderBy.contains('DESC')
              ? b.content.compareTo(a.content)
              : a.content.compareTo(b.content);
        });
      }

      // 分页
      final start = offset;
      final end = (start + limit).clamp(0, filtered.length);
      return filtered.sublist(start, end);
    }

    // 非Web平台直接查询数据库
    final db = _database!; // 直接使用数据库，不进行安全检查

    // 构建查询条件
    final conditions = <String>[];
    final args = <dynamic>[];

    // 标签筛选
    if (tagIds != null && tagIds.isNotEmpty) {
      final tagPlaceholders = tagIds.map((_) => '?').join(',');
      conditions.add(
        'q.id IN (SELECT quote_id FROM quote_tags WHERE tag_id IN ($tagPlaceholders))',
      );
      args.addAll(tagIds);
    }

    // 分类筛选
    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add('q.category_id = ?');
      args.add(categoryId);
    }

    // 搜索查询
    // TODO(low): 该 LIKE 搜索模式在第 696、1992、2430 行重复了 3 次，
    // 可提取为共享方法。当前量级（个人笔记）性能足够，暂不需要 FTS5。
    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add(
        '(q.content LIKE ? OR (q.source LIKE ? OR q.source_author LIKE ? OR q.source_work LIKE ?))',
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

    final whereClause =
        conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    // 优化：使用JOIN一次性获取所有数据，避免N+1查询问题
    final query = '''
      SELECT 
        q.*,
        GROUP_CONCAT(qt.tag_id) as tag_ids_joined
      FROM quotes q
      LEFT JOIN quote_tags qt ON q.id = qt.quote_id
      $whereClause
      GROUP BY q.id
      ORDER BY q.$orderBy
      LIMIT ? OFFSET ?
    ''';

    args.addAll([limit, offset]);

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, args);
    final quotes = <Quote>[];

    for (final map in maps) {
      try {
        // 解析聚合的标签ID
        final tagIdsJoined = map['tag_ids_joined'];
        final tagIds = <String>{
          if (tagIdsJoined != null && tagIdsJoined.toString().isNotEmpty)
            ...tagIdsJoined
                .toString()
                .split(',')
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty),
        }.toList();

        // 创建Quote对象（移除临时字段）
        final quoteData = Map<String, dynamic>.from(map);
        quoteData.remove('tag_ids_joined');

        final quote = Quote.fromJson({...quoteData, 'tag_ids': tagIds});
        quotes.add(quote);
      } catch (e) {
        logDebug('解析笔记数据失败: $e, 数据: $map');
      }
    }

    return quotes;
  }

  /// 获取所有分类列表


  /// 检查并修复数据库结构，确保所有必要的列都存在
  /// 修复：检查并修复数据库结构，包括字段和索引
  Future<void> _checkAndFixDatabaseStructure() async {
    await _schemaManager.checkAndFixDatabaseStructure(database);
  }

  /// 初始化默认一言分类标签


  /// 修复：带重试机制的查询执行
  Future<T> _executeQueryWithRetry<T>(
    Future<T> Function() query, {
    int maxRetries = 2,
    Duration? timeout,
  }) async {
    // 修复：根据平台调整超时时间
    timeout ??= _getOptimalTimeout();
    final actualTimeout = timeout; // 确保非空

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final completer = Completer<T>();
        Timer? timeoutTimer;

        timeoutTimer = Timer(actualTimeout, () {
          if (!completer.isCompleted) {
            logError(
              '数据库查询超时（${actualTimeout.inSeconds}秒）',
              source: 'DatabaseService',
            );
            completer.completeError(TimeoutException('数据库查询超时', actualTimeout));
          }
        });

        // 异步执行查询
        query().then((result) {
          timeoutTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        }).catchError((error) {
          timeoutTimer?.cancel();
          if (!completer.isCompleted) {
            logError(
              '数据库查询失败: $error',
              error: error,
              source: 'DatabaseService',
            );
            completer.completeError(error);
          }
        });

        final result = await completer.future;
        timeoutTimer.cancel();
        return result;
      } catch (e) {
        if (attempt == maxRetries - 1) {
          // 最后一次尝试失败
          if (e is TimeoutException) {
            rethrow;
          }
          rethrow;
        }

        // 如果是超时异常，等待后重试
        if (e is TimeoutException) {
          logDebug('查询超时，准备重试 (${attempt + 1}/$maxRetries)');
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        } else {
          // 其他异常直接抛出
          rethrow;
        }
      }
    }

    throw Exception('查询重试失败');
  }

  /// 修复：根据平台和设备性能获取最优超时时间
  Duration _getOptimalTimeout() {
    if (kIsWeb) {
      return const Duration(seconds: 8); // Web平台网络延迟较高
    } else if (Platform.isAndroid) {
      return const Duration(seconds: 10); // Android设备性能差异较大
    } else if (Platform.isIOS) {
      return const Duration(seconds: 6); // iOS设备性能相对稳定
    } else {
      return const Duration(seconds: 8); // 桌面平台
    }
  }

  /// 执行实际的数据库查询（修复版本）


  /// 执行实际的数据库查询（修复版本）
  Future<List<Quote>> _performDatabaseQuery({
    required Database db,
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    required String orderBy,
    required int limit,
    required int offset,
    bool excludeHiddenNotes = true,
  }) async {
    // 修复：添加数据库连接状态检查
    if (!db.isOpen) {
      throw Exception('数据库连接已关闭');
    }
    // 优化：使用单一查询替代两步查询，减少数据库往返
    List<String> conditions = [];
    List<dynamic> args = [];
    String fromClause = 'FROM quotes q';
    String joinClause = '';
    String groupByClause = '';
    String havingClause = '';

    // 排除隐藏笔记（如果需要）
    if (excludeHiddenNotes) {
      conditions.add('''
        NOT EXISTS (
          SELECT 1 FROM quote_tags qt_hidden
          WHERE qt_hidden.quote_id = q.id
          AND qt_hidden.tag_id = ?
        )
      ''');
      args.add(hiddenTagId);
    }

    // 分类筛选
    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add('q.category_id = ?');
      args.add(categoryId);
    }

    // 优化：搜索查询使用FTS（全文搜索）如果可用，否则使用优化的LIKE查询
    if (searchQuery != null && searchQuery.isNotEmpty) {
      // 使用更高效的搜索策略：优先匹配内容，然后匹配其他字段
      conditions.add(
        '(q.content LIKE ? OR (q.source LIKE ? OR q.source_author LIKE ? OR q.source_work LIKE ?))',
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

    /// 修复：优化标签筛选查询，减少复杂度
    /// 关键修复：始终使用独立的 LEFT JOIN 获取所有标签，不受筛选条件影响
    if (tagIds != null && tagIds.isNotEmpty) {
      if (tagIds.length == 1) {
        // 单标签查询：使用简单的INNER JOIN筛选，但用另一个JOIN获取所有标签
        conditions.add('''
          EXISTS (
            SELECT 1 FROM quote_tags qt_filter
            WHERE qt_filter.quote_id = q.id
            AND qt_filter.tag_id = ?
          )
        ''');
        args.add(tagIds.first);
      } else {
        // 多标签查询：使用EXISTS确保所有标签都匹配
        final tagPlaceholders = tagIds.map((_) => '?').join(',');
        conditions.add('''
          EXISTS (
            SELECT 1 FROM quote_tags qt_filter
            WHERE qt_filter.quote_id = q.id
            AND qt_filter.tag_id IN ($tagPlaceholders)
            GROUP BY qt_filter.quote_id
            HAVING COUNT(DISTINCT qt_filter.tag_id) = ?
          )
        ''');
        args.addAll(tagIds);
        args.add(tagIds.length);
      }
    }

    // 始终使用独立的 LEFT JOIN 来获取所有标签（不受筛选条件影响）
    joinClause = 'LEFT JOIN quote_tags qt ON q.id = qt.quote_id';
    groupByClause = 'GROUP BY q.id';

    final where =
        conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final orderByParts = orderBy.split(' ');
    final correctedOrderBy =
        'q.${orderByParts[0]} ${orderByParts.length > 1 ? orderByParts[1] : ''}';

    /// 修复：始终使用 qt.tag_id 获取所有标签
    // 优化：指定查询列，排除大文本字段(ai_analysis, summary等)以提升列表加载性能
    // 注意：delta_content 必须保留！列表卡片通过 QuoteContent 组件渲染富文本（加粗、图片等）
    final query = '''
      SELECT
        q.id, q.content, q.date, q.source, q.source_author, q.source_work,
        q.category_id, q.color_hex, q.location, q.latitude, q.longitude,
        q.weather, q.temperature, q.edit_source, q.delta_content, q.day_period,
        q.last_modified, q.favorite_count,
        GROUP_CONCAT(qt.tag_id) as tag_ids
      $fromClause
      $joinClause
      $where
      $groupByClause
      $havingClause
      ORDER BY $correctedOrderBy
      LIMIT ? OFFSET ?
    ''';

    args.addAll([limit, offset]);

    if (kDebugMode) {
      logDebug('执行优化查询: $query\n参数: $args');
    }

    /// 修复：增强查询性能监控和慢查询检测
    final stopwatch = Stopwatch()..start();
    final maps = await db.rawQuery(query, args);
    stopwatch.stop();

    final queryTime = stopwatch.elapsedMilliseconds;

    // 记录查询统计（用于性能分析）
    _updateQueryStats('getQuotesCount', queryTime);

    // 慢查询检测和警告（阈值降低到100ms，更敏感）
    if (queryTime > 100) {
      final level = queryTime > 1000
          ? '🔴 严重慢查询'
          : queryTime > 500
              ? '⚠️ 慢查询警告'
              : 'ℹ️ 性能提示';
      logDebug('$level: 查询耗时 ${queryTime}ms');

      if (queryTime > 500) {
        logDebug('慢查询SQL: $query');
        logDebug('查询参数: $args');

        // 可选：记录查询执行计划用于优化
        try {
          final plan = await db.rawQuery('EXPLAIN QUERY PLAN $query', args);
          logDebug('查询执行计划:');
          for (final step in plan) {
            logDebug('  ${step['detail']}');
          }
        } catch (e) {
          logDebug('获取查询执行计划失败: $e');
        }
      }
    }

    logDebug('查询完成，耗时: ${queryTime}ms，结果数量: ${maps.length}');

    // 更新性能统计
    _updateQueryStats('getUserQuotes', queryTime);

    return maps.map((m) => Quote.fromJson(m)).toList();
  }

  /// 修复：更新查询性能统计


  /// 修复：更新查询性能统计
  void _updateQueryStats(String queryType, int timeMs) {
    _healthService.recordQueryStats(queryType, timeMs);
  }

  /// 智能推送专用轻量查询


  /// 修复：安全地创建索引，检查列是否存在
  Future<void> _createIndexSafely(
    Database db,
    String tableName,
    String columnName,
    String indexName,
  ) async {
    await _healthService.createIndexSafely(
      db,
      tableName,
      columnName,
      indexName,
    );
  }

  /// 修复：检查列是否存在


  /// 修复：检查列是否存在
  Future<bool> _checkColumnExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    return _healthService.checkColumnExists(db, tableName, columnName);
  }

  /// 启动时执行数据库健康检查

}
