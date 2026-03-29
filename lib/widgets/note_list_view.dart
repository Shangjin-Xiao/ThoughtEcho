import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;
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
import '../widgets/quote_content_widget.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import 'note_filter_sort_sheet.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import '../utils/color_utils.dart';
import '../services/weather_service.dart'; // 导入天气服务
import '../utils/time_utils.dart'; // 导入时间工具
import '../controllers/search_controller.dart';
import '../constants/app_constants.dart'; // 导入应用常量
import '../utils/quill_editor_extensions.dart' show isListScrolling;
import '../services/settings_service.dart'; // 导入设置服务

part 'note_list/note_list_scroll.dart';
part 'note_list/note_list_data_stream.dart';
part 'note_list/note_list_items.dart';
part 'note_list/note_list_filters.dart';

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
  final Function(Quote)? onFavorite; // 心形按钮点击回调
  final Function(Quote)? onLongPressFavorite; // 心形按钮长按回调（清除收藏）
  final bool isLoadingTags; // 新增标签加载状态参数
  final List<String> selectedWeathers; // 新增天气筛选参数
  final List<String> selectedDayPeriods; // 新增时间段筛选参数
  final Function(List<String>, List<String>) onFilterChanged; // 新增筛选变化回调
  final GlobalKey? filterButtonKey; // 功能引导：筛选按钮的 Key
  final GlobalKey? favoriteButtonGuideKey; // 功能引导：心形按钮 Key
  final GlobalKey? moreButtonGuideKey; // 功能引导：更多按钮 Key
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
    this.onFavorite, // 心形按钮点击回调
    this.onLongPressFavorite, // 心形按钮长按回调（清除收藏）
    this.isLoadingTags = false, // 默认为false
    this.selectedWeathers = const [],
    this.selectedDayPeriods = const [],
    required this.onFilterChanged,
    this.filterButtonKey, // 功能引导 Key
    this.favoriteButtonGuideKey,
    this.moreButtonGuideKey,
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

  /// 事件驱动：首批数据加载完成信号，替代忙等轮询
  Completer<void>? _initialDataCompleter = Completer<void>();

  // AI搜索模式标志
  bool _isAISearchMode = false;

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = true; // 初始化为 true，避免闪现"无笔记"
  bool _hasMore = true;
  static const int _pageSize = AppConstants.defaultPageSize;
  StreamSubscription<List<Quote>>? _quotesSub;

  // 修复：添加等待服务初始化的标志
  bool _waitingForServices = true;

  // 修复：本地标签缓存，用于在外部标签为空时自己加载
  List<NoteCategory> _localTagsCache = [];

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

  // 开发者模式：首次打开后首次手势滑动性能监测（非首帧）
  bool _firstOpenScrollPerfEnabled = false;
  bool _firstOpenScrollPerfRecording = false;
  bool _firstOpenScrollPerfCaptured = false;
  final List<FrameTiming> _firstOpenScrollFrameTimings = <FrameTiming>[];
  final List<int> _firstOpenScrollUpdateMicros = <int>[];
  Timer? _firstOpenScrollStopTimer;

  bool _hasExpandableQuoteCached = false;
  bool _hasExpandableQuoteComputed = false;

  // 添加滚动状态标志，防止在用户滑动时触发自动滚动
  bool _isUserScrolling = false;
  double _lastScrollOffset = 0;
  static const double _scrollThreshold = 5.0; // 性能优化：5像素阈值

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  /// 获取有效的标签列表：优先使用外部传入的，若为空则使用本地缓存
  List<NoteCategory> get _effectiveTags =>
      widget.tags.isNotEmpty ? widget.tags : _localTagsCache;

  bool get hasQuotes => _quotes.isNotEmpty;

  bool get hasExpandableQuote => _hasExpandableQuoteCached;

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
    _isLoading = true; // 修复：保持为 true，避免闪现"无笔记"
    _isInitializing = true;
    _waitingForServices = true; // 初始等待服务初始化

    // 添加焦点节点监听器，用于Web平台的焦点管理
    _searchFocusNode.addListener(_onFocusChanged);

    // 添加滚动控制器监听器，用于检测用户滑动状态
    _scrollController.addListener(_onScroll);

    // 优化：延迟初始化数据流订阅，避免build过程中的副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkServicesAndInitialize();
      if (!mounted) return;
      widget.onGuideTargetsReady?.call();
    });
  }

  /// 修复：检查服务初始化状态并初始化数据流
  Future<void> _checkServicesAndInitialize() async {
    if (!mounted) return;

    final db = Provider.of<DatabaseService>(context, listen: false);

    // 如果数据库已初始化，直接初始化数据流
    if (db.isInitialized) {
      _waitingForServices = false;
      // 修复：如果外部传入的标签为空，先等待加载本地标签缓存
      await _loadLocalTagsCacheIfNeeded();
      _initializeDataStream();
      return;
    }

    // 否则，等待数据库初始化
    logDebug('等待数据库初始化...', source: 'NoteListView');
    db.addListener(_onDatabaseServiceChanged);
  }

  /// 修复：如果外部传入的标签为空，加载本地标签缓存
  Future<void> _loadLocalTagsCacheIfNeeded() async {
    if (widget.tags.isEmpty && _localTagsCache.isEmpty) {
      try {
        final db = Provider.of<DatabaseService>(context, listen: false);
        final categories = await db.getCategories();
        if (mounted && categories.isNotEmpty) {
          setState(() {
            _localTagsCache = categories;
          });
          logDebug(
            'NoteListView 本地标签缓存加载完成，共 ${categories.length} 个标签',
            source: 'NoteListView',
          );
        }
      } catch (e) {
        logDebug('NoteListView 加载本地标签缓存失败: $e', source: 'NoteListView');
      }
    }
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

    // 极致轻量：仅设置标志位，不做任何分配或重操作
    // 重活（异常检测、状态重置）全部推迟到 ScrollEndNotification 中处理
    if (_isInitializing || _isAutoScrolling) return;
    _isUserScrolling = true;
  }

  void _collectFrameTimings(List<FrameTiming> timings) {
    if (!_firstOpenScrollPerfRecording) {
      return;
    }
    _firstOpenScrollFrameTimings.addAll(timings);
  }

  /// 数据库服务变化监听器
  void _onDatabaseServiceChanged() {
    if (!mounted) return;

    final db = Provider.of<DatabaseService>(context, listen: false);
    if (db.isInitialized) {
      logDebug('数据库初始化完成，重新订阅数据流', source: 'NoteListView');
      // 移除监听器，避免重复监听
      db.removeListener(_onDatabaseServiceChanged);

      // 修复：更新等待服务状态
      _waitingForServices = false;

      // 针对安卓平台的特殊处理
      if (!kIsWeb && Platform.isAndroid) {
        // 安卓平台延迟重新订阅，确保数据库完全准备好
        Future.delayed(const Duration(milliseconds: 200), () async {
          if (mounted) {
            // 修复：先加载本地标签缓存
            await _loadLocalTagsCacheIfNeeded();
            _initializeDataStream();
          }
        });
      } else {
        // 其他平台：先加载标签再初始化数据流
        _loadLocalTagsCacheIfNeeded().then((_) {
          if (mounted) {
            _initializeDataStream();
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(NoteListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 更新搜索控制器文本，避免与外部状态不同步
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }

    // 修复：当外部标签从空变为有数据时，清空本地缓存以使用外部标签
    // 并触发 setState 确保 UI 使用新的标签数据重建
    if (oldWidget.tags.isEmpty && widget.tags.isNotEmpty) {
      setState(() {
        _localTagsCache = [];
      });
      logDebug('外部标签已更新，清空本地缓存并刷新 UI', source: 'NoteListView');
    }

    // 优化：只有在筛选条件真正改变时才更新订阅
    final bool shouldUpdate = _shouldUpdateSubscription(oldWidget);

    if (shouldUpdate && _initialDataLoaded) {
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
            oldWidget.selectedDayPeriods,
            widget.selectedDayPeriods,
          ) &&
          (oldWidget.sortType != widget.sortType ||
              oldWidget.sortAscending != widget.sortAscending);

      // 更新流订阅，传入是否仅为排序变化
      _updateStreamSubscription(preserveScrollPosition: isOnlySortChange);
    } else if (shouldUpdate) {
      logDebug('跳过更新：数据尚未完成首次加载', source: 'NoteListView');
    }
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
    _firstOpenScrollStopTimer?.cancel();

    if (_firstOpenScrollPerfRecording) {
      WidgetsBinding.instance.removeTimingsCallback(_collectFrameTimings);
      _firstOpenScrollPerfRecording = false;
    }

    for (final notifier in _expansionNotifiers.values) {
      notifier.dispose();
    }
    _expansionNotifiers.clear();

    // 修复问题3：移除页面切换时的缓存清空，保留缓存以提升返回体验
    // QuoteContent.resetCaches(); // 缓存将由 LRU 自动管理

    // 清理初始化状态
    _isInitializing = false;
    // 安全释放 Completer，避免 scrollToQuoteById 永久挂起
    if (_initialDataCompleter != null && !_initialDataCompleter!.isCompleted) {
      _initialDataCompleter!.complete();
    }
    _initialDataCompleter = null;
    super.dispose();
  }

  Future<void> resetAndLoad() async {
    _quotes.clear();
    _hasMore = true;
    _loadMore();
  }

  Future<void> scrollToQuoteById(String quoteId) async {
    if (!mounted || quoteId.isEmpty) return;

    // ── 阶段 1: 事件驱动等待首批数据（取代忙等轮询）──
    if (!_initialDataLoaded) {
      final completer = _initialDataCompleter;
      if (completer != null && !completer.isCompleted) {
        try {
          await completer.future.timeout(
            const Duration(seconds: 5),
          );
        } on TimeoutException {
          logDebug(
            'scrollToQuoteById 放弃：首次数据加载超时',
            source: 'NoteListView',
          );
          return;
        }
      }
      if (!mounted || !_initialDataLoaded) return;
    }

    // ── 阶段 2: 在分页数据中查找目标笔记 ──
    const maxAttempts = 20;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final index = _quotes.indexWhere((quote) => quote.id == quoteId);
      if (index >= 0) {
        // 展开目标笔记
        final notifier = _obtainExpansionNotifier(quoteId);
        if (!notifier.value) {
          notifier.value = true;
          _expandedItems[quoteId] = true;
        }

        await Future.delayed(const Duration(milliseconds: 80));
        if (!mounted) return;

        _autoScrollEnabled = true;
        _isInitializing = false;
        _isUserScrolling = false;
        _lastUserScrollTime = null;

        // ── 阶段 3: 动态估算偏移量触发 ListView 构建 ──
        if (_scrollController.hasClients) {
          final key = _itemKeys[quoteId];
          if (key == null || key.currentContext == null) {
            final estimatedHeight = _estimateItemHeight();
            final estimatedOffset = index * estimatedHeight;
            final maxOffset = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(estimatedOffset.clamp(0.0, maxOffset));
          }
        }

        // ── 阶段 4: 指数退避等待 widget build + context 就绪 ──
        const maxRenderWait = 8;
        var renderDelay = 30; // ms, 指数增长
        for (var renderWait = 0; renderWait < maxRenderWait; renderWait++) {
          await Future.delayed(
            Duration(milliseconds: renderDelay),
          );
          if (!mounted) return;
          // 让出一帧给框架完成 layout
          await WidgetsBinding.instance.endOfFrame;
          final key = _itemKeys[quoteId];
          if (key != null && key.currentContext != null) {
            _scrollToItem(quoteId, index);
            return;
          }
          renderDelay = (renderDelay * 1.5).toInt().clamp(30, 200);
        }

        // 最终兜底尝试
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToItem(quoteId, index);
        });
        return;
      }

      // 目标不在已加载范围内，等待或加载更多
      if (!_hasMore || _isLoading) {
        await Future.delayed(const Duration(milliseconds: 200));
      } else {
        await _loadMore();
      }
    }

    logDebug('未能在列表中定位笔记: $quoteId', source: 'NoteListView');
  }

  /// 动态估算列表项高度：从已渲染的 item 中采样。
  /// 比硬编码 120.0 精确得多，分页/长内容场景偏差更小。
  double _estimateItemHeight() {
    const fallback = 120.0;
    if (_itemKeys.isEmpty) return fallback;

    double totalHeight = 0;
    int measured = 0;
    for (final key in _itemKeys.values) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final rb = ctx.findRenderObject();
      if (rb is RenderBox && rb.hasSize) {
        totalHeight += rb.size.height;
        measured++;
        if (measured >= 10) break; // 最多采样 10 个，够用了
      }
    }
    return measured > 0 ? totalHeight / measured : fallback;
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

  @override
  Widget build(BuildContext context) => _buildNoteListView(context);
}
