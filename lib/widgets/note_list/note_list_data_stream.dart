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

      final bool hasExpandable = _quotes
          .take(80)
          .any(QuoteItemWidget.needsExpansionFor);

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

    final db = Provider.of<DatabaseService>(context, listen: false);

    if (!db.isInitialized) {
      logDebug('数据库未初始化，等待初始化完成后重新订阅');
      db.addListener(_onDatabaseServiceChanged);
      return;
    }

    bool isFirstLoad = !_initialDataLoaded;

    _quotesSub = db
        .watchQuotes(
          tagIds: widget.selectedTagIds.isNotEmpty
              ? widget.selectedTagIds
              : null,
          limit: NoteListViewState._pageSize,
          orderBy: widget.sortType == 'time'
              ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : widget.sortType == 'favorite'
              ? 'favorite_count ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
          searchQuery: widget.searchQuery.isNotEmpty
              ? widget.searchQuery
              : null,
          selectedWeathers: widget.selectedWeathers.isNotEmpty
              ? widget.selectedWeathers
              : null,
          selectedDayPeriods: widget.selectedDayPeriods.isNotEmpty
              ? widget.selectedDayPeriods
              : null,
        )
        .listen(
          (list) {
            if (mounted) {
              final isPlaceholderInitialEmission =
                  isFirstLoad && list.isEmpty && db.hasMoreQuotes;

              if (isPlaceholderInitialEmission) {
                logDebug('忽略首个占位空列表，继续等待真实首批数据', source: 'NoteListView');
                return;
              }

              // 修复：在首次加载期间保存滚动位置，避免数据刷新时滚动到顶部
              double? savedScrollOffset;
              if (isFirstLoad &&
                  _scrollController.hasClients &&
                  _quotes.isNotEmpty) {
                savedScrollOffset = _scrollController.offset;
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
                _isLoading = false;
                _pruneExpansionControllers();
              });
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
                  if (mounted &&
                      _scrollController.hasClients &&
                      offset <= _scrollController.position.maxScrollExtent) {
                    _scrollController.jumpTo(offset);
                    logDebug('首次加载期间恢复滚动位置: $offset', source: 'NoteListView');
                  }
                });
              }

              if (isFirstLoad) {
                _initialDataLoaded = true;
                // 通知 Completer：首批数据已就绪（scrollToQuoteById 事件驱动等待）
                if (_initialDataCompleter != null &&
                    !_initialDataCompleter!.isCompleted) {
                  _initialDataCompleter!.complete();
                }
                // 延迟启用自动滚动，避免冷启动时的滚动冲突
                Future.delayed(const Duration(milliseconds: 1500), () {
                  if (mounted) {
                    _autoScrollEnabled = true;
                    _isInitializing = false;
                    logDebug('首次加载完成，启用自动滚动', source: 'NoteListView');
                  }
                });
                // 冷启动保护期：设置较长的保护期，避免首次进入时的滚动冲突
                _lastUserScrollTime = DateTime.now();
                // 只预热首屏附近富文本，避免首滑前后集中解析所有 Delta JSON。
                QuoteContent.prewarmDocumentCache(list);
                logDebug('首次数据加载完成', source: 'NoteListView');
              }

              // 修复：同步 _hasMore 状态与数据库服务状态
              final dbService = Provider.of<DatabaseService>(
                context,
                listen: false,
              );
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

              if (isFirstLoad) {
                isFirstLoad = false;
              }
            }
          },
          onError: (error) {
            if (mounted) {
              _updateState(() {
                _isLoading = false;
              });

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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    error.toString().contains('TimeoutException')
                        ? '查询超时'
                        : (kDebugMode ? error.toString() : '加载失败'),
                  ),
                  duration: AppConstants.snackBarDurationImportant,
                  backgroundColor: Colors.red,
                  action: SnackBarAction(
                    label: '重试',
                    textColor: Colors.white,
                    onPressed: () => _updateStreamSubscription(),
                  ),
                ),
              );
            }
          },
        );
    // 注释掉重复的loadMore调用，因为watchQuotes已经会自动加载数据
    // _loadMore(); // 这行导致双重加载和滚动位置混乱
  }

  /// 优化：判断是否需要更新订阅
  bool _shouldUpdateSubscription(NoteListView oldWidget) {
    return oldWidget.searchQuery != widget.searchQuery ||
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
  void _updateStreamSubscription({bool preserveScrollPosition = false}) {
    if (!mounted) return; // 确保组件仍然挂载

    logDebug(
      '更新数据流订阅 (preserveScrollPosition: $preserveScrollPosition)',
      source: 'NoteListView',
    );

    double? savedScrollOffset;
    // 只有在需要保持滚动位置时才保存（仅排序变化时）
    if (preserveScrollPosition &&
        _scrollController.hasClients &&
        _quotes.isNotEmpty) {
      savedScrollOffset = _scrollController.offset;
      logDebug('保存滚动位置: $savedScrollOffset', source: 'NoteListView');
    } else if (!preserveScrollPosition) {
      logDebug('筛选条件变化，不保存滚动位置，将重置到顶部', source: 'NoteListView');
    }

    // Set loading only if not first load
    if (_initialDataLoaded) {
      _updateState(() {
        _isLoading = true;
      });
    }

    _hasMore = true;

    final db = Provider.of<DatabaseService>(context, listen: false);

    _quotesSub?.cancel();

    _quotesSub = db
        .watchQuotes(
          tagIds: widget.selectedTagIds.isNotEmpty
              ? widget.selectedTagIds
              : null,
          limit: NoteListViewState._pageSize,
          orderBy: widget.sortType == 'time'
              ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : widget.sortType == 'favorite'
              ? 'favorite_count ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
          searchQuery: widget.searchQuery.isNotEmpty
              ? widget.searchQuery
              : null,
          selectedWeathers: widget.selectedWeathers.isNotEmpty
              ? widget.selectedWeathers
              : null,
          selectedDayPeriods: widget.selectedDayPeriods.isNotEmpty
              ? widget.selectedDayPeriods
              : null,
        )
        .listen(
          (list) {
            if (mounted) {
              _updateState(() {
                _quotes.clear();
                _quotes.addAll(list);
                _hasMore = list.length >= NoteListViewState._pageSize;
                _isLoading = false;
                _pruneExpansionControllers();
              });
              _scheduleExpandableQuoteCheck();

              if (widget.onGuideTargetsReady != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  widget.onGuideTargetsReady!.call();
                });
              }

              // Restore scroll position smoothly (only if preserveScrollPosition is true)
              if (savedScrollOffset != null &&
                  _scrollController.hasClients &&
                  _initialDataLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (savedScrollOffset != null &&
                      _scrollController.hasClients &&
                      savedScrollOffset <=
                          _scrollController.position.maxScrollExtent) {
                    _scrollController.animateTo(
                      savedScrollOffset,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                    logDebug(
                      '平滑恢复滚动位置: $savedScrollOffset',
                      source: 'NoteListView',
                    );
                  } else {
                    logDebug('滚动位置超出范围或条件不满足，保持当前位置', source: 'NoteListView');
                  }
                });
              }

              // 修复：同步 _hasMore 状态与数据库服务状态
              final dbServiceForSync = Provider.of<DatabaseService>(
                context,
                listen: false,
              );
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
