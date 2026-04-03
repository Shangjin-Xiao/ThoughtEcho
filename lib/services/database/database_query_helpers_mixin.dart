part of '../database_service.dart';

/// Mixin providing query helper operations for DatabaseService.
mixin _DatabaseQueryHelpersMixin on _DatabaseServiceBase {
  /// 修复：直接查询数据库，不进行初始化状态检查，用于内部调用
  @override
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
    final db = _DatabaseServiceBase._database!; // 直接使用数据库，不进行安全检查

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

    // ⚡ Bolt: 使用标量子查询替代 LEFT JOIN 和 GROUP BY，避免在 LIMIT 分页前全表聚合的性能瓶颈
    final sanitizedOrderBy = sanitizeOrderBy(orderBy, prefix: 'q');
    final query = '''
      SELECT 
        q.*,
        (SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id) as tag_ids_joined
      FROM quotes q
      $whereClause
      ORDER BY $sanitizedOrderBy
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

  /// 检查并修复数据库结构，确保所有必要的列都存在
  /// 修复：检查并修复数据库结构，包括字段和索引
  @override
  Future<void> _checkAndFixDatabaseStructure() async {
    await _schemaManager.checkAndFixDatabaseStructure(database);
  }

  /// 智能推送专用轻量查询
  @override
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
      args.add(_DatabaseServiceBase.hiddenTagId);

      if (whereSql != null && whereSql.isNotEmpty) {
        conditions.add(whereSql);
        if (whereArgs != null) {
          args.addAll(whereArgs);
        }
      }

      final where =
          conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

      // 只取必要列，不取 delta_content/ai_analysis/summary/keywords
      final sanitizedOrderBy = sanitizeOrderBy(orderBy, prefix: 'q');
      final query = '''
        SELECT q.id, q.content, q.date, q.source, q.source_author, q.source_work,
               q.category_id, q.color_hex, q.location, q.latitude, q.longitude,
               q.weather, q.temperature, q.edit_source, q.day_period,
               q.last_modified, q.favorite_count
        FROM quotes q
        $where
        ORDER BY $sanitizedOrderBy
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

  /// 获取笔记总数，用于分页
  /// [excludeHiddenNotes] 是否排除隐藏笔记，默认为 true
  @override
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
  }) async {
    // 判断是否正在查询隐藏标签
    final isQueryingHiddenTag =
        tagIds != null && tagIds.contains(_DatabaseServiceBase.hiddenTagId);
    // 如果正在查询隐藏标签，则不排除隐藏笔记
    final shouldExcludeHidden = excludeHiddenNotes && !isQueryingHiddenTag;

    if (kIsWeb) {
      // 优化：Web平台直接在内存中应用筛选逻辑计算数量，避免加载大量数据
      var filtered = _memoryStore;

      // 排除隐藏笔记
      if (shouldExcludeHidden) {
        filtered = filtered
            .where((q) => !q.tagIds.contains(_DatabaseServiceBase.hiddenTagId))
            .toList();
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
        args.add(_DatabaseServiceBase.hiddenTagId);
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
}
