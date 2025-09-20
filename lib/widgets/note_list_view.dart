import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import 'package:thoughtecho/utils/app_logger.dart';
import '../controllers/search_controller.dart';
import '../constants/app_constants.dart'; // 导入应用常量

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
  final Function(Quote)? onGenerateCard;
  final Function(Quote)? onFavorite; // 新增：心形按钮点击回调
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
    this.onGenerateCard,
    this.onFavorite, // 新增：心形按钮点击回调
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
  final FocusNode _searchFocusNode = FocusNode(); // 添加焦点节点管理
  final ScrollController _scrollController = ScrollController(); // 添加滚动控制器
  final Map<String, bool> _expandedItems = {};
  final Map<String, GlobalKey> _itemKeys = {}; // 保存每个笔记的GlobalKey

  // ---- 用户滑动状态 ----
  Timer? _userScrollingTimer;

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = true;
  bool _hasMore = true;
  static const int _pageSize = AppConstants.defaultPageSize;
  StreamSubscription<List<Quote>>? _quotesSub;

  // 修复：添加防抖定时器和性能优化
  Timer? _searchDebounceTimer;
  // ---- 自动滚动控制新增状态 ----
  // bool _autoScrollEnabled = false; // 首批数据加载完成后再允许自动滚动
  bool _initialDataLoaded = false; // 标记是否已收到首批数据（后续用于启用自动滚动）
  // bool _isAutoScrolling = false; // 当前是否有程序驱动的滚动动画
  // DateTime? _lastUserScrollTime; // 最近一次用户滚动时间

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    _hasMore = true;
    _isLoading = true;

    // 添加焦点节点监听器，用于Web平台的焦点管理
    _searchFocusNode.addListener(_onFocusChanged);

    // 添加滚动控制器监听器，用于检测用户滑动状态
    _scrollController.addListener(_onScroll);

    // 优化：延迟初始化数据流订阅，避免build过程中的副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataStream();
    });
  }

  /// 焦点变化监听器，用于处理Web平台的焦点管理问题
  void _onFocusChanged() {
    if (!mounted) return;
    // 可以在这里添加焦点变化时的逻辑
    logDebug('搜索框焦点状态: ${_searchFocusNode.hasFocus}');
  }

  /// 滚动监听器，用于检测用户滑动状态
  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;

    // 当滚动到列表底部时，加载更多数据
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }

    // _lastUserScrollTime = DateTime.now();

    // 重置定时器
    _userScrollingTimer?.cancel();

    // 设置定时器，滑动停止后1秒重置状态
    _userScrollingTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          // 可以在这里添加滑动停止后的逻辑
        });
      }
    });
  }

  /// 数据库服务变化监听器
  void _onDatabaseServiceChanged() {
    if (!mounted) return;

    final db = Provider.of<DatabaseService>(context, listen: false);
    if (db.isInitialized) {
      logDebug('数据库初始化完成，重新订阅数据流');
      // 移除监听器，避免重复监听
      db.removeListener(_onDatabaseServiceChanged);

      // 针对安卓平台的特殊处理
      if (!kIsWeb && Platform.isAndroid) {
        // 安卓平台延迟重新订阅，确保数据库完全准备好
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _initializeDataStream();
          }
        });
      } else {
        // 其他平台立即重新订阅
        _initializeDataStream();
      }
    }
  }

  /// 修复：将数据流初始化分离到独立方法
  void _initializeDataStream() {
    if (!mounted) return; // 确保组件仍然挂载

    // 修复：安全取消现有订阅
    _quotesSub?.cancel();

    final db = Provider.of<DatabaseService>(context, listen: false);

    // 修复：检查数据库是否已初始化，如果未初始化则等待
    if (!db.isInitialized) {
      logDebug('数据库未初始化，等待初始化完成后重新订阅');
      // 监听数据库服务的变化，当初始化完成时重新订阅
      db.addListener(_onDatabaseServiceChanged);
      return;
    }

    _quotesSub = db
        .watchQuotes(
      tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
      limit: _pageSize,
      orderBy: widget.sortType == 'time'
          ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
          : widget.sortType == 'favorite'
              ? 'favorite_count ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
      searchQuery: widget.searchQuery.isNotEmpty ? widget.searchQuery : null,
      selectedWeathers:
          widget.selectedWeathers.isNotEmpty ? widget.selectedWeathers : null,
      selectedDayPeriods: widget.selectedDayPeriods.isNotEmpty
          ? widget.selectedDayPeriods
          : null,
    )
        .listen(
      (list) {
        if (mounted) {
          setState(() {
            _quotes.clear();
            _quotes.addAll(list);
            // 修复：简化_hasMore逻辑，避免Web平台无限加载
            _hasMore = list.length >= _pageSize;
            _isLoading = false;
          });

          // 首批数据加载完成，立即启用自动滚动但设置保护期
          if (!_initialDataLoaded) {
            _initialDataLoaded = true;
            // 立即启用自动滚动，但设置更长的保护期防止误触发
            // _autoScrollEnabled = true;
            // 设置较长的保护期，避免首次进入时的滚动冲突
            // _lastUserScrollTime = DateTime.now();
            logDebug('首批数据加载完成，自动滚动功能已启用（保护期2秒）', source: 'NoteListView');
          }

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
      },
      onError: (error) {
        if (mounted) {
          setState(() {
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
                '加载失败: ${error.toString().contains('TimeoutException') ? '查询超时' : error.toString()}',
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
      // 如果是首次加载期间（初始数据还未加载完成），避免重置滚动位置
      if (!_initialDataLoaded) {
        logDebug('跳过更新订阅：首次数据加载中', source: 'NoteListView');
        return;
      }

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
  void _updateStreamSubscription() {
    if (!mounted) return; // 确保组件仍然挂载

    logDebug('更新数据流订阅，当前加载状态: $_isLoading', source: 'NoteListView');

    // 保存当前滚动位置（仅在有数据且用户已滚动时）
    double? savedScrollOffset;
    if (_scrollController.hasClients &&
        _quotes.isNotEmpty &&
        _initialDataLoaded) {
      savedScrollOffset = _scrollController.offset;
      logDebug('保存滚动位置: $savedScrollOffset', source: 'NoteListView');
    }

    setState(() {
      _isLoading = true; // 开始加载
      _hasMore = true; // 假设有更多数据
      _quotes.clear(); // 清空当前列表
    });

    final db = Provider.of<DatabaseService>(context, listen: false);

    // 修复：安全取消现有订阅
    try {
      _quotesSub?.cancel();
    } catch (e) {
      logDebug('取消订阅时出错: $e');
    }

    // 创建新的订阅 - 优化：减少不必要的参数传递
    _quotesSub = db
        .watchQuotes(
      tagIds: widget.selectedTagIds.isNotEmpty ? widget.selectedTagIds : null,
      limit: _pageSize, // 初始加载限制
      orderBy: widget.sortType == 'time'
          ? 'date ${widget.sortAscending ? 'ASC' : 'DESC'}'
          : widget.sortType == 'favorite'
              ? 'favorite_count ${widget.sortAscending ? 'ASC' : 'DESC'}'
              : 'content ${widget.sortAscending ? 'ASC' : 'DESC'}',
      searchQuery: widget.searchQuery.isNotEmpty ? widget.searchQuery : null,
      selectedWeathers:
          widget.selectedWeathers.isNotEmpty ? widget.selectedWeathers : null,
      selectedDayPeriods: widget.selectedDayPeriods.isNotEmpty
          ? widget.selectedDayPeriods
          : null,
    )
        .listen(
      (list) {
        if (mounted) {
          // 确保组件仍然挂载
          setState(() {
            _quotes.clear();
            _quotes.addAll(list);
            _hasMore = list.length >= _pageSize;
            _isLoading = false;
          });

          // 恢复滚动位置（在数据加载完成后）
          if (savedScrollOffset != null && _scrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final offset = savedScrollOffset;
              if (_scrollController.hasClients &&
                  offset != null &&
                  offset <= _scrollController.position.maxScrollExtent) {
                _scrollController.jumpTo(offset);
                logDebug('恢复滚动位置: $offset', source: 'NoteListView');
              }
            });
          }
          setState(() {
            _quotes.clear();
            _quotes.addAll(list);

            // 修复：简化_hasMore逻辑，与line 137保持一致
            // 如果返回的数据量大于等于页面大小，说明可能还有更多数据
            _hasMore = list.length >= _pageSize;
            _isLoading = false; // 加载完成
            logDebug('数据更新：${list.length}条，_hasMore=$_hasMore',
                source: 'NoteListView');
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

          logDebug(
            '数据流更新完成，加载了 ${list.length} 条记录',
            source: 'NoteListView',
          );
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
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

  /// 优化：显示错误提示的统一方法
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AppConstants.snackBarDurationNormal,
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
    // 修复：安全清理所有资源
    try {
      _quotesSub?.cancel();
    } catch (e) {
      logDebug('取消订阅时出错: $e');
    }

    // 修复：清理数据库服务监听器
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      db.removeListener(_onDatabaseServiceChanged);
    } catch (e) {
      logDebug('清理数据库服务监听器时出错: $e');
    }

    _searchController.dispose();

    // 清理滚动控制器和监听器
    try {
      _scrollController.removeListener(_onScroll);
      _scrollController.dispose();
    } catch (e) {
      logDebug('清理滚动控制器时出错: $e');
    }

    // 安全地清理焦点节点和监听器
    try {
      _searchFocusNode.removeListener(_onFocusChanged);
      _searchFocusNode.dispose();
    } catch (e) {
      logDebug('清理焦点节点时出错: $e');
    }

    _searchDebounceTimer?.cancel(); // 清理防抖定时器
    _userScrollingTimer?.cancel(); // 清理用户滑动定时器
    super.dispose();
  }

  // 优化：将搜索框提取为独立组件
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: '搜索笔记...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    widget.onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.0),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
        onChanged: (value) {
          _searchDebounceTimer?.cancel();
          _searchDebounceTimer = Timer(
            const Duration(milliseconds: 500),
            () => widget.onSearchChanged(value),
          );
        },
      ),
    );
  }

  // 优化：将筛选和排序栏提取为独立组件
  Widget _buildFilterAndSortBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _buildFilterChips(),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: '筛选和排序',
            onPressed: () => _showFilterSortSheet(context),
          ),
        ],
      ),
    );
  }

  // 优化：构建筛选标签的部分
  Widget _buildFilterChips() {
    if (widget.isLoadingTags) {
      return const SizedBox(
        height: 40,
        child: Center(child: AppLoadingView(message: '加载标签...')),
      );
    }

    if (widget.tags.isEmpty) {
      return const SizedBox(height: 40);
    }

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.tags.length,
        itemBuilder: (context, index) {
          final tag = widget.tags[index];
          final isSelected = widget.selectedTagIds.contains(tag.id);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ChoiceChip(
              label: Text(tag.name),
              avatar: tag.icon != null
                  ? IconUtils.getIcon(
                      tag.icon!,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    )
                  : null,
              selected: isSelected,
              onSelected: (selected) {
                final newSelection = List<String>.from(widget.selectedTagIds);
                if (selected) {
                  newSelection.add(tag.id);
                } else {
                  newSelection.remove(tag.id);
                }
                widget.onTagSelectionChanged(newSelection);
              },
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildFilterAndSortBar(),
        Expanded(
          child: _buildNoteList(),
        ),
      ],
    );
  }

  Widget _buildNoteList() {
    if (_isLoading && _quotes.isEmpty) {
      return const AppLoadingView(message: '正在加载笔记...');
    }

    if (_quotes.isEmpty) {
      return const AppEmptyView(
        text: '没有找到相关笔记',
        svgAsset: 'assets/empty.svg', // 请确保此资源存在
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _updateStreamSubscription();
      },
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _quotes.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _quotes.length) {
            // 不再在这里调用 _loadMore()，由 _onScroll 统一处理
            return _hasMore
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }

          final quote = _quotes[index];
          final key = _itemKeys.putIfAbsent(quote.id!, () => GlobalKey());
          final isExpanded = _expandedItems[quote.id] ?? false;

          return QuoteItemWidget(
            key: key,
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
            onGenerateCard: widget.onGenerateCard != null
                ? () => widget.onGenerateCard!(quote)
                : null,
            onFavorite: widget.onFavorite != null
                ? () => widget.onFavorite!(quote)
                : null,
            searchQuery: widget.searchQuery,
          );
        },
      ),
    );
  }

  /// 加载更多数据
  Future<void> _loadMore() async {
    // 防止重复加载
    if (!_hasMore || _isLoading) {
      logDebug('跳过加载更多：_hasMore=$_hasMore, _isLoading=$_isLoading',
          source: 'NoteListView');
      return;
    }

    // 修复：立即设置加载状态，防止并发调用
    setState(() {
      _isLoading = true;
    });

    try {
      logDebug('触发加载更多，当前有${_quotes.length}条数据', source: 'NoteListView');
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.loadMoreQuotes();

      // 强制检查状态更新
      if (mounted) {
        setState(() {
          _hasMore = db.hasMoreQuotes;
          _isLoading = false; // 加载完成后重置状态
        });
      }
    } catch (e) {
      // 修复：出错时也要重置加载状态
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      logError('加载更多笔记失败: $e', error: e, source: 'NoteListView');
    }
  }

  void _showFilterSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return NoteFilterSortSheet(
          allTags: widget.tags,
          selectedTagIds: widget.selectedTagIds,
          sortType: widget.sortType,
          sortAscending: widget.sortAscending,
          selectedWeathers: widget.selectedWeathers,
          selectedDayPeriods: widget.selectedDayPeriods,
          onApply: (tagIds, sortType, sortAscending, weathers, dayPeriods) {
            widget.onTagSelectionChanged(tagIds);
            widget.onSortChanged(sortType, sortAscending);
            widget.onFilterChanged(weathers, dayPeriods);
            Navigator.pop(context);
          },
        );
      },
    );
  }

  void forceRefresh() {
    _updateStreamSubscription();
  }
}
