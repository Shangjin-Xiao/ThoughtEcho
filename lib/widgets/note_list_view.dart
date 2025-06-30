import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../utils/icon_utils.dart';
import '../widgets/quote_item_widget.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import 'note_filter_sort_sheet.dart';
import '../utils/color_utils.dart'; // Import color_utils
import 'package:thoughtecho/utils/app_logger.dart';
import '../services/weather_service.dart'; // 导入天气服务
import '../utils/time_utils.dart'; // 导入时间工具
import '../controllers/search_controller.dart';

class NoteListView extends StatefulWidget {
  final List<NoteCategory> tags;
  final List<String> selectedTagIds;
  final Function(List<String>) onTagSelectionChanged;
  final String searchQuery;
  final String sortType;
  final bool sortAscending;
  final Function(String, bool) onSortChanged;
  final Function(String) onSearchChanged; // 新增搜索变化回调
  final Function(Quote) onEdit;
  final Function(Quote) onDelete;
  final Function(Quote) onAskAI;
  final bool isLoadingTags; // 新增标签加载状态参数
  final List<String> selectedWeathers; // 新增天气筛选参数
  final List<String> selectedDayPeriods; // 新增时间段筛选参数
  final Function(List<String>, List<String>) onFilterChanged; // 新增筛选变化回调

  const NoteListView({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    required this.onTagSelectionChanged,
    required this.searchQuery,
    required this.sortType,
    required this.sortAscending,
    required this.onSortChanged,
    required this.onSearchChanged, // 新增必需的搜索回调
    required this.onEdit,
    required this.onDelete,
    required this.onAskAI,
    this.isLoadingTags = false, // 默认为false
    this.selectedWeathers = const [],
    this.selectedDayPeriods = const [],
    required this.onFilterChanged,
  });

  @override
  State<NoteListView> createState() => NoteListViewState();
}

