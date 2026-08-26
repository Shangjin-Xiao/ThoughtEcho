part of '../note_list_view.dart';

/// Data stream and subscription management for NoteListViewState.
extension _NoteListDataStreamExtension on NoteListViewState {
  /// 数据事件推来的列表是否与当前 `_quotes` **逐条同一个实例**。
  ///
  /// `watchQuotes` 每次都重发整个累积列表（`List.from(_currentQuotes)`），而
  /// `_currentQuotes` 是增量维护的：没被重新查询过的笔记还是原来那批 [Quote]
  /// 对象。于是"翻到最后一页""重复通知"这类什么都没变的事件可以逐指针比出来。
  /// [Quote] 全字段 final，同一实例就意味着内容一定没变，跳过重建不可能漏更新。
  ///
  /// 这件事值得比：照旧整表替换的话，一个空事件就是一轮整列表 setState。实测
  /// 首滑期间两个这样的事件重建了 241 次卡片（`built=155` + `built=86`），
  /// 而列表内容一条都没变。
  /// 数据事件里内容没变的行，复用**旧实例**。
  ///
  /// 卡片记忆化（`_QuoteItemMemo.matches`）和 [_isSameQuoteInstances] 都按
  /// `identical` 判断 —— 那是最快也最保险的判据，[Quote] 全字段 final，同一实例
  /// 就意味着内容一定没变。问题出在上游：数据库一旦重新查询（回前台刷新、换页、
  /// 重新订阅），就会造出一批全新的 [Quote] 对象，内容一个字没改身份却全变了，
  /// 这道防线于是整条失效 —— 一次数据事件把整屏卡片全部重建。
  ///
  /// 2026-08-23 的日志里 `itemMemo={size=121,hit+0,miss+113}`、
  /// `worstBuild=74.9ms`：113 张卡片在一个滚动帧里重建完，而内容一条都没变。
  ///
  /// 判据用 [Quote.hasSameContentAs]（持久化字段 + 标签），**不能用 `==`**：
  /// 那个只比 id，会把「同一条笔记被改过内容」也当成没变，卡片就永远停在旧内容上。
  ///
  /// 没有一条能复用时原样返回，不产生任何拷贝。
  List<Quote> _reuseUnchangedQuoteInstances(
    List<Quote> incoming, {
    required bool recordProfile,
  }) {
    if (_quotes.isEmpty || incoming.isEmpty) return incoming;
    final stopwatch = Stopwatch()..start();

    final previousById = <String, Quote>{};
    for (final quote in _quotes) {
      final id = quote.id;
      if (id != null) previousById[id] = quote;
    }
    if (previousById.isEmpty) return incoming;

    List<Quote>? reconciled;
    for (var i = 0; i < incoming.length; i++) {
      final quote = incoming[i];
      final id = quote.id;
      if (id == null) continue;
      final previous = previousById[id];
      // 已经是同一实例的不必比内容，那是最常见的情况（服务层增量维护
      // `_currentQuotes`，没被重新查询的行本来就还是原对象）。
      if (previous == null || identical(previous, quote)) continue;
      if (!previous.hasSameContentAs(quote)) continue;
      reconciled ??= List<Quote>.of(incoming);
      reconciled[i] = previous;
      _quoteInstanceReuseCount++;
    }
    stopwatch.stop();
    // 只有确认是分页带来的那一次数据事件才记账：搜索、筛选刷新、回填分块也会走这里，
    // 混进去的话 `loadMore={}` 描述的就不是那一次分页了。
    if (recordProfile) {
      NoteListLoadMoreProfile.recordReuse(stopwatch.elapsedMicroseconds);
    }
    return reconciled ?? incoming;
  }

  bool _isSameQuoteInstances(List<Quote> list) {
    if (list.length != _quotes.length) return false;
    for (var i = 0; i < list.length; i++) {
      if (!identical(list[i], _quotes[i])) return false;
    }
    return true;
  }

