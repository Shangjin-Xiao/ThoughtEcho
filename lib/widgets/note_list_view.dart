import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../extensions/note_category_localization_extension.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../utils/icon_utils.dart';
import '../utils/jank_detector.dart';
import '../utils/lottie_animation_manager.dart';
import '../widgets/quote_item_widget.dart';
import '../widgets/quote_content_widget.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import 'note_filter_sort_sheet.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import '../utils/app_tracer.dart';
import '../utils/color_utils.dart';
import '../services/weather_service.dart'; // 导入天气服务
import '../utils/time_utils.dart'; // 导入时间工具
import '../controllers/search_controller.dart';
import '../constants/app_constants.dart'; // 导入应用常量
import '../utils/quill_editor_extensions.dart'
    show QuillImageEmbedPerfStats, isListScrolling;
import '../services/settings_service.dart'; // 导入设置服务
import '../services/pdf_export_service.dart';
import '../services/pdf_font_service.dart';
import '../widgets/pdf_preview_dialog.dart';
import 'note_list/scroll_alignment.dart';

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

  /// Returns whether a note-list item should be kept alive after it scrolls off
  /// screen.
  ///
  /// Rich/media/expandable notes are expensive to lay out and should keep their
  /// measured extent. Plain notes are handled by a viewport-relative keep-alive
  /// window in [NoteListViewState] so a parent rebuild does not sweep the whole
  /// loaded list.
  @visibleForTesting
  static bool shouldKeepAliveQuoteItem(Quote quote) {
    final deltaContent = quote.deltaContent;
    if (deltaContent == null || quote.editSource != 'fullscreen') {
      return false;
    }

    if (deltaContent.contains('"image"') ||
        deltaContent.contains('"video"') ||
        deltaContent.contains('"audio"')) {
      return true;
    }

    return QuoteItemWidget.needsExpansionFor(quote);
  }
}

