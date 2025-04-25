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
  });

  @override
  State<NoteListView> createState() => _NoteListViewState();
}

class _NoteListViewState extends State<NoteListView> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedItems = {};
  // 添加固定的GlobalKey，避免重建时生成新Key
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 20;
  late StreamSubscription<List<Quote>> _quotesSub;
  List<String> _selectedWeathers = [];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    _offset = 0; _hasMore = true;
    _isLoading = true;
    // 初始订阅数据流
    final db = Provider.of<DatabaseService>(context, listen: false);
    _quotesSub = db.watchQuotes(
      tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
      limit: _pageSize,
      orderBy: widget.sortType == 'time'
        ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
        : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
    ).listen((list) {
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
    
    // 检查是否有条件变化
    if (oldWidget.searchQuery != widget.searchQuery ||
        !_areListsEqual(oldWidget.selectedTagIds, widget.selectedTagIds) ||
        oldWidget.sortType != widget.sortType ||
        oldWidget.sortAscending != widget.sortAscending) {
      
      setState(() {
        _isLoading = true;
      });
      
      // 使用更新条件的方式而不是重新订阅
      final db = Provider.of<DatabaseService>(context, listen: false);
      
      // 取消现有订阅
      _quotesSub.cancel();
      
      // 创建新的订阅
      _quotesSub = db.watchQuotes(
        tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
        limit: _pageSize,
        orderBy: widget.sortType == 'time'
            ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
            : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
        searchQuery: widget.searchQuery.isNotEmpty ? widget.searchQuery : null,
      ).listen((list) {
        setState(() {
          _quotes.clear();
          _quotes.addAll(list);
          _hasMore = list.length % _pageSize == 0;
          _isLoading = false;
        });
      });
      
      // 重置状态
      _offset = 0;
      _hasMore = true;
      _quotes.clear();
    }
  }
  
  // 辅助方法：比较两个列表是否相等
  bool _areListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _quotesSub.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _resetAndLoad() async {
    _quotes.clear();
    _hasMore = true;
    _offset = 0;
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
      return const AppEmptyView(svgAsset: 'assets/empty/empty_state.svg', text: '还没有笔记，开始记录吧！');
    }
    if (_quotes.isEmpty && widget.searchQuery.isNotEmpty) {
      return const AppEmptyView(svgAsset: 'assets/empty/no_search_results.svg', text: '未找到相关笔记');
    }
    
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        // 预加载逻辑：当用户滚动到距离底部20%的位置时，提前加载下一页
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels > metrics.maxScrollExtent - metrics.viewportDimension * 0.2) {
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
                    begin: const Offset(0.1, 0),
                    end: Offset.zero,
                  ),
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
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.searchQuery != value) {
        // 触发父组件更新搜索参数
        widget.onSortChanged(widget.sortType, widget.sortAscending);
        // 更新全局搜索状态
        final searchController = Provider.of<NoteSearchController>(context, listen: false);
        searchController.updateSearch(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度自适应调整内容宽度
        double maxWidth;
        
        if (constraints.maxWidth < 600) {
          maxWidth = constraints.maxWidth; // 小屏完全利用可用空间
        } else if (constraints.maxWidth < 960) {
          maxWidth = constraints.maxWidth * 0.98; // 中小屏几乎铺满
        } else if (constraints.maxWidth < 1280) {
          maxWidth = constraints.maxWidth * 0.95; // 中屏更高利用率
        } else {
          maxWidth = 1800; // 大屏更宽的最大宽度，充分利用大屏空间
        }
        
        // 根据屏幕尺寸调整边距 - 小屏幕紧凑一些
        final horizontalPadding = constraints.maxWidth < 600 ? 4.0 : 8.0;
        final verticalPadding = constraints.maxWidth < 600 ? 2.0 : 4.0;
        
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4), // 减少顶部组件间距
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
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40), // 更紧凑的按钮
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true, // 允许更大的底部表单
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              builder: (context) => NoteFilterSortSheet(
                                allTags: widget.tags,
                                selectedTagIds: widget.selectedTagIds,
                                sortType: widget.sortType,
                                sortAscending: widget.sortAscending,
                                selectedWeathers: _selectedWeathers,
                                onApply: (tagIds, sortType, sortAscending, selectedWeathers) {
                                  widget.onTagSelectionChanged(tagIds);
                                  widget.onSortChanged(sortType, sortAscending);
                                  setState(() {
                                    _selectedWeathers = selectedWeathers;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildNoteList(db, theme)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
