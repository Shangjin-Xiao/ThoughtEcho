part of '../database_service.dart';

/// Mixin providing core query operations for DatabaseService.
mixin _DatabaseQueryMixin on _DatabaseServiceBase {
  /// 获取笔记列表，支持标签、分类、搜索、天气和时间段筛选
  @override
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
    bool includeDeleted = false,
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
      scheduleCacheCleanupForParts();

      // 判断是否正在查询隐藏标签
      final isQueryingHiddenTag =
          tagIds != null && tagIds.contains(_DatabaseServiceBase.hiddenTagId);
      // 如果正在查询隐藏标签，则不排除隐藏笔记
      final shouldExcludeHidden = excludeHiddenNotes && !isQueryingHiddenTag;

      if (kIsWeb) {
        // Web平台的完整筛选逻辑
        var filtered = _memoryStore;

        // 排除隐藏笔记（除非正在查询隐藏标签）
        if (shouldExcludeHidden) {
          filtered = filtered
              .where(
                (q) => !q.tagIds.contains(_DatabaseServiceBase.hiddenTagId),
              )
              .toList();
        }

        if (!includeDeleted) {
          filtered = filtered.where((q) => !q.isDeleted).toList();
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
          includeDeleted: includeDeleted,
        );
      });
    } catch (e) {
      logError('获取笔记失败: $e', error: e, source: 'DatabaseService');
      return [];
    }
  }

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
        query()
            .then((result) {
              timeoutTimer?.cancel();
              if (!completer.isCompleted) {
                completer.complete(result);
              }
            })
            .catchError((error) {
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
    bool includeDeleted = false,
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
      args.add(_DatabaseServiceBase.hiddenTagId);
    }

    if (!includeDeleted) {
      conditions.add('(q.is_deleted = 0 OR q.is_deleted IS NULL)');
    }

    // 分类筛选
    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add('q.category_id = ?');
      args.add(categoryId);
    }

    // 优化：搜索查询使用FTS（全文搜索）如果可用，否则使用优化的LIKE查询
    _applySearchQuery(searchQuery, conditions, args);

    // 天气筛选
    if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
      final weatherPlaceholders = selectedWeathers.map((_) => '?').join(',');
      conditions.add('q.weather IN ($weatherPlaceholders)');
      args.addAll(selectedWeathers);
    }

    // 时间段筛选
    if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
      final dayPeriodPlaceholders = selectedDayPeriods
          .map((_) => '?')
          .join(',');
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
    // 优化：使用标量子查询替代 LEFT JOIN 和 GROUP BY，避免全表聚合开销
    joinClause = '';
    groupByClause = '';

    final where = conditions.isNotEmpty
        ? 'WHERE ${conditions.join(' AND ')}'
        : '';

    final correctedOrderBy = sanitizeOrderBy(orderBy, prefix: 'q');

    /// 修复：始终使用 qt.tag_id 获取所有标签
    // 优化：指定查询列，排除大文本字段(ai_analysis, summary等)以提升列表加载性能
    // 注意：delta_content 必须保留！列表卡片通过 QuoteContent 组件渲染富文本（加粗、图片等）
    // 性能提升：(SELECT GROUP_CONCAT(tag_id) ...) 仅对 LIMIT 返回的数据执行
    final query =
        '''
      SELECT
        q.id, q.content, q.date, q.source, q.source_author, q.source_work,
        q.category_id, q.color_hex, q.location, q.latitude, q.longitude,
        q.weather, q.temperature, q.edit_source, q.delta_content, q.day_period,
        q.last_modified, q.favorite_count, q.is_deleted, q.deleted_at,
        (SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id) as tag_ids
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
  void _updateQueryStats(String queryType, int timeMs) {
    _healthService.recordQueryStats(queryType, timeMs);
  }
}
