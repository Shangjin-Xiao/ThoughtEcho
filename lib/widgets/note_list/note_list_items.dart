part of '../note_list_view.dart';

/// 列表底部"还有下一页"占位格的高度。空闲占位与加载动画共用，
/// 保证 `_isLoading` 翻转不会改变列表总高度。
/// 取值对齐 [AppLoadingView] 内部 Lottie 的最小尺寸（80），动画正好填满不溢出。
const double _loadMoreFooterHeight = 80.0;

/// List building, search, and item rendering for NoteListViewState.
extension _NoteListItemsExtension on NoteListViewState {
  Widget _buildNoteListView(BuildContext context) {
    final searchError = context.select<NoteSearchController, String?>(
      (controller) => controller.searchError,
    );
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);
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
    if (searchError != null && _isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateState(() {
            _isLoading = false;
          });
          context.read<NoteSearchController>().resetSearchState();
        }
      });
    }

    // 响应式设计：根据屏幕宽度调整布局
    final width = MediaQuery.sizeOf(context).width;
    final topPadding = MediaQuery.paddingOf(context).top;
    final isTablet = width > AppConstants.tabletMinWidth;
    final maxWidth = isTablet ? AppConstants.tabletMaxContentWidth : width;
    final horizontalPadding = isTablet ? 16.0 : 8.0;

    // 布局构建
    return LayoutBuilder(
      builder: (context, constraints) {
        // 主体内容 - 底色由主题下发：手工色板用自己的纸色，material 保持原算法。
        final backgroundColor = AppSurfaceTokens.of(context).noteList;

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
                        topPadding + 8.0,
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
                          fillColor: AppSurfaceTokens.of(context).searchBox,
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
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(
                                          AppShapeTokens.of(context)
                                              .dialogRadius,
                                        ),
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
                            borderRadius:
                                BorderRadius.circular(shape.inputRadius),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.28),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(shape.inputRadius),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.20),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(shape.inputRadius),
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
                      opacity: _isSearchUpdating ? 0.7 : 1.0,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        // 双向交叉淡化：旧内容快速淡出、新内容淡入，
                        // 避免被硬切（opacity 直接归零）造成的生硬感。
                        // 注意：results→results 不再切换（key 固定），这里只处理
                        // loading / empty / no_results / results 之间的状态切换，
                        // 因此不会再出现两个 ListView 同时挂在同一个滚动控制器上。
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
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
              top: _isExportMode ? topPadding + 8.0 : -(topPadding + 80.0),
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
                      borderRadius: BorderRadius.circular(shape.cardRadius),
                      boxShadow: shape.restShadow,
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
                      borderRadius: BorderRadius.circular(shape.cardRadius),
                      boxShadow: shape.raisedShadow,
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
    final hasEffectiveSearchQuery = _effectiveSearchQuery.isNotEmpty;
    // 结果列表使用固定 key：搜索词变化（含删字）时不再重建 ListView，
    // 而是原地更新数据源。重建会让新 ListView 挂到同一个 _scrollController
    // 上并以 offset=0 渲染若干帧，视口顶部露出的半截卡片（标签行）就会在
    // 搜索栏下方闪一下——这正是历次修复都没根治的闪烁来源。
    // 结果集切换的视觉反馈由外层 AnimatedOpacity（_isSearchUpdating）承担。
    const loadingKey = ValueKey('note_list_loading');
    const emptyKey = ValueKey('note_list_empty');
    const noResultsKey = ValueKey('note_list_no_results');
    const resultsKey = ValueKey('note_list_results');

    // 仅在服务初始化或首批笔记尚未返回时显示 loading。
    // 本地 SQLite 搜索通常 < 100 ms，不单独显示搜索加载动画；
    // 旧结果保持可见直到新结果到达，由 AnimatedSwitcher 淡入淡出切换。
    if (_waitingForServices || (_isLoading && _quotes.isEmpty)) {
      return AppLoadingView(key: loadingKey);
    }
    if (_quotes.isEmpty && !hasEffectiveSearchQuery) {
      return AppEmptyView(
        key: emptyKey,
        svgAsset: 'assets/empty/empty_state.svg',
        text: l10n.noteListEmptyTitle,
      );
    }
    if (_quotes.isEmpty && hasEffectiveSearchQuery) {
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
    final tagMap = _obtainTagMap();
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
          // 手指按住但暂停移动时 isListScrolling 会因 32ms 无更新而回落，
          // 单独的拖拽信号让冷 Quill 恢复队列在整个手势期间保持静默。
          isListDragActive.value = true;
          _cancelScrollEndSettledWork();
          // 用户重新接管列表：放弃尚未执行的数据事件位置还原，避免回拉手感。
          _cancelPendingScrollRestore();
          if (_searchFocusNode.hasFocus) {
            _searchFocusNode.unfocus();
          }
          _startScrollSessionPerfCapture(notification.metrics);
        } else if (notification is ScrollUpdateNotification) {
          _recordScrollSessionUpdate(notification.metrics);
        } else if (notification is ScrollEndNotification) {
          isListDragActive.value = false;
          _scheduleScrollSessionPerfFinalize(notification.metrics);
        }

        // 预加载逻辑：热路径不做日志、不做分配
        if (notification is ScrollUpdateNotification) {
          // 标记列表正在滚动（含惯性阶段），阻止图片提前解码
          _scrollEndSettleGeneration++;
          _scrollEndSettleTimer?.cancel();
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
          // 重置用户滚动状态。
          _isUserScrolling = false;

          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 100 &&
              !_isAutoScrolling &&
              _hasMore &&
              !_isLoading) {
            _loadMore();
          }

          _scheduleScrollEndSettledWork();
        }
        return false;
      },
      // 性能优化：BackdropGroup 让多个 BackdropFilter.grouped 共享采样
      // 减少 GPU 重复帧缓冲读回，显著降低多模糊 item 同屏时的光栅开销
      child: BackdropGroup(
        child: ListView.builder(
          controller: _scrollController, // 添加滚动控制器
          // 必须显式给 padding。padding 为 null 时 BoxScrollView 会把
          // MediaQuery.padding 的主轴部分包成 SliverPadding "帮忙"避开系统栏——
          // 记录页没有 AppBar，状态栏高度不会被 Scaffold 消费，于是整条状态栏
          // 高度又被加在了列表顶部。搜索框上方已经自己让开了 topPadding，这里
          // 再让一次就是白送几十 dp 的空档：先前两次收紧首条卡片上边距
          // （6 → 4 → 2.67）动的只是那几个像素，看上去当然"没变化"。
          // 底部同理交回自己控制：Scaffold 有 bottomNavigationBar，body 的
          // padding.bottom 已被置零，这里取到的就是 0。
          // 负值仍然不可行——会命中 RenderSliverPadding 的
          // assert(padding.isNonNegative)，首条间距只能靠卡片自身的上边距收。
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
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
          // 避免 drag→ballistic 过渡时集中构建新 item 导致卡顿。
          // 静止期还会在这个基础上一级一级往上撑，把下一屏卡片的挂载挪进空闲帧，
          // 见 `_growIdleCacheExtent`。
          cacheExtent: MediaQuery.sizeOf(context).height.clamp(400, 900).toDouble() +
                _idleCacheExtentBoostPx,
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
                    builder: (context, isExpanded, child) => _obtainQuoteItem(
                      quoteId: quoteId,
                      quote: quote,
                      index: index,
                      tagMap: tagMap,
                      isExpanded: isExpanded,
                      isSelected: isSelected,
                      expansionNotifier: expansionNotifier,
                      favoriteGuideKey: attachFavoriteGuideKey
                          ? widget.favoriteButtonGuideKey
                          : null,
                      moreGuideKey:
                          attachMoreGuideKey ? widget.moreButtonGuideKey : null,
                      foldGuideKey:
                          attachFoldGuideKey ? widget.foldToggleGuideKey : null,
                    ),
                  );
                  final keepAliveItem =
                      _shouldKeepAliveNoteListItem(index, quote);

                  itemWidget = Stack(
                    children: [
                      itemWidget,
                      if (_isExportMode)
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggleExportSelection(quoteId),
                              borderRadius: BorderRadius.circular(
                                  AppShapeTokens.of(context).cardRadius),
                            ),
                          ),
                        ),
                    ],
                  );

                  itemWidget = _NoteListItemKeepAlive(
                    keepAlive: keepAliveItem,
                    child: itemWidget,
                  );

                  // 动效层常驻：入场和删除都在这一层里播，动画开始/结束都不改变
                  // widget 树形状，卡片子树不会因为包装层进出而重新挂载。
                  itemWidget = NoteItemMotion(
                    key: ValueKey('note_item_motion_$quoteId'),
                    insertVersion: insertAnimationVersion,
                    insertAnimationType: noteInsertAnimationType,
                    animateInsertLayout: isStructuralInsert,
                    isDeleting: _deletingQuoteIds.contains(quoteId),
                    onInsertCompleted: (version) =>
                        _handleInsertAnimationCompleted(quoteId, version),
                    onDeleteCompleted: () => _finishNoteDelete(quote),
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
            //
            // 由 _loadMoreIndicator 驱动，切换只重建这一格，不牵动整列表；
            // 也保证加载结束后指示器一定会收起（不再依赖别处恰好有 setState）。
            //
            // 两种状态必须同高。此前空闲占位 48、加载态是 80 的 Lottie 外加
            // 上下各 16 的内边距（合计 112）——每翻转一次列表总高就跳 64 像素，
            // 正在底部附近滑动时就是肉眼可见的"列表抖一下/飞一下"。
            // 这一格永远处在"还有下一页"的过渡区，等高之后用户察觉不到差异。
            return ValueListenableBuilder<bool>(
              valueListenable: _loadMoreIndicator,
              builder: (context, loading, _) => SizedBox(
                height: _loadMoreFooterHeight,
                child: loading
                    ? const AppLoadingView(size: _loadMoreFooterHeight)
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }

  void _cancelScrollEndSettledWork() {
    _scrollEndSettleGeneration++;
    _scrollEndSettleTimer?.cancel();
    _scrollEndSettleTimer = null;
    isListScrolling.value = true;
  }

  void _scheduleScrollEndSettledWork() {
    final generation = ++_scrollEndSettleGeneration;
    _scrollEndSettleTimer?.cancel();
    _scrollEndSettleTimer = Timer(const Duration(milliseconds: 32), () {
      if (!mounted || generation != _scrollEndSettleGeneration) {
        return;
      }

      // 延迟放行图片解码和异常检测，避免与 ScrollEnd 帧的 loadMore 挤在同一帧。
      isListScrolling.value = false;
      // 停下来了：接着把还没暖过的卡片测量补上，让下一次滑动也吃到缓存。
      _scheduleIdleLayoutWarmup();
      // 拖拽期间不跟手势抢位置，挂起的还原留到这里补做。
      _reconcileScrollAnchor(null);
      _checkAndFixScrollExtentAnomaly();
    });
  }

  /// 标签映射表，只在标签本身变化时重建。
  ///
  /// 它是 [_obtainQuoteItem] 记忆化键的一员：每次 build 都新建一个 Map 的话，
  /// 身份永远对不上，记忆化就一次都命不中。
  Map<String, NoteTag> _obtainTagMap() {
    final tags = _effectiveTags;
    final cached = _tagMapCache;
    if (cached != null && _isSameTagList(_tagMapSource, tags)) {
      return cached;
    }
    final map = {for (final tag in tags) tag.id: tag};
    _tagMapSource = List<NoteTag>.unmodifiable(tags);
    _tagMapCache = map;
    return map;
  }

  bool _isSameTagList(List<NoteTag>? a, List<NoteTag> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// 取这条笔记的卡片 widget，输入没变就返回**上一次那个实例**。
  ///
  /// 这是整列表重建的主要解药。`Element.updateChild` 里有一条短路：
  ///
  /// ```dart
  /// if (hasSameSuperclass && child.widget == newWidget) { ... }  // framework.dart
  /// ```
  ///
  /// 新旧 widget 是同一个实例时，整棵子树连 build 都不进 —— 也就顺带跳过了
  /// [QuoteItemWidget] 里那两层 `LayoutBuilder`、折叠判定的 `TextPainter` 和
  /// `CollapsedRichTextMetrics.plan()`。而这些正是"一次 setState 重建上百张卡片"
  /// 的全部成本：实测 `built=140` 的那一帧 `worstBuild=89.8ms`。
  ///
  /// 记忆化**不会**让卡片错过 Inherited 依赖的更新：主题、语言、
  /// `context.select` 的那几项设置都由框架直接把依赖它们的 Element 标脏，
  /// 和父级传下来的是不是同一个 widget 无关。这里挡掉的只有"入参没变"那种重建，
  /// 而入参正是下面这张键覆盖的东西。
  ///
  /// 回调不进键：它们在**调用时**才去读 `widget.onEdit` 一类的最新值，所以父组件
  /// 换一批回调下来也不需要让缓存失效。只有可空的那几个要记住"当时是不是 null"，
  /// 因为它决定按钮画不画。
  Widget _obtainQuoteItem({
    required String quoteId,
    required Quote quote,
    required int index,
    required Map<String, NoteTag> tagMap,
    required bool isExpanded,
    required bool isSelected,
    required ValueNotifier<bool> expansionNotifier,
    required GlobalKey? favoriteGuideKey,
    required GlobalKey? moreGuideKey,
    required GlobalKey? foldGuideKey,
  }) {
    final cached = _quoteItemMemos[quoteId];
    if (cached != null &&
        cached.matches(
          quote: quote,
          index: index,
          tagMap: tagMap,
          selectedTagIds: widget.selectedTagIds,
          isExpanded: isExpanded,
          isSelected: isSelected,
          selectionMode: _isExportMode,
          hasGenerateCard: widget.onGenerateCard != null,
          hasFavorite: widget.onFavorite != null,
          hasLongPressFavorite: widget.onLongPressFavorite != null,
          favoriteGuideKey: favoriteGuideKey,
          moreGuideKey: moreGuideKey,
          foldGuideKey: foldGuideKey,
        )) {
      _quoteItemMemoHits++;
      return cached.widget;
    }

    _quoteItemMemoMisses++;
    final built = QuoteItemWidget(
      quote: quote,
      tagMap: tagMap,
      selectedTagIds: widget.selectedTagIds,
      isExpanded: isExpanded,
      isSelected: isSelected,
      selectionMode: _isExportMode,
      // 首条与搜索框之间只隔这一层卡片上边距。
      topMarginOverride: index == 0 ? QuoteItemWidget.firstItemTopMargin : null,
      onToggleExpanded: (expanded) {
        if (expansionNotifier.value != expanded) {
          expansionNotifier.value = expanded;
        }
        _expandedItems[quoteId] = expanded;

        final bool requiresAlignment = QuoteItemWidget.needsExpansionFor(quote);

        if (!expanded && requiresAlignment) {
          final waitDuration = QuoteItemWidget.expandCollapseDuration +
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
      // 折叠动画播完后才真正删除：时序由 [NoteItemMotion] 的完成
      // 回调驱动，不再用挂钟定时器猜动画什么时候结束。
      onDelete: () => _beginNoteDelete(quote),
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
      onFavorite:
          widget.onFavorite != null ? () => widget.onFavorite!(quote) : null,
      onLongPressFavorite: widget.onLongPressFavorite != null
          ? () => widget.onLongPressFavorite!(quote)
          : null,
      favoriteButtonGuideKey: favoriteGuideKey,
      moreButtonGuideKey: moreGuideKey,
      foldToggleGuideKey: foldGuideKey,
    );

    _quoteItemMemos[quoteId] = _QuoteItemMemo(
      widget: built,
      quote: quote,
      index: index,
      tagMap: tagMap,
      selectedTagIds: widget.selectedTagIds,
      isExpanded: isExpanded,
      isSelected: isSelected,
      selectionMode: _isExportMode,
      hasGenerateCard: widget.onGenerateCard != null,
      hasFavorite: widget.onFavorite != null,
      hasLongPressFavorite: widget.onLongPressFavorite != null,
      favoriteGuideKey: favoriteGuideKey,
      moreGuideKey: moreGuideKey,
      foldGuideKey: foldGuideKey,
    );
    return built;
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
      onMount: _recordNoteListItemMount,
      child: child,
    );
  }

  /// 性能日志里给条目分类用的标签。
  ///
  /// 走 [DeltaMediaCache]，不再自己 `contains`：这个方法每次条目构建要被调两次
  /// （记账一次、探针一次），全量扫描整份 delta 的话**监控本身**就会把它想测的
  /// 帧撑大，测出来的绝对值全部偏高。
  ///
  /// 只问一次 `of`：`hasMediaOf` 会顺手填好摘要缓存，但在这里先问 bool 再问摘要
  /// 是白跑一趟——分类本来就要用到三个计数。
  String _noteListPerfKindFor(Quote quote) {
    final deltaContent = quote.deltaContent;
    if (deltaContent == null || quote.editSource != 'fullscreen') {
      return 'plain';
    }
    final media = DeltaMediaCache.of(deltaContent);
    if (media.imageCount > 0) {
      return 'rich-image';
    }
    if (media.videoCount > 0) {
      return 'rich-video';
    }
    if (media.audioCount > 0) {
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

    // 仅在有效搜索（长度达到阈值）时才显示“更新中”过渡，
    // 避免快速删字（2→1→0）触发重复变淡闪烁。
    final shouldShowSearchUpdating =
        value.length >= AppConstants.minSearchLength;
    _setSearchUpdating(shouldShowSearchUpdating);

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
            final semantic = AppSemanticColors.of(context);
            AppSnackBar.show(
              context,
              l10n.noteSearchTimeoutMessage,
              duration: AppConstants.snackBarDurationImportant,
              backgroundColor: semantic.warningContainer,
              foregroundColor: semantic.onWarningContainer,
              action: SnackBarAction(
                label: l10n.retry,
                textColor: semantic.onWarningContainer,
                onPressed: () => _performSearch(value),
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
    for (final quote in _quotes) {
      if (quote.id != null &&
          _selectedExportNoteIds.contains(quote.id) &&
          quote.date.length >= 7) {
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
    for (final quote in _quotes) {
      if (quote.id != null && _selectedExportNoteIds.contains(quote.id)) {
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
    required this.onMount,
    required super.child,
  });

  final int index;
  final String quoteId;
  final String kind;
  final String? sessionId;
  final _NoteListItemLayoutCallback onLayout;
  final _NoteListItemMountCallback onMount;

  @override
  SingleChildRenderObjectElement createElement() =>
      _NoteListItemPerfProbeElement(this);

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

/// 计量「这张卡片的子树第一次被建出来」花了多久。
///
/// `itemLayout` 那个探针只盖到布局：`LayoutBuilder` 里的折叠判定和折叠排版被算
/// 在里面，**挂载**（构造 widget、建 element 与 RenderObject）却一直没有任何
/// 计数器。而一张最小卡片就有 90 个 element，首滑一次要建三十多张 —— 这一项拆
/// 不出来，就只能继续猜首滑的成本落在哪。
///
/// `mount` 只在真正新建时走一次：被 keepAlive 留住、或被记忆化短路掉的重建都
/// 不会进这里，正好就是「第一次」的定义。
class _NoteListItemPerfProbeElement extends SingleChildRenderObjectElement {
  _NoteListItemPerfProbeElement(_NoteListItemPerfProbe super.widget);

  @override
  void mount(Element? parent, Object? newSlot) {
    final probe = widget as _NoteListItemPerfProbe;
    final stopwatch = Stopwatch()..start();
    try {
      super.mount(parent, newSlot);
    } finally {
      stopwatch.stop();
    }
    probe.onMount(
      index: probe.index,
      quoteId: probe.quoteId,
      kind: probe.kind,
      durationMicros: stopwatch.elapsedMicroseconds,
    );
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

typedef _NoteListItemMountCallback = void Function({
  required int index,
  required String quoteId,
  required String kind,
  required int durationMicros,
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

/// [_NoteListItemsExtension._obtainQuoteItem] 的记忆化条目。
///
/// 存的是"上次用什么入参建出了哪个 widget"。字段就是那张键 —— 加参数时必须同步
/// 加到这里，漏一个就会让卡片停在旧数据上。
@immutable
class _QuoteItemMemo {
  const _QuoteItemMemo({
    required this.widget,
    required this.quote,
    required this.index,
    required this.tagMap,
    required this.selectedTagIds,
    required this.isExpanded,
    required this.isSelected,
    required this.selectionMode,
    required this.hasGenerateCard,
    required this.hasFavorite,
    required this.hasLongPressFavorite,
    required this.favoriteGuideKey,
    required this.moreGuideKey,
    required this.foldGuideKey,
  });

  final Widget widget;
  final Quote quote;
  final int index;
  final Map<String, NoteTag> tagMap;
  final List<String> selectedTagIds;
  final bool isExpanded;
  final bool isSelected;
  final bool selectionMode;
  final bool hasGenerateCard;
  final bool hasFavorite;
  final bool hasLongPressFavorite;
  final GlobalKey? favoriteGuideKey;
  final GlobalKey? moreGuideKey;
  final GlobalKey? foldGuideKey;

  /// [quote] 按实例比：[Quote] 全字段 final，同一实例就是同样的内容。
  /// [selectedTagIds] 按内容比：父组件常常传一份等价的新列表下来，按身份比会让
  /// 每次父级重建都全部失效 —— 而那正是最需要命中的场合。
  bool matches({
    required Quote quote,
    required int index,
    required Map<String, NoteTag> tagMap,
    required List<String> selectedTagIds,
    required bool isExpanded,
    required bool isSelected,
    required bool selectionMode,
    required bool hasGenerateCard,
    required bool hasFavorite,
    required bool hasLongPressFavorite,
    required GlobalKey? favoriteGuideKey,
    required GlobalKey? moreGuideKey,
    required GlobalKey? foldGuideKey,
  }) {
    if (!identical(this.quote, quote) ||
        this.index != index ||
        !identical(this.tagMap, tagMap) ||
        this.isExpanded != isExpanded ||
        this.isSelected != isSelected ||
        this.selectionMode != selectionMode ||
        this.hasGenerateCard != hasGenerateCard ||
        this.hasFavorite != hasFavorite ||
        this.hasLongPressFavorite != hasLongPressFavorite ||
        !identical(this.favoriteGuideKey, favoriteGuideKey) ||
        !identical(this.moreGuideKey, moreGuideKey) ||
        !identical(this.foldGuideKey, foldGuideKey)) {
      return false;
    }
    if (identical(this.selectedTagIds, selectedTagIds)) return true;
    if (this.selectedTagIds.length != selectedTagIds.length) return false;
    for (var i = 0; i < selectedTagIds.length; i++) {
      if (this.selectedTagIds[i] != selectedTagIds[i]) return false;
    }
    return true;
  }
}
