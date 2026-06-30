part of '../note_list_view.dart';

/// List building, search, and item rendering for NoteListViewState.
extension _NoteListItemsExtension on NoteListViewState {
  Widget _buildNoteListView(BuildContext context) {
    final searchController = Provider.of<NoteSearchController>(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    _firstOpenScrollPerfEnabled = context.select<SettingsService, bool>(
      (s) => s.appSettings.developerMode && s.enableFirstOpenScrollPerfMonitor,
    );
    final noteInsertAnimationType = context.select<SettingsService, String>(
      (s) => s.noteInsertAnimationType,
    );
    if (_firstOpenScrollPerfEnabled) {
      _noteListBuildCount++;
    }

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

        Widget mainContent = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              children: [
                // 搜索框 - 现代圆角样式，筛选按钮内嵌到右侧
                // 使用 AnimatedOpacity 保持布局树稳定，避免 ListView 滚动跳动
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  opacity: _isExportMode ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _isExportMode,
                    child: Container(
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
                        onSubmitted: (_) => _searchFocusNode.unfocus(),
                        decoration: InputDecoration(
                          hintText: l10n.searchNotes,
                          isDense: true,
                          filled: true,
                          fillColor: ColorUtils.getSearchBoxBackgroundColor(
                            theme.colorScheme.surface,
                            theme.brightness,
                          ),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                  ),
                ),

                // 筛选条件展示区域
                _buildFilterDisplay(theme, horizontalPadding),

                // 笔记列表 - 搜索过渡动画 + 状态切换动画
                // AnimatedOpacity: 搜索时列表轻微变淡提示"更新中"，结果到达后淡入恢复
                // AnimatedSwitcher: 处理 loading/empty/no_results/results 之间的状态切换
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      opacity: _isSearchUpdating ? 0.4 : 1.0,
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
                        child: _buildNoteList(theme, noteInsertAnimationType),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        mainContent = Stack(
          children: [
            mainContent,
            // 顶部悬浮控制栏
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              top: _isExportMode
                  ? MediaQuery.of(context).padding.top + 8.0
                  : -(MediaQuery.of(context).padding.top + 80.0),
              left: horizontalPadding,
              right: horizontalPadding,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _isExportMode ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_isExportMode,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            _updateState(() {
                              _isExportMode = false;
                              _selectedExportNoteIds.clear();
                            });
                          },
                          child: Text(l10n.cancel),
                        ),
                        const Spacer(),
                        Text(
                          "${l10n.pdfExportSelectionMode} (${_selectedExportNoteIds.length})",
                          style: theme.textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _selectAllVisibleNotes,
                          child: Text(
                            _selectedExportNoteIds.containsAll(_quotes
                                    .map((q) => q.id)
                                    .whereType<String>())
                                ? l10n.prefClearAll
                                : l10n.prefSelectAll,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 底部悬浮控制栏
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              bottom: _isExportMode ? 16.0 : -100.0,
              left: horizontalPadding,
              right: horizontalPadding,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _isExportMode ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_isExportMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _selectSameMonthNotes,
                            icon: const Icon(Icons.calendar_month_outlined,
                                size: 18),
                            label: Text(l10n.selectSameMonth,
                                style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _selectSameCategoryNotes,
                            icon: const Icon(Icons.label_outline, size: 18),
                            label: Text(l10n.selectSameCategory,
                                style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _selectedExportNoteIds.isEmpty
                                ? null
                                : _exportSelectedNotesToPdf,
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: Text(
                              l10n.exportSelected(
                                  _selectedExportNoteIds.length),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        return Container(
          color: backgroundColor,
          child: mainContent,
        );
      },
    );
  }

  Widget _buildNoteList(ThemeData theme, String noteInsertAnimationType) {
    final l10n = AppLocalizations.of(context);
    // key 拆分，避免状态内输入时由于 searchQuery 改变导致 AnimatedSwitcher 触发不必要闪烁：
    // • loadingKey 用于加载态的 Key
    // • emptyKey 用于初始无笔记状态的 Key
    // • noResultsKey 用于搜索无匹配结果状态的 Key
    // • resultsKey 用于展示列表的 Key
    final filterBase =
        '${widget.selectedTagIds.join(',')}_${widget.selectedWeathers.join(',')}_${widget.selectedDayPeriods.join(',')}';
    final loadingKey = ValueKey('${filterBase}_loading');
    final emptyKey = ValueKey('${filterBase}_empty');
    final noResultsKey = ValueKey('${filterBase}_no_results');
    final resultsKey = ValueKey('${filterBase}_results_$_resultsVersion');

    // 仅在服务初始化或首批笔记尚未返回时显示 loading。
    // 本地 SQLite 搜索通常 < 100 ms，不单独显示搜索加载动画；
    // 旧结果保持可见直到新结果到达，由 AnimatedSwitcher 淡入淡出切换。
    if (_waitingForServices || (_isLoading && _quotes.isEmpty)) {
      return AppLoadingView(key: loadingKey);
    }
    if (_quotes.isEmpty && widget.searchQuery.isEmpty) {
      return AppEmptyView(
        key: emptyKey,
        svgAsset: 'assets/empty/empty_state.svg',
        text: l10n.noteListEmptyTitle,
      );
    }
    if (_quotes.isEmpty && widget.searchQuery.isNotEmpty) {
      return Center(
        key: noResultsKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 32),
              SizedBox(
                width: 180,
                height: 180,
                child: EnhancedLottieAnimation(
                  type: LottieAnimationType.notFound,
                  width: 180,
                  height: 180,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noteSearchEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.noteSearchEmptySubtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    }

    var favoriteGuideAssigned = false;
    var moreGuideAssigned = false;
    var foldGuideAssigned = false;

    // 优化：提前创建标签映射，避免在 item builder 中重复计算
    // 将整体复杂度从 O(L * T) 优化为 O(L + T)，其中构建映射为 O(L)，每次查找为 O(1)
    final tagMap = {for (var t in _effectiveTags) t.id: t};
    final rowIndexByKey = <String, int>{
      for (var i = 0; i < _quotes.length; i++)
        if (_quotes[i].id case final id?) 'note-list-row-$id': i,
    };

    return NotificationListener<ScrollNotification>(
      key: resultsKey,
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

        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          if (_searchFocusNode.hasFocus) {
            _searchFocusNode.unfocus();
          }
          _startScrollSessionPerfCapture(notification.metrics);
        } else if (notification is ScrollUpdateNotification) {
          _recordScrollSessionUpdate(notification.metrics);
        } else if (notification is ScrollEndNotification) {
          _scheduleScrollSessionPerfFinalize(notification.metrics);
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
              !_isAutoScrolling &&
              !_isLoading &&
              _hasMore) {
            _loadMore();
          }
        }

        // 滚动完全停止（含惯性）：重置用户滚动状态 + 延迟检查
        if (notification is ScrollEndNotification) {
          // 列表完全静止，允许图片开始解码
          isListScrolling.value = false;
          // 重置用户滚动状态。
          _isUserScrolling = false;

          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 100 &&
              !_isAutoScrolling &&
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
          findChildIndexCallback: (key) {
            if (key is ValueKey<String>) {
              return rowIndexByKey[key.value];
            }
            return null;
          },
          physics: const AlwaysScrollableScrollPhysics(),
          addAutomaticKeepAlives: true, // 保持默认：图片组件依赖 keepAlive 避免重加载闪烁
          addRepaintBoundaries: true, // 性能优化：减少重绘范围
          addSemanticIndexes: false, // 性能权衡：关闭所有列表项的自动顺序语义索引
          // 性能优化：惯性首帧移动距离远大于拖拽帧，需要更大缓存区预构建 item
          // 避免 drag→ballistic 过渡时集中构建新 item 导致卡顿
          scrollCacheExtent: ScrollCacheExtent.pixels(
            MediaQuery.sizeOf(context).height.clamp(400, 900).toDouble(),
          ),
          semanticChildCount: _quotes.length + (_hasMore ? 1 : 0),
          itemCount: _quotes.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < _quotes.length) {
              return _traceNoteListItemBuild(
                index: index,
                quote: _quotes[index],
                builder: () {
                  final quote = _quotes[index];
                  if (quote.id == null) {
                    logDebug('笔记缺少ID，跳过扩展状态管理', source: 'NoteListView');
                    return const SizedBox.shrink();
                  }

                  final quoteId = quote.id!;
                  final itemKey = quoteId == _positioningQuoteId
                      ? _positioningItemKey
                      : ValueKey<String>('note-list-row-$quoteId');

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

                  final isSelected = _selectedExportNoteIds.contains(quoteId);

                  final insertAnimationVersion =
                      _animatingQuoteVersions[quoteId];
                  final isStructuralInsert =
                      _structuralInsertQuoteIds.contains(quoteId);

                  Widget itemWidget = ValueListenableBuilder<bool>(
                    valueListenable: expansionNotifier,
                    builder: (context, isExpanded, child) => QuoteItemWidget(
                      quote: quote,
                      tagMap: tagMap,
                      selectedTagIds: widget.selectedTagIds,
                      isExpanded: isExpanded,
                      isSelected: isSelected,
                      selectionMode: _isExportMode,
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
                              unawaited(
                                _positionAndAlignQuote(
                                  quoteId,
                                  index,
                                  forceAlignToTop: false,
                                ),
                              );
                            });
                          });
                        }
                      },
                      onEdit: () => widget.onEdit(quote),
                      onDelete: () {
                        if (quoteId.isNotEmpty) {
                          if (_deletingQuoteIds.contains(quoteId)) {
                            return;
                          }
                          _updateState(() {
                            _deletingQuoteIds.add(quoteId);
                          });
                          // 等动画播完（250ms）+ 50ms 余量再执行真正的删除。
                          // 先从本地列表乐观移除，避免 stream 更新时的视觉跳动。
                          Future.delayed(
                            const Duration(milliseconds: 280),
                            () {
                              if (mounted) {
                                _updateState(() {
                                  _quotes.removeWhere(
                                    (q) => q.id == quoteId,
                                  );
                                  _deletingQuoteIds.remove(quoteId);
                                });
                              }
                              widget.onDelete(quote);
                            },
                          );
                        } else {
                          widget.onDelete(quote);
                        }
                      },
                      onAskAI: () => widget.onAskAI(quote),
                      onGenerateCard: widget.onGenerateCard != null
                          ? () => widget.onGenerateCard!(quote)
                          : null,
                      onExportPdf: () {
                        HapticFeedback.selectionClick();
                        _updateState(() {
                          _isExportMode = true;
                          _selectedExportNoteIds.clear();
                          if (quote.id != null) {
                            _selectedExportNoteIds.add(quote.id!);
                          }
                        });
                      },
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
                    ),
                  );
                  final keepAliveItem =
                      _shouldKeepAliveNoteListItem(index, quote);

                  itemWidget = Stack(
                    children: [
                      itemWidget,
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_isExportMode,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isExportMode
                                  ? () => _toggleExportSelection(quoteId)
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );

                  itemWidget = _NoteListItemKeepAlive(
                    keepAlive: keepAliveItem,
                    child: itemWidget,
                  );

                  final isDeleting = _deletingQuoteIds.contains(quoteId);
                  itemWidget = AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInCubic,
                    opacity: isDeleting ? 0.0 : 1.0,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInCubic,
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.hardEdge,
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: isDeleting ? 0.0 : 1.0,
                        child: itemWidget,
                      ),
                    ),
                  );

                  itemWidget = _wrapNoteInsertAnimation(
                    quoteId: quoteId,
                    version: insertAnimationVersion,
                    animateLayout: isStructuralInsert,
                    animationType: noteInsertAnimationType,
                    child: itemWidget,
                  );

                  return KeyedSubtree(
                    key: itemKey,
                    child: _wrapNoteListItemPerfProbe(
                      quote: quote,
                      index: index,
                      child: itemWidget,
                    ),
                  );
                },
              );
            }
            // 底部加载指示器：仅在主动加载时显示动画，
            // 空闲态用透明占位确保 itemCount 正确以触发自动加载。
            if (_isLoading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: AppLoadingView(size: 32),
              );
            }
            return const SizedBox(height: 48);
          },
        ),
      ),
    );
  }

  bool _shouldKeepAliveNoteListItem(int index, Quote quote) {
    if (NoteListView.shouldKeepAliveQuoteItem(quote)) {
      return true;
    }

    if (_quotes.length <=
        NoteListViewState._plainKeepAliveWindowRadius * 2 + 1) {
      return true;
    }

    final centerIndex = _estimatedScrollCenterIndex();
    return (index - centerIndex).abs() <=
        NoteListViewState._plainKeepAliveWindowRadius;
  }

  int _estimatedScrollCenterIndex() {
    if (_quotes.isEmpty || !_scrollController.hasClients) {
      return 0;
    }

    final position = _safeScrollPosition;
    if (position == null) {
      return 0;
    }
    if (!position.hasContentDimensions) {
      return 0;
    }
    final maxExtent = position.maxScrollExtent;
    if (maxExtent <= 0) {
      return 0;
    }

    final viewportCenter = (position.pixels + position.viewportDimension / 2)
        .clamp(0.0, maxExtent);
    final fraction = (viewportCenter / maxExtent).clamp(0.0, 1.0);
    return (fraction * (_quotes.length - 1)).round();
  }

  Widget _traceNoteListItemBuild({
    required int index,
    required Quote quote,
    required Widget Function() builder,
  }) {
    _recordNoteListItemBuild(index: index, quote: quote);
    if (!_firstOpenScrollPerfEnabled || !kDebugMode) {
      return builder();
    }

    developer.Timeline.startSync(
      'ThoughtEcho.NoteListView.itemBuilder',
      arguments: <String, Object>{
        'index': index,
        'quoteId': quote.id ?? 'null',
        'kind': _noteListPerfKindFor(quote),
        if (_scrollSessionId != null) 'session': _scrollSessionId!,
      },
    );
    try {
      return builder();
    } finally {
      developer.Timeline.finishSync();
    }
  }

  void _recordNoteListItemBuild({
    required int index,
    required Quote quote,
  }) {
    if (!_scrollSessionPerfRecording) {
      return;
    }

    _scrollSessionItemBuildCount++;
    if (index < _scrollSessionMinBuiltIndex) {
      _scrollSessionMinBuiltIndex = index;
    }
    if (index > _scrollSessionMaxBuiltIndex) {
      _scrollSessionMaxBuiltIndex = index;
    }

    final kind = _noteListPerfKindFor(quote);
    if (kind == 'plain') {
      _scrollSessionBuiltPlain++;
    } else if (kind == 'rich') {
      _scrollSessionBuiltRich++;
    } else {
      _scrollSessionBuiltMedia++;
    }
  }

  Widget _wrapNoteListItemPerfProbe({
    required Quote quote,
    required int index,
    required Widget child,
  }) {
    if (!_firstOpenScrollPerfEnabled) {
      return child;
    }

    return _NoteListItemPerfProbe(
      index: index,
      quoteId: quote.id ?? 'null',
      kind: _noteListPerfKindFor(quote),
      sessionId: _scrollSessionId,
      onLayout: _recordNoteListItemLayout,
      child: child,
    );
  }

  String _noteListPerfKindFor(Quote quote) {
    final deltaContent = quote.deltaContent;
    if (deltaContent == null || quote.editSource != 'fullscreen') {
      return 'plain';
    }
    if (deltaContent.contains('"image"')) {
      return 'rich-image';
    }
    if (deltaContent.contains('"video"')) {
      return 'rich-video';
    }
    if (deltaContent.contains('"audio"')) {
      return 'rich-audio';
    }
    return 'rich';
  }

  // 优化：搜索内容变化回调，添加防抖机制
  void _onSearchChanged(String value) {
    // 取消之前的防抖定时器
    _searchDebounceTimer?.cancel();

    // 性能优化：搜索时不设置 _isLoading，避免无视觉变化的 setState 引起 jank。
    // 旧结果保持可见，新结果到达后由 AnimatedOpacity 平滑淡入。
    // 仅在清空搜索时重置 loading 标志（防止之前残留状态卡住）。
    if (value.isEmpty && _isLoading) {
      _updateState(() {
        _isLoading = false;
      });
      logDebug('搜索内容被清空，重置加载状态');
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

  /// 设置搜索过渡动画状态。
  /// - updating=true：延迟 120ms 再变淡，避免快速搜索（< 120ms 就返回结果）引起闪烁。
  /// - updating=false：立即取消延迟定时器并恢复透明度。
  /// - 内置 800ms 安全定时器，防止 stream 回调丢失导致列表卡在变淡状态。
  void _setSearchUpdating(bool updating) {
    if (!mounted) return;
    _searchUpdatingTimer?.cancel();
    if (!updating) {
      // 立即取消延迟定时器，结果已回来就不需要变淡了
      _searchDimTimer?.cancel();
      if (_isSearchUpdating) {
        _updateState(() {
          _isSearchUpdating = false;
        });
      }
      return;
    }
    // updating=true：延迟 120ms 再变淡
    _searchDimTimer?.cancel();
    _searchDimTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (!_isSearchUpdating) {
        _updateState(() {
          _isSearchUpdating = true;
        });
      }
      // 800ms 安全定时器，防止卡在变淡状态
      _searchUpdatingTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && _isSearchUpdating) {
          _updateState(() {
            _isSearchUpdating = false;
          });
        }
      });
    });
  }

  /// 优化：执行搜索的统一方法
  void _performSearch(String value) {
    if (!mounted) return;

    logDebug('执行搜索: "$value"', source: 'NoteListView');

    // 绑定当前搜索版本（超时 SnackBar 用）
    _searchTimeoutVersion++;
    final capturedVersion = _searchTimeoutVersion;

    // 标记搜索更新中（延迟 120ms 再变淡，避免快速搜索闪烁）
    _setSearchUpdating(true);

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

    // 超时保护：绑定版本号，过期的超时不弹提示
    if (value.isNotEmpty && value.length >= AppConstants.minSearchLength) {
      Timer(AppConstants.searchTimeout, () {
        // 版本号不匹配说明用户已开始搜索其他内容，不弹过期的超时提示
        if (capturedVersion != _searchTimeoutVersion) return;
        if (mounted && _isLoading) {
          _updateState(() {
            _isLoading = false;
          });
          _setSearchUpdating(false);
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

          // 弹超时提示（版本号匹配才弹）
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

  void _toggleExportSelection(String quoteId) {
    HapticFeedback.selectionClick();
    _updateState(() {
      if (_selectedExportNoteIds.contains(quoteId)) {
        _selectedExportNoteIds.remove(quoteId);
      } else {
        _selectedExportNoteIds.add(quoteId);
      }
    });
  }

  void _selectAllVisibleNotes() {
    HapticFeedback.selectionClick();
    _updateState(() {
      final allIds = _quotes.map((q) => q.id).whereType<String>().toSet();
      if (_selectedExportNoteIds.containsAll(allIds)) {
        _selectedExportNoteIds.removeAll(allIds);
      } else {
        _selectedExportNoteIds.addAll(allIds);
      }
    });
  }

  void _selectSameMonthNotes() {
    final l10n = AppLocalizations.of(context);
    if (_selectedExportNoteIds.isEmpty) {
      _showInfoSnackBar(l10n.pleaseSelectAtLeastOneNote);
      return;
    }
    final selectedMonths = <String>{};
    for (final id in _selectedExportNoteIds) {
      final quote = _quotes.firstWhereOrNull((q) => q.id == id);
      if (quote != null && quote.date.length >= 7) {
        selectedMonths.add(quote.date.substring(0, 7));
      }
    }
    HapticFeedback.selectionClick();
    _updateState(() {
      for (final q in _quotes) {
        if (q.id != null && q.date.length >= 7) {
          final m = q.date.substring(0, 7);
          if (selectedMonths.contains(m)) {
            _selectedExportNoteIds.add(q.id!);
          }
        }
      }
    });
  }

  void _selectSameCategoryNotes() {
    final l10n = AppLocalizations.of(context);
    if (_selectedExportNoteIds.isEmpty) {
      _showInfoSnackBar(l10n.pleaseSelectAtLeastOneNote);
      return;
    }
    final selectedTags = <String>{};
    for (final id in _selectedExportNoteIds) {
      final quote = _quotes.firstWhereOrNull((q) => q.id == id);
      if (quote != null) {
        selectedTags.addAll(quote.tagIds);
      }
    }
    if (selectedTags.isEmpty) {
      _showInfoSnackBar(l10n.selectedNotesHaveNoCategories);
      return;
    }
    HapticFeedback.selectionClick();
    _updateState(() {
      for (final q in _quotes) {
        if (q.id != null && q.tagIds.any(selectedTags.contains)) {
          _selectedExportNoteIds.add(q.id!);
        }
      }
    });
  }

  void _showInfoSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _wrapNoteInsertAnimation({
    required String quoteId,
    required int? version,
    required bool animateLayout,
    required String animationType,
    required Widget child,
  }) {
    if (version == null) return child;
    if (animationType == 'none') return child;

    final isScale = animationType == 'scale';

    return TweenAnimationBuilder<double>(
      key: ValueKey('note_list_insert_${quoteId}_${animationType}_$version'),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: NoteListViewState._noteInsertAnimationDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        if (value >= 0.99) return child!;

        final progress = value.clamp(0.0, 1.0);
        Widget animatedChild = Opacity(
          opacity: progress,
          child: child,
        );

        animatedChild = isScale
            ? Transform.scale(
                alignment: Alignment.topCenter,
                scale: 0.98 + 0.02 * progress,
                child: animatedChild,
              )
            : Transform.translate(
                offset: Offset(0, -16.0 * (1.0 - progress)),
                child: animatedChild,
              );

        if (!animateLayout) return animatedChild;

        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: progress,
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }

  Future<void> _exportSelectedNotesToPdf() async {
    if (_selectedExportNoteIds.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    try {
      _showLoadingDialog(l10n.generatingPdf);
      final selectedQuotes = _quotes
          .where((q) => q.id != null && _selectedExportNoteIds.contains(q.id))
          .toList();
      final fontSet = await PdfFontService.loadFontSet();
      if (!mounted) return;
      final pdfBytes = await PdfExportService.exportNotesToPdf(
          selectedQuotes, fontSet, context);
      if (!mounted) return;
      Navigator.pop(context);

      _updateState(() {
        _isExportMode = false;
        _selectedExportNoteIds.clear();
      });

      if (fontSet.isFallback) {
        _showInfoSnackBar(l10n.pdfFontFallbackWarning);
      }

      showDialog(
        context: context,
        builder: (context) => PdfPreviewDialog(
          pdfBytes: pdfBytes,
          fileName: "thoughtecho_notes_batch.pdf",
        ),
      );
    } catch (e, stack) {
      logError("ExportSelectedNotesToPdf", error: e, stackTrace: stack);
      if (mounted) Navigator.pop(context);
      _showInfoSnackBar(l10n.batchPdfExportFailed(e.toString()));
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteListItemKeepAlive extends StatefulWidget {
  const _NoteListItemKeepAlive({
    required this.keepAlive,
    required this.child,
  });

  final bool keepAlive;
  final Widget child;

  @override
  State<_NoteListItemKeepAlive> createState() => _NoteListItemKeepAliveState();
}

class _NoteListItemKeepAliveState extends State<_NoteListItemKeepAlive>
    with AutomaticKeepAliveClientMixin<_NoteListItemKeepAlive> {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(covariant _NoteListItemKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) {
      updateKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _NoteListItemPerfProbe extends SingleChildRenderObjectWidget {
  const _NoteListItemPerfProbe({
    required this.index,
    required this.quoteId,
    required this.kind,
    required this.sessionId,
    required this.onLayout,
    required super.child,
  });

  final int index;
  final String quoteId;
  final String kind;
  final String? sessionId;
  final _NoteListItemLayoutCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _NoteListItemPerfProbeRenderObject(
      index: index,
      quoteId: quoteId,
      kind: kind,
      sessionId: sessionId,
      onLayout: onLayout,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _NoteListItemPerfProbeRenderObject renderObject,
  ) {
    renderObject
      ..index = index
      ..quoteId = quoteId
      ..kind = kind
      ..sessionId = sessionId
      ..onLayout = onLayout;
  }
}

class _NoteListItemPerfProbeRenderObject extends RenderProxyBox {
  _NoteListItemPerfProbeRenderObject({
    required int index,
    required String quoteId,
    required String kind,
    required String? sessionId,
    required _NoteListItemLayoutCallback onLayout,
  })  : _index = index,
        _quoteId = quoteId,
        _kind = kind,
        _sessionId = sessionId,
        _onLayout = onLayout;

  int _index;
  String _quoteId;
  String _kind;
  String? _sessionId;
  _NoteListItemLayoutCallback _onLayout;
  Size? _previousSize;

  set index(int value) => _index = value;
  set quoteId(String value) => _quoteId = value;
  set kind(String value) => _kind = value;
  set sessionId(String? value) => _sessionId = value;
  set onLayout(_NoteListItemLayoutCallback value) => _onLayout = value;

  @override
  void performLayout() {
    final previousSize = _previousSize;
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      developer.Timeline.startSync(
        'ThoughtEcho.NoteListView.itemLayout',
        arguments: <String, Object>{
          'index': _index,
          'quoteId': _quoteId,
          'kind': _kind,
          'oldHeight': previousSize?.height.toStringAsFixed(1) ?? 'none',
          if (_sessionId != null) 'session': _sessionId!,
        },
      );
    }
    try {
      super.performLayout();
    } finally {
      if (kDebugMode) {
        developer.Timeline.finishSync();
      }
      stopwatch.stop();
    }

    _onLayout(
      index: _index,
      quoteId: _quoteId,
      kind: _kind,
      durationMicros: stopwatch.elapsedMicroseconds,
      height: size.height,
      oldHeight: previousSize?.height,
    );

    if (previousSize == null ||
        (size.height - previousSize.height).abs() >= 1) {
      if (kDebugMode) {
        developer.Timeline.instantSync(
          'ThoughtEcho.NoteListView.itemSizeChanged',
          arguments: <String, Object>{
            'index': _index,
            'quoteId': _quoteId,
            'kind': _kind,
            'oldHeight': previousSize?.height.toStringAsFixed(1) ?? 'none',
            'newHeight': size.height.toStringAsFixed(1),
            'deltaHeight':
                (size.height - (previousSize?.height ?? 0)).toStringAsFixed(1),
            if (_sessionId != null) 'session': _sessionId!,
          },
        );
      }
    }
    _previousSize = size;
  }
}

typedef _NoteListItemLayoutCallback = void Function({
  required int index,
  required String quoteId,
  required String kind,
  required int durationMicros,
  required double height,
  required double? oldHeight,
});

class _SlowItemLayoutSample {
  const _SlowItemLayoutSample({
    required this.index,
    required this.quoteId,
    required this.kind,
    required this.durationMicros,
    required this.height,
    required this.oldHeight,
  });

  final int index;
  final String quoteId;
  final String kind;
  final int durationMicros;
  final double height;
  final double? oldHeight;

  String toCompactText() {
    final oldHeightText = oldHeight?.toStringAsFixed(0) ?? 'none';
    return '$index:$quoteId:$kind:'
        '${(durationMicros / 1000.0).toStringAsFixed(1)}ms:'
        'h=$oldHeightText→${height.toStringAsFixed(0)}';
  }
}
