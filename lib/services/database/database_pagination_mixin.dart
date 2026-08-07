part of '../database_service.dart';

/// Mixin providing pagination and stream operations for DatabaseService.
mixin _DatabasePaginationMixin on _DatabaseServiceBase {
  /// 刷新回填单次查询的条数上限。超过这个量级会分多次查询，
  /// 既不把一次刷新拖成慢查询，也不会让列表停在更短的中间态
  /// （全部取回后才推送，见 [_refillAfterRefresh]）。
  static const int _maxRefillChunk = 500;

  /// 判断刷新前后的可见列表是否逐条完全一致。
  ///
  /// 用 [Quote.toJson] 逐字段比较而不是挑几个字段：挑字段的写法一旦漏掉展示用
  /// 的列（weather、day_period、location……）就会把真实更新误判成"没变"从而
  /// 吞掉推送，而且新增字段时没人会记得同步这里。`toJson` 覆盖所有持久化字段，
  /// 天然不会漏；`tagIds` 不在 `toJson` 里，单独比。
  ///
  /// 只在刷新路径上跑一次，不在滚动帧里，这点比较开销远小于一次整表重建。
  bool _quoteListsEquivalent(List<Quote> previous, List<Quote> current) {
    // 空列表不参与去重：首屏/清空后的刷新必须让 UI 收到事件。
    if (previous.isEmpty) return false;
    if (previous.length != current.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (!_quoteEquivalent(previous[i], current[i])) return false;
    }
    return true;
  }

  bool _quoteEquivalent(Quote a, Quote b) {
    if (identical(a, b)) return true;

    final aTags = a.tagIds;
    final bTags = b.tagIds;
    if (aTags.length != bTags.length) return false;
    for (var i = 0; i < aTags.length; i++) {
      if (aTags[i] != bTags[i]) return false;
    }

    final aJson = a.toJson();
    final bJson = b.toJson();
    if (aJson.length != bJson.length) return false;
    for (final entry in aJson.entries) {
      if (!bJson.containsKey(entry.key)) return false;
      if (bJson[entry.key] != entry.value) return false;
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
  }) async {
    final generation = _quotesLoadGeneration;
    var failed = false;

    while (_currentQuotes.length < targetCount &&
        _watchHasMore &&
        !_isDisposed &&
        generation == _quotesLoadGeneration) {
      final before = _currentQuotes.length;
      try {
        await loadMoreQuotes(
          refillCount: targetCount - before,
          suppressNotify: true,
        );
      } catch (e, stackTrace) {
        // 查询失败/超时。loadMoreQuotes 对超时会 rethrow，这里必须接住，
        // 否则 unawaited 的回填会变成未处理的异步异常。
        failed = true;
        logError(
          '刷新回填失败: $e',
          error: e,
          stackTrace: stackTrace,
          source: 'DatabaseService',
        );
        break;
      }
      // 没有新增说明结果被去重光了，再循环就是死循环。
      if (_currentQuotes.length <= before) break;
    }

    // 期间又来了一次刷新：由那一次负责推送，这里直接退场。
    if (_isDisposed || generation != _quotesLoadGeneration) return;

    // 回填因失败中断且没取够：**不要推**。推出去的短列表会把用户正滑到的
    // 位置夹紧，正是这个 PR 要修的塌陷。保留 UI 上那份更长（略旧）的列表，
    // 并保住回填目标，等下一次刷新继续补齐。
    // 注意只在失败时这么做：正常取完发现变短是真实的删除，必须如实推送。
    // 这条保护依赖 loadMoreQuotes 在 suppressNotify 时把所有错误都抛出来，
    // 否则被吞掉的错误会伪装成"取完了"，仍然推出截断列表。
    if (failed && _currentQuotes.length < previousQuotes.length) {
      logDebug(
        '刷新回填未取满（${_currentQuotes.length}/${previousQuotes.length}），'
        '跳过推送以免列表塌缩',
      );
      return;
    }

    _pendingRefillTarget = 0;

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
      // 列表本来就是空的（首屏前的刷新）：照旧取一页。
      final int reloadCount = loadedCount > 0 ? loadedCount : _watchLimit;
      _pendingRefillTarget = reloadCount;
      // 回填结果和刷新前一模一样时不再向 UI 推送：整表推送会让列表页
      // 重建全部已加载 item（上百次 build + 首次布局），发生在滚动帧里
      // 就是一次明显的卡顿。回收站过期清理、同步后的例行刷新等场景，
      // 可见列表其实一条都没变。
      final List<Quote> previousQuotes = List<Quote>.from(_currentQuotes);
      logDebug('刷新笔记流数据，需回填 $reloadCount 条');
      // 优化：清除所有缓存，确保获取最新数据
      clearAllCacheForParts();

      // 重置状态并加载新数据
      _watchOffset = 0;
      _quotesCache = [];
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
      _watchHasMore = true; // 重置分页状态

      // 性能优化：仅在首次调用时同步发送空列表（UI 需要显示 loading/空状态）。
      // 搜索/筛选变化时不发送空列表，让 UI 保留旧结果可见，
      // 等异步加载完成后用新数据平滑替换，避免列表瞬间清空造成视觉闪烁。
      if (isFirstCall) {
        _quotesController!.add([]);
      }

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
    final requestOffset = _watchOffset;
    // 刷新回填：一次尽量多取，避免列表在用户滚动途中变短。
    // 单次查询封顶，超出的部分由 _refillAfterRefresh 继续分块取。
    // refillCount 一给就照它来（只受分块上限约束）：最后一块往往小于一页，
    // 若这时退回 _watchLimit 就会多取一整页，回填出比刷新前更长的列表。
    final int requestLimit = refillCount == null
        ? _watchLimit
        : (refillCount > _maxRefillChunk ? _maxRefillChunk : refillCount);
    logDebug(
      '开始加载更多笔记，当前已有 ${_currentQuotes.length} 条，offset=$requestOffset，limit=$requestLimit',
    );

    try {
      final quotes = await getUserQuotes(
        tagIds: tagIds,
        categoryId: categoryId,
        offset: requestOffset,
        limit: requestLimit,
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

      if (loadGeneration != _quotesLoadGeneration) {
        logDebug('丢弃过期笔记加载结果');
        return;
      }

      _watchOffset = requestOffset + quotes.length;

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
        _watchHasMore = quotes.length >= requestLimit;
      }

      // 通知状态变化
      notifyListeners();

      // 回填分块进行时由 _refillAfterRefresh 在全部到位后统一推送：
      // 中途推出去的短列表会把用户的滚动位置夹紧。
      if (suppressNotify) return;

      // 修复：使用安全的方式通知订阅者
      _safeNotifyQuotesStream();
    } catch (e) {
      if (loadGeneration != _quotesLoadGeneration) {
        logDebug('忽略过期笔记加载错误: $e');
        return;
      }
      logError('加载更多笔记失败: $e', error: e, source: 'DatabaseService');
      // 确保即使出错也通知UI，避免无限加载状态。
      // 但分块回填期间不推：半成品比原列表更短，推出去就是一次列表塌缩，
      // 失败后的最终状态由 _refillAfterRefresh 统一决定。
      if (!suppressNotify) {
        _safeNotifyQuotesStream();
      }

      // 回填期间必须把**所有**错误交出去：_refillAfterRefresh 要靠异常判断
      // 「保留旧列表」还是「如实推送」。只 rethrow 超时的话，SQLite 异常、
      // 反序列化失败等会被这里吞掉、正常返回，回填便误以为成功，
      // 截断后的列表照样推给 UI —— 列表塌缩的保护就形同虚设。
      if (suppressNotify || e is TimeoutException) {
        rethrow;
      }
    } finally {
      if (loadGeneration == _quotesLoadGeneration) {
        _isLoading = false; // 确保当前加载状态总是被重置
      }
    }
  }
}
