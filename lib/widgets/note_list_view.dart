import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../controllers/search_controller.dart'; // 导入我们自定义的搜索控制器
import '../utils/icon_utils.dart';
import '../widgets/quote_item_widget.dart';

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

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    // 初始化并加载第一页
    _resetAndLoad();
  }

  @override
  void didUpdateWidget(NoteListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 搜索、筛选或排序变化时重置并重新加载
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.selectedTagIds != widget.selectedTagIds ||
        oldWidget.sortType != widget.sortType ||
        oldWidget.sortAscending != widget.sortAscending) {
      _resetAndLoad();
    }
    // 同步搜索框内容
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  void _resetAndLoad() {
    _quotes.clear();
    _offset = 0;
    _hasMore = true;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);
    final db = Provider.of<DatabaseService>(context, listen: false);
    // 构建排序字符串
    final orderBy = widget.sortType == 'time'
        ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
        : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}';
    // 分页查询
    final newQuotes = await db.getUserQuotes(
      tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
      limit: _pageSize,
      offset: _offset,
      orderBy: orderBy,
    );
    // 本地搜索过滤
    final filtered = widget.searchQuery.isNotEmpty
        ? newQuotes.where((q) =>
            q.content.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
            (q.source?.toLowerCase().contains(widget.searchQuery.toLowerCase()) ?? false)
          ).toList()
        : newQuotes;
    setState(() {
      _quotes.addAll(filtered);
      _offset += newQuotes.length;
      _hasMore = newQuotes.length == _pageSize;
      _isLoading = false;
    });
  }

  Widget _buildNoteList(DatabaseService db, ThemeData theme) {
    // 加载中且还没数据
    if (_quotes.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // 无数据
    if (_quotes.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_alt_outlined,
              size: 64,
              color: theme.colorScheme.primary.withAlpha(128),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有笔记，开始记录吧！',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary.withAlpha(128),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _quotes.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _quotes.length) {
          final quote = _quotes[index];
          // 获取展开状态，如果不存在则默认为折叠状态
          final bool isExpanded = _expandedItems[quote.id] ?? false;

          return QuoteItemWidget(
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
            // 显示标签和emoji
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
          );
        }
        // 列表底部加载更多提示
        _loadMore();
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        );
      },
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索笔记...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.sort),
                tooltip: '排序',
                onPressed: () => _showSortDialog(context),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: '标签筛选',
                onPressed: () => _showFilterDialog(context),
              ),
            ],
          ),
        ),
        Expanded(child: _buildNoteList(db, theme)),
      ],
    );
  }

  // 显示排序对话框
  void _showSortDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setModalState) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '排序方式',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 按时间排序
                      RadioListTile<String>(
                        title: const Text('按时间排序'),
                        subtitle: Text(widget.sortAscending ? '从旧到新' : '从新到旧'),
                        value: 'time',
                        groupValue: widget.sortType,
                        onChanged: (value) {
                          setModalState(() {
                            widget.onSortChanged(value!, widget.sortAscending);
                          });
                        },
                      ),
                      // 按名称排序
                      RadioListTile<String>(
                        title: const Text('按名称排序'),
                        subtitle: Text(
                          widget.sortAscending ? '升序 A-Z' : '降序 Z-A',
                        ),
                        value: 'name',
                        groupValue: widget.sortType,
                        onChanged: (value) {
                          setModalState(() {
                            widget.onSortChanged(value!, widget.sortAscending);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      // 排序方向
                      SwitchListTile(
                        title: const Text('排序方向'),
                        subtitle: Text(widget.sortAscending ? '升序' : '降序'),
                        value: widget.sortAscending,
                        onChanged: (value) {
                          setModalState(() {
                            widget.onSortChanged(widget.sortType, value);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  // 显示标签筛选对话框
  void _showFilterDialog(BuildContext context) {
    // 创建一个临时的已选标签ID列表，以便在确认前可以取消操作
    List<String> tempSelectedTagIds = List.from(widget.selectedTagIds);

    showModalBottomSheet(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setModalState) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '按标签筛选',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children:
                            widget.tags.map((tag) {
                              final isSelected = tempSelectedTagIds.contains(
                                tag.id,
                              );
                              return FilterChip(
                                selected: isSelected,
                                label: Text(tag.name),
                                avatar:
                                    IconUtils.isEmoji(tag.iconName)
                                        ? Text(
                                          IconUtils.getDisplayIcon(
                                            tag.iconName,
                                          ),
                                          style: const TextStyle(fontSize: 16),
                                        )
                                        : Icon(
                                          IconUtils.getIconData(tag.iconName),
                                        ),
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      tempSelectedTagIds.add(tag.id);
                                    } else {
                                      tempSelectedTagIds.remove(tag.id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                tempSelectedTagIds.clear();
                              });
                            },
                            child: const Text('清除筛选'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              widget.onTagSelectionChanged(tempSelectedTagIds);
                              Navigator.pop(context);
                            },
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          ),
    );
  }
}