class NoteListViewState extends State<NoteListView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(); // 添加焦点节点管理
  final ScrollController _scrollController = ScrollController(); // 添加滚动控制器
  final Map<String, bool> _expandedItems = {};
  final Map<String, ValueNotifier<bool>> _expansionNotifiers = {};
  String? _positioningQuoteId;
  GlobalKey? _positioningItemKey;
  int _positioningRequest = 0;

  /// 保存/修改笔记后触发入场动画的 ID 集合，动画完成后自动清除
  final Set<String> _animatingQuoteIds = {};
  final Map<String, Timer> _animationTimers = {};

  /// 事件驱动：首批数据加载完成信号，替代忙等轮询
  Completer<void>? _initialDataCompleter = Completer<void>();

  // PDF 导出选择模式状态
  bool _isExportMode = false;
  final Set<String> _selectedExportNoteIds = {};

  // 分页和懒加载状态
  final List<Quote> _quotes = [];
  bool _isLoading = true; // 初始化为 true，避免闪现"无笔记"
  bool _hasMore = true;
  static const int _pageSize = AppConstants.defaultPageSize;
  StreamSubscription<List<Quote>>? _quotesSub;
  static const int _plainKeepAliveWindowRadius = 18;

  // 修复：添加等待服务初始化的标志
  bool _waitingForServices = true;

  // 修复：本地标签缓存，用于在外部标签为空时自己加载
  List<NoteCategory> _localTagsCache = [];

  // 修复：用于检测和恢复滚动范围异常的计数器
  int _scrollExtentCheckCounter = 0;
  static const int _maxScrollExtentChecks = 3;

  // 修复：添加防抖定时器和性能优化
  Timer? _searchDebounceTimer;

  // 搜索过渡动画状态：搜索开始时置 true 让列表轻微变淡提示"更新中"，
  // 搜索结果到达后置 false 恢复。配合 AnimatedOpacity 实现 200ms 淡入淡出。
  // _searchDimTimer：延迟 120ms 再变淡，避免快速搜索（< 120ms）触发不必要的闪烁。
  bool _isSearchUpdating = false;
  Timer? _searchUpdatingTimer;
  Timer? _searchDimTimer; // 延迟变淡，防止快速搜索结果回来之前列表闪烁
  int _searchTimeoutVersion = 0; // 超时 SnackBar 版本号，过期不弹
  int _resultsVersion = 0; // 结果版本号，results→results 切换时驱动 AnimatedSwitcher 淡入淡出
  // ---- 自动滚动控制新增状态 ----
  bool _initialDataLoaded = false; // 标记是否已收到首批数据（后续用于启用自动滚动）
  bool _isAutoScrolling = false; // 当前是否有程序驱动的滚动动画
  bool _isInitializing = true; // 标记是否正在初始化，避免冷启动滚动冲突

  // 开发者模式：首次打开后首次手势滑动性能监测（非首帧）
  bool _perfTimingsCallbackAttached = false;
  AppTracer? _firstOpenTracer;
  AppTracer? _loadMoreTracer;
  AppTracer? _scrollSessionTracer;
  bool _firstOpenScrollPerfEnabled = false;
  bool _firstOpenScrollPerfRecording = false;
  bool _firstOpenScrollPerfCaptured = false;
  final List<FrameTiming> _firstOpenScrollFrameTimings = <FrameTiming>[];
  final List<int> _firstOpenScrollUpdateMicros = <int>[];
  Timer? _firstOpenScrollStopTimer;
  bool _loadMorePerfRecording = false;
  bool _loadMorePerfPendingFrameSettle = false;
  int _loadMorePerfStartCount = 0;
  int _loadMorePerfTriggerOffset = 0;
  final Stopwatch _loadMorePerfStopwatch = Stopwatch();
  final List<FrameTiming> _loadMorePerfFrameTimings = <FrameTiming>[];
  Timer? _loadMorePerfStopTimer;
  bool _loadMoreAwaitingPage = false;
  int _loadMoreRequestStartCount = 0;
  Timer? _loadMoreSettleTimer;
  bool _scrollSessionPerfRecording = false;
  bool _scrollSessionPerfPendingFinalize = false;
  bool _scrollSessionPerfFinalizeScheduled = false;
  int _scrollSessionSequence = 0;
  String? _scrollSessionId;
  int _scrollSessionStartMicros = 0;
  double _scrollSessionStartOffset = 0;
  double _scrollSessionLastOffset = 0;
  double _scrollSessionMinOffset = 0;
  double _scrollSessionMaxOffset = 0;
  double _scrollSessionStartMaxExtent = 0;
  double _scrollSessionLastMaxExtent = 0;
  double _scrollSessionMinMaxExtent = 0;
  double _scrollSessionMaxMaxExtent = 0;
  int _scrollSessionExtentChangeCount = 0;
  int _scrollSessionStartStateUpdateCount = 0;
  int _scrollSessionStartNoteListBuildCount = 0;
  int _scrollSessionStartLoadMoreAttemptCount = 0;
  int _scrollSessionStartLoadMoreStartCount = 0;
  int _scrollSessionStartLoadMoreSkipCount = 0;
  int _scrollSessionStartDataEventCount = 0;
  int _scrollSessionNotificationStarts = 0;
  int _scrollSessionNotificationUpdates = 0;
  int _scrollSessionNotificationEnds = 0;
  int _scrollSessionItemBuildCount = 0;
  int _scrollSessionMinBuiltIndex = 1 << 30;
  int _scrollSessionMaxBuiltIndex = -1;
  int _scrollSessionBuiltPlain = 0;
  int _scrollSessionBuiltRich = 0;
  int _scrollSessionBuiltMedia = 0;
  final List<int> _scrollSessionUpdateMicros = <int>[];
  final List<FrameTiming> _scrollSessionFrameTimings = <FrameTiming>[];
  Timer? _scrollSessionPerfStopTimer;
  Map<String, dynamic>? _scrollSessionStartQuoteContentStats;
  Map<String, int>? _scrollSessionStartQuoteItemStats;
  Map<String, int>? _scrollSessionStartImageEmbedStats;
  int _scrollSessionStartImageCount = 0;
  int _scrollSessionStartImageBytes = 0;
  int _scrollSessionItemLayoutCount = 0;
  int _scrollSessionItemLayoutMicros = 0;
  int _scrollSessionItemLayoutJank = 0;
  int _scrollSessionWorstItemLayoutMicros = 0;
  final List<_SlowItemLayoutSample> _scrollSessionSlowItemLayouts =
      <_SlowItemLayoutSample>[];
  int _stateUpdateCount = 0;
  int _noteListBuildCount = 0;
  int _loadMoreAttemptCount = 0;
  int _loadMoreStartCount = 0;
  int _loadMoreSkipCount = 0;
  int _dataStreamEventCount = 0;

  bool _hasExpandableQuoteCached = false;
  bool _hasExpandableQuoteComputed = false;

  // 添加滚动状态标志，防止在用户滑动时触发自动滚动
  bool _isUserScrolling = false;
  double _lastScrollOffset = 0;
  static const double _scrollThreshold = 5.0; // 性能优化：5像素阈值

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    _stateUpdateCount++;
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
    if (_firstOpenScrollPerfRecording) {
      _firstOpenScrollFrameTimings.addAll(timings);
    }
    if (_loadMorePerfRecording) {
      _loadMorePerfFrameTimings.addAll(timings);
    }
    if (_scrollSessionPerfRecording) {
      _scrollSessionFrameTimings.addAll(timings);
      if (_scrollSessionPerfPendingFinalize &&
          !_scrollSessionPerfFinalizeScheduled) {
        _scrollSessionPerfFinalizeScheduled = true;
        Timer.run(_finalizeScrollSessionPerfCapture);
      }
    }
  }

  void _ensurePerfTimingsCallback() {
    if (_perfTimingsCallbackAttached) {
      return;
    }
    WidgetsBinding.instance.addTimingsCallback(_collectFrameTimings);
    _perfTimingsCallbackAttached = true;
  }

  void _releasePerfTimingsCallbackIfIdle() {
    if (!_perfTimingsCallbackAttached ||
        _firstOpenScrollPerfRecording ||
        _loadMorePerfRecording ||
        _scrollSessionPerfRecording) {
      return;
    }
    WidgetsBinding.instance.removeTimingsCallback(_collectFrameTimings);
    _perfTimingsCallbackAttached = false;
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

      // 搜索 query 变化时也保留滚动位置，避免删字时列表跳回顶部加剧闪烁感。
      // stream callback 会校验 offset 是否仍在 maxScrollExtent 范围内。
      final bool isSearchChange = oldWidget.searchQuery != widget.searchQuery;

      // 更新流订阅，传入是否仅为排序变化
      _updateStreamSubscription(
        preserveScrollPosition: isOnlySortChange || isSearchChange,
        isSearchUpdate: isSearchChange,
      );
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

    _firstOpenTracer?.finish();
    _firstOpenTracer = null;
    _loadMoreTracer?.finish();
    _loadMoreTracer = null;
    _scrollSessionTracer?.finish();
    _scrollSessionTracer = null;
    final scrollSessionId = _scrollSessionId;
    if (scrollSessionId != null) {
      JankDetector.endSession(scrollSessionId);
      _scrollSessionId = null;
    }
    _searchDebounceTimer?.cancel(); // 清理防抖定时器
    _searchUpdatingTimer?.cancel(); // 清理搜索过渡动画安全定时器
    _searchDimTimer?.cancel(); // 清理延迟变淡定时器
    _firstOpenScrollStopTimer?.cancel();
    _loadMorePerfStopTimer?.cancel();
    _loadMoreSettleTimer?.cancel();
    _scrollSessionPerfStopTimer?.cancel();
    // 清理动画定时器
    for (final timer in _animationTimers.values) {
      timer.cancel();
    }
    _animationTimers.clear();

    if (_perfTimingsCallbackAttached) {
      WidgetsBinding.instance.removeTimingsCallback(_collectFrameTimings);
      _perfTimingsCallbackAttached = false;
      _firstOpenScrollPerfRecording = false;
      _loadMorePerfRecording = false;
      _scrollSessionPerfRecording = false;
      _scrollSessionPerfPendingFinalize = false;
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

  /// 触发指定 ID 的笔记卡片入场/更新动画（保存/修改后调用）。
  /// 动画时长 250ms，1500ms 后自动清除状态以保证性能，并处理多次连续保存的情况。
  void triggerInsertAnimation(String id) {
    if (!mounted) return;
    _animationTimers[id]?.cancel();
    setState(() {
      _animatingQuoteIds.add(id);
    });
    _animationTimers[id] = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _animatingQuoteIds.remove(id);
          _animationTimers.remove(id);
        });
      }
    });
  }

  Future<bool> scrollToQuoteById(String quoteId) async {
    if (!mounted || quoteId.isEmpty) return false;

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
          return false;
        }
      }
      if (!mounted || !_initialDataLoaded) return false;
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
        if (!mounted) return false;

        _isInitializing = false;
        _isUserScrolling = false;

        return _positionAndAlignQuote(
          quoteId,
          index,
          forceAlignToTop: true,
        );
      }

      // 目标不在已加载范围内，等待或加载更多
      if (!_hasMore) {
        logDebug('目标笔记不在可见列表且已无更多分页: $quoteId', source: 'NoteListView');
        return false;
      }
      if (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 200));
      } else {
        await _loadMore();
      }
    }

    logDebug('未能在列表中定位笔记: $quoteId', source: 'NoteListView');
    return false;
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
    }
  }

  @override
  Widget build(BuildContext context) => _buildNoteListView(context);
}
