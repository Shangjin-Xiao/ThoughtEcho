part of '../note_list_view.dart';

/// Data stream and subscription management for NoteListViewState.
extension _NoteListDataStreamExtension on NoteListViewState {
  void _scheduleExpandableQuoteCheck() {
    _hasExpandableQuoteComputed = false;
    _hasExpandableQuoteCached = false;

    if (_quotes.isEmpty) {
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
      (list) {
        if (mounted) {
          _dataStreamEventCount++;
          final isLoadMorePage = _loadMoreAwaitingPage &&
              (list.length > _loadMoreRequestStartCount ||
                  list.length < NoteListViewState._pageSize);
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

          _updateState(() {
            if (isFirstLoad) {
              _quotes.clear();
            }
            _quotes
              ..clear()
              ..addAll(
                list,
              ); // Simplified: always replace for consistency, but flag prevents extra sets
            _hasMore = list.length >= NoteListViewState._pageSize;
            _isLoading = isLoadMorePage;
            _pruneExpansionControllers();
            // 注意：此处不递增 _resultsVersion。
            // _initializeDataStream 的 stream 持续接收事件（含 load more），
            // 若递增则 resultsKey 变化，AnimatedSwitcher 会销毁旧 ListView 并
            // 创建从偏移量 0 开始的新 ListView，导致列表跳回顶部。
            // 搜索/筛选切换动画由 _updateStreamSubscription 的首个数据事件负责递增。
          });
          if (_loadMorePerfRecording &&
              (_quotes.length > _loadMorePerfStartCount || !_hasMore)) {
            _markLoadMorePerfDataArrived();
          }
          if (isLoadMorePage) {
            _settleLoadMoreGateAfterPage();
          }
          _scheduleExpandableQuoteCheck();

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
          }

          // 修复：同步 _hasMore 状态与数据库服务状态
          final dbService = _databaseService ?? _readDatabaseService();
          if (_hasMore != dbService.hasMoreQuotes) {
            logDebug(
              '同步 _hasMore 状态: $_hasMore -> ${dbService.hasMoreQuotes}',
              source: 'NoteListView',
            );
            _hasMore = dbService.hasMoreQuotes;
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
          AppSnackBar.error(
            context,
            error.toString().contains('TimeoutException')
                ? '查询超时'
                : (kDebugMode ? error.toString() : '加载失败'),
            action: SnackBarAction(
              label: '重试',
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
      (list) {
        if (mounted) {
          _dataStreamEventCount++;
          final isLoadMorePage = _loadMoreAwaitingPage &&
              (list.length > _loadMoreRequestStartCount ||
                  list.length < NoteListViewState._pageSize);
          _updateState(() {
            _quotes.clear();
            _quotes.addAll(list);
            _hasMore = list.length >= NoteListViewState._pageSize;
            _isLoading = isLoadMorePage;
            _pruneExpansionControllers();
          });

          // 筛选条件变化：新结果的第一次事件到达后回到顶部。
          // 之前依赖 ListView 换 key 重建来隐式归零，现在列表常驻，需显式归零。
          if (pendingScrollToTop) {
            pendingScrollToTop = false;
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
          }
          _scheduleExpandableQuoteCheck();

          if (widget.onGuideTargetsReady != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onGuideTargetsReady!.call();
            });
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

          // 修复：同步 _hasMore 状态与数据库服务状态
          final dbServiceForSync = _databaseService ?? _readDatabaseService();
          if (_hasMore != dbServiceForSync.hasMoreQuotes) {
            logDebug(
              '更新订阅后同步 _hasMore 状态: $_hasMore -> ${dbServiceForSync.hasMoreQuotes}',
              source: 'NoteListView',
            );
            _hasMore = dbServiceForSync.hasMoreQuotes;
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
          String errorMessage = '加载笔记失败';
          if (error.toString().contains('TimeoutException')) {
            errorMessage = '查询超时，请重试';
          } else if (error.toString().contains('DatabaseException')) {
            errorMessage = '数据库查询出错';
          }
          _showErrorSnackBar(errorMessage);
        }
      },
    );
  }
}
