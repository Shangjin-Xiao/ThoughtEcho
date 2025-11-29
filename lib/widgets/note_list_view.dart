import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../utils/icon_utils.dart';
import '../utils/lottie_animation_manager.dart';
import '../widgets/quote_item_widget.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import 'note_filter_sort_sheet.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import '../utils/color_utils.dart';
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
  final GlobalKey? filterButtonKey; // 功能引导：筛选按钮的 Key
  final GlobalKey? favoriteButtonGuideKey; // 功能引导：心形按钮 Key
  final GlobalKey? foldToggleGuideKey; // 功能引导：折叠/展开区域 Key
  final VoidCallback? onGuideTargetsReady; // 功能引导：目标就绪回调

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
    this.filterButtonKey, // 功能引导 Key
    this.favoriteButtonGuideKey,
    this.foldToggleGuideKey,
    this.onGuideTargetsReady,
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
  final Map<String, ValueNotifier<bool>> _expansionNotifiers = {};
  // 移除AnimatedList相关的Key，改用ListView.builder

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = true;
  bool _hasMore = true;
  static const int _pageSize = AppConstants.defaultPageSize;
  StreamSubscription<List<Quote>>? _quotesSub;

  // 修复：用于检测和恢复滚动范围异常的计数器
  int _scrollExtentCheckCounter = 0;
  static const int _maxScrollExtentChecks = 3;

  // 修复：添加防抖定时器和性能优化
  Timer? _searchDebounceTimer;
  // ---- 自动滚动控制新增状态 ----
  bool _autoScrollEnabled = false; // 首批数据加载完成后再允许自动滚动
  bool _initialDataLoaded = false; // 标记是否已收到首批数据（后续用于启用自动滚动）
  bool _isAutoScrolling = false; // 当前是否有程序驱动的滚动动画
  DateTime? _lastUserScrollTime; // 最近一次用户滚动时间
  bool _isInitializing = true; // 标记是否正在初始化，避免冷启动滚动冲突

  bool get hasQuotes => _quotes.isNotEmpty;

  bool get hasExpandableQuote => _quotes.any(QuoteItemWidget.needsExpansionFor);

  bool get isFilterGuideReady =>
      widget.filterButtonKey != null &&
      widget.filterButtonKey!.currentContext != null &&
      widget.filterButtonKey!.currentContext!.findRenderObject() is RenderBox;

  bool get canShowFavoriteGuide =>
      widget.onFavorite != null &&
      hasQuotes &&
      widget.favoriteButtonGuideKey != null &&
      widget.favoriteButtonGuideKey!.currentContext != null &&
      widget.favoriteButtonGuideKey!.currentContext!.findRenderObject()
          is RenderBox;

  bool get canShowExpandGuide =>
      hasExpandableQuote &&
      widget.foldToggleGuideKey != null &&
      widget.foldToggleGuideKey!.currentContext != null &&
      widget.foldToggleGuideKey!.currentContext!.findRenderObject()
          is RenderBox;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    _hasMore = true;
    _isLoading = false; // Changed to false to avoid initial flash
    _isInitializing = true;

    // 添加焦点节点监听器，用于Web平台的焦点管理
    _searchFocusNode.addListener(_onFocusChanged);

    // 添加滚动控制器监听器，用于检测用户滑动状态
    _scrollController.addListener(_onScroll);

    // 优化：延迟初始化数据流订阅，避免build过程中的副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataStream();
      if (!mounted) return;
      widget.onGuideTargetsReady?.call();
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

    // 性能优化：增加阈值判断，避免微小滚动触发逻辑
    final currentOffset = _scrollController.offset;
    if ((currentOffset - _lastScrollOffset).abs() < _scrollThreshold) {
      return;
    }
    _lastScrollOffset = currentOffset;

    // 修复：检测滚动范围异常（列表提前终止的情况）
    _checkAndFixScrollExtentAnomaly();

    // 如果正在初始化，忽略滚动事件以避免冲突
    if (_isInitializing) {
      logDebug('正在初始化，忽略滚动事件', source: 'NoteListView');
      return;
    }

    // 自动滚动过程中产生的事件不视为用户操作
    if (_isAutoScrolling) {
      logDebug('自动滚动进行中，忽略滚动事件', source: 'NoteListView');
      return;
    }

    // 用户正在滑动（通过滚动事件检测）
    if (!_isUserScrolling) {
      _isUserScrolling = true;
    }

    final now = DateTime.now();
    _lastUserScrollTime = now;

    // 重置定时器
    _userScrollingTimer?.cancel();

    // 设置定时器，滑动停止后快速重置状态
    _userScrollingTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_isAutoScrolling) return;

      if (_isUserScrolling) {
        setState(() {
          _isUserScrolling = false;
        });
      }
      _lastUserScrollTime = null;
    });
  }

  /// 修复：检测并修复滚动范围异常
  /// 当用户滚动到接近底部但列表提前终止时，尝试强制刷新
  void _checkAndFixScrollExtentAnomaly() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_isLoading || !_hasMore) return;

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final currentOffset = position.pixels;

    // 如果用户滚动到了接近底部（最后 200 像素），但 _hasMore 为 true
    // 且列表似乎没有更多内容可滚动，这可能是异常情况
    if (maxExtent > 0 && currentOffset > maxExtent - 200) {
      // 检查是否实际还有更多数据
      final db = Provider.of<DatabaseService>(context, listen: false);
      final dbHasMore = db.hasMoreQuotes;

      if (dbHasMore && !_isLoading) {
        // 数据库表示还有更多数据，但列表可能没有正确更新
        _scrollExtentCheckCounter++;
        logDebug(
          '检测到可能的滚动范围异常 (第 $_scrollExtentCheckCounter 次): '
          'maxExtent=$maxExtent, offset=$currentOffset, dbHasMore=$dbHasMore',
          source: 'NoteListView',
        );

        if (_scrollExtentCheckCounter >= _maxScrollExtentChecks) {
          // 多次检测到异常，尝试强制加载更多
          logDebug('触发强制加载更多数据以修复滚动范围', source: 'NoteListView');
          _scrollExtentCheckCounter = 0;
          _forceLoadMore();
        }
      } else if (!dbHasMore && _hasMore) {
        // 数据库表示没有更多数据，但本地状态不一致，同步状态
        logDebug('同步 _hasMore 状态: 从 true 改为 false', source: 'NoteListView');
        setState(() {
          _hasMore = false;
        });
        _scrollExtentCheckCounter = 0;
      }
    } else {
      // 不在底部区域，重置计数器
      _scrollExtentCheckCounter = 0;
    }
  }

  /// 修复：强制加载更多数据
  Future<void> _forceLoadMore() async {
    if (!mounted || _isLoading) return;

    logDebug('强制加载更多数据开始', source: 'NoteListView');

    setState(() {
      _isLoading = true;
    });

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.loadMoreQuotes();

      if (mounted) {
        setState(() {
          _hasMore = db.hasMoreQuotes;
          _isLoading = false;
        });

        // 强制刷新 ScrollController 以更新滚动范围
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            // 触发轻微滚动以强制重新计算滚动范围
            final currentOffset = _scrollController.offset;
            _scrollController.jumpTo(currentOffset + 0.1);
            _scrollController.jumpTo(currentOffset);
          }
        });
      }
    } catch (e) {
      logError('强制加载更多数据失败: $e', error: e, source: 'NoteListView');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
    if (!mounted) return;

    _quotesSub?.cancel();

    final db = Provider.of<DatabaseService>(context, listen: false);

    if (!db.isInitialized) {
      logDebug('数据库未初始化，等待初始化完成后重新订阅');
      db.addListener(_onDatabaseServiceChanged);
      return;
    }

    bool isFirstLoad = !_initialDataLoaded;

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
          // 修复：在首次加载期间保存滚动位置，避免数据刷新时滚动到顶部
          double? savedScrollOffset;
          if (isFirstLoad &&
              _scrollController.hasClients &&
              _quotes.isNotEmpty) {
            savedScrollOffset = _scrollController.offset;
            logDebug('首次加载期间保存滚动位置: $savedScrollOffset',
                source: 'NoteListView');
          }

          setState(() {
            if (isFirstLoad) {
              _quotes.clear();
            }
            _quotes
              ..clear()
              ..addAll(
                  list); // Simplified: always replace for consistency, but flag prevents extra sets
            _hasMore = list.length >= _pageSize;
            _isLoading = false;
            _pruneExpansionControllers();
          });

          if (widget.onGuideTargetsReady != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onGuideTargetsReady!.call();
            });
          }

          // 修复：在首次加载期间恢复滚动位置
          if (savedScrollOffset != null &&
              savedScrollOffset > 0 &&
              !_isUserScrolling) {
            final offset = savedScrollOffset; // 捕获非空值
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _scrollController.hasClients &&
                  offset <= _scrollController.position.maxScrollExtent) {
                _scrollController.jumpTo(offset);
                logDebug('首次加载期间恢复滚动位置: $offset', source: 'NoteListView');
              }
            });
          }

          if (isFirstLoad) {
            _initialDataLoaded = true;
            // 延迟启用自动滚动，避免冷启动时的滚动冲突
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                _autoScrollEnabled = true;
                _isInitializing = false;
                logDebug('首次加载完成，启用自动滚动', source: 'NoteListView');
              }
            });
            // 冷启动保护期：设置较长的保护期，避免首次进入时的滚动冲突
            _lastUserScrollTime = DateTime.now();
            logDebug('首次数据加载完成', source: 'NoteListView');
          }

          // 修复：同步 _hasMore 状态与数据库服务状态
          final dbService = Provider.of<DatabaseService>(context, listen: false);
          if (_hasMore != dbService.hasMoreQuotes) {
            logDebug(
              '同步 _hasMore 状态: $_hasMore -> ${dbService.hasMoreQuotes}',
              source: 'NoteListView',
            );
            _hasMore = dbService.hasMoreQuotes;
          }
          // 重置滚动范围检查计数器
          _scrollExtentCheckCounter = 0;

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

          if (isFirstLoad) {
            isFirstLoad = false;
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

    if (shouldUpdate && _initialDataLoaded && !_isInitializing) {
      // 如果是首次加载期间（初始数据还未加载完成），避免重置滚动位置
      if (!_initialDataLoaded) {
        logDebug('跳过更新订阅：首次数据加载中', source: 'NoteListView');
        return;
      }

      // 判断是否仅为排序变化（不影响列表内容，只影响顺序）
      final bool isOnlySortChange = oldWidget.searchQuery ==
              widget.searchQuery &&
          _areListsEqual(oldWidget.selectedTagIds, widget.selectedTagIds) &&
          _areListsEqual(oldWidget.selectedWeathers, widget.selectedWeathers) &&
          _areListsEqual(
              oldWidget.selectedDayPeriods, widget.selectedDayPeriods) &&
          (oldWidget.sortType != widget.sortType ||
              oldWidget.sortAscending != widget.sortAscending);

      // 更新流订阅，传入是否仅为排序变化
      _updateStreamSubscription(preserveScrollPosition: isOnlySortChange);
    } else if (shouldUpdate) {
      logDebug('跳过更新：初始化中或数据未加载', source: 'NoteListView');
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
  void _updateStreamSubscription({bool preserveScrollPosition = false}) {
    if (!mounted) return; // 确保组件仍然挂载

    logDebug('更新数据流订阅 (preserveScrollPosition: $preserveScrollPosition)',
        source: 'NoteListView');

    double? savedScrollOffset;
    // 只有在需要保持滚动位置时才保存（仅排序变化时）
    if (preserveScrollPosition &&
        _scrollController.hasClients &&
        _quotes.isNotEmpty) {
      savedScrollOffset = _scrollController.offset;
      logDebug('保存滚动位置: $savedScrollOffset', source: 'NoteListView');
    } else if (!preserveScrollPosition) {
      logDebug('筛选条件变化，不保存滚动位置，将重置到顶部', source: 'NoteListView');
    }

    // Set loading only if not first load
    if (_initialDataLoaded) {
      setState(() {
        _isLoading = true;
      });
    }

    _hasMore = true;

    final db = Provider.of<DatabaseService>(context, listen: false);

    _quotesSub?.cancel();

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
            _hasMore = list.length >= _pageSize;
            _isLoading = false;
            _pruneExpansionControllers();
          });

          if (widget.onGuideTargetsReady != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onGuideTargetsReady!.call();
            });
          }

          // Restore scroll position smoothly (only if preserveScrollPosition is true)
          if (savedScrollOffset != null &&
              _scrollController.hasClients &&
              _initialDataLoaded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (savedScrollOffset != null &&
                  _scrollController.hasClients &&
                  savedScrollOffset <=
                      _scrollController.position.maxScrollExtent) {
                _scrollController.animateTo(
                  savedScrollOffset,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
                logDebug('平滑恢复滚动位置: $savedScrollOffset',
                    source: 'NoteListView');
              } else {
                logDebug('滚动位置超出范围或条件不满足，保持当前位置', source: 'NoteListView');
              }
            });
          }

          // 修复：同步 _hasMore 状态与数据库服务状态
          final dbServiceForSync = Provider.of<DatabaseService>(context, listen: false);
          if (_hasMore != dbServiceForSync.hasMoreQuotes) {
            logDebug(
              '更新订阅后同步 _hasMore 状态: $_hasMore -> ${dbServiceForSync.hasMoreQuotes}',
              source: 'NoteListView',
            );
            _hasMore = dbServiceForSync.hasMoreQuotes;
          }
          // 重置滚动范围检查计数器
          _scrollExtentCheckCounter = 0;

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

    for (final notifier in _expansionNotifiers.values) {
      notifier.dispose();
    }
    _expansionNotifiers.clear();

    // 修复问题3：移除页面切换时的缓存清空，保留缓存以提升返回体验
    // QuoteContent.resetCaches(); // 缓存将由 LRU 自动管理

    // 清理初始化状态
    _isInitializing = false;
    super.dispose();
  }

  Future<void> resetAndLoad() async {
    _quotes.clear();
    _hasMore = true;
    _loadMore();
  }

  ValueNotifier<bool> _obtainExpansionNotifier(String quoteId) {
    return _expansionNotifiers.putIfAbsent(
      quoteId,
      () => ValueNotifier<bool>(_expandedItems[quoteId] ?? false),
    );
  }

  void _pruneExpansionControllers() {
    final activeIds =
        _quotes.map((quote) => quote.id).whereType<String>().toSet();

    final removableIds = _expansionNotifiers.keys
        .where((id) => !activeIds.contains(id))
        .toList();

    for (final id in removableIds) {
      _expansionNotifiers.remove(id)?.dispose();
      _expandedItems.remove(id);
      _itemKeys.remove(id);
    }
  }

  // 添加滚动状态标志，防止在用户滑动时触发自动滚动
  bool _isUserScrolling = false;
  Timer? _userScrollingTimer;
  double _lastScrollOffset = 0;
  static const double _scrollThreshold = 5.0; // 性能优化：5像素阈值

  /// 滚动到指定笔记的顶部 - 使用 ensureVisible 确保多展开笔记时定位准确
  /// 注意：目前未被使用，因为折叠时的自动滚动被禁用以改善用户体验
  /// 如果将来需要重新启用，可以取消注释相关调用代码
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
            const Duration(milliseconds: 900)) {
      logDebug('跳过自动滚动：用户刚刚滚动 (<900ms)', source: 'NoteListView');
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

      final targetContext = key.currentContext;
      if (targetContext == null) {
        logDebug('笔记Context为空，无法滚动', source: 'NoteListView');
        return;
      }

      final renderObject = targetContext.findRenderObject();
      if (renderObject == null) {
        logDebug('找不到RenderObject，跳过滚动', source: 'NoteListView');
        return;
      }

      final viewport = RenderAbstractViewport.of(renderObject);

      final reveal = viewport.getOffsetToReveal(renderObject, 0.0);
      final targetOffset = reveal.offset;
      final position = _scrollController.position;
      final viewportExtent = position.viewportDimension;
      final currentOffset = position.pixels;

      if (viewportExtent > 0) {
        final topVisible = targetOffset >= currentOffset &&
            targetOffset < currentOffset + viewportExtent;
        if (topVisible) {
          logDebug('笔记顶部已在视口内，跳过自动滚动', source: 'NoteListView');
          return;
        }
      }

      final minExtent = position.minScrollExtent;
      final maxExtent = position.maxScrollExtent;

      double desiredOffset =
          (targetOffset - 12.0).clamp(minExtent, maxExtent).toDouble();

      if ((currentOffset - desiredOffset).abs() <= 4) {
        logDebug('目标偏移量变化较小，跳过自动滚动', source: 'NoteListView');
        return;
      }

      _isAutoScrolling = true;
      logDebug(
        '滚动到笔记: $quoteId (index: $index), target=${desiredOffset.toStringAsFixed(1)}',
        source: 'NoteListView',
      );

      _scrollController
          .animateTo(
        desiredOffset,
        duration: QuoteItemWidget.expandCollapseDuration,
        curve: Curves.easeOutCubic,
      )
          .then((_) {
        logDebug('滚动完成', source: 'NoteListView');
      }).catchError((e) {
        logDebug('滚动失败: $e', source: 'NoteListView');
      }).whenComplete(() {
        _isAutoScrolling = false;
      });
    } catch (e, st) {
      logDebug('滚动失败: $e\n$st', source: 'NoteListView');
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

    // 修复：在加载前先同步一次状态，确保 _hasMore 是最新的
    final db = Provider.of<DatabaseService>(context, listen: false);
    if (!db.hasMoreQuotes) {
      logDebug('数据库显示无更多数据，同步 _hasMore 为 false', source: 'NoteListView');
      setState(() {
        _hasMore = false;
      });
      return;
    }

    // 修复：立即设置加载状态，防止并发调用
    setState(() {
      _isLoading = true;
    });

    try {
      logDebug('触发加载更多，当前有${_quotes.length}条数据', source: 'NoteListView');
      await db.loadMoreQuotes();

      // 强制检查状态更新
      if (mounted) {
        setState(() {
          _hasMore = db.hasMoreQuotes;
          _isLoading = false; // 加载完成后重置状态
        });

        // 修复：加载更多后强制刷新滚动范围
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            // 触发轻微滚动以强制重新计算滚动范围
            final currentOffset = _scrollController.offset;
            if (currentOffset > 0) {
              _scrollController.jumpTo(currentOffset + 0.1);
              _scrollController.jumpTo(currentOffset);
            }
          }
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
    // 为 AnimatedSwitcher 提供唯一 key，确保筛选变化时能触发动画
    final listKey = ValueKey(
        '${widget.selectedTagIds.join(',')}_${widget.selectedWeathers.join(',')}_${widget.selectedDayPeriods.join(',')}_${widget.searchQuery}');

    if (_isLoading && _quotes.isEmpty) {
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
                semanticLabel: '搜索中',
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
        text: '还没有笔记，开始记录吧！',
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

    var favoriteGuideAssigned = false;
    var foldGuideAssigned = false;

    return NotificationListener<ScrollNotification>(
      key: listKey,
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

        // 修复：在滚动结束时检查是否需要加载更多
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          // 如果滚动到了底部附近，且还有更多数据，确保触发加载
          if (metrics.pixels >= metrics.maxScrollExtent - 100 &&
              _hasMore &&
              !_isLoading) {
            logDebug(
                '滚动结束时检测到接近底部，尝试加载更多',
                source: 'NoteListView');
            _loadMore();
          }
        }
        return true;
      },
      child: ListView.builder(
        controller: _scrollController, // 添加滚动控制器
        physics: const AlwaysScrollableScrollPhysics(),
        addAutomaticKeepAlives: true, // 性能优化：保持滚动位置
        addRepaintBoundaries: true, // 性能优化：减少重绘范围
        cacheExtent: 500, // 性能优化：预渲染500像素范围
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
                quoteId, () => GlobalKey(debugLabel: itemKey));

            final bool needsExpansion =
                QuoteItemWidget.needsExpansionFor(quote);

            final attachFavoriteGuideKey = !favoriteGuideAssigned &&
                widget.favoriteButtonGuideKey != null &&
                widget.onFavorite != null;
            final attachFoldGuideKey = !foldGuideAssigned &&
                widget.foldToggleGuideKey != null &&
                needsExpansion;

            if (attachFavoriteGuideKey) {
              favoriteGuideAssigned = true;
            }

            if (attachFoldGuideKey) {
              foldGuideAssigned = true;
            }

            final expansionNotifier = _obtainExpansionNotifier(quoteId);
            _expandedItems.putIfAbsent(quoteId, () => expansionNotifier.value);

            return RepaintBoundary(
              key: _itemKeys[quoteId],
              child: ValueListenableBuilder<bool>(
                valueListenable: expansionNotifier,
                builder: (context, isExpanded, child) => QuoteItemWidget(
                  quote: quote,
                  tags: widget.tags,
                  selectedTagIds: widget.selectedTagIds,
                  isExpanded: isExpanded,
                  onToggleExpanded: (expanded) {
                    if (expansionNotifier.value != expanded) {
                      expansionNotifier.value = expanded;
                    }
                    _expandedItems[quoteId] = expanded;

                    final bool requiresAlignment = needsExpansion;

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
                  favoriteButtonGuideKey: attachFavoriteGuideKey
                      ? widget.favoriteButtonGuideKey
                      : null,
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
      setState(() {
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
                          hintText: AppLocalizations.of(context).searchNotes,
                          isDense: true,
                          filled: true,
                          fillColor: ColorUtils.getSearchBoxBackgroundColor(
                            theme.colorScheme.surface,
                            theme.brightness,
                          ),
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
                            key: widget.filterButtonKey, // 功能引导 key
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
            ));
      },
    );
  }

  /// 构建现代化的筛选条件展示区域
  Widget _buildFilterDisplay(ThemeData theme, double horizontalPadding) {
    final hasFilters = widget.selectedTagIds.isNotEmpty ||
        widget.selectedWeathers.isNotEmpty ||
        widget.selectedDayPeriods.isNotEmpty;

    // 使用 AnimatedSize 实现整个筛选区域的展开/收起动画
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: !hasFilters
          ? const SizedBox.shrink()
          : _buildFilterContent(theme, horizontalPadding),
    );
  }

  /// 构建筛选条件的实际内容
  Widget _buildFilterContent(ThemeData theme, double horizontalPadding) {
    // 收集所有筛选chip
    final List<Widget> allChips = [];

    // 添加标签chip (带图标支持) - 添加进出场动画
    if (widget.selectedTagIds.isNotEmpty) {
      allChips.addAll(widget.selectedTagIds.map((tagId) {
        final tag = widget.tags.firstWhere(
          (tag) => tag.id == tagId,
          orElse: () => NoteCategory(id: tagId, name: '未知标签'),
        );
        return TweenAnimationBuilder<double>(
          key: ValueKey('tag_$tagId'),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.8 + (0.2 * value),
                child: child,
              ),
            );
          },
          child: _buildModernFilterChip(
            theme: theme,
            label: tag.name,
            icon: IconUtils.isEmoji(tag.iconName)
                ? IconUtils.getDisplayIcon(tag.iconName)
                : IconUtils.getIconData(tag.iconName),
            isIconEmoji: IconUtils.isEmoji(tag.iconName),
            color: theme.colorScheme.primary,
            onDeleted: () {
              final newSelectedTags = List<String>.from(
                widget.selectedTagIds,
              )..remove(tagId);
              widget.onTagSelectionChanged(newSelectedTags);
            },
          ),
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
        return TweenAnimationBuilder<double>(
          key: ValueKey('weather_cat_$cat'),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.8 + (0.2 * value),
                child: child,
              ),
            );
          },
          child: _buildModernFilterChip(
            theme: theme,
            label: label,
            icon: icon,
            color: theme.colorScheme.secondary,
            onDeleted: () {
              final keysToRemove =
                  WeatherService.getWeatherKeysByFilterCategory(cat);
              final newWeathers = List<String>.from(widget.selectedWeathers)
                ..removeWhere((w) => keysToRemove.contains(w));
              widget.onFilterChanged(
                newWeathers,
                widget.selectedDayPeriods,
              );
              _updateStreamSubscription();
            },
          ),
        );
      }));

      // 处理未归类的key
      final Set<String> knownKeys = categorySet
          .expand((cat) => WeatherService.getWeatherKeysByFilterCategory(cat))
          .toSet();
      final List<String> others =
          widget.selectedWeathers.where((k) => !knownKeys.contains(k)).toList();
      for (final k in others) {
        final label = WeatherService.weatherKeyToLabel[k] ?? k;
        allChips.add(
          TweenAnimationBuilder<double>(
            key: ValueKey('weather_$k'),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: child,
                ),
              );
            },
            child: _buildModernFilterChip(
              theme: theme,
              label: label,
              color: theme.colorScheme.secondary,
              onDeleted: () {
                final newWeathers = List<String>.from(widget.selectedWeathers)
                  ..remove(k);
                widget.onFilterChanged(newWeathers, widget.selectedDayPeriods);
                _updateStreamSubscription();
              },
            ),
          ),
        );
      }
    }

    // 添加时间段chip - 添加进出场动画
    if (widget.selectedDayPeriods.isNotEmpty) {
      allChips.addAll(widget.selectedDayPeriods.map((periodKey) {
        final periodLabel = TimeUtils.getDayPeriodLabel(periodKey);
        final periodIcon = TimeUtils.getDayPeriodIconByKey(periodKey);
        return TweenAnimationBuilder<double>(
          key: ValueKey('period_$periodKey'),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.8 + (0.2 * value),
                child: child,
              ),
            );
          },
          child: _buildModernFilterChip(
            theme: theme,
            label: periodLabel,
            icon: periodIcon,
            color: theme.colorScheme.tertiary,
            onDeleted: () {
              final newDayPeriods = List<String>.from(widget.selectedDayPeriods)
                ..remove(periodKey);
              widget.onFilterChanged(
                widget.selectedWeathers,
                newDayPeriods,
              );
              _updateStreamSubscription();
            },
          ),
        );
      }));
    }

    // 创建清除全部按钮
    final clearAllButton = Container(
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
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
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      ),
    );

    final width = MediaQuery.of(context).size.width;
    final isTablet = width > AppConstants.tabletMinWidth;
    final maxWidth = isTablet ? AppConstants.tabletMaxContentWidth : width;
    // 为chip之间添加间距
    List<Widget> spacedChips = [];
    for (int i = 0; i < allChips.length; i++) {
      spacedChips.add(allChips[i]);
      if (i != allChips.length - 1) {
        spacedChips.add(const SizedBox(width: 8));
      }
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(
          horizontalPadding,
          6.0,
          horizontalPadding,
          0,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 筛选图标 - 与芯片同高
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    Icons.filter_alt_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: spacedChips,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              clearAllButton,
            ],
          ),
        ),
      ),
    );
  }

  /// 构建现代化的筛选条件芯片 (支持图标显示)
  Widget _buildModernFilterChip({
    required ThemeData theme,
    required String label,
    required Color color,
    required VoidCallback onDeleted,
    dynamic icon,
    bool isIconEmoji = false,
  }) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: 10,
              right: icon != null ? 4 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  if (isIconEmoji) ...[
                    Text(
                      icon as String,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ] else ...[
                    Icon(
                      icon as IconData,
                      size: 15,
                      color: color,
                    ),
                  ],
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Center(
                  child: Icon(
                    Icons.close,
                    size: 15,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
