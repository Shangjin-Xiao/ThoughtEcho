import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../controllers/search_controller.dart'; // 导入我们自定义的搜索控制器
import '../utils/icon_utils.dart';
import '../widgets/quote_item_widget.dart';
import 'dart:async';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import 'note_filter_sort_sheet.dart';
import '../utils/color_utils.dart'; // Import color_utils
import 'package:thoughtecho/utils/app_logger.dart';

class NoteListView extends StatefulWidget {
  final List<NoteCategory> tags;
  final List<String> selectedTagIds;
  final Function(List<String>) onTagSelectionChanged;
  final String searchQuery;
  final String sortType;
  final bool sortAscending;
  final Function(String, bool) onSortChanged;
  final Function(Quote) onEdit;
  final Function(Quote) onDelete;
  final Function(Quote) onAskAI;
  final bool isLoadingTags; // 新增标签加载状态参数

  const NoteListView({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    required this.onTagSelectionChanged,
    required this.searchQuery,
    required this.sortType,
    required this.sortAscending,
    required this.onSortChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onAskAI,
    this.isLoadingTags = false, // 默认为false
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
  List<String> _selectedWeathers = [];
  List<String> _selectedDayPeriods = []; // 添加时间段筛选状态

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    _hasMore = true;
    _isLoading = true;
    // 初始订阅数据流
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
          selectedWeathers:
              _selectedWeathers.isNotEmpty ? _selectedWeathers : null,
          selectedDayPeriods:
              _selectedDayPeriods.isNotEmpty ? _selectedDayPeriods : null,
        )
        .listen((list) {
          setState(() {
            _quotes.clear();
            _quotes.addAll(list);
            _hasMore = list.length % _pageSize == 0;
            _isLoading = false;
          });
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

    // 检查是否有条件变化（来自父组件的 props）
    if (oldWidget.searchQuery != widget.searchQuery ||
        !_areListsEqual(oldWidget.selectedTagIds, widget.selectedTagIds) ||
        oldWidget.sortType != widget.sortType ||
        oldWidget.sortAscending != widget.sortAscending) {
      // 如果 props 变化，则更新流订阅
      _updateStreamSubscription();
    }
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

  // 新增方法：更新数据库监听流
  void _updateStreamSubscription() {
    setState(() {
      _isLoading = true; // 开始加载
      _hasMore = true; // 假设有更多数据
      _quotes.clear(); // 清空当前列表
    });

    // 使用更新条件的方式而不是重新订阅
    final db = Provider.of<DatabaseService>(context, listen: false);

    // 取消现有订阅
    _quotesSub.cancel();

    // 创建新的订阅
    _quotesSub = db
        .watchQuotes(
          tagIds:
              widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
          limit: _pageSize, // 初始加载限制
          // offset: _offset,   // 移除 offset，watchQuotes 不支持，分页由 loadMoreQuotes 处理
          orderBy:
              widget.sortType == 'time'
                  ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
                  : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
          searchQuery:
              widget.searchQuery.isNotEmpty ? widget.searchQuery : null,
          selectedWeathers:
              _selectedWeathers.isNotEmpty ? _selectedWeathers : null,
          selectedDayPeriods:
              _selectedDayPeriods.isNotEmpty ? _selectedDayPeriods : null,
        )
        .listen(
          (list) {
            if (mounted) {
              // 确保组件仍然挂载
              setState(() {
                // _quotes.clear(); // 不再需要，因为在开始时已清空
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
              // 可以添加错误处理逻辑，例如显示 SnackBar
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('加载笔记失败: $error')));
            }
          },
        );
  }

  // 移除重复的 _areListsEqual 定义

  @override
  void dispose() {
    _quotesSub.cancel();
    _searchController.dispose();
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

  // 搜索内容变化回调
  void _onSearchChanged(String value) {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.searchQuery != value) {
        // 使用超时机制，避免搜索无限等待
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _isLoading) {
            setState(() {
              _isLoading = false;
            });
            logDebug('搜索超时，已重置加载状态');
          }
        });

        // 触发父组件更新搜索参数
        widget.onSortChanged(widget.sortType, widget.sortAscending);

        // 更新全局搜索状态 - 使用立即更新以提高响应速度
        final searchController = Provider.of<NoteSearchController>(
          context,
          listen: false,
        );

        // 如果是清空搜索，使用clearSearch方法，避免任何延迟
        if (value.isEmpty) {
          searchController.clearSearch();
        } else {
          searchController.updateSearch(value);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final theme = Theme.of(context);

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
                            prefixIcon: const Icon(Icons.search),
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
                                  selectedWeathers: _selectedWeathers,
                                  selectedDayPeriods:
                                      _selectedDayPeriods, // 传递时间段筛选状态
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
                                    setState(() {
                                      _selectedWeathers = selectedWeathers;
                                      _selectedDayPeriods =
                                          selectedDayPeriods; // 更新时间段筛选状态
                                    });
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
