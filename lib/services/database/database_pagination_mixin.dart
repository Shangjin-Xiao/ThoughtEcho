part of '../database_service.dart';

/// Mixin providing pagination and stream operations for DatabaseService.
mixin _DatabasePaginationMixin on _DatabaseServiceBase {
  /// 修复：安全地通知笔记流订阅者
  /// 性能优化：由于 _currentQuotes 已通过 _currentQuoteIds 保证唯一性，
  /// 此处直接发送，无需再次遍历去重
  @override
  void _safeNotifyQuotesStream() {
    // 修复：检查服务是否已销毁
    if (_isDisposed) return;

    if (_quotesController != null && !_quotesController!.isClosed) {
      // 直接发送当前列表的副本，已保证唯一性
      _quotesController!.add(List.from(_currentQuotes));
    }
  }

  /// 刷新笔记流数据（公开方法）
  @override
  void refreshQuotes() {
    _refreshQuotesStream();
  }

  // 在增删改后刷新分页流数据
  @override
  void _refreshQuotesStream() {
    if (_quotesController != null && !_quotesController!.isClosed) {
      logDebug('刷新笔记流数据');
      // 优化：清除所有缓存，确保获取最新数据
      clearAllCacheForParts();

      // 重置状态并加载新数据
      _watchOffset = 0;
      _quotesCache = [];
      _watchHasMore = true;
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set

      // 触发重新加载
      loadMoreQuotes();
    } else {
      logDebug('笔记流无监听器或已关闭，跳过刷新');
    }
  }

  /// 修复：监听笔记列表，支持分页加载和筛选
  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers, // 天气筛选
    List<String>? selectedDayPeriods, // 时间段筛选
    bool includeDeleted = false,
  }) {
    // 修复：如果数据库未初始化，先返回空流并等待初始化
    if (!_isInitialized) {
      logDebug('数据库尚未初始化，返回空流并等待初始化...');

      // 创建一个临时的流控制器
      final tempController = StreamController<List<Quote>>.broadcast();
      tempController.add([]); // 立即发送空列表

      // 异步等待初始化完成后重新调用
      Future.microtask(() async {
        try {
          if (_isInitializing && _initCompleter != null) {
            await _initCompleter!.future;
          } else if (!_isInitialized) {
            await init();
          }

          // 修复：初始化完成后，通知UI重新订阅
          logDebug('数据库初始化完成，通知UI重新订阅数据流');
          tempController.close();

          // 针对安卓平台的特殊处理
          if (!kIsWeb && Platform.isAndroid) {
            // 安卓平台延迟更长时间通知，确保UI完全准备好
            Future.delayed(const Duration(milliseconds: 300), () {
              notifyListeners();
            });
          } else {
            // 其他平台立即通知
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!_isDisposed) notifyListeners();
            });
          }
        } catch (e) {
          logError('等待数据库初始化失败: $e', error: e, source: 'watchQuotes');
          tempController.addError(e);
          await tempController.close(); // 修复：异常路径也关闭 controller
        }
      });

      return tempController.stream;
    }
    // 检查是否有筛选条件改变
    bool hasFilterChanged = false;

    // 修复：检查是否是首次调用
    bool isFirstCall =
        (_quotesController == null || _quotesController!.isClosed) ||
        (_currentQuotes.isEmpty);

    logDebug(
      'watchQuotes调用 - isFirstCall: $isFirstCall, hasController: ${_quotesController != null}, '
      'currentQuotesCount: ${_currentQuotes.length}, tagIds: $tagIds, categoryId: $categoryId',
    );

    // 检查标签是否变更
    if (_watchTagIds != null && tagIds != null) {
      if (_watchTagIds!.length != tagIds.length) {
        hasFilterChanged = true;
        logDebug('标签数量变更: ${_watchTagIds!.length} -> ${tagIds.length}');
      } else {
        // 比较标签内容是否一致
        for (int i = 0; i < _watchTagIds!.length; i++) {
          if (!tagIds.contains(_watchTagIds![i])) {
            hasFilterChanged = true;
            logDebug('标签内容变更');
            break;
          }
        }
      }
    } else if ((_watchTagIds == null) != (tagIds == null)) {
      hasFilterChanged = true;
      logDebug(
        '标签筛选条件状态变更: ${_watchTagIds == null ? "无" : "有"} -> ${tagIds == null ? "无" : "有"}',
      );
    }

    // 检查分类是否变更
    if (_watchCategoryId != categoryId) {
      hasFilterChanged = true;
      logDebug('分类变更: $_watchCategoryId -> $categoryId');
    }

    // 检查排序是否变更
    if (_watchOrderBy != orderBy) {
      hasFilterChanged = true;
      logDebug('排序变更: $_watchOrderBy -> $orderBy');
    }

    if (_watchIncludeDeleted != includeDeleted) {
      hasFilterChanged = true;
      logDebug('已删除筛选变更: $_watchIncludeDeleted -> $includeDeleted');
    }

    // 检查搜索条件是否变更
    final normalizedSearchQuery =
        (searchQuery != null && searchQuery.isNotEmpty) ? searchQuery : null;
    if (_watchSearchQuery != normalizedSearchQuery) {
      hasFilterChanged = true;
      logDebug('搜索条件变更: $_watchSearchQuery -> $normalizedSearchQuery');
    }

    // 检查天气筛选条件是否变更
    if (_watchSelectedWeathers != null && selectedWeathers != null) {
      if (_watchSelectedWeathers!.length != selectedWeathers.length) {
        hasFilterChanged = true;
        logDebug(
          '天气筛选数量变更: ${_watchSelectedWeathers!.length} -> ${selectedWeathers.length}',
        );
      } else {
        // 比较天气筛选内容是否一致
        for (int i = 0; i < _watchSelectedWeathers!.length; i++) {
          if (!selectedWeathers.contains(_watchSelectedWeathers![i])) {
            hasFilterChanged = true;
            logDebug('天气筛选内容变更');
            break;
          }
        }
      }
    } else if ((_watchSelectedWeathers == null) != (selectedWeathers == null)) {
      hasFilterChanged = true;
      logDebug('天气筛选条件状态变更');
    }

    // 检查时间段筛选条件是否变更
    if (_watchSelectedDayPeriods != null && selectedDayPeriods != null) {
      if (_watchSelectedDayPeriods!.length != selectedDayPeriods.length) {
        hasFilterChanged = true;
        logDebug(
          '时间段筛选数量变更: ${_watchSelectedDayPeriods!.length} -> ${selectedDayPeriods.length}',
        );
      } else {
        // 比较时间段筛选内容是否一致
        for (int i = 0; i < _watchSelectedDayPeriods!.length; i++) {
          if (!selectedDayPeriods.contains(_watchSelectedDayPeriods![i])) {
            hasFilterChanged = true;
            logDebug('时间段筛选内容变更');
            break;
          }
        }
      }
    } else if ((_watchSelectedDayPeriods == null) !=
        (selectedDayPeriods == null)) {
      hasFilterChanged = true;
      logDebug('时间段筛选条件状态变更');
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
    _watchIncludeDeleted = includeDeleted;

    // 修复：筛选条件变化时重置_watchHasMore状态
    if (hasFilterChanged || isFirstCall) {
      _watchHasMore = true;
      if (isFirstCall) {
        logDebug('首次调用watchQuotes，准备加载初始数据');
      } else {
        logDebug('筛选条件变化，重置_watchHasMore=true');
      }
    }

    // 修复：如果有筛选条件变更、首次调用或未初始化，重新创建流
    if (hasFilterChanged ||
        isFirstCall ||
        _quotesController == null ||
        _quotesController!.isClosed) {
      // 安全关闭现有控制器
      if (_quotesController != null && !_quotesController!.isClosed) {
        _quotesController!.close();
      }
      _quotesController = StreamController<List<Quote>>.broadcast();

      // 修复：在重置状态时确保原子性操作，避免竞态条件
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set
      _isLoading = false;
      _watchHasMore = true; // 重置分页状态

      // 修复：使用同步方式立即发送空列表，然后异步加载数据
      _quotesController!.add([]);

      // 在新的异步上下文中执行初始化
      Future.microtask(() async {
        try {
          // 优化：移除重复的数据迁移检查，这些已在初始化阶段完成

          // 加载第一页数据
          await loadMoreQuotes(
            tagIds: tagIds,
            categoryId: categoryId,
            searchQuery: searchQuery,
            selectedWeathers: selectedWeathers,
            selectedDayPeriods: selectedDayPeriods,
            includeDeleted: includeDeleted,
          );
        } catch (e) {
          logError('数据初始化或加载失败: $e', error: e, source: 'DatabaseService');
          // 即使失败也发送空列表，避免UI挂起
          if (_quotesController != null && !_quotesController!.isClosed) {
            _quotesController!.add([]);
          }
        }
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logError('数据加载超时（10秒）', source: 'DatabaseService');
          // 超时时发送空列表，确保UI不会永远卡住
          if (_quotesController != null && !_quotesController!.isClosed) {
            _quotesController!.add([]);
          }
        },
      );
    }

    return _quotesController!.stream;
  }

  /// 修复：加载更多笔记数据（用于分页）
  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
  }) async {
    // 使用当前观察的参数作为默认值
    tagIds ??= _watchTagIds;
    categoryId ??= _watchCategoryId;
    searchQuery ??= _watchSearchQuery;
    selectedWeathers ??= _watchSelectedWeathers;
    selectedDayPeriods ??= _watchSelectedDayPeriods;
    includeDeleted ??= _watchIncludeDeleted;

    // 修复：防止重复加载和检查是否还有更多数据
    if (_isLoading || !_watchHasMore) {
      logDebug('跳过加载：正在加载($_isLoading) 或无更多数据(!$_watchHasMore)');
      return;
    }

    _isLoading = true;
    logDebug(
      '开始加载更多笔记，当前已有 ${_currentQuotes.length} 条，offset=${_currentQuotes.length}，limit=$_watchLimit',
    );

    try {
      final quotes =
          await getUserQuotes(
            tagIds: tagIds,
            categoryId: categoryId,
            offset: _currentQuotes.length,
            limit: _watchLimit,
            orderBy: _watchOrderBy,
            searchQuery: searchQuery,
            selectedWeathers: selectedWeathers,
            selectedDayPeriods: selectedDayPeriods,
            includeDeleted: includeDeleted,
          ).timeout(
            const Duration(seconds: 5), // 缩短超时时间
            onTimeout: () {
              logError('getUserQuotes 查询超时（5秒）', source: 'DatabaseService');
              throw TimeoutException('数据库查询超时', const Duration(seconds: 5));
            },
          );

      if (quotes.isEmpty) {
        // 没有更多数据了
        _watchHasMore = false;
        logDebug('没有更多笔记数据，设置_watchHasMore=false');
      } else {
        // 性能优化：使用增量维护的 _currentQuoteIds 进行去重
        // 避免每次都遍历 _currentQuotes 构建 Set
        final newQuotes = <Quote>[];
        for (final quote in quotes) {
          if (quote.id != null && !_currentQuoteIds.contains(quote.id)) {
            _currentQuoteIds.add(quote.id!);
            newQuotes.add(quote);
          }
        }

        if (newQuotes.isNotEmpty) {
          _currentQuotes.addAll(newQuotes);
          logDebug(
            '本次加载${quotes.length}条，去重后添加${newQuotes.length}条，总计${_currentQuotes.length}条',
          );
        } else {
          logDebug('本次加载${quotes.length}条，但全部为重复数据，已过滤');
        }

        // 简化：统一的_watchHasMore判断逻辑
        _watchHasMore = quotes.length >= _watchLimit;
      }

      // 通知状态变化
      notifyListeners();

      // 修复：使用安全的方式通知订阅者
      _safeNotifyQuotesStream();
    } catch (e) {
      logError('加载更多笔记失败: $e', error: e, source: 'DatabaseService');
      // 确保即使出错也通知UI，避免无限加载状态
      _safeNotifyQuotesStream();

      // 如果是超时错误，重新抛出让UI处理
      if (e is TimeoutException) {
        rethrow;
      }
    } finally {
      _isLoading = false; // 确保加载状态总是被重置
    }
  }
}
