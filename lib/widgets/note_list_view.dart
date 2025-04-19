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

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
  }

  @override
  void didUpdateWidget(NoteListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                  onChanged: (value) {
                    // 搜索内容改变时触发外部回调
                    _onSearchChanged(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 排序按钮
              IconButton(
                icon: const Icon(Icons.sort),
                tooltip: '排序',
                onPressed: () => _showSortDialog(context),
              ),
              const SizedBox(width: 8),
              // 标签筛选按钮
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

  void _onSearchChanged(String value) {
    // 通知父级组件搜索内容改变
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.searchQuery != value) {
        // 使用回调传递搜索值到父组件，而不是仅传递标签ID
        widget.onSortChanged(widget.sortType, widget.sortAscending);
        
        // 使用Provider更新搜索状态
        final searchController = Provider.of<NoteSearchController>(context, listen: false);
        searchController.updateSearch(value);
      }
    });
  }

  Widget _buildNoteList(DatabaseService db, ThemeData theme) {
    return FutureBuilder<List<Quote>>(
      future: db.getUserQuotes(
        tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
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

        var quotes = snapshot.data!;
        if (widget.searchQuery.isNotEmpty) {
          quotes =
              quotes
                  .where(
                    (quote) =>
                        quote.content.toLowerCase().contains(
                          widget.searchQuery.toLowerCase(),
                        ) ||
                        (quote.source != null &&
                            quote.source!.toLowerCase().contains(
                              widget.searchQuery.toLowerCase(),
                            )),
                  )
                  .toList();
        }

        if (quotes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: theme.colorScheme.primary.withAlpha(128),
                ),
                const SizedBox(height: 16),
                Text(
                  '没有找到匹配的笔记',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary.withAlpha(128),
                  ),
                ),
              ],
            ),
          );
        }

        // 根据排序类型和排序方向对笔记进行排序
        if (widget.sortType == 'time') {
          quotes.sort((a, b) {
            final dateA = DateTime.parse(a.date);
            final dateB = DateTime.parse(b.date);
            return widget.sortAscending
                ? dateA.compareTo(dateB) // 升序：从旧到新
                : dateB.compareTo(dateA); // 降序：从新到旧
          });
        } else if (widget.sortType == 'name') {
          quotes.sort((a, b) {
            return widget.sortAscending
                ? a.content.compareTo(b.content) // 升序：A-Z
                : b.content.compareTo(a.content); // 降序：Z-A
          });
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: quotes.length,
          itemBuilder: (context, index) {
            final quote = quotes[index];
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
          },
        );
      },
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