  void _scheduleExpandableQuoteCheck() {
    // **不要**在这里把 _hasExpandableQuoteCached 清成 false。清了之后下面那句
    // `_hasExpandableQuoteCached != hasExpandable` 比的是刚清掉的值而不是旧答案，
    // 于是只要列表里有可折叠笔记（常态），每个数据事件都必然多出一次整列表
    // setState —— 实测日志里数据事件后紧跟的第二轮上百次卡片重建就是它。
    // 顺带还会让功能引导的目标短暂消失一帧。旧答案留着，新答案算出来再比。
    _hasExpandableQuoteComputed = false;

    if (_quotes.isEmpty) {
      _hasExpandableQuoteCached = false;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasExpandableQuoteComputed) {
        return;
      }

      final bool hasExpandable = _quotes.take(80).any(
            QuoteItemWidget.needsExpansionFor,
          );

      if (!mounted) {
        return;
      }

      _hasExpandableQuoteComputed = true;
      if (_hasExpandableQuoteCached != hasExpandable) {
        _updateState(() {
          _hasExpandableQuoteCached = hasExpandable;
        });
      } else {
        _hasExpandableQuoteCached = hasExpandable;
      }
    });
  }

  /// 修复：将数据流初始化分离到独立方法
  void _initializeDataStream() {
    if (!mounted) return;

    _quotesSub?.cancel();

    final db = _readDatabaseService();

    if (!db.isInitialized) {
      logDebug('数据库未初始化，等待初始化完成后重新订阅');
      _attachDatabaseServiceListener(db);
      return;
    }

    bool isFirstLoad = !_initialDataLoaded;

    _quotesSub = db
        .watchQuotes(
      tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
      limit: NoteListViewState._pageSize,
      orderBy: widget.sortType == 'time'
          ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
          : widget.sortType == 'favorite'
              ? 'favorite_count ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
      searchQuery:
          _effectiveSearchQuery.isNotEmpty ? _effectiveSearchQuery : null,
      selectedWeathers:
          widget.selectedWeathers.isNotEmpty ? widget.selectedWeathers : null,
      selectedDayPeriods: widget.selectedDayPeriods.isNotEmpty
          ? widget.selectedDayPeriods
          : null,
    )
        .listen(
      (rawList) {
        if (mounted) {
          _dataStreamEventCount++;
          // `isLoadMorePage` 先算：它决定 _isLoading 何时归位，判据是「这一批到底
          // 是不是新页」，所以要看长度。
          final isLoadMorePage = _loadMoreAwaitingPage &&
              (rawList.length > _loadMoreRequestStartCount ||
                  rawList.length < NoteListViewState._pageSize);
          // 分段计时的门控用的是 `_loadMoreAwaitingPage` 而**不是** isLoadMorePage：
          // 分页查到「没有更多了」时列表不变长、长度也不小于一页，isLoadMorePage 为
          // 假，可那次数据事件仍然是分页带来的。2026-08-26 的日志里就是这样：
          // `reuseΔ=117` 明明做了 117 行的内容比较，`loadMore` 里却是 `ev=0`、
          // `reuse=0.0ms` —— 门控太严，把要量的那一次漏掉了。
          final profilesLoadMore = _loadMoreAwaitingPage;
          final list = _reuseUnchangedQuoteInstances(
            rawList,
            recordProfile: profilesLoadMore,
          );
          final isPlaceholderInitialEmission =
              isFirstLoad && list.isEmpty && db.hasMoreQuotes;

          if (isPlaceholderInitialEmission) {
            logDebug(
              '忽略首个占位空列表，继续等待真实首批数据',
              source: 'NoteListView',
            );
            return;
          }

          // 修复：在首次加载期间保存滚动位置，避免数据刷新时滚动到顶部
          double? savedScrollOffset;
          if (isFirstLoad &&
              _scrollController.hasClients &&
              _quotes.isNotEmpty) {
            savedScrollOffset = _safeScrollOffset;
            logDebug(
              '首次加载期间保存滚动位置: $savedScrollOffset',
              source: 'NoteListView',
            );
          }

          // _hasMore 必须在 setState 内就取数据库的真实分页状态。
          // 早先用 `list.length >= _pageSize` 推断、事后再普通赋值纠正，
          // 会让每个数据事件都先渲染一帧多出来的尾部占位/转圈，
          // 表现就是"加载图标闪一下"，同时 itemCount 变化还会抖动列表高度。
          final bool dbHasMore = db.hasMoreQuotes;
          // 列表被整表替换前的偏移，用于事件后校正被夹紧的滚动位置。
          final double? offsetBeforeUpdate = _safeScrollOffset;

          // 内容逐条同一实例、分页标志也没变 = 这次事件什么都没改变，
          // 唯一还需要落地的 _isLoading 由自己的 ValueNotifier 驱动底部指示器，
          // 不需要整列表重建。两个前提都要：
          // - 空列表时 _isLoading 决定的是加载态还是空状态，会真的改变树形；
          // - _hasMore 参与 itemCount，翻转必须走 setState。
          final bool quotesUnchanged = list.isNotEmpty &&
              _hasMore == dbHasMore &&
              _isSameQuoteInstances(list);

          if (quotesUnchanged) {
            _isLoading = isLoadMorePage;
          } else {
            final applyStopwatch = Stopwatch()..start();
            _updateState(() {
              _quotes
                ..clear()
                ..addAll(list);
              _hasMore = dbHasMore;
              _isLoading = isLoadMorePage;
              _pruneExpansionControllers();
              // 注意：此处不递增 _resultsVersion。
              // _initializeDataStream 的 stream 持续接收事件（含 load more），
              // 若递增则 resultsKey 变化，AnimatedSwitcher 会销毁旧 ListView 并
              // 创建从偏移量 0 开始的新 ListView，导致列表跳回顶部。
              // 搜索/筛选切换动画由 _updateStreamSubscription 的首个数据事件负责递增。
            });
            applyStopwatch.stop();
            if (profilesLoadMore) {
              NoteListLoadMoreProfile.recordApply(
                applyStopwatch.elapsedMicroseconds,
              );
            }
          }
          // 没换过列表就没有新的夹紧可记；传 null 让它只重试挂起的还原。
          _guardScrollAnchorAfterDataEvent(
            quotesUnchanged ? null : offsetBeforeUpdate,
          );

          if (_loadMorePerfRecording &&
              (_quotes.length > _loadMorePerfStartCount || !_hasMore)) {
            _markLoadMorePerfDataArrived();
          }
          if (isLoadMorePage) {
            _settleLoadMoreGateAfterPage();
          }
          // 列表没变，"有没有可展开的笔记"就不会变。照常调用反而先把缓存清成
          // false，再排一次帧回调重算同一个答案。
          if (!quotesUnchanged) {
            _scheduleExpandableQuoteCheck();
          }

          if (widget.onGuideTargetsReady != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onGuideTargetsReady!.call();
            });
          }

          // 修复：在首次加载期间恢复滚动位置
          if (savedScrollOffset != null &&
              savedScrollOffset > 0 &&
              !_isUserScrolling) {
            final offset = savedScrollOffset; // 捕获非空值
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scrollController.hasClients) {
                final pos = _safeScrollPosition;
                if (pos != null && offset <= pos.maxScrollExtent) {
                  _scrollController.jumpTo(offset);
                }
                logDebug('首次加载期间恢复滚动位置: $offset', source: 'NoteListView');
              }
            });
          }

          if (isFirstLoad) {
            _initialDataLoaded = true;
            _initialLoadTimeoutRecoveries = 0;
            _initialLoadSafetyTimer?.cancel();
            // 通知 Completer：首批数据已就绪（scrollToQuoteById 事件驱动等待）
            if (_initialDataCompleter != null &&
                !_initialDataCompleter!.isCompleted) {
              _initialDataCompleter!.complete();
            }
            // 冷启动完成后允许正常记录用户滚动。
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                _isInitializing = false;
                logDebug('首次加载完成，结束滚动保护期', source: 'NoteListView');
              }
            });
            logDebug('首次数据加载完成', source: 'NoteListView');
            // 首屏就绪后尽快启动空闲预取：用户常在冷启动后 1~2 秒内就开始快滑，
            // 预取必须抢在前面；tick 自带滚动/加载让路，起步早不会挤占滚动帧。
            _scheduleIdlePrefetch(
              delay: const Duration(milliseconds: 400),
            );
            // 同理，首屏卡片一建出来就开始预热后面那些卡片的测量。
            _scheduleIdleLayoutWarmup();
          }

          // 重置滚动范围检查计数器
          _scrollExtentCheckCounter = 0;

          // 通知搜索控制器数据加载完成
          try {
            final searchController = Provider.of<NoteSearchController>(
              context,
              listen: false,
            );
            searchController.setSearchState(false);
          } catch (e) {
            logDebug('更新搜索控制器状态失败: $e');
          }
          // 保险清除搜索过渡状态（首次加载期间用户可能已输入搜索）
          _setSearchUpdating(false);

          if (isFirstLoad) {
            isFirstLoad = false;
          }
        }
      },
      onError: (error) {
        if (mounted) {
          // 出错时也需要 complete completer，避免 scrollToQuoteById 挂起直到超时
          if (_initialDataCompleter != null &&
              !_initialDataCompleter!.isCompleted) {
            _initialDataCompleter!.complete();
          }
          _updateState(() {
            _isLoading = false;
          });
          _setSearchUpdating(false); // 出错时清除搜索过渡状态

          // 重置搜索控制器状态
          try {
            final searchController = Provider.of<NoteSearchController>(
              context,
              listen: false,
            );
            searchController.resetSearchState();
          } catch (e) {
            logDebug('重置搜索控制器状态失败: $e');
          }

          logError('加载笔记失败: $error', error: error, source: 'NoteListView');

          // 显示错误提示
          final l10n = AppLocalizations.of(context);
          AppSnackBar.error(
            context,
            error.toString().contains('TimeoutException')
                ? l10n.queryTimeoutShort
                : (kDebugMode ? error.toString() : l10n.loadFailedSimple),
            action: SnackBarAction(
              label: l10n.retry,
              textColor: Theme.of(context).colorScheme.onErrorContainer,
              onPressed: () => _updateStreamSubscription(),
            ),
          );
        }
      },
    );
    // 安全超时：首次加载若 8 秒仍未收到数据，先区分“确认空数据”
    // 和“分页仍未决”。后者恢复数据流并继续等待，避免把慢查询误判成无笔记。
    if (isFirstLoad) {
      _scheduleInitialLoadSafetyTimer();
    }
  }

  void _scheduleInitialLoadSafetyTimer() {
    _initialLoadSafetyTimer?.cancel();
    _initialLoadSafetyTimer = Timer(
      const Duration(seconds: 8),
      _handleInitialLoadSafetyTimeout,
    );
  }

  void _handleInitialLoadSafetyTimeout() {
    if (!mounted || _initialDataLoaded || !_isLoading || _quotes.isNotEmpty) {
      return;
    }

    final db = _databaseService;
    if (db != null && db.hasMoreQuotes) {
      _initialLoadTimeoutRecoveries++;
      logDebug(
        '首次数据加载安全超时（8s），数据库仍有未决分页，尝试恢复数据流: $_initialLoadTimeoutRecoveries',
        source: 'NoteListView',
      );
      db.refreshQuotes();
      _scheduleInitialLoadSafetyTimer();
      return;
    }

    logDebug(
      '首次数据加载安全超时（8s），结束加载状态',
      source: 'NoteListView',
    );
    _updateState(() {
      _isLoading = false;
    });
    // 只有在数据库也确认没有更多数据时才释放等待定位的 completer；
    // 否则通知定位会在数据仍未决时快速耗尽重试。
    if (_initialDataCompleter != null && !_initialDataCompleter!.isCompleted) {
      _initialDataCompleter!.complete();
    }
  }

  /// 优化：判断是否需要更新订阅
  bool _shouldUpdateSubscription(NoteListView oldWidget) {
    final oldEffectiveQuery =
        NoteListViewState._normalizeSearchQuery(oldWidget.searchQuery);
    return oldEffectiveQuery != _effectiveSearchQuery ||
        !_areListsEqual(oldWidget.selectedTagIds, widget.selectedTagIds) ||
        oldWidget.sortType != widget.sortType ||
        oldWidget.sortAscending != widget.sortAscending ||
        !_areListsEqual(oldWidget.selectedWeathers, widget.selectedWeathers) ||
        !_areListsEqual(
          oldWidget.selectedDayPeriods,
          widget.selectedDayPeriods,
        );
  }

  // 辅助方法：比较两个列表是否相等（深比较）
  bool _areListsEqual(List<dynamic> list1, List<dynamic> list2) {
    if (list1.length != list2.length) return false;
    // 确保顺序一致，如果需要忽略顺序，可以先排序再比较
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  // 修复：新增方法：更新数据库监听流（改进版本）
  void _updateStreamSubscription({
    bool preserveScrollPosition = false,
    bool isSearchUpdate = false,
    bool resetScrollToTop = false,
  }) {
    if (!mounted) return; // 确保组件仍然挂载

    // 结果列表 key 固定，新结果原地替换数据源，不再重建 ListView。
    // 筛选条件变化需要回到顶部时，由 resetScrollToTop 在首个数据事件后显式归零。
    bool pendingScrollToTop = resetScrollToTop;

    logDebug(
      '更新数据流订阅 (preserveScrollPosition: $preserveScrollPosition, isSearchUpdate: $isSearchUpdate, resetScrollToTop: $resetScrollToTop)',
      source: 'NoteListView',
    );

    if (isSearchUpdate) {
      _clearPendingInsertAnimations();
    }

    double? savedScrollOffset;
    // 只有在需要保持滚动位置时才保存（仅排序变化时）
    if (preserveScrollPosition &&
        _scrollController.hasClients &&
        _quotes.isNotEmpty) {
      // ListView 不再重建，position 本身不会丢失偏移；这里保存只是为了在
      // 数据替换导致内容高度变化时把偏移拉回原处。
      savedScrollOffset = _safeScrollOffset;
      logDebug('保存滚动位置: $savedScrollOffset', source: 'NoteListView');
    } else if (!preserveScrollPosition) {
      logDebug('筛选条件变化，不保存滚动位置，将重置到顶部', source: 'NoteListView');
    }

    // 搜索/筛选更新时不设 _isLoading：旧内容保持显示直到新结果淡入替换，
    // 避免底部临时闪现加载动画。仅排序等其余变化设 _isLoading = true。
    if (_initialDataLoaded && !isSearchUpdate && !resetScrollToTop) {
      _updateState(() {
        _isLoading = true;
      });
    }

    // 搜索更新时不重置 _hasMore，防止底部加载动画瞬间闪现
    if (!isSearchUpdate) {
      _hasMore = true;
    }

    final db = _readDatabaseService();

    _quotesSub?.cancel();

    _quotesSub = db
        .watchQuotes(
      tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
      limit: NoteListViewState._pageSize,
      orderBy: widget.sortType == 'time'
          ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
          : widget.sortType == 'favorite'
              ? 'favorite_count ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
      searchQuery:
          _effectiveSearchQuery.isNotEmpty ? _effectiveSearchQuery : null,
      selectedWeathers:
          widget.selectedWeathers.isNotEmpty ? widget.selectedWeathers : null,
      selectedDayPeriods: widget.selectedDayPeriods.isNotEmpty
          ? widget.selectedDayPeriods
          : null,
    )
        .listen(
      (rawList) {
        if (mounted) {
          _dataStreamEventCount++;
          final isLoadMorePage = _loadMoreAwaitingPage &&
              (rawList.length > _loadMoreRequestStartCount ||
                  rawList.length < NoteListViewState._pageSize);
          // 门控用 `_loadMoreAwaitingPage`，理由同上面那条 listen。
          final profilesLoadMore = _loadMoreAwaitingPage;
          final list = _reuseUnchangedQuoteInstances(
            rawList,
            recordProfile: profilesLoadMore,
          );
          final bool dbHasMore = db.hasMoreQuotes;
          final double? offsetBeforeUpdate =
              pendingScrollToTop ? null : _safeScrollOffset;
          // 同 _initializeDataStream：什么都没变的事件不重建整列表。
          // 还等着归零时不能跳过——那一步要靠这次事件把新结果落地后再 jumpTo(0)。
          final bool quotesUnchanged = !pendingScrollToTop &&
              list.isNotEmpty &&
              _hasMore == dbHasMore &&
              _isSameQuoteInstances(list);
          if (quotesUnchanged) {
            _isLoading = isLoadMorePage;
          } else {
            final applyStopwatch = Stopwatch()..start();
            _updateState(() {
              _quotes
                ..clear()
                ..addAll(list);
              _hasMore = dbHasMore;
              _isLoading = isLoadMorePage;
              _pruneExpansionControllers();
            });
            applyStopwatch.stop();
            if (profilesLoadMore) {
              NoteListLoadMoreProfile.recordApply(
                applyStopwatch.elapsedMicroseconds,
              );
            }
          }

          // 筛选条件变化：新结果的第一次事件到达后回到顶部。
          // 之前依赖 ListView 换 key 重建来隐式归零，现在列表常驻，需显式归零。
          if (pendingScrollToTop) {
            pendingScrollToTop = false;
            // 结果集换了，旧的还原目标作废，否则回到顶部后又被拽回旧位置。
            _cancelPendingScrollRestore();
            final pos = _safeScrollPosition;
            if (pos != null && pos.pixels != 0) {
              pos.jumpTo(0);
            }
          }
          if (_loadMorePerfRecording &&
              (_quotes.length > _loadMorePerfStartCount || !_hasMore)) {
            _markLoadMorePerfDataArrived();
          }
          if (isLoadMorePage) {
            _settleLoadMoreGateAfterPage();
          } else {
            // 筛选/排序切换回到第一页后重新预取，让新结果集也覆盖首次快滑。
            _scheduleIdlePrefetch();
            // 只有结果集**真的换过**才把预热游标拨回开头。什么都没变的重复事件
            // （watchQuotes 每次都重发整个累积列表）照样重置的话，游标会被反复
            // 拽回 0，列表尾部的卡片可能永远等不到预热。
            if (!quotesUnchanged) {
              _resetIdleLayoutWarmup();
              _scheduleIdleLayoutWarmup();
            }
          }
          if (!quotesUnchanged) {
            _scheduleExpandableQuoteCheck();
          }

          if (widget.onGuideTargetsReady != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onGuideTargetsReady!.call();
            });
          }

          // 没有走"保留滚动位置"分支时，由通用锚点保护兜住列表变短造成的位移。
          if (savedScrollOffset == null) {
            _guardScrollAnchorAfterDataEvent(
              quotesUnchanged ? null : offsetBeforeUpdate,
            );
          }

          // Restore scroll position smoothly (only if preserveScrollPosition is true)
          // 只在第一次数据到达时恢复一次；之后置 null 防止后续 stream 事件
          // （如 load more）重复 animateTo，导致用户滑动时列表跳回旧位置。
          if (savedScrollOffset != null &&
              _scrollController.hasClients &&
              _initialDataLoaded) {
            final offsetToRestore = savedScrollOffset;
            savedScrollOffset = null; // 立即置空，防止后续 stream 事件再次触发
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (offsetToRestore == null || !_scrollController.hasClients) {
                return;
              }
              // 列表常驻，position 通常已经停在原偏移；只有新结果集变短被
              // 夹紧时才会偏离。用 jumpTo 无动画纠正，避免任何可见位移。
              final pos = _safeScrollPosition;
              if (pos != null &&
                  offsetToRestore <= pos.maxScrollExtent &&
                  (pos.pixels - offsetToRestore).abs() > 0.5) {
                pos.jumpTo(offsetToRestore);
                logDebug('恢复滚动位置: $offsetToRestore', source: 'NoteListView');
              }
            });
          }

          // 重置滚动范围检查计数器
          _scrollExtentCheckCounter = 0;

          // 通知搜索控制器数据加载完成
          try {
            final searchController = Provider.of<NoteSearchController>(
              context,
              listen: false,
            );
            searchController.setSearchState(false);
          } catch (e) {
            logDebug('更新搜索控制器状态失败: $e');
          }

          // 清除搜索过渡动画状态，让列表从"更新中"淡入恢复到正常透明度
          _setSearchUpdating(false);

          logDebug(
            '数据流更新完成，加载了 ${list.length} 条记录',
            source: 'NoteListView',
          );
        }
      },
      onError: (error) {
        if (mounted) {
          _updateState(() {
            _isLoading = false; // 出错时停止加载
          });
          _setSearchUpdating(false); // 出错时也清除搜索过渡状态

          // 重置搜索控制器状态
          try {
            final searchController = Provider.of<NoteSearchController>(
              context,
              listen: false,
            );
            searchController.resetSearchState();
          } catch (e) {
            logDebug('重置搜索控制器状态失败: $e');
          }

          logError('数据流加载失败: $error', error: error, source: 'NoteListView');

          // 优化：更友好的错误提示
          final l10n = AppLocalizations.of(context);
          String errorMessage = l10n.loadNoteFailed;
          if (error.toString().contains('TimeoutException')) {
            errorMessage = l10n.queryTimeoutRetry;
          } else if (error.toString().contains('DatabaseException')) {
            errorMessage = l10n.databaseQueryError;
          }
          _showErrorSnackBar(errorMessage);
        }
      },
    );
  }
}