class NoteListViewState extends State<NoteListView> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedItems = {};
  // 添加固定的GlobalKey，避免重建时生成新Key
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = true;
  bool _hasMore = true;
  static const int _pageSize = 20;
  late StreamSubscription<List<Quote>> _quotesSub;

  // 优化：添加防抖定时器
  Timer? _searchDebounceTimer;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    _hasMore = true;
    _isLoading = true;
    // 优化：延迟初始化数据流订阅，避免build过程中的副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataStream();
    });
  }

  /// 优化：将数据流初始化分离到独立方法
  void _initializeDataStream() {
    if (!mounted) return; // 确保组件仍然挂载

    final db = Provider.of<DatabaseService>(context, listen: false);
    _quotesSub = db
        .watchQuotes(
          tagIds:
              widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
          limit: _pageSize,
          orderBy:
              widget.sortType == 'time'
                  ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
                  : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
          searchQuery:
              widget.searchQuery.isNotEmpty ? widget.searchQuery : null,
          selectedWeathers:
              widget.selectedWeathers.isNotEmpty ? widget.selectedWeathers : null,
          selectedDayPeriods:
              widget.selectedDayPeriods.isNotEmpty ? widget.selectedDayPeriods : null,
        )
        .listen((list) {
          if (mounted) {
            setState(() {
              _quotes.clear();
              _quotes.addAll(list);
              _hasMore = list.length % _pageSize == 0;
              _isLoading = false;
            });

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
          }
        });
    // 加载第一页
    _loadMore();
  }

  @override
  void didUpdateWidget(NoteListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 更新搜索控制器文本，避免与外部状态不同步
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }

    // 优化：只有在筛选条件真正改变时才更新订阅
    final bool shouldUpdate = _shouldUpdateSubscription(oldWidget);

    if (shouldUpdate) {
      // 更新流订阅
      _updateStreamSubscription();
    }
  }

  /// 优化：判断是否需要更新订阅
  bool _shouldUpdateSubscription(NoteListView oldWidget) {
    return oldWidget.searchQuery != widget.searchQuery ||
        !_areListsEqual(oldWidget.selectedTagIds, widget.selectedTagIds) ||
        oldWidget.sortType != widget.sortType ||
        oldWidget.sortAscending != widget.sortAscending ||
        !_areListsEqual(oldWidget.selectedWeathers, widget.selectedWeathers) ||
        !_areListsEqual(oldWidget.selectedDayPeriods, widget.selectedDayPeriods);
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

  // 优化：新增方法：更新数据库监听流（改进版本）
  void _updateStreamSubscription() {
    // 防止重复更新
    if (_isLoading) return;

    setState(() {
      _isLoading = true; // 开始加载
      _hasMore = true; // 假设有更多数据
      _quotes.clear(); // 清空当前列表
    });

    // 使用更新条件的方式而不是重新订阅
    final db = Provider.of<DatabaseService>(context, listen: false);

    // 取消现有订阅
    _quotesSub.cancel();

    // 创建新的订阅 - 优化：减少不必要的参数传递
    _quotesSub = db
        .watchQuotes(
          tagIds:
              widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
          limit: _pageSize, // 初始加载限制
          orderBy:
              widget.sortType == 'time'
                  ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
                  : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
          searchQuery:
              widget.searchQuery.isNotEmpty ? widget.searchQuery : null,
          selectedWeathers:
              widget.selectedWeathers.isNotEmpty ? widget.selectedWeathers : null,
          selectedDayPeriods:
              widget.selectedDayPeriods.isNotEmpty ? widget.selectedDayPeriods : null,
        )
        .listen(
          (list) {
            if (mounted) {
              // 确保组件仍然挂载
              setState(() {
                _quotes.clear();
                _quotes.addAll(list);
                _hasMore = list.length == _pageSize; // 判断是否还有更多
                _isLoading = false; // 加载完成
              });
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false; // 出错时停止加载
              });
              // 优化：更友好的错误提示
              _showErrorSnackBar('加载笔记失败: $error');
            }
          },
        );
  }

  /// 优化：显示错误提示的统一方法
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '重试',
          onPressed: () => _updateStreamSubscription(),
        ),
      ),
    );
  }

  // 移除重复的 _areListsEqual 定义

  @override
  void dispose() {
    _quotesSub.cancel();
    _searchController.dispose();
    _searchDebounceTimer?.cancel(); // 优化：清理防抖定时器
    super.dispose();
  }

  Future<void> resetAndLoad() async {
    _quotes.clear();
    _hasMore = true;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (!_hasMore) return;
    final db = Provider.of<DatabaseService>(context, listen: false);
    await db.loadMoreQuotes();
  }

  Widget _buildNoteList(DatabaseService db, ThemeData theme) {
    if (_isLoading) {
      return const AppLoadingView();
    }
    if (_quotes.isEmpty && widget.searchQuery.isEmpty) {
      return const AppEmptyView(
        svgAsset: 'assets/empty/empty_state.svg',
        text: '还没有笔记，开始记录吧！',
      );
    }
    if (_quotes.isEmpty && widget.searchQuery.isNotEmpty) {
      return const AppEmptyView(
        svgAsset: 'assets/empty/no_search_results.svg',
        text: '未找到相关笔记',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        // 预加载逻辑：当用户滚动到距离底部20%的位置时，提前加载下一页
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels >
              metrics.maxScrollExtent - metrics.viewportDimension * 0.2) {
            _loadMore();
          }
        }
        return true;
      },
      child: AnimatedList(
        key: _listKey,
        initialItemCount: _quotes.length + (_hasMore ? 1 : 0),
        physics: const AlwaysScrollableScrollPhysics(),
        scrollDirection: Axis.vertical,
        itemBuilder: (context, index, animation) {
          if (index < _quotes.length) {
            final quote = _quotes[index];
            // 获取展开状态，如果不存在则默认为折叠状态
            final bool isExpanded = _expandedItems[quote.id] ?? false;

            // 使用FadeTransition为新项目添加淡入效果
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: animation.drive(
                  Tween<Offset>(
                    begin: const Offset(0, 0.1), // 从下方微妙滑入
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)), // 更平滑的缓动
                ),
                child: QuoteItemWidget(
                  quote: quote,
                  tags: widget.tags,
                  isExpanded: isExpanded,
                  onToggleExpanded: (expanded) {
                    setState(() {
                      _expandedItems[quote.id!] = expanded;
                    });
                  },
                  onEdit: () => widget.onEdit(quote),
                  onDelete: () => widget.onDelete(quote),
                  onAskAI: () => widget.onAskAI(quote),
                  tagBuilder: (tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.applyOpacity(
                          0.1,
                        ), // MODIFIED
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (IconUtils.isEmoji(tag.iconName)) ...[
                            Text(
                              IconUtils.getDisplayIcon(tag.iconName),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 4),
                          ] else ...[
                            Icon(
                              IconUtils.getIconData(tag.iconName),
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            tag.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          }
          // 底部加载指示器，也使用动画淡入显示
          return FadeTransition(
            opacity: animation,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: AppLoadingView(size: 32),
            ),
          );
        },
      ),
    );
  }

  // 优化：搜索内容变化回调，添加防抖机制
  void _onSearchChanged(String value) {
    // 取消之前的防抖定时器
    _searchDebounceTimer?.cancel();

    // 立即更新本地UI状态
    setState(() {
      // 如果搜索框被清空，立即重置加载状态
      if (value.isEmpty && widget.searchQuery.isNotEmpty) {
        _isLoading = true;
        logDebug('搜索内容被清空，重置加载状态');
      } else if (value.isNotEmpty) {
        _isLoading = true;
      }
    });

    // 对于清空操作，立即执行
    if (value.isEmpty) {
      _performSearch(value);
      return;
    }

    // 对于输入操作，使用防抖延迟
    _searchDebounceTimer = Timer(_searchDebounceDelay, () {
      if (mounted) {
        _performSearch(value);
      }
    });
  }

  /// 优化：执行搜索的统一方法
  void _performSearch(String value) {
    if (!mounted) return;

    // 如果是非空搜索，通知搜索控制器开始搜索
    if (value.isNotEmpty) {
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

    // 设置超时保护，确保加载状态不会永远卡住
    Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoading) {
        setState(() {
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final searchController = Provider.of<NoteSearchController>(context);
    final theme = Theme.of(context);

    // 监听搜索控制器状态，如果搜索出错则重置本地加载状态
    if (searchController.searchError != null && _isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          searchController.resetSearchState();
        }
      });
    }

    // 响应式设计：根据屏幕宽度调整布局
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 600;
    final maxWidth = isTablet ? 800.0 : width;
    final horizontalPadding = isTablet ? 16.0 : 8.0;

    // 布局构建
    return LayoutBuilder(
      builder: (context, constraints) {
        // 主体内容
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              children: [
                // 搜索框 - 移到最顶部，增加上边距以适应没有AppBar的情况
                Container(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    MediaQuery.of(context).padding.top + 8.0, // 顶部安全区域 + 一些额外空间
                    horizontalPadding,
                    0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索笔记...',
                            prefixIcon:
                                searchController.isSearching
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                    : const Icon(Icons.search),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: constraints.maxWidth < 600 ? 8.0 : 12.0,
                            ),
                            isDense: constraints.maxWidth < 600, // 小屏幕更紧凑
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.tune),
                        tooltip: '筛选/排序',
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ), // 更紧凑的按钮
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true, // 允许更大的底部表单
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                            ),
                            builder:
                                (context) => NoteFilterSortSheet(
                                  allTags: widget.tags,
                                  selectedTagIds: widget.selectedTagIds,
                                  sortType: widget.sortType,
                                  sortAscending: widget.sortAscending,
                                  selectedWeathers: widget.selectedWeathers,
                                  selectedDayPeriods: widget.selectedDayPeriods, // 传递时间段筛选状态
                                  onApply: (
                                    tagIds,
                                    sortType,
                                    sortAscending,
                                    selectedWeathers,
                                    selectedDayPeriods, // 接收时间段筛选结果
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
                                    // 在状态更新后，立即触发数据库流的更新
                                    _updateStreamSubscription();
                                  },
                                ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // 筛选条件总结
                (widget.selectedWeathers.isNotEmpty ||
                        widget.selectedDayPeriods.isNotEmpty ||
                        widget.selectedTagIds.isNotEmpty)
                    ? Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 8.0,
                      ),
                      width: double.infinity,
                      child: Row(
                        children: [
                          Icon(
                            Icons.filter_alt,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '已选择筛选条件',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if (widget.selectedTagIds.isNotEmpty ||
                              widget.selectedWeathers.isNotEmpty ||
                              widget.selectedDayPeriods.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                widget.onTagSelectionChanged([]);
                                widget.onFilterChanged([], []);
                                _updateStreamSubscription();
                              },
                              child: const Text('清除全部'),
                            ),
                        ],
                      ),
                    )
                    : const SizedBox.shrink(),

                // 标签筛选器
                widget.selectedTagIds.isNotEmpty
                    ? Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 8.0,
                      ),
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            widget.selectedTagIds.map((tagId) {
                              final tag = widget.tags.firstWhere(
                                (tag) => tag.id == tagId,
                                orElse:
                                    () => NoteCategory(id: tagId, name: '未知标签'),
                              );
                              return Chip(
                                label: Text(tag.name),
                                onDeleted: () {
                                  final newSelectedTags = List<String>.from(
                                    widget.selectedTagIds,
                                  )..remove(tagId);
                                  widget.onTagSelectionChanged(newSelectedTags);
                                },
                                backgroundColor: theme.colorScheme.primary
                                    .applyOpacity(0.1), // MODIFIED
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              );
                            }).toList(),
                      ),
                    )
                    : const SizedBox.shrink(),

                // 天气筛选器
                widget.selectedWeathers.isNotEmpty
                    ? Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 4.0,
                      ),
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            widget.selectedWeathers.map((weatherKey) {
                              // 找到对应的天气分类
                              String? categoryKey;
                              for (final entry
                                  in WeatherService
                                      .filterCategoryToLabel
                                      .entries) {
                                final categoryWeathers =
                                    WeatherService.getWeatherKeysByFilterCategory(
                                      entry.key,
                                    );
                                if (categoryWeathers.contains(weatherKey)) {
                                  categoryKey = entry.key;
                                  break;
                                }
                              }

                              final weatherLabel =
                                  WeatherService
                                      .weatherKeyToLabel[weatherKey] ??
                                  weatherKey;
                              final weatherIcon =
                                  categoryKey != null
                                      ? WeatherService.getFilterCategoryIcon(
                                        categoryKey,
                                      )
                                      : Icons.wb_sunny;

                              return Chip(
                                avatar: Icon(weatherIcon, size: 16),
                                label: Text(weatherLabel),
                                onDeleted: () {
                                  final newWeathers = List<String>.from(widget.selectedWeathers)
                                    ..remove(weatherKey);
                                  widget.onFilterChanged(newWeathers, widget.selectedDayPeriods);
                                  _updateStreamSubscription();
                                },
                                backgroundColor: theme.colorScheme.secondary
                                    .applyOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              );
                            }).toList(),
                      ),
                    )
                    : const SizedBox.shrink(),

                // 时间段筛选器
                widget.selectedDayPeriods.isNotEmpty
                    ? Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 4.0,
                      ),
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            widget.selectedDayPeriods.map((periodKey) {
                              final periodLabel = TimeUtils.getDayPeriodLabel(
                                periodKey,
                              );
                              final periodIcon =
                                  TimeUtils.getDayPeriodIconByKey(periodKey);

                              return Chip(
                                avatar: Icon(periodIcon, size: 16),
                                label: Text(periodLabel),
                                onDeleted: () {
                                  final newDayPeriods = List<String>.from(widget.selectedDayPeriods)
                                    ..remove(periodKey);
                                  widget.onFilterChanged(widget.selectedWeathers, newDayPeriods);
                                  _updateStreamSubscription();
                                },
                                backgroundColor: theme.colorScheme.tertiary
                                    .applyOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              );
                            }).toList(),
                      ),
                    )
                    : const SizedBox.shrink(),

                // 笔记列表
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: _buildNoteList(db, theme),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
