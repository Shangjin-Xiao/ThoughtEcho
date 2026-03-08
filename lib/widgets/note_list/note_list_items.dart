part of '../note_list_view.dart';

/// List building, search, and item rendering for NoteListViewState.
extension _NoteListItemsExtension on NoteListViewState {
  Widget _buildNoteListView(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final searchController = Provider.of<NoteSearchController>(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    _firstOpenScrollPerfEnabled = context.select<SettingsService, bool>(
      (s) => s.appSettings.developerMode && s.enableFirstOpenScrollPerfMonitor,
    );

    // 监听搜索控制器状态，如果搜索出错则重置本地加载状态
    if (searchController.searchError != null && _isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateState(() {
            _isLoading = false;
          });
          searchController.resetSearchState();
        }
      });
    }

    // 响应式设计：根据屏幕宽度调整布局
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > AppConstants.tabletMinWidth;
    final maxWidth = isTablet ? AppConstants.tabletMaxContentWidth : width;
    final horizontalPadding = isTablet ? 16.0 : 8.0;

    // 布局构建
    return LayoutBuilder(
      builder: (context, constraints) {
        // 主体内容 - 使用极浅主题色背景，适配深色模式
        final backgroundColor = ColorUtils.getNoteListBackgroundColor(
          theme.colorScheme.surface,
          theme.brightness,
        );

        return Container(
          color: backgroundColor,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  // 搜索框 - 现代圆角样式，筛选按钮内嵌到右侧
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      MediaQuery.of(context).padding.top + 8.0,
                      horizontalPadding,
                      0,
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: l10n.searchNotes,
                        isDense: true,
                        filled: true,
                        fillColor: ColorUtils.getSearchBoxBackgroundColor(
                          theme.colorScheme.surface,
                          theme.brightness,
                        ),
                        prefixIcon: searchController.isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Icon(Icons.search),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // AI搜索切换按钮
                            Consumer<SettingsService>(
                              builder: (context, settings, _) {
                                final localAI = settings.localAISettings;
                                // 只有启用了本地AI和AI搜索功能才显示
                                if (localAI.enabled &&
                                    localAI.aiSearchEnabled) {
                                  return IconButton(
                                    icon: Icon(
                                      _isAISearchMode
                                          ? Icons.auto_awesome
                                          : Icons.search,
                                      color: _isAISearchMode
                                          ? theme.colorScheme.primary
                                          : null,
                                    ),
                                    tooltip: _isAISearchMode
                                        ? l10n.aiSearchMode
                                        : l10n.normalSearchMode,
                                    onPressed: () {
                                      _updateState(() {
                                        _isAISearchMode = !_isAISearchMode;
                                      });
                                      // 如果有搜索词，重新搜索
                                      if (_searchController.text.isNotEmpty) {
                                        _onSearchChanged(
                                            _searchController.text);
                                      }
                                    },
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            // 筛选按钮
                            IconButton(
                              key: widget.filterButtonKey, // 功能引导 key
                              icon: const Icon(Icons.tune),
                              tooltip: l10n.filterAndSortTooltip,
                              onPressed: () {
                                final settings =
                                    context.read<SettingsService>();
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLowest,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                  ),
                                  builder: (context) => NoteFilterSortSheet(
                                    allTags: _effectiveTags,
                                    selectedTagIds: widget.selectedTagIds,
                                    sortType: widget.sortType,
                                    sortAscending: widget.sortAscending,
                                    selectedWeathers: widget.selectedWeathers,
                                    selectedDayPeriods:
                                        widget.selectedDayPeriods,
                                    requireBiometricForHidden:
                                        settings.requireBiometricForHidden,
                                    onApply: (
                                      tagIds,
                                      sortType,
                                      sortAscending,
                                      selectedWeathers,
                                      selectedDayPeriods,
                                    ) {
                                      widget.onTagSelectionChanged(tagIds);
                                      widget.onSortChanged(
                                        sortType,
                                        sortAscending,
                                      );
                                      widget.onFilterChanged(
                                        selectedWeathers,
                                        selectedDayPeriods,
                                      );
                                      _updateStreamSubscription();
                                    },
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.28),
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.20),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.65),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 筛选条件展示区域
                  _buildFilterDisplay(theme, horizontalPadding),

                  // 笔记列表 - 添加平滑过渡动画
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeOut,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: _buildNoteList(db, theme),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoteList(DatabaseService db, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    // 为 AnimatedSwitcher 提供唯一 key，确保筛选变化时能触发动画
    final listKey = ValueKey(
      '${widget.selectedTagIds.join(',')}_${widget.selectedWeathers.join(',')}_${widget.selectedDayPeriods.join(',')}_${widget.searchQuery}',
    );

    // 修复：检查标签是否已加载（外部标签或本地缓存任一不为空即可）
    final bool tagsLoaded =
        widget.tags.isNotEmpty || _localTagsCache.isNotEmpty;

    // 修复：等待服务初始化或标签未加载时显示加载动画，避免闪现"无笔记"或"未知标签"
    if (_waitingForServices ||
        (_isLoading && _quotes.isEmpty) ||
        (!tagsLoaded && _quotes.isNotEmpty)) {
      // 搜索时用专属动画
      if (widget.searchQuery.isNotEmpty) {
        return LayoutBuilder(
          key: listKey,
          builder: (context, constraints) {
            final size = (constraints.maxHeight * 0.7).clamp(120.0, 400.0);
            return Center(
              child: EnhancedLottieAnimation(
                type: LottieAnimationType.weatherSearchLoading,
                width: size,
                height: size,
                semanticLabel: l10n.searchingLabel,
              ),
            );
          },
        );
      }
      return AppLoadingView(key: listKey);
    }
    if (_quotes.isEmpty && widget.searchQuery.isEmpty) {
      return AppEmptyView(
        key: listKey,
        svgAsset: 'assets/empty/empty_state.svg',
        text: l10n.noteListEmptyTitle,
      );
    }
    if (_quotes.isEmpty && widget.searchQuery.isNotEmpty) {
      return Center(
        key: listKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final size = (constraints.maxHeight * 0.5).clamp(80.0, 220.0);
                return EnhancedLottieAnimation(
                  type: LottieAnimationType.notFound,
                  width: size,
                  height: size,
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noteSearchEmptyTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noteSearchEmptySubtitle,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    var favoriteGuideAssigned = false;
    var moreGuideAssigned = false;
    var foldGuideAssigned = false;

    // 优化：提前创建标签映射，避免在 item builder 中重复计算
    // 将整体复杂度从 O(L * T) 优化为 O(L + T)，其中构建映射为 O(L)，每次查找为 O(1)
    final tagMap = {for (var t in _effectiveTags) t.id: t};

    return NotificationListener<ScrollNotification>(
      key: listKey,
      onNotification: (ScrollNotification notification) {
        if (_firstOpenScrollPerfEnabled && !_firstOpenScrollPerfCaptured) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _startFirstOpenScrollPerfCapture();
          } else if (_firstOpenScrollPerfRecording &&
              notification is ScrollUpdateNotification) {
            _firstOpenScrollUpdateMicros
                .add(DateTime.now().microsecondsSinceEpoch);
          } else if (notification is ScrollEndNotification) {
            _stopFirstOpenScrollPerfCapture();
          }
        }

        // 预加载逻辑：热路径不做日志、不做分配
        if (notification is ScrollUpdateNotification) {
          // 标记列表正在滚动（含惯性阶段），阻止图片提前解码
          isListScrolling.value = true;
          final metrics = notification.metrics;
          final threshold =
              metrics.maxScrollExtent * AppConstants.scrollPreloadThreshold;
          if (metrics.pixels > threshold &&
              metrics.maxScrollExtent > 0 &&
              !_isLoading &&
              _hasMore) {
            _loadMore();
          }
        }

        // 滚动完全停止（含惯性）：重置用户滚动状态 + 延迟检查
        if (notification is ScrollEndNotification) {
          // 列表完全静止，允许图片开始解码
          isListScrolling.value = false;
          // 重置用户滚动状态，记录最后滚动时间用于 _scrollToItem 的 900ms 冷却
          _isUserScrolling = false;
          _lastUserScrollTime = DateTime.now();

          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 100 &&
              _hasMore &&
              !_isLoading) {
            _loadMore();
          }

          // 滚动范围异常检测：从 _onScroll 热路径移至此处，避免滚动期间做 Provider 查找
          _checkAndFixScrollExtentAnomaly();
        }
        return false;
      },
      // 性能优化：BackdropGroup 让多个 BackdropFilter.grouped 共享采样
      // 减少 GPU 重复帧缓冲读回，显著降低多模糊 item 同屏时的光栅开销
      child: BackdropGroup(
        child: ListView.builder(
          controller: _scrollController, // 添加滚动控制器
          physics: const AlwaysScrollableScrollPhysics(),
          addAutomaticKeepAlives: true, // 保持默认：图片组件依赖 keepAlive 避免重加载闪烁
          addRepaintBoundaries: true, // 性能优化：减少重绘范围
          // 性能优化：惯性首帧移动距离远大于拖拽帧，需要更大缓存区预构建 item
          // 避免 drag→ballistic 过渡时集中构建新 item 导致卡顿
          cacheExtent: MediaQuery.sizeOf(context).height.clamp(400, 900),
          itemCount: _quotes.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < _quotes.length) {
              final quote = _quotes[index];
              if (quote.id == null) {
                logDebug('笔记缺少ID，跳过扩展状态管理', source: 'NoteListView');
                return const SizedBox.shrink();
              }

              final quoteId = quote.id!;
              final String itemKey = 'quote_${quoteId}_$index';
              _itemKeys.putIfAbsent(
                quoteId,
                () => GlobalKey(debugLabel: itemKey),
              );

              final bool shouldCheckExpansionForGuide =
                  !foldGuideAssigned && widget.foldToggleGuideKey != null;
              final bool needsExpansion = shouldCheckExpansionForGuide
                  ? QuoteItemWidget.needsExpansionFor(quote)
                  : false;

              final attachFavoriteGuideKey = !favoriteGuideAssigned &&
                  widget.favoriteButtonGuideKey != null &&
                  widget.onFavorite != null;
              final attachMoreGuideKey =
                  !moreGuideAssigned && widget.moreButtonGuideKey != null;
              final attachFoldGuideKey = !foldGuideAssigned &&
                  widget.foldToggleGuideKey != null &&
                  needsExpansion;

              if (attachFavoriteGuideKey) {
                favoriteGuideAssigned = true;
              }

              if (attachMoreGuideKey) {
                moreGuideAssigned = true;
              }

              if (attachFoldGuideKey) {
                foldGuideAssigned = true;
              }

              final expansionNotifier = _obtainExpansionNotifier(quoteId);
              _expandedItems.putIfAbsent(
                  quoteId, () => expansionNotifier.value);

              return KeyedSubtree(
                key: _itemKeys[quoteId],
                child: ValueListenableBuilder<bool>(
                  valueListenable: expansionNotifier,
                  builder: (context, isExpanded, child) => QuoteItemWidget(
                    quote: quote,
                    tagMap: tagMap,
                    selectedTagIds: widget.selectedTagIds,
                    isExpanded: isExpanded,
                    onToggleExpanded: (expanded) {
                      if (expansionNotifier.value != expanded) {
                        expansionNotifier.value = expanded;
                      }
                      _expandedItems[quoteId] = expanded;

                      final bool requiresAlignment =
                          QuoteItemWidget.needsExpansionFor(quote);

                      if (!expanded && requiresAlignment) {
                        final waitDuration =
                            QuoteItemWidget.expandCollapseDuration +
                                const Duration(milliseconds: 80);
                        Future.delayed(waitDuration, () {
                          if (!mounted) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _scrollToItem(quoteId, index);
                          });
                        });
                      }
                    },
                    onEdit: () => widget.onEdit(quote),
                    onDelete: () => widget.onDelete(quote),
                    onAskAI: () => widget.onAskAI(quote),
                    onGenerateCard: widget.onGenerateCard != null
                        ? () => widget.onGenerateCard!(quote)
                        : null,
                    onFavorite: widget.onFavorite != null
                        ? () => widget.onFavorite!(quote)
                        : null,
                    onLongPressFavorite: widget.onLongPressFavorite != null
                        ? () => widget.onLongPressFavorite!(quote)
                        : null,
                    favoriteButtonGuideKey: attachFavoriteGuideKey
                        ? widget.favoriteButtonGuideKey
                        : null,
                    moreButtonGuideKey:
                        attachMoreGuideKey ? widget.moreButtonGuideKey : null,
                    foldToggleGuideKey:
                        attachFoldGuideKey ? widget.foldToggleGuideKey : null,
                    // 不使用自定义 tagBuilder，让 QuoteItemWidget 使用内部的标签渲染逻辑
                    // 这样可以支持筛选标签的优先显示和高亮效果
                  ),
                ),
              );
            }
            // 底部加载指示器
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: AppLoadingView(size: 32),
            );
          },
        ),
      ),
    );
  }

  // 优化：搜索内容变化回调，添加防抖机制
  void _onSearchChanged(String value) {
    // 取消之前的防抖定时器
    _searchDebounceTimer?.cancel();

    // 性能优化：只在必要时调用 setState，避免不必要的重建
    final shouldSetLoading = (value.isEmpty && widget.searchQuery.isNotEmpty) ||
        (value.isNotEmpty && value.length >= AppConstants.minSearchLength);

    if (shouldSetLoading && !_isLoading) {
      _updateState(() {
        _isLoading = true;
      });
      if (value.isEmpty) {
        logDebug('搜索内容被清空，重置加载状态');
      }
    }

    // 对于清空操作，立即执行
    if (value.isEmpty) {
      _performSearch(value);
      return;
    }

    // 优化：只有当搜索内容长度>=2时才使用防抖延迟
    if (value.length >= AppConstants.minSearchLength) {
      _searchDebounceTimer = Timer(AppConstants.searchDebounceDelay, () {
        if (mounted) {
          _performSearch(value);
        }
      });
    } else {
      // 长度小于2时直接执行，不触发实际搜索
      _performSearch(value);
    }
  }

  /// 优化：执行搜索的统一方法
  void _performSearch(String value) {
    if (!mounted) return;

    logDebug('执行搜索: "$value"', source: 'NoteListView');

    // 如果是非空搜索且长度>=2，通知搜索控制器开始搜索
    if (value.isNotEmpty && value.length >= AppConstants.minSearchLength) {
      try {
        final searchController = Provider.of<NoteSearchController>(
          context,
          listen: false,
        );
        searchController.setSearchState(true);
      } catch (e) {
        logDebug('设置搜索状态失败: $e');
      }
    }

    // 直接调用父组件的搜索回调
    widget.onSearchChanged(value);

    // 优化：只有在实际搜索时才设置超时保护，使用常量配置的超时时间
    if (value.isNotEmpty && value.length >= AppConstants.minSearchLength) {
      Timer(AppConstants.searchTimeout, () {
        if (mounted && _isLoading) {
          _updateState(() {
            _isLoading = false;
          });
          try {
            final searchController = Provider.of<NoteSearchController>(
              context,
              listen: false,
            );
            searchController.resetSearchState();
          } catch (e) {
            logDebug('重置搜索状态失败: $e');
          }
          logDebug('搜索超时，已重置加载状态');

          // 显示超时提示
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.noteSearchTimeoutMessage),
                duration: AppConstants.snackBarDurationImportant,
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: l10n.retry,
                  textColor: Colors.white,
                  onPressed: () => _performSearch(value),
                ),
              ),
            );
          }
        }
      });
    }
  }
}
