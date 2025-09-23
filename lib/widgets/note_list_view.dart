import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../utils/icon_utils.dart';
import '../utils/lottie_animation_manager.dart';
import '../widgets/quote_item_widget.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import 'note_filter_sort_sheet.dart';
import '../utils/color_utils.dart'; // Import color_utils
import 'package:thoughtecho/utils/app_logger.dart';
import '../services/weather_service.dart'; // 导入天气服务
import '../utils/time_utils.dart'; // 导入时间工具
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
  // 移除AnimatedList相关的Key，改用ListView.builder

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = true;
  bool _hasMore = true;
  static const int _pageSize = AppConstants.defaultPageSize;
  StreamSubscription<List<Quote>>? _quotesSub;

  // 修复：添加防抖定时器和性能优化
  Timer? _searchDebounceTimer;
  // ---- 自动滚动控制新增状态 ----
  bool _autoScrollEnabled = false; // 首批数据加载完成后再允许自动滚动
  bool _initialDataLoaded = false; // 标记是否已收到首批数据（后续用于启用自动滚动）
  bool _isAutoScrolling = false; // 当前是否有程序驱动的滚动动画
  DateTime? _lastUserScrollTime; // 最近一次用户滚动时间
  bool _isInitializing = true; // 标记是否正在初始化，避免冷启动滚动冲突

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    _hasMore = true;
    _isLoading = true;
    _isInitializing = true; // 初始化状态标记

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

    // 如果正在初始化，忽略滚动事件以避免冲突
    if (_isInitializing) {
      logDebug('正在初始化，忽略滚动事件', source: 'NoteListView');
      return;
    }

    // 用户正在滑动（通过滚动事件检测）
    _isUserScrolling = true;
    _lastUserScrollTime = DateTime.now();

    // 重置定时器
    _userScrollingTimer?.cancel();

    // 设置定时器，滑动停止后1秒重置状态
    _userScrollingTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isUserScrolling = false;
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
            // 延迟启用自动滚动，避免冷启动时的滚动冲突
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                _autoScrollEnabled = true;
                _isInitializing = false; // 结束初始化状态
                logDebug('延迟启用自动滚动功能', source: 'NoteListView');
              }
            });
            // 冷启动保护期：设置较长的保护期，避免首次进入时的滚动冲突
            _lastUserScrollTime = DateTime.now();
            logDebug('首批数据加载完成，将延迟启用自动滚动', source: 'NoteListView');
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
    // 注释掉重复的loadMore调用，因为watchQuotes已经会自动加载数据
    // _loadMore(); // 这行导致双重加载和滚动位置混乱
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

          // 恢复滚动位置（在数据加载完成后，且不在初始化状态）
          if (savedScrollOffset != null &&
              _scrollController.hasClients &&
              !_isInitializing &&
              _initialDataLoaded) {
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

    // 清理初始化状态
    _isInitializing = false;
    super.dispose();
  }

  Future<void> resetAndLoad() async {
    _quotes.clear();
    _hasMore = true;
    _loadMore();
  }

  // 添加滚动状态标志，防止在用户滑动时触发自动滚动
  bool _isUserScrolling = false;
  Timer? _userScrollingTimer;

  /// 滚动到指定笔记的顶部 - 使用 ensureVisible 确保多展开笔记时定位准确
  void _scrollToItem(String quoteId, int index) {
    if (!mounted || !_scrollController.hasClients) return;
    // 多重保护条件
    if (_isInitializing) {
      logDebug('跳过自动滚动：正在初始化', source: 'NoteListView');
      return;
    }
    if (!_autoScrollEnabled) {
      logDebug('跳过自动滚动（未启用 _autoScrollEnabled）', source: 'NoteListView');
      return;
    }
    if (_isUserScrolling) {
      logDebug('跳过自动滚动：用户正在滑动', source: 'NoteListView');
      return;
    }
    if (_lastUserScrollTime != null &&
        DateTime.now().difference(_lastUserScrollTime!) <
            const Duration(milliseconds: 3000)) {
      // 增加保护期到3秒，给冷启动更多时间
      logDebug('跳过自动滚动：用户刚刚滚动 (<3000ms)', source: 'NoteListView');
      return;
    }
    if (_isAutoScrolling) {
      logDebug('跳过自动滚动：已有动画', source: 'NoteListView');
      return;
    }

    try {
      final key = _itemKeys[quoteId];
      if (key == null || key.currentContext == null) {
        logDebug('笔记Key或Context不存在，跳过滚动', source: 'NoteListView');
        return;
      }

      _isAutoScrolling = true;
      logDebug('使用ensureVisible滚动到笔记: $quoteId (index: $index)',
          source: 'NoteListView');

      // 使用 Scrollable.ensureVisible 自动处理动态布局
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: 0.0, // 滚动到顶部
      ).then((_) {
        _isAutoScrolling = false;
        logDebug('ensureVisible滚动完成', source: 'NoteListView');
      }).catchError((e) {
        _isAutoScrolling = false;
        logDebug('ensureVisible滚动失败: $e', source: 'NoteListView');
      });
    } catch (e, st) {
      logDebug('滚动到笔记失败: $e\n$st', source: 'NoteListView');
      _isAutoScrolling = false;
    }
  }

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
      logError('加载更多数据失败: $e', error: e, source: 'NoteListView');
      rethrow;
    }
  }

  Widget _buildNoteList(DatabaseService db, ThemeData theme) {
    if (_isLoading) {
      // 搜索时用专属动画
      if (widget.searchQuery.isNotEmpty) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = (constraints.maxHeight * 0.7).clamp(120.0, 400.0);
            return Center(
              child: EnhancedLottieAnimation(
                type: LottieAnimationType.weatherSearchLoading,
                width: size,
                height: size,
                semanticLabel: '搜索中',
              ),
            );
          },
        );
      }
      return const AppLoadingView();
    }
    if (_quotes.isEmpty && widget.searchQuery.isEmpty) {
      return const AppEmptyView(
        svgAsset: 'assets/empty/empty_state.svg',
        text: '还没有笔记，开始记录吧！',
      );
    }
    if (_quotes.isEmpty && widget.searchQuery.isNotEmpty) {
      return Center(
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
            const Text(
              '未找到相关笔记',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              '尝试使用其他关键词或检查拼写',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        // 修复：优化预加载逻辑，减少频繁触发
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          // 修复：使用常量文件中的阈值，适应不同屏幕尺寸
          final threshold =
              metrics.maxScrollExtent * AppConstants.scrollPreloadThreshold;
          if (metrics.pixels > threshold &&
              metrics.maxScrollExtent > 0 &&
              !_isLoading &&
              _hasMore) {
            logDebug(
                '滚动触发加载：pixels=${metrics.pixels.toInt()}, maxExtent=${metrics.maxScrollExtent.toInt()}, threshold=${threshold.toInt()}',
                source: 'NoteListView');
            _loadMore();
          }
        }
        return true;
      },
      child: ListView.builder(
        controller: _scrollController, // 添加滚动控制器
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _quotes.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < _quotes.length) {
            final quote = _quotes[index];
            // 获取展开状态，如果不存在则默认为折叠状态
            final bool isExpanded = _expandedItems[quote.id] ?? false;

            // 为每个笔记生成一个唯一的key用于滚动定位
            final String itemKey = 'quote_${quote.id}_$index';
            if (!_itemKeys.containsKey(quote.id)) {
              _itemKeys[quote.id!] = GlobalKey(debugLabel: itemKey);
            }

            // 直接返回QuoteItemWidget，移除动画
            return Container(
              key: _itemKeys[quote.id],
              child: QuoteItemWidget(
                quote: quote,
                tags: widget.tags,
                isExpanded: isExpanded,
                onToggleExpanded: (expanded) {
                  setState(() {
                    _expandedItems[quote.id!] = expanded;
                  });

                  // 折叠后滚动到笔记顶部
                  if (!expanded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToItem(quote.id!, index);
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
                    : null, // 新增：心形按钮回调
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
            );
          }
          // 底部加载指示器
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: AppLoadingView(size: 32),
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
        // 优化：只有当搜索内容长度>=2时才显示加载状态
      } else if (value.isNotEmpty &&
          value.length >= AppConstants.minSearchLength) {
        // 优化：只有当搜索内容长度>=2时才显示加载状态
        _isLoading = true;
      }
    });

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

          // 显示超时提示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('搜索超时，请重试或检查网络连接'),
                duration: AppConstants.snackBarDurationImportant,
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: '重试',
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
    final isTablet = width > AppConstants.tabletMinWidth;
    final maxWidth = isTablet ? AppConstants.tabletMaxContentWidth : width;
    final horizontalPadding = isTablet ? 16.0 : 8.0;

    // 布局构建
    return LayoutBuilder(
      builder: (context, constraints) {
        // 主体内容 - 添加白色背景容器
        return Container(
            color: Colors.white, // 固定白色背景，不受主题影响
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
                          hintText: '搜索笔记...',
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          prefixIcon: searchController.isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: EnhancedLottieAnimation(
                                      type: LottieAnimationType.searchLoading,
                                      width: 16,
                                      height: 16,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.search),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.tune),
                            tooltip: '筛选/排序',
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLowest,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                ),
                                builder: (context) => NoteFilterSortSheet(
                                  allTags: widget.tags,
                                  selectedTagIds: widget.selectedTagIds,
                                  sortType: widget.sortType,
                                  sortAscending: widget.sortAscending,
                                  selectedWeathers: widget.selectedWeathers,
                                  selectedDayPeriods: widget.selectedDayPeriods,
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.28),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.20),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.65),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 筛选条件展示区域
                    _buildFilterDisplay(theme, horizontalPadding),

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
            ));
      },
    );
  }

  /// 构建现代化的筛选条件展示区域
  Widget _buildFilterDisplay(ThemeData theme, double horizontalPadding) {
    final hasFilters = widget.selectedTagIds.isNotEmpty ||
        widget.selectedWeathers.isNotEmpty ||
        widget.selectedDayPeriods.isNotEmpty;

    if (!hasFilters) return const SizedBox.shrink();

    // 收集所有筛选chip
    final List<Widget> allChips = [];

    // 添加标签chip
    if (widget.selectedTagIds.isNotEmpty) {
      allChips.addAll(widget.selectedTagIds.map((tagId) {
        final tag = widget.tags.firstWhere(
          (tag) => tag.id == tagId,
          orElse: () => NoteCategory(id: tagId, name: '未知标签'),
        );
        return _buildModernFilterChip(
          theme: theme,
          label: tag.name,
          color: theme.colorScheme.primary,
          onDeleted: () {
            final newSelectedTags = List<String>.from(
              widget.selectedTagIds,
            )..remove(tagId);
            widget.onTagSelectionChanged(newSelectedTags);
          },
        );
      }));
    }

    // 添加天气chip（按大类显示）
    if (widget.selectedWeathers.isNotEmpty) {
      final Set<String> categorySet = {};
      for (final key in widget.selectedWeathers) {
        final cat = WeatherService.getFilterCategoryByWeatherKey(key);
        if (cat != null) categorySet.add(cat);
      }

      allChips.addAll(categorySet.map((cat) {
        final label = WeatherService.filterCategoryToLabel[cat] ?? cat;
        final icon = WeatherService.getFilterCategoryIcon(cat);
        return _buildModernFilterChip(
          theme: theme,
          label: label,
          icon: icon,
          color: theme.colorScheme.secondary,
          onDeleted: () {
            final keysToRemove = WeatherService.getWeatherKeysByFilterCategory(cat);
            final newWeathers = List<String>.from(widget.selectedWeathers)
              ..removeWhere((w) => keysToRemove.contains(w));
            widget.onFilterChanged(
              newWeathers,
              widget.selectedDayPeriods,
            );
            _updateStreamSubscription();
          },
        );
      }));

      // 处理未归类的key
      final Set<String> knownKeys = categorySet
          .expand((cat) => WeatherService.getWeatherKeysByFilterCategory(cat))
          .toSet();
      final List<String> others = widget.selectedWeathers
          .where((k) => !knownKeys.contains(k))
          .toList();
      for (final k in others) {
        final label = WeatherService.weatherKeyToLabel[k] ?? k;
        allChips.add(
          _buildModernFilterChip(
            theme: theme,
            label: label,
            color: theme.colorScheme.secondary,
            onDeleted: () {
              final newWeathers = List<String>.from(widget.selectedWeathers)..remove(k);
              widget.onFilterChanged(newWeathers, widget.selectedDayPeriods);
              _updateStreamSubscription();
            },
          ),
        );
      }
    }

    // 添加时间段chip
    if (widget.selectedDayPeriods.isNotEmpty) {
      allChips.addAll(widget.selectedDayPeriods.map((periodKey) {
        final periodLabel = TimeUtils.getDayPeriodLabel(periodKey);
        final periodIcon = TimeUtils.getDayPeriodIconByKey(periodKey);
        return _buildModernFilterChip(
          theme: theme,
          label: periodLabel,
          icon: periodIcon,
          color: theme.colorScheme.tertiary,
          onDeleted: () {
            final newDayPeriods = List<String>.from(widget.selectedDayPeriods)..remove(periodKey);
            widget.onFilterChanged(
              widget.selectedWeathers,
              newDayPeriods,
            );
            _updateStreamSubscription();
          },
        );
      }));
    }

    // 创建清除全部按钮
    final clearAllButton = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            widget.onTagSelectionChanged([]);
            widget.onFilterChanged([], []);
            _updateStreamSubscription();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 6.0,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // 筛选图标
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.filter_alt_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              ...allChips,
              if (allChips.isNotEmpty) const SizedBox(width: 12),
              clearAllButton,
            ],
          ),
        ),
      ),
    );
  }


  /// 构建现代化的筛选条件芯片
  Widget _buildModernFilterChip({
    required ThemeData theme,
    required String label,
    required Color color,
    required VoidCallback onDeleted,
    IconData? icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: IntrinsicWidth(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 12,
                top: 8,
                bottom: 8,
                right: icon != null ? 4 : 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDeleted,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
