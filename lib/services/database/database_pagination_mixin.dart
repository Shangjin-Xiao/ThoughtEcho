part of '../database_service.dart';

/// Mixin providing pagination and stream operations for DatabaseService.
mixin _DatabasePaginationMixin on _DatabaseServiceBase, _DatabaseQueryMixin {
  /// 刷新回填单次查询的条数上限。超过这个量级会分多次查询，
  /// 既不把一次刷新拖成慢查询，也不会让列表停在更短的中间态
  /// （全部取回后才推送，见 [_refillAfterRefresh]）。
  static const int _maxRefillChunk = 500;

  Future<List<Quote>> _queryQuotesPageSingleFlight({
    required List<String>? tagIds,
    required String? categoryId,
    required int offset,
    required int limit,
    required String orderBy,
    required String? searchQuery,
    required List<String>? selectedWeathers,
    required List<String>? selectedDayPeriods,
    required bool includeDeleted,
    required bool Function() isCancelled,
  }) {
    final signature = _buildQuoteQuerySignature(
      tagIds: tagIds,
      categoryId: categoryId,
      offset: offset,
      limit: limit,
      orderBy: orderBy,
      searchQuery: searchQuery,
      selectedWeathers: selectedWeathers,
      selectedDayPeriods: selectedDayPeriods,
      excludeHiddenNotes: true,
      dateStart: null,
      dateEnd: null,
      includeDeleted: includeDeleted,
      enforceForegroundLifecycle: true,
    );

    return _coalesceInFlightQuoteQuery(
      signature: signature,
      isCancelled: isCancelled,
      runFlight: (flight) => runZoned(
        () => getUserQuotes(
          tagIds: tagIds,
          categoryId: categoryId,
          offset: offset,
          limit: limit,
          orderBy: orderBy,
          searchQuery: searchQuery,
          selectedWeathers: selectedWeathers,
          selectedDayPeriods: selectedDayPeriods,
          includeDeleted: includeDeleted,
        ),
        zoneValues: <Object?, Object?>{
          _paginationThrowingQueryZoneKey: _PaginationQueryZoneContext(
            isCancelled: () => _isDisposed || flight.areAllWaitersCancelled,
            enforceForegroundLifecycle: true,
          ),
        },
      ),
    );
  }

  /// 判断刷新前后的可见列表是否逐条完全一致。
  ///
  /// 直接委托 [Quote.hasSameContentAs] 逐字段比较而不是挑几个字段：挑字段的写法一旦漏掉展示用
  /// 的列（weather、day_period、location……）就会把真实更新误判成"没变"从而
  /// 吞掉推送，而且新增字段时没人会记得同步这里。[Quote.hasSameContentAs] 覆盖所有持久化字段
  /// （由 `test/unit/models/quote_has_same_content_as_test.dart` 自动化守卫验证），
  /// 天然不会漏；`tagIds` 也由它一并零分配比对。
  ///
  /// 只在刷新路径上跑一次，不在滚动帧里，这点比较开销远小于一次整表重建。
  bool _quoteListsEquivalent(List<Quote> previous, List<Quote> current) {
    // 空列表不参与去重：首屏/清空后的刷新必须让 UI 收到事件。
    if (previous.isEmpty) return false;
    if (previous.length != current.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (!previous[i].hasSameContentAs(current[i])) return false;
    }
    return true;
  }

  /// 刷新后的回填：分块把原有条数全部取回，**全部到位后才推送一次**。
  ///
  /// 中途不推送是关键——只要推出去一个比原来短的列表，用户正滑到的位置就会被
  /// maxScrollExtent 夹紧，也就是这个 PR 要修的"列表突然飞走"。
  Future<void> _refillAfterRefresh({
    required int targetCount,
    required List<Quote> previousQuotes,
    required bool previousHasMore,
  }) async {
    final generation = _quotesLoadGeneration;
    var failed = false;
    Object? failureError;
    StackTrace? failureStackTrace;

    while (_currentQuotes.length < targetCount &&
        _watchHasMore &&
        !_isDisposed &&
        generation == _quotesLoadGeneration) {
      final before = _currentQuotes.length;
      try {
        await _loadMoreQuotesInternal(
          refillCount: targetCount - before,
          suppressNotify: true,
          logFailureAtBoundary: false,
        );
      } on _QueryCancelledException {
        return;
      } catch (e, stackTrace) {
        failed = true;
        failureError = e;
        failureStackTrace = stackTrace;
        break;
      }
      // 没有新增说明结果被去重光了，再循环就是死循环。
      if (_currentQuotes.length <= before) break;
    }

    // 期间又来了一次刷新：由那一次负责推送，这里直接退场。
    if (_isDisposed || generation != _quotesLoadGeneration) return;

    if (failed) {
      final error = failureError!;
      final stackTrace = failureStackTrace ?? StackTrace.current;
      final suspendedInBackground =
          error is TimeoutException && !_isAppLifecycleActive();
      if (!suspendedInBackground) {
        logErrorOnce(
          '刷新回填失败: $error',
          error: error,
          stackTrace: stackTrace,
          source: 'DatabaseService',
        );
      } else {
        logDebug('后台生命周期下刷新回填已挂起: $error');
        _coordinatorState.markDeferredRefresh(_quotesController);
      }

      if (previousQuotes.isNotEmpty ||
          (suspendedInBackground &&
              _coordinatorState.hasDeliveredForController(_quotesController))) {
        logDebug(
          '刷新回填未取满（${_currentQuotes.length}/${previousQuotes.length}），'
          '回滚到刷新前的状态以免列表塌缩',
        );
        _currentQuotes = List<Quote>.from(previousQuotes);
        _currentQuoteIds
          ..clear()
          ..addAll(
            previousQuotes.map((quote) => quote.id).whereType<String>(),
          );
        _watchOffset = _currentQuotes.length;
        _watchHasMore = previousHasMore;
        _pendingRefillTarget = 0;
        return;
      }

      // 首屏尚未拿到任何数据时恢复/刷新失败：不推送伪装成“无笔记”的空列表，
      // 复原分页标志并向流订阅方显式下发错误事件。
      _currentQuotes = [];
      _currentQuoteIds.clear();
      _watchOffset = 0;
      _watchHasMore = previousHasMore;
      _pendingRefillTarget = 0;
      if (_quotesController != null && !_quotesController!.isClosed) {
        _quotesController!.addError(error, stackTrace);
      }
      return;
    }

    _pendingRefillTarget = 0;
    _coordinatorState.markDelivered(_quotesController);

    if (_quoteListsEquivalent(previousQuotes, _currentQuotes)) {
      logDebug('刷新后可见列表无变化，跳过整表推送');
      return;
    }

    _safeNotifyQuotesStream();
  }

  /// 修复：安全地通知笔记流订阅者
  /// 性能优化：由于 _currentQuotes 已通过 _currentQuoteIds 保证唯一性，
  /// 此处直接发送，无需再次遍历去重
  @override
  void _safeNotifyQuotesStream() {
    // 修复：检查服务是否已销毁
    if (_isDisposed) return;

    if (_quotesController != null && !_quotesController!.isClosed) {
      _coordinatorState.markDelivered(_quotesController);
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
      // 刷新前记住已经加载出来的条数：任何一次数据变更（保存笔记、收藏、
      // 位置回填、回收站清理、同步导入……）都会走到这里，若只重新取回第一页，
      // 已经滑到深处的列表会瞬间从 N 条塌回一页，maxScrollExtent 随之骤减，
      // 滚动位置被夹紧 —— 表现就是「列表突然飞走/弹回顶部 + 底部转圈 + 大片空白」。
      // 所以刷新必须一次把原有页数全部取回，列表长度保持不变。
      //
      // 上一次刷新可能还在回填途中（那时 _currentQuotes 已被清空），
      // 此时按当时的长度 0 算目标会退化成只取一页，等于把这个 bug 放回来。
      // 沿用在途目标即可。
      final int loadedCount = _currentQuotes.isNotEmpty
          ? _currentQuotes.length
          : _pendingRefillTarget;
      // 列表本来不足一页（如首屏前或总笔记数少于一页时新增/同步合入）：至少取满一页容量。
      final int reloadCount =
          loadedCount > _watchLimit ? loadedCount : _watchLimit;
      _pendingRefillTarget = reloadCount;
      // 回填结果和刷新前一模一样时不再向 UI 推送：整表推送会让列表页
      // 重建全部已加载 item（上百次 build + 首次布局），发生在滚动帧里
      // 就是一次明显的卡顿。回收站过期清理、同步后的例行刷新等场景，
      // 可见列表其实一条都没变。
      final List<Quote> previousQuotes = List<Quote>.from(_currentQuotes);
      // 回填失败要整体回滚时，分页游标也得跟着回到刷新前的样子。
      final bool previousHasMore = _watchHasMore;
      logDebug('刷新笔记流数据，需回填 $reloadCount 条');
      // 优化：清除所有缓存，确保获取最新数据
      clearAllCacheForParts();

      // 重置状态并加载新数据
      _watchOffset = 0;
      _watchHasMore = true;
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set
      _quotesLoadGeneration++;
      _isLoading = false;

      // 触发重新加载
      unawaited(
        _refillAfterRefresh(
          targetCount: reloadCount,
          previousQuotes: previousQuotes,
          previousHasMore: previousHasMore,
        ),
      );
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
    // 修复：如果数据库未初始化，先返回临时流并等待初始化完成再通知重订
    if (!isInitialized) {
      logDebug('数据库尚未初始化，等待初始化完成后通知重新订阅...');

      final tempController = StreamController<List<Quote>>.broadcast();

      Future.microtask(() async {
        try {
          if (_isInitializing && _initCompleter != null) {
            await _initCompleter!.future;
          } else if (!isInitialized) {
            await init();
          }

          logDebug('数据库初始化完成，通知UI重新订阅数据流');
          await tempController.close();

          if (!kIsWeb && Platform.isAndroid) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!_isDisposed) notifyListeners();
            });
          } else {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!_isDisposed) notifyListeners();
            });
          }
        } catch (e, stackTrace) {
          logErrorOnce(
            '等待数据库初始化失败: $e',
            error: e,
            stackTrace: stackTrace,
            source: 'watchQuotes',
          );
          if (!tempController.isClosed) {
            tempController.addError(e, stackTrace);
            await tempController.close();
          }
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
      _coordinatorState.resetForNewWatchController();

      // 修复：在重置状态时确保原子性操作，避免竞态条件
      // 注意：_watchOffset 只能在这里（真正重建流、清空 _currentQuotes 时）归零。
      // 复用已有流的分支若也归零，下一次 loadMoreQuotes 会重新查第一页，
      // 结果全是重复数据被去重掉——列表一条都不增长，_watchHasMore 却被
      // 重新置回 true，底部加载指示器就此常驻并反复触发无效分页。
      _watchOffset = 0;
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set
      // 换了筛选条件，旧结果集的回填目标不再适用，留着会让下一次刷新
      // 按旧条数超量加载。
      _pendingRefillTarget = 0;
      _isLoading = false;
      _quotesLoadGeneration++;
      final generation = _quotesLoadGeneration;
      _watchHasMore = true; // 重置分页状态

      // 在新的异步上下文中加载首屏/新筛选结果；不再预发空白占位列表，也不包裹跨层 10 秒超时。
      Future.microtask(() async {
        if (_isDisposed || generation != _quotesLoadGeneration) return;
        try {
          await _loadMoreQuotesInternal(
            tagIds: tagIds,
            categoryId: categoryId,
            searchQuery: searchQuery,
            selectedWeathers: selectedWeathers,
            selectedDayPeriods: selectedDayPeriods,
            includeDeleted: includeDeleted,
            suppressNotify: false,
            logFailureAtBoundary: false,
          );
        } on _QueryCancelledException {
          return;
        } catch (e, stackTrace) {
          if (_isDisposed || generation != _quotesLoadGeneration) {
            return;
          }
          final suspendedInBackground =
              e is TimeoutException && !_isAppLifecycleActive();
          if (!suspendedInBackground) {
            logErrorOnce(
              '数据初始化或加载失败: $e',
              error: e,
              stackTrace: stackTrace,
              source: 'DatabaseService',
            );
          } else {
            logDebug('后台生命周期下首屏/筛选查询已挂起: $e');
            _coordinatorState.markDeferredRefresh(_quotesController);
          }
          if (_quotesController != null && !_quotesController!.isClosed) {
            _quotesController!.addError(e, stackTrace);
          }
        }
      });
    } else {
      // 修复：复用已有流时，新订阅者不会收到历史数据。
      // 通过 microtask 发送当前缓存数据，确保新订阅者能立即获取已有数据。
      // microtask 保证在调用方完成 .listen() 订阅后再发送，避免数据丢失。
      Future.microtask(() {
        if (_quotesController != null && !_quotesController!.isClosed) {
          logDebug('watchQuotes 复用已有流，向新订阅者发送 ${_currentQuotes.length} 条缓存数据');
          _safeNotifyQuotesStream();
        }
      });
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
    int? refillCount,
    bool suppressNotify = false,
  }) {
    return _loadMoreQuotesInternal(
      tagIds: tagIds,
      categoryId: categoryId,
      searchQuery: searchQuery,
      selectedWeathers: selectedWeathers,
      selectedDayPeriods: selectedDayPeriods,
      includeDeleted: includeDeleted,
      refillCount: refillCount,
      suppressNotify: suppressNotify,
      logFailureAtBoundary: !suppressNotify,
    );
  }

  Future<void> _loadMoreQuotesInternal({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
    int? refillCount,
    required bool suppressNotify,
    required bool logFailureAtBoundary,
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
    final loadGeneration = _quotesLoadGeneration;
    final controllerAtStart = _quotesController;
    final requestOffset = _watchOffset;
    final int requestLimit = refillCount == null
        ? _watchLimit
        : (refillCount > _maxRefillChunk ? _maxRefillChunk : refillCount);
    logDebug(
      '开始加载更多笔记，当前已有 ${_currentQuotes.length} 条，offset=$requestOffset，limit=$requestLimit',
    );

    bool isRequestCancelled() =>
        _isDisposed ||
        loadGeneration != _quotesLoadGeneration ||
        (controllerAtStart != null && controllerAtStart.isClosed);

    try {
      final quotes = await _queryQuotesPageSingleFlight(
        tagIds: tagIds,
        categoryId: categoryId,
        offset: requestOffset,
        limit: requestLimit,
        orderBy: _watchOrderBy,
        searchQuery: searchQuery,
        selectedWeathers: selectedWeathers,
        selectedDayPeriods: selectedDayPeriods,
        includeDeleted: includeDeleted,
        isCancelled: isRequestCancelled,
      );

      if (loadGeneration != _quotesLoadGeneration) {
        logDebug('丢弃过期笔记加载结果');
        return;
      }

      _watchOffset = requestOffset + quotes.length;

      if (quotes.isEmpty) {
        _watchHasMore = false;
        logDebug('没有更多笔记数据，设置_watchHasMore=false');
      } else {
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

        _watchHasMore = quotes.length >= requestLimit;
      }

      notifyListeners();

      if (suppressNotify) return;

      _safeNotifyQuotesStream();
    } on _QueryCancelledException catch (e) {
      logDebug('忽略已取消的分页加载请求: $e');
      if (!logFailureAtBoundary) {
        rethrow;
      }
      return;
    } catch (e, stackTrace) {
      if (loadGeneration != _quotesLoadGeneration) {
        logDebug('忽略过期笔记加载错误: $e');
        return;
      }
      if (logFailureAtBoundary) {
        final suspendedInBackground =
            e is TimeoutException && !_isAppLifecycleActive();
        if (!suspendedInBackground) {
          logErrorOnce(
            '加载更多笔记失败: $e',
            error: e,
            stackTrace: stackTrace,
            source: 'DatabaseService',
          );
        }
      }
      // 翻页失败保持现有已加载列表与游标不变，不向流重发伪成功列表，向上抛出供终端调用方处理。
      rethrow;
    } finally {
      if (loadGeneration == _quotesLoadGeneration) {
        _isLoading = false;
      }
    }
  }
}
