import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'; // 导入 markdown 库
import 'package:provider/provider.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/app_tracer.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/thoughter_entry.dart';
import '../models/note_tag.dart';
import '../models/quote_model.dart';
import '../pages/thoughter_page.dart';
import '../pages/note_full_editor_page.dart'; // 导入全屏富文本编辑器
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/local_geocoding_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../theme/theme_style.dart';
import '../utils/feature_guide_helper.dart';
import '../utils/time_utils.dart'; // 导入时间工具类
import 'accessible_color_grid.dart'; // Import the new accessible color grid
import 'add_note_ai_menu.dart'; // 导入 AI 菜单组件
import '../controllers/add_note_controller.dart';
import 'add_note_dialog_parts.dart'; // 导入拆分的组件
import 'app_snackbar.dart';

// TODO(refactor): This file exceeds 2400 lines and contains redundant location/weather logic.
// Consider extracting core business logic into a separate controller or service.
class AddNoteDialog extends StatefulWidget {
  final Quote? initialQuote; // 如果是编辑笔记，则传入初始值
  final String? prefilledContent; // 预填充的内容
  final String? prefilledAuthor; // 预填充的作者
  final String? prefilledWork; // 预填充的作品
  final Map<String, dynamic>? hitokotoData; // 添加一言API返回的完整数据
  final List<NoteTag> tags;
  final FutureOr<void> Function(Quote) onSave; // 关闭后由外层执行保存
  /// 预填充的标签 ID 列表
  final List<String>? prefilledTagIds;

  /// 预填充的是否包含位置信息
  final bool? prefilledIncludeLocation;

  /// 预填充的是否包含天气信息
  final bool? prefilledIncludeWeather;

  /// 是否使用 AI 预填充的位置和天气标记
  final bool? useAIPrefilledLocationWeather;

  const AddNoteDialog({
    super.key,
    this.initialQuote,
    this.prefilledContent,
    this.prefilledAuthor,
    this.prefilledWork,
    this.hitokotoData,
    this.prefilledTagIds,
    this.prefilledIncludeLocation,
    this.prefilledIncludeWeather,
    this.useAIPrefilledLocationWeather,
    required this.tags,
    required this.onSave,
  });

  @override
  State<AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<AddNoteDialog>
    with WidgetsBindingObserver {
  late TextEditingController _contentController;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  final GlobalKey _fullscreenButtonKey = GlobalKey();
  final GlobalKey _tagGuideKey = GlobalKey(); // 标签功能引导 Key
  final List<String> _selectedTagIds = [];
  String? _aiSummary;
  Quote? _fullInitialQuote;
  bool _isLoadingFullQuote = false;

  // 优化：内部维护标签列表，支持动态更新
  List<NoteTag> _availableTags = [];
  DatabaseService? _databaseService;

  // 分类选择 (Now in Controller, except for early init use but we'll adapt)
  // 颜色选择
  String? _selectedColorHex;

  // 性能优化：等 BottomSheet 入场动画进行到一定程度再请求焦点，避免首帧竞争导致卡顿
  final FocusNode _contentFocusNode = FocusNode();
  Animation<double>? _routeAnimation;
  bool _focusRequested = false;

  // 开发者模式：添加笔记弹窗打开/键盘性能监测。
  bool _dialogPerfEnabled = false;
  bool _dialogPerfRecording = false;
  bool _dialogPerfTimingsCallbackAttached = false;
  bool _dialogPerfFirstFrameLogged = false;
  bool _dialogPerfFocusLogged = false;
  bool _dialogPerfKeyboardStartLogged = false;
  double? _dialogPerfLastInsetBuildValue;
  int _dialogPerfBuildCount = 0;
  int _dialogPerfBodyReuseCount = 0;
  int _dialogPerfInsetBuildCount = 0;
  int _dialogPerfInsetChangeCount = 0;
  int _dialogPerfMetricsChangeCount = 0;
  int? _dialogPerfFirstFrameMs;
  int? _dialogPerfFocusRequestMs;
  int? _dialogPerfFocusAcquiredMs;
  int? _dialogPerfKeyboardStartMs;
  int? _dialogPerfKeyboardSettledMs;
  final Stopwatch _dialogPerfStopwatch = Stopwatch();
  final List<FrameTiming> _dialogPerfFrameTimings = <FrameTiming>[];
  // 主体 Widget 树的构造耗时。首帧的 buildDuration 里既有它，也有路由/弹窗自身的
  // element 挂载和布局；分开记一笔才知道该砍谁。
  int _dialogPerfBodyBuildCount = 0;
  double _dialogPerfBodyBuildWorstMs = 0;
  double? _dialogPerfFirstBodyBuildMs;
  // 自动附加阶段：抓取被挪到键盘稳定之后，已经落在上面那个采样窗口之外了，
  // 单独记一段，否则这段的耗时和掉帧完全看不见。
  final List<FrameTiming> _autoMetadataFrameTimings = <FrameTiming>[];
  final Stopwatch _autoMetadataStopwatch = Stopwatch();
  bool _autoMetadataRecording = false;
  int? _autoMetadataLocationDoneMs;
  int? _autoMetadataWeatherDoneMs;
  final Map<String, int> _dialogPerfStateChanges = <String, int>{};
  late final AppTracer _dialogOpenTimelineTask;
  bool _dialogOpenTimelineFinished = false;
  Timer? _dialogOpenTimelineTimeout;
  Timer? _dialogPerfKeyboardSettleTimer;
  Timer? _dialogPerfFinalizeTimer;

  // 键盘 inset 的依赖只挂在 KeyboardInsetPadding 上，本 State 不再订阅 MediaQuery，
  // 否则键盘每动一帧都会把整个弹窗标脏。这个值由 KeyboardInsetPadding 回传。
  double _lastKeyboardInset = 0;

  // 键盘弹出期间 showModalBottomSheet 会随 viewInsets 连续重跑 builder，可那几帧里
  // 弹窗自己的状态一点没变。按修订号复用上一次的 Widget 实例——Flutter 见到同一个
  // 实例会整棵子树跳过 diff。状态真的变了（setState / 依赖变化 / 入参变化）修订号
  // 就往前走，缓存立刻作废，不会像按定时器冻结那样把 setState 吞掉。
  Widget? _cachedDialogBody;
  int _dialogBodyRevision = 0;
  int? _cachedDialogBodyRevision;

  // 性能优化：缓存Provider引用，避免重复查找
  LocationService? _cachedLocationService;
  WeatherService? _cachedWeatherService;

  // 数据库监听防抖
  Timer? _dbChangeDebounceTimer;

  bool _isSaving = false;
  bool _closeRequestInFlight = false; // 未保存确认框只允许在飞一个
  bool _waitingForFetch = false; // 用户已触发保存，正在等待位置/天气获取完成
  bool _deferredControlsVisible = true;
  Timer? _deferredControlsTimer;
  Timer? _autoFocusTimer;

  // 自动附加位置/天气：initState 就按偏好确定要抓什么，抓取本身推迟到 UI 稳定后。
  bool _autoAttachLocationPlanned = false;
  bool _autoAttachWeatherPlanned = false;
  bool _autoMetadataStarted = false;
  Timer? _autoMetadataFallbackTimer;
  Timer? _databaseListenerTimer;

  // AI推荐标签相关状态
  // 预留：后续接入本地 embedding/标签推荐时使用

  // 用于检测未保存内容的初始状态
  late String _initialContent;
  late String _initialAuthor;
  late String _initialWork;
  late List<String> _initialTagIds;
  late String? _initialColorHex;

  late final AddNoteController _controller;

  T? _readServiceOrNull<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AddNoteController(
      context: context,
      initialQuote: widget.initialQuote,
      hitokotoData: widget.hitokotoData,
      initialTagIds: _selectedTagIds,
      onLocationError: (msg) {
        if (!mounted || !context.mounted) return;
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.getLocationFailedTitle),
            content: Text(l10n.getLocationFailedDesc(msg)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(l10n.iKnow)),
            ],
          ),
        );
      },
      onLocationPermissionDenied: () {
        if (!mounted || !context.mounted) return;
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.cannotGetLocationTitle),
            content: Text(l10n.cannotGetLocationPermissionShort),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(l10n.iKnow)),
            ],
          ),
        );
      },
      onLocationFetchEmpty: () {
        if (!mounted || !context.mounted) return;
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.cannotGetLocationTitle),
            content: Text(l10n.cannotGetLocationDesc),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(l10n.iKnow)),
            ],
          ),
        );
      },
      onWeatherFetchEmpty: () {
        if (!mounted || !context.mounted) return;
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.weatherFetchFailedTitle),
            content: Text(l10n.weatherFetchFailedDesc),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(l10n.iKnow)),
            ],
          ),
        );
      },
      onWeatherMissingCoordinates: () {
        if (!mounted || !context.mounted) return;
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.weatherFetchFailedTitle),
            content: Text(l10n.locationAndWeatherUnavailable),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(l10n.iKnow)),
            ],
          ),
        );
      },
      onWeatherFetchError: () {
        if (!mounted || !context.mounted) return;
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.weatherFetchFailedTitle),
            content: Text(l10n.weatherFetchFailedDesc),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(l10n.iKnow)),
            ],
          ),
        );
      },
    );

    final settingsService = _readServiceOrNull<SettingsService>(context);

    // 先按偏好/预填充确定自动附加计划，并立刻把「获取中」标志立起来，再挂监听：
    // 抓取本身要等 UI 稳定后才启动，这段时间里点保存必须能等到元数据。
    // （挂监听之前 arm，避免 notifyListeners 在 initState 里触发 setState。）
    if (widget.initialQuote == null) {
      final bool useAIPrefill = widget.useAIPrefilledLocationWeather ?? false;
      _autoAttachLocationPlanned = useAIPrefill
          ? (widget.prefilledIncludeLocation ?? false)
          : (widget.prefilledIncludeLocation ??
              (settingsService?.autoAttachLocation ?? false));
      _autoAttachWeatherPlanned = useAIPrefill
          ? (widget.prefilledIncludeWeather ?? false)
          : (widget.prefilledIncludeWeather ??
              (settingsService?.autoAttachWeather ?? false));
      _controller.armAutoMetadataFetch(
        location: _autoAttachLocationPlanned,
        weather: _autoAttachWeatherPlanned,
      );
    }

    _controller.addListener(_onControllerChanged);
    _controller.updateServices(
      locService: _readServiceOrNull<LocationService>(context),
      weaService: _readServiceOrNull<WeatherService>(context),
      dbService: _readServiceOrNull<DatabaseService>(context),
    );

    _dialogOpenTimelineTask = AppTracer.start(
      'ThoughtEcho.AddNoteDialog.open',
      operation: 'ui.load',
      arguments: <String, Object>{
        'mode': widget.initialQuote == null ? 'create' : 'edit',
        'tagCount': widget.tags.length,
        'contentLength':
            (widget.initialQuote?.content ?? widget.prefilledContent ?? '')
                .length,
      },
    );
    _dialogOpenTimelineTask
        .instant('ThoughtEcho.AddNoteDialog.initState.start');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _dialogOpenTimelineTask
            .instant('ThoughtEcho.AddNoteDialog.firstFrame.complete');
      }
    });
    _dialogOpenTimelineTimeout = Timer(
      const Duration(milliseconds: 2400),
      () => _finishDialogOpenTimeline('timeout'),
    );

    // 每日一言双击添加：使用一言数据专属填充，跳过通用默认填充（作者/出处/默认标签）
    final bool isHitokotoQuickAdd = widget.hitokotoData != null;

    // 初始化控制器
    _contentController = TextEditingController(
      text: widget.initialQuote?.content ?? widget.prefilledContent ?? '',
    );

    _authorController = TextEditingController(
      text: widget.initialQuote?.sourceAuthor ?? widget.prefilledAuthor ?? '',
    );

    _workController = TextEditingController(
      text: widget.initialQuote?.sourceWork ?? widget.prefilledWork ?? '',
    );

    // 优化：初始化内部标签列表
    _availableTags = List.from(widget.tags);

    WidgetsBinding.instance.addObserver(this);
    _contentFocusNode.addListener(_onContentFocusChanged);
    _startDialogPerfCapture();

    // 新建笔记时，自动填充默认作者、出处和标签
    if (widget.initialQuote == null && !isHitokotoQuickAdd) {
      if (widget.prefilledTagIds != null &&
          widget.prefilledTagIds!.isNotEmpty) {
        _selectedTagIds.addAll(widget.prefilledTagIds!);
      }

      if (settingsService != null) {
        // 仅在没有预填充值时使用默认值
        if (_authorController.text.isEmpty &&
            settingsService.defaultAuthor != null &&
            settingsService.defaultAuthor!.isNotEmpty) {
          _authorController.text = settingsService.defaultAuthor!;
        }
        if (_workController.text.isEmpty &&
            settingsService.defaultSource != null &&
            settingsService.defaultSource!.isNotEmpty) {
          _workController.text = settingsService.defaultSource!;
        }
        // 自动添加标签
        if (_selectedTagIds.isEmpty &&
            settingsService.defaultTagIds.isNotEmpty) {
          _selectedTagIds.addAll(settingsService.defaultTagIds);
        }
      }
    }

    if (widget.initialQuote == null) {
      // 记录自动填充后的初始状态（用于检测未保存内容）
      // 这些值是自动预填充的，不应被视为用户输入
      _captureInitialState();
    }

    // 优化：完全延迟所有服务初始化和数据库监听器，避免阻塞首次绘制
    // 定位、反查地址、天气请求都要走平台通道和网络，压在入场/键盘动画上最容易掉帧。
    // 实际启动时机取「键盘 inset 稳定」和下面这个兜底延迟里先到的那个；用户提前点保存
    // 时也会立刻启动（见 _startAutoMetadataFetch）。
    // 实验开关 addNoteDialogDeferAutoMetadata（默认 false）：
    //   false → 兜底 900ms（略晚于典型键盘动画）
    //   true  → 兜底 1500ms（更保守的实验值）
    final deferMetadata =
        settingsService?.addNoteDialogDeferAutoMetadata ?? false;
    final metadataDelay = deferMetadata
        ? const Duration(milliseconds: 1500)
        : const Duration(milliseconds: 900);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        final animation = route.animation!;
        if (animation.isCompleted) {
          _showDeferredControls();
        } else {
          void statusListener(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              animation.removeStatusListener(statusListener);
              _showDeferredControls();
            }
          }

          animation.addStatusListener(statusListener);
          // 兜底定时器：如果由于某些原因没有触发 completed 状态，也在 350ms 后显示次要控件
          _deferredControlsTimer = Timer(const Duration(milliseconds: 350), () {
            animation.removeStatusListener(statusListener);
            _showDeferredControls();
          });
        }
      } else {
        _showDeferredControls();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 兜底：键盘没弹出（关闭了自动聚焦、外接键盘、桌面端）时也要把元数据抓起来。
      _autoMetadataFallbackTimer = Timer(
        metadataDelay,
        () => unawaited(_startAutoMetadataFetch('fallbackTimer')),
      );
    });

    // 性能优化：等 BottomSheet 入场和次要控件挂载稳定后再请求焦点弹出键盘。
    // 避免键盘 inset 动画与打开首帧/次要控件挂载叠加导致掉帧。
    // 实验开关 addNoteDialogAutoFocus（默认 true）：关闭后跳过自动聚焦。
    final autoFocusEnabled = settingsService?.addNoteDialogAutoFocus ?? true;
    if (autoFocusEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null && route.animation != null) {
          _routeAnimation = route.animation;
          if (route.animation!.isCompleted) {
            // 动画已完成（如无障碍关闭动画），直接请求焦点
            _dialogOpenTimelineTask
                .instant('ThoughtEcho.AddNoteDialog.routeAnimation.complete');
            _scheduleContentFocus('routeCompleted');
            _focusRequested = true;
          } else {
            // 监听动画完成后请求焦点
            route.animation!.addListener(_onRouteAnimationProgress);
          }
        } else {
          // 无法获取路由动画，直接请求焦点
          _dialogOpenTimelineTask
              .instant('ThoughtEcho.AddNoteDialog.routeAnimation.unavailable');
          _scheduleContentFocus('noRouteAnimation');
          _focusRequested = true;
        }
      });
    } else {
      // 实验模式：不自动聚焦，标记为已处理避免监听器泄漏
      _focusRequested = true;
    }

    // 性能优化：延迟 Feature Guide 弹出，避免与键盘动画竞争
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 延迟 500ms 显示功能引导，确保 UI 稳定
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showGuides();
        }
      });
    });

    // 如果是编辑已有笔记
    if (widget.initialQuote != null) {
      _aiSummary = widget.initialQuote!.aiAnalysis;
      _selectedColorHex = widget.initialQuote!.colorHex;

      // 已经在 controller 构造函数中初始化

      // 添加标签
      if (widget.initialQuote!.tagIds.isNotEmpty) {
        _selectedTagIds.addAll(widget.initialQuote!.tagIds);
      }

      // 如果源字段存在但分离的作者/作品字段为空，尝试解析
      if ((widget.initialQuote!.sourceAuthor == null ||
              widget.initialQuote!.sourceAuthor!.isEmpty) &&
          (widget.initialQuote!.sourceWork == null ||
              widget.initialQuote!.sourceWork!.isEmpty) &&
          widget.initialQuote!.source != null &&
          widget.initialQuote!.source!.isNotEmpty) {
        _parseSource(
          widget.initialQuote!.source!,
          _authorController,
          _workController,
        );
      }

      _captureInitialState();

      // 异步获取完整的 Quote 信息（防止列表页传递的是不完整的对象）
      _isLoadingFullQuote = true;
      _fetchFullQuote().whenComplete(() {
        if (mounted) {
          _recordDialogPerfStateChange('fullQuoteLoadingDone');
          setState(() {
            _isLoadingFullQuote = false;
          });
        }
      });
    }

    // 优化：完全异步执行重量级操作，不阻塞 UI
    if (widget.hitokotoData != null) {
      unawaited(
        Future.microtask(() async {
          if (!mounted) return;
          final db =
              _databaseService ?? _readServiceOrNull<DatabaseService>(context);
          _controller.updateServices(dbService: db);
          await _controller.addDefaultHitokotoTagsAsync((category) {
            if (mounted && category != null) {
              setState(() {
                _controller.selectedCategory = category;
              });
            }
          });
          if (!mounted || db == null) return;
          final updatedTags = await db.getTags();
          if (!mounted) return;
          setState(() {
            _availableTags = updatedTags;
            _initialTagIds = List.from(_controller.selectedTagIds);
          });
        }),
      );
    }
  }

  /// 用户主动关掉位置/天气后，作废对应的自动附加计划。
  ///
  /// 计划是在 initState 定下的，而抓取要等 UI 稳定（或用户点保存）才执行。
  /// 中间这段时间里用户把开关关掉，计划却还留着的话，
  /// `_startAutoMetadataFetch` 会把它重新打开并再抓一次——用户明确移除的东西
  /// 在保存时又被静默加回来。
  void _cancelAutoAttachPlan({bool location = false, bool weather = false}) {
    if (location) _autoAttachLocationPlanned = false;
    if (weather) _autoAttachWeatherPlanned = false;
  }

  /// 缓存位置/天气/数据库服务引用。
  ///
  /// 自动附加的抓取推迟到 UI 稳定后才跑，但用户可能更早点位置/天气按钮，
  /// 所以每个用到服务的入口都先确保引用就位，否则 fetch 会因为服务为 null 直接空转。
  void _ensureMetadataServices() {
    _cachedLocationService ??= _readServiceOrNull<LocationService>(context);
    _cachedWeatherService ??= _readServiceOrNull<WeatherService>(context);
    _databaseService ??= _readServiceOrNull<DatabaseService>(context);
    _controller.updateServices(
      locService: _cachedLocationService,
      weaService: _cachedWeatherService,
      dbService: _databaseService,
    );
  }

  /// 按 initState 定下的计划真正抓取位置/天气。
  ///
  /// 触发点有三个，谁先到谁执行，只跑一次：键盘 inset 稳定、兜底定时器、
  /// 用户提前点保存。推迟到这些时机是为了不和入场/键盘动画抢主线程；
  /// 保存路径上的「获取中」标志从 initState 就立着，所以推迟不会让元数据丢失。
  Future<void> _startAutoMetadataFetch(String reason) async {
    if (_autoMetadataStarted) return;
    _autoMetadataStarted = true;
    _autoMetadataFallbackTimer?.cancel();
    _autoMetadataFallbackTimer = null;
    if (!mounted) return;

    _dialogOpenTimelineTask.instant(
      'ThoughtEcho.AddNoteDialog.deferredMetadata.start',
      arguments: <String, Object>{'reason': reason},
    );
    if (_dialogPerfEnabled) {
      _autoMetadataRecording = true;
      if (!_dialogPerfTimingsCallbackAttached) {
        WidgetsBinding.instance.addTimingsCallback(_collectDialogPerfTimings);
        _dialogPerfTimingsCallbackAttached = true;
      }
      _autoMetadataFrameTimings.clear();
      _autoMetadataStopwatch
        ..reset()
        ..start();
    }
    _ensureMetadataServices();

    // 延迟注册监听器，避免初始化时触发不必要的查询
    _databaseListenerTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _databaseService != null) {
        _databaseService!.addListener(_onDatabaseChanged);
      }
    });

    final autoLocation = _autoAttachLocationPlanned;
    final autoWeather = _autoAttachWeatherPlanned;
    if (autoLocation || autoWeather) {
      _recordDialogPerfStateChange('autoAttachPrefs');
      setState(() {
        if (autoLocation) {
          _controller.includeLocation = true;
        }
        if (autoWeather) {
          _controller.includeWeather = true;
        }
      });

      // 天气要用位置的坐标，所以先等位置抓完再抓天气。
      // 这两步之间 isFetchingWeather 必须一直立着（initState 已 arm），
      // 否则位置刚抓完的那一瞬间点保存，会被当成元数据已就绪，天气就丢了。
      if (autoLocation) {
        await _controller.fetchLocationForNewNote();
        _autoMetadataLocationDoneMs =
            _autoMetadataStopwatch.elapsedMilliseconds;
        if (!mounted) {
          _finalizeAutoMetadataCapture('unmounted');
          return;
        }
      }

      if (autoWeather) {
        final hasCoordinates = _controller.newLatitude != null ||
            _cachedLocationService?.currentPosition != null;
        if (!_controller.includeWeather) {
          // 定位还没回来的时候用户就把天气去掉了，尊重它，别再发一次已取消的请求。
          _recordDialogPerfStateChange('autoWeatherCancelled');
          _controller.clearPendingWeatherFetch();
        } else if (!autoLocation ||
            (_controller.includeLocation && hasCoordinates)) {
          await _controller.fetchWeatherForNewNote();
        } else {
          // 位置没拿到，天气也无从获取：取消这次附加并放掉标志。
          // 只清标志不清勾选的话，保存会把 WeatherService 里上一次的天气
          // 写进一条根本没有坐标的笔记。
          _recordDialogPerfStateChange('autoWeatherDisabled');
          _controller.removeNewWeather();
        }
        _autoMetadataWeatherDoneMs = _autoMetadataStopwatch.elapsedMilliseconds;
      }
    }

    _dialogOpenTimelineTask
        .instant('ThoughtEcho.AddNoteDialog.deferredMetadata.complete');
    _finalizeAutoMetadataCapture(reason);
  }

  /// 自动附加阶段的采样收尾。
  ///
  /// 这段现在跑在键盘稳定之后，已经在「打开性能结果」的采样窗口之外——
  /// 之前那份 log 里 `stateChanges={}` 就是因为它整段发生在窗口关闭以后。
  void _finalizeAutoMetadataCapture(String trigger) {
    if (!_autoMetadataRecording) {
      return;
    }
    _autoMetadataRecording = false;
    _autoMetadataStopwatch.stop();
    _detachDialogPerfHooks();

    final summary = _summarizeFrames(_autoMetadataFrameTimings);
    final locationOutcome = !_autoAttachLocationPlanned
        ? 'skip'
        : (_controller.includeLocation && _controller.newLatitude != null
            ? 'ok'
            : 'failed');
    final weatherOutcome = !_autoAttachWeatherPlanned
        ? 'skip'
        : (_controller.includeWeather &&
                (_cachedWeatherService?.hasData ?? false)
            ? 'ok'
            : 'failed');

    logDebug(
      '自动附加耗时: trigger=$trigger, '
      'total=${_autoMetadataStopwatch.elapsedMilliseconds}ms, '
      'locationDone=${_autoMetadataLocationDoneMs ?? -1}ms, '
      'weatherDone=${_autoMetadataWeatherDoneMs ?? -1}ms, '
      'location=$locationOutcome, weather=$weatherOutcome, '
      'frames=${summary.frames}, jank16=${summary.jank16}, '
      'jank32=${summary.jank32}, jank50=${summary.jank50}, '
      'avg=${summary.avgMs.toStringAsFixed(1)}ms, '
      'worst=${summary.worstMs.toStringAsFixed(1)}ms, '
      'buildWorst=${summary.buildWorstMs.toStringAsFixed(1)}ms, '
      'rasterWorst=${summary.rasterWorstMs.toStringAsFixed(1)}ms',
      source: 'AddNoteDialog.Perf',
    );
  }

  void _captureInitialState() {
    _initialContent = _contentController.text;
    _initialAuthor = _authorController.text;
    _initialWork = _workController.text;
    _initialTagIds = List.from(_selectedTagIds);
    _initialColorHex = _selectedColorHex;
  }

  /// 异步获取完整的 Quote 对象
  Future<void> _fetchFullQuote() async {
    if (widget.initialQuote == null || widget.initialQuote!.id == null) return;

    // 延迟一点执行，确保 Provider 可用
    await Future.delayed(Duration.zero);
    if (!mounted) return;

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      final fullQuote = await db.getQuoteById(widget.initialQuote!.id!);
      if (fullQuote != null && mounted) {
        _recordDialogPerfStateChange('fullQuoteLoaded');
        _controller.hydrateFromQuote(fullQuote);
        if (fullQuote.categoryId != null) {
          final category = await db.getTagById(fullQuote.categoryId!);
          if (category != null && mounted) {
            setState(() {
              _controller.selectedCategory = category;
            });
          }
        }
        if (!mounted) return;
        setState(() {
          _fullInitialQuote = fullQuote;
          // 如果列表页传递的对象缺少 AI 分析等大字段，这里补全
          if (_aiSummary == null && fullQuote.aiAnalysis != null) {
            _aiSummary = fullQuote.aiAnalysis;
          }
        });
      }
    } catch (e) {
      logDebug('获取完整笔记详情失败: $e');
    }
  }

  // 优化：数据库变化监听回调 - 自动更新标签列表（带防抖）
  void _onDatabaseChanged() {
    if (!mounted || _databaseService == null) return;

    // 防抖：300ms 内的多次变化只触发一次更新
    _dbChangeDebounceTimer?.cancel();
    _dbChangeDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || _databaseService == null) return;

      try {
        // 重新获取最新的标签列表
        final updatedTags = await _databaseService!.getTags();

        if (!mounted) return;

        // 脏检查：比较完整列表，避免新增标签但首尾不变时漏更新
        bool needsUpdate = _availableTags.length != updatedTags.length;
        if (!needsUpdate) {
          for (int i = 0; i < _availableTags.length; i++) {
            final current = _availableTags[i];
            final updated = updatedTags[i];
            if (current.id != updated.id ||
                current.name != updated.name ||
                current.iconName != updated.iconName ||
                current.isDefault != updated.isDefault) {
              needsUpdate = true;
              break;
            }
          }
        }

        if (needsUpdate) {
          _recordDialogPerfStateChange('databaseTagsUpdated');
          setState(() {
            _availableTags = updatedTags;
          });
          logDebug('标签列表已更新，当前共 ${updatedTags.length} 个标签');
        }
      } catch (e) {
        logDebug('更新标签列表失败: $e');
      }
    });
  }

  /// 显示功能引导：两个候选里只弹靠前的那个。
  ///
  /// 这里是用户正要写东西的时刻，连弹两个气泡会直接挡在编辑区前面；
  /// 没弹到的那个留到下次打开对话框。
  void _showGuides() {
    FeatureGuideHelper.showFirstAvailable(
      context: context,
      guides: [
        ('add_note_fullscreen_button', _fullscreenButtonKey),
        ('add_note_tag_hidden', _tagGuideKey),
      ],
    );
  }

  /// BottomSheet 入场动画进度回调：动画完成后请求焦点弹出键盘。
  void _onRouteAnimationProgress() {
    if (_focusRequested) return;
    final animation = _routeAnimation;
    if (animation == null) {
      _focusRequested = true;
      return;
    }
    if (animation.isCompleted) {
      _focusRequested = true;
      animation.removeListener(_onRouteAnimationProgress);
      _dialogOpenTimelineTask
          .instant('ThoughtEcho.AddNoteDialog.routeAnimation.complete');
      _scheduleContentFocus('routeCompleted');
    }
  }

  void _startDialogPerfCapture() {
    final settingsService = _readServiceOrNull<SettingsService>(context);
    if (settingsService == null ||
        !settingsService.appSettings.developerMode ||
        !settingsService.enableFirstOpenScrollPerfMonitor) {
      return;
    }

    _dialogPerfEnabled = true;
    _dialogPerfRecording = true;
    _dialogPerfFrameTimings.clear();
    _dialogPerfStateChanges.clear();
    _dialogPerfBuildCount = 0;
    _dialogPerfBodyReuseCount = 0;
    _dialogPerfBodyBuildCount = 0;
    _dialogPerfBodyBuildWorstMs = 0;
    _dialogPerfFirstBodyBuildMs = null;
    _dialogPerfInsetBuildCount = 0;
    _dialogPerfInsetChangeCount = 0;
    _dialogPerfMetricsChangeCount = 0;
    _dialogPerfFirstFrameMs = null;
    _dialogPerfFocusRequestMs = null;
    _dialogPerfFocusAcquiredMs = null;
    _dialogPerfKeyboardStartMs = null;
    _dialogPerfKeyboardSettledMs = null;
    _dialogPerfLastInsetBuildValue = null;
    _dialogPerfStopwatch
      ..reset()
      ..start();

    WidgetsBinding.instance.addTimingsCallback(_collectDialogPerfTimings);
    _dialogPerfTimingsCallbackAttached = true;
    logDebug(
      '打开性能监测开始: editing=${widget.initialQuote != null}, '
      'tags=${widget.tags.length}, contentLength=${_contentController.text.length}, '
      'autoKeyboard=true',
      source: 'AddNoteDialog.Perf',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dialogPerfRecording || _dialogPerfFirstFrameLogged) {
        return;
      }
      _dialogPerfFirstFrameLogged = true;
      _dialogPerfFirstFrameMs = _dialogPerfStopwatch.elapsedMilliseconds;
      logDebug(
        '首帧完成: elapsed=${_dialogPerfFirstFrameMs}ms',
        source: 'AddNoteDialog.Perf',
      );
    });

    _dialogPerfFinalizeTimer = Timer(
      const Duration(milliseconds: 2400),
      () => _finalizeDialogPerfCapture('timeout'),
    );
  }

  void _collectDialogPerfTimings(List<FrameTiming> timings) {
    if (_dialogPerfRecording) {
      _dialogPerfFrameTimings.addAll(timings);
    }
    if (_autoMetadataRecording) {
      _autoMetadataFrameTimings.addAll(timings);
    }
  }

  void _requestContentFocus(String reason) {
    _dialogOpenTimelineTask.instant(
      'ThoughtEcho.AddNoteDialog.focus.requested',
      arguments: <String, Object>{'reason': reason},
    );
    if (_dialogPerfEnabled) {
      _dialogPerfFocusRequestMs ??= _dialogPerfStopwatch.elapsedMilliseconds;
      final routeValue = _routeAnimation?.value.toStringAsFixed(2) ?? 'none';
      logDebug(
        '请求内容焦点: reason=$reason, route=$routeValue, '
        'elapsed=${_dialogPerfFocusRequestMs}ms',
        source: 'AddNoteDialog.Perf',
      );
    }
    _contentFocusNode.requestFocus();
  }

  void _showDeferredControls() {
    if (!mounted || _deferredControlsVisible) return;
    _deferredControlsTimer?.cancel();
    _recordDialogPerfStateChange('deferredControlsVisible');
    _dialogOpenTimelineTask.instant(
      'ThoughtEcho.AddNoteDialog.deferredControls.visible',
    );
    setState(() {
      _deferredControlsVisible = true;
    });
  }

  void _scheduleContentFocus(String reason) {
    _autoFocusTimer?.cancel();
    _dialogOpenTimelineTask.instant(
      'ThoughtEcho.AddNoteDialog.focus.scheduled',
      arguments: <String, Object>{'reason': reason},
    );
    _autoFocusTimer = Timer(Duration.zero, () {
      if (!mounted || _contentFocusNode.hasFocus) return;
      _requestContentFocus(reason);
    });
  }

  @override
  void setState(VoidCallback fn) {
    _dialogBodyRevision++;
    super.setState(fn);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 主题/语言等继承数据变了，缓存里那棵树是拿旧值构造的，必须重建。
    _dialogBodyRevision++;
  }

  @override
  void didUpdateWidget(AddNoteDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只比 build 真正读的入参。tags / prefilled* 都只在 initState 用一次，
    // 主体渲染的是内部的 _availableTags 和几个 controller。
    //
    // 尤其不能比 tags：调用方给的是 `UnmodifiableListView get tags` 这种
    // 每次取值都新建包装对象的 getter，identity 恒不相等。拿它当判据的话，
    // 键盘每动一帧修订号都往前走一格，缓存一次都命中不了——整棵主体逐帧重建，
    // 比不做缓存还糟，因为连原本的那层节流也一起没了。
    if (oldWidget.initialQuote != widget.initialQuote) {
      _dialogBodyRevision++;
    }
  }

  Widget _buildCachedDialogBody(Widget Function() buildBody) {
    final cached = _cachedDialogBody;
    if (cached != null && _cachedDialogBodyRevision == _dialogBodyRevision) {
      if (_dialogPerfRecording) {
        _dialogPerfBodyReuseCount++;
      }
      return cached;
    }

    final body = _buildMeasuredDialogBody(buildBody);
    _cachedDialogBody = body;
    _cachedDialogBodyRevision = _dialogBodyRevision;
    return body;
  }

  Widget _buildMeasuredDialogBody(Widget Function() buildBody) {
    if (!_dialogPerfRecording) {
      return buildBody();
    }

    // 只测 Widget 树的构造，不含 element 挂载、布局和光栅化——
    // 拿它和帧的 buildDuration 对比，才知道首帧那一下重在我们这棵树还是框架侧。
    final stopwatch = Stopwatch()..start();
    final body = buildBody();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000.0;
    _dialogPerfBodyBuildCount++;
    _dialogPerfFirstBodyBuildMs ??= elapsedMs;
    if (elapsedMs > _dialogPerfBodyBuildWorstMs) {
      _dialogPerfBodyBuildWorstMs = elapsedMs;
    }
    return body;
  }

  void _onContentFocusChanged() {
    if (!_contentFocusNode.hasFocus) {
      return;
    }

    _dialogOpenTimelineTask.instant('ThoughtEcho.AddNoteDialog.focus.acquired');
    if (!_dialogPerfEnabled || _dialogPerfFocusLogged) {
      return;
    }

    _dialogPerfFocusLogged = true;
    _dialogPerfFocusAcquiredMs = _dialogPerfStopwatch.elapsedMilliseconds;
    logDebug(
      '内容输入框获得焦点: elapsed=${_dialogPerfFocusAcquiredMs}ms',
      source: 'AddNoteDialog.Perf',
    );
  }

  void _recordDialogPerfStateChange(String source) {
    if (!_dialogPerfEnabled || !_dialogPerfRecording) {
      return;
    }
    _dialogPerfStateChanges[source] =
        (_dialogPerfStateChanges[source] ?? 0) + 1;
  }

  /// KeyboardInsetPadding 每次按 inset 重排都回调这里。
  /// 弹窗自己不订阅 MediaQuery，键盘的实时值只能从这条路进来。
  void _onKeyboardInsetBuild(double keyboardInset) {
    _lastKeyboardInset = keyboardInset;
    if (!_dialogPerfEnabled || !_dialogPerfRecording) {
      return;
    }
    _dialogPerfInsetBuildCount++;
    final lastValue = _dialogPerfLastInsetBuildValue;
    if (lastValue == null || (keyboardInset - lastValue).abs() >= 1) {
      _dialogPerfInsetChangeCount++;
      _dialogPerfLastInsetBuildValue = keyboardInset;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      // 注意：这里不能读 MediaQuery.viewInsetsOf(context)。即使在帧回调里读，
      // 也会给本 State 挂上 viewInsets 依赖，键盘每动一帧都把整个弹窗标脏。
      // 值改由 KeyboardInsetPadding 在自己的 build 里回传。
      final keyboardInset = _lastKeyboardInset;
      if (keyboardInset <= 0) {
        return;
      }

      if (!_dialogPerfKeyboardStartLogged) {
        _dialogPerfKeyboardStartLogged = true;
        if (_dialogPerfRecording) {
          _dialogPerfKeyboardStartMs = _dialogPerfStopwatch.elapsedMilliseconds;
        }
        _dialogOpenTimelineTask.instant(
          'ThoughtEcho.AddNoteDialog.keyboardInset.started',
          arguments: <String, Object>{'inset': keyboardInset.round()},
        );
        if (_dialogPerfRecording) {
          logDebug(
            '键盘 inset 开始变化: inset=${keyboardInset.round()}, '
            'elapsed=${_dialogPerfKeyboardStartMs}ms',
            source: 'AddNoteDialog.Perf',
          );
        }
      }

      _dialogPerfKeyboardSettleTimer?.cancel();
      _dialogPerfKeyboardSettleTimer = Timer(
        const Duration(milliseconds: 220),
        () {
          // 键盘动画结束，主线程空出来了，这时候再去抓位置/天气。
          unawaited(_startAutoMetadataFetch('keyboardSettled'));
          if (_dialogPerfRecording) {
            _dialogPerfKeyboardSettledMs =
                _dialogPerfStopwatch.elapsedMilliseconds;
          }
          _dialogOpenTimelineTask.instant(
            'ThoughtEcho.AddNoteDialog.keyboardInset.settled',
            arguments: <String, Object>{
              'inset': _lastKeyboardInset.round(),
            },
          );
          _finishDialogOpenTimeline('keyboardSettled');
          if (!_dialogPerfRecording) {
            return;
          }
          logDebug(
            '键盘 inset 稳定: inset=${_lastKeyboardInset.round()}, '
            'elapsed=${_dialogPerfKeyboardSettledMs}ms',
            source: 'AddNoteDialog.Perf',
          );
          _finalizeDialogPerfCapture('keyboardSettled');
        },
      );
    });

    if (!_dialogPerfEnabled || !_dialogPerfRecording) {
      return;
    }
    _dialogPerfMetricsChangeCount++;
  }

  _FramePhaseSummary _summarizeFrames(List<FrameTiming> timings) {
    int jankyFrames = 0;
    int jankyFrames32 = 0;
    int jankyFrames50 = 0;
    int totalFrameMicros = 0;
    int totalBuildMicros = 0;
    int totalRasterMicros = 0;
    double worstFrameMs = 0;
    double worstBuildMs = 0;
    double worstRasterMs = 0;

    for (final timing in timings) {
      final buildMicros = timing.buildDuration.inMicroseconds;
      final rasterMicros = timing.rasterDuration.inMicroseconds;
      final totalMicros = buildMicros + rasterMicros;
      totalBuildMicros += buildMicros;
      totalRasterMicros += rasterMicros;
      totalFrameMicros += totalMicros;

      final frameMs = totalMicros / 1000.0;
      final buildMs = buildMicros / 1000.0;
      final rasterMs = rasterMicros / 1000.0;
      if (frameMs > worstFrameMs) {
        worstFrameMs = frameMs;
      }
      if (buildMs > worstBuildMs) {
        worstBuildMs = buildMs;
      }
      if (rasterMs > worstRasterMs) {
        worstRasterMs = rasterMs;
      }
      if (totalMicros > 16600) {
        jankyFrames++;
      }
      if (totalMicros > 32000) {
        jankyFrames32++;
      }
      if (totalMicros > 50000) {
        jankyFrames50++;
      }
    }

    final totalFrames = timings.length;
    return _FramePhaseSummary(
      frames: totalFrames,
      jank16: jankyFrames,
      jank32: jankyFrames32,
      jank50: jankyFrames50,
      avgMs: totalFrames == 0 ? 0.0 : (totalFrameMicros / totalFrames) / 1000.0,
      worstMs: worstFrameMs,
      buildAvgMs:
          totalFrames == 0 ? 0.0 : (totalBuildMicros / totalFrames) / 1000.0,
      buildWorstMs: worstBuildMs,
      rasterAvgMs:
          totalFrames == 0 ? 0.0 : (totalRasterMicros / totalFrames) / 1000.0,
      rasterWorstMs: worstRasterMs,
    );
  }

  void _finalizeDialogPerfCapture(String reason) {
    if (!_dialogPerfRecording) {
      return;
    }

    _dialogPerfRecording = false;
    _dialogPerfStopwatch.stop();
    _dialogPerfFinalizeTimer?.cancel();
    _dialogPerfKeyboardSettleTimer?.cancel();
    _detachDialogPerfHooks();

    final summary = _summarizeFrames(_dialogPerfFrameTimings);
    final jankyFrames = summary.jank16;
    final jankyFrames32 = summary.jank32;
    final jankyFrames50 = summary.jank50;
    final worstFrameMs = summary.worstMs;
    final worstBuildMs = summary.buildWorstMs;
    final worstRasterMs = summary.rasterWorstMs;
    final totalFrames = summary.frames;
    final avgFrameMs = summary.avgMs;
    final avgBuildMs = summary.buildAvgMs;
    final avgRasterMs = summary.rasterAvgMs;
    final keyboardDurationMs = _dialogPerfKeyboardStartMs == null ||
            _dialogPerfKeyboardSettledMs == null
        ? null
        : _dialogPerfKeyboardSettledMs! - _dialogPerfKeyboardStartMs!;

    logDebug(
      '打开性能结果: reason=$reason, '
      'elapsed=${_dialogPerfStopwatch.elapsedMilliseconds}ms, '
      'frames=$totalFrames, jank=$jankyFrames, '
      'avg=${avgFrameMs.toStringAsFixed(1)}ms, '
      'worst=${worstFrameMs.toStringAsFixed(1)}ms, '
      'focus=$_dialogPerfFocusLogged, '
      'keyboardInset=${_lastKeyboardInset.round()}',
      source: 'AddNoteDialog.Perf',
    );

    logDebug(
      '打开性能明细: firstFrame=${_dialogPerfFirstFrameMs ?? -1}ms, '
      'focusRequest=${_dialogPerfFocusRequestMs ?? -1}ms, '
      'focus=${_dialogPerfFocusAcquiredMs ?? -1}ms, '
      'keyboardStart=${_dialogPerfKeyboardStartMs ?? -1}ms, '
      'keyboardSettled=${_dialogPerfKeyboardSettledMs ?? -1}ms, '
      'keyboardDuration=${keyboardDurationMs ?? -1}ms, '
      'widgetBuilds=$_dialogPerfBuildCount, '
      'bodyBuilds=$_dialogPerfBodyBuildCount, '
      'bodyBuildFirst='
      '${_dialogPerfFirstBodyBuildMs?.toStringAsFixed(1) ?? "-1"}ms, '
      'bodyBuildWorst=${_dialogPerfBodyBuildWorstMs.toStringAsFixed(1)}ms, '
      'bodyReuses=$_dialogPerfBodyReuseCount, '
      'insetBuilds=$_dialogPerfInsetBuildCount, '
      'insetChanges=$_dialogPerfInsetChangeCount, '
      'metrics=$_dialogPerfMetricsChangeCount, '
      'stateChanges=$_dialogPerfStateChanges',
      source: 'AddNoteDialog.Perf',
    );

    logDebug(
      '打开帧耗时明细: jank16=$jankyFrames, jank32=$jankyFrames32, '
      'jank50=$jankyFrames50, '
      'buildAvg=${avgBuildMs.toStringAsFixed(1)}ms, '
      'buildWorst=${worstBuildMs.toStringAsFixed(1)}ms, '
      'rasterAvg=${avgRasterMs.toStringAsFixed(1)}ms, '
      'rasterWorst=${worstRasterMs.toStringAsFixed(1)}ms',
      source: 'AddNoteDialog.Perf',
    );
  }

  void _finishDialogOpenTimeline(String reason) {
    if (_dialogOpenTimelineFinished) {
      return;
    }
    _dialogOpenTimelineFinished = true;
    _dialogOpenTimelineTimeout?.cancel();
    _dialogOpenTimelineTask.finish(
      arguments: <String, Object>{'reason': reason},
    );
  }

  void _detachDialogPerfHooks() {
    // 两段采样共用同一个帧回调，任意一段还在跑就先别摘：
    // 自动附加可能被保存提前触发并先结束，这时打开阶段还在录，摘早了后面的帧全丢。
    if (_autoMetadataRecording || _dialogPerfRecording) {
      return;
    }
    if (_dialogPerfTimingsCallbackAttached) {
      WidgetsBinding.instance.removeTimingsCallback(_collectDialogPerfTimings);
      _dialogPerfTimingsCallbackAttached = false;
    }
  }

  /// 获取位置提示文本（支持坐标显示）
  /// 修复：新建模式只显示实时获取的位置，而不是从 LocationService 获取的缓存位置
  String _getLocationTooltipText(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // 编辑模式：显示原始位置
    if (widget.initialQuote != null) {
      if (_controller.originalLocation != null &&
          _controller.originalLocation!.isNotEmpty) {
        return LocationService.formatLocationForDisplay(
            _controller.originalLocation);
      }
      if (_controller.originalLatitude != null &&
          _controller.originalLongitude != null) {
        return LocationService.formatCoordinates(
          _controller.originalLatitude,
          _controller.originalLongitude,
        );
      }
      return l10n.noLocationInfo;
    }

    // 新建模式：只显示实时获取的位置
    if (_controller.newLocation != null &&
        _controller.newLocation!.isNotEmpty) {
      return LocationService.formatLocationForDisplay(_controller.newLocation);
    }
    if (_controller.newLatitude != null && _controller.newLongitude != null) {
      return LocationService.formatCoordinates(
          _controller.newLatitude, _controller.newLongitude);
    }
    // 未获取位置时显示"当前位置"提示
    return l10n.currentLocationLabel;
  }

  /// 编辑模式下的位置对话框
  Future<void> _showLocationDialog(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasLocationData = _controller.originalLocation != null ||
        (_controller.originalLatitude != null &&
            _controller.originalLongitude != null);
    final hasCoordinates = _controller.originalLatitude != null &&
        _controller.originalLongitude != null;
    final hasOnlyCoordinates =
        _controller.originalLocation == null && hasCoordinates;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasLocationData) {
      // 没有位置数据
      title = l10n.cannotAddLocation;
      content = l10n.cannotAddLocationDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有位置数据
      title = l10n.locationInfo;
      content = hasOnlyCoordinates
          ? l10n.locationUpdateHint(LocationService.formatCoordinates(
              _controller.originalLatitude, _controller.originalLongitude))
          : l10n.locationRemoveHint(
              LocationService.formatLocationForDisplay(
                  _controller.originalLocation),
            );
      actions = [
        if (_controller.includeLocation)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        if (hasOnlyCoordinates)
          TextButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(l10n.updateLocation),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'update' && hasCoordinates) {
      // 尝试用坐标更新地址
      try {
        // 获取当前语言设置
        final localeCode = l10n.localeName;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
          _controller.originalLatitude!,
          _controller.originalLongitude!,
          localeCode: localeCode,
        );
        if (addressInfo != null && mounted) {
          // 使用 country,province,city,district 拼成标准存储格式，
          // 而不是 formatted_address（带空格进行英文拼接的格式），
          // 避免 formatLocationForDisplay 解析失败导致显示英文。
          final country = addressInfo['country'] ?? '';
          final province = addressInfo['province'] ?? '';
          final city = addressInfo['city'] ?? '';
          final district = addressInfo['district'] ?? '';
          final standardAddress = '$country,$province,$city,$district';
          final hasAnyField =
              country.isNotEmpty || province.isNotEmpty || city.isNotEmpty;
          if (hasAnyField) {
            _controller.setOriginalLocationData(
              standardAddress,
              _controller.originalLatitude,
              _controller.originalLongitude,
            );
            _controller.setIncludeLocation(true);
            setState(() {});
            if (context.mounted) {
              final l10n = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.locationUpdatedTo(
                      LocationService.formatLocationForDisplay(standardAddress),
                    ),
                  ),
                ),
              );
            }
          } else if (context.mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
          }
        } else if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
        }
      } catch (e) {
        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
              SnackBar(content: Text(l10n.updateFailed(e.toString()))));
        }
      }
    } else if (result == 'remove') {
      _controller.removeOriginalLocation();
      setState(() {});
    }
  }

  /// 编辑模式下的天气对话框
  Future<void> _showWeatherDialog(BuildContext context, ThemeData theme) async {
    final l10n = AppLocalizations.of(context);
    final hasWeatherData = _controller.originalWeather != null;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasWeatherData) {
      // 没有天气数据
      title = l10n.cannotAddWeather;
      content = l10n.cannotAddWeatherDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有天气数据
      title = l10n.weatherInfo2;
      final weatherDisplay =
          '${_controller.originalWeather}${_controller.originalTemperature != null ? " ${_controller.originalTemperature}" : ""}';
      content = l10n.weatherRemoveHint(weatherDisplay);
      actions = [
        if (_controller.includeWeather)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'remove') {
      setState(() {
        _controller.includeWeather = false;
      });
    }
  }

  /// 新建模式下的位置信息对话框
  /// 支持查看当前坐标、手动触发地址解析、移除位置
  Future<void> _showNewNoteLocationDialog(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasAddress =
        _controller.newLocation != null && _controller.newLocation!.isNotEmpty;
    final hasCoordinates =
        _controller.newLatitude != null && _controller.newLongitude != null;
    final hasOnlyCoordinates = !hasAddress && hasCoordinates;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasCoordinates) {
      // 没有任何位置数据
      title = l10n.cannotGetLocationTitle;
      content = l10n.cannotGetLocationDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      title = l10n.locationInfo;
      content = hasOnlyCoordinates
          ? l10n.locationUpdateHint(LocationService.formatCoordinates(
              _controller.newLatitude, _controller.newLongitude))
          : l10n.locationRemoveHint(
              LocationService.formatLocationForDisplay(_controller.newLocation),
            );
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context, 'remove'),
          child: Text(l10n.remove),
        ),
        if (hasOnlyCoordinates)
          TextButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(l10n.updateLocation),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'update' && hasCoordinates) {
      // 尝试用坐标更新地址（优先在线 Nominatim → 回退系统 SDK）
      try {
        _ensureMetadataServices();
        final locationService = _cachedLocationService;
        if (locationService != null) {
          locationService.currentLocaleCode = l10n.localeName;
          locationService.setCoordinates(
            _controller.newLatitude!,
            _controller.newLongitude!,
          );
          await locationService.getAddressFromLatLng();
          final resolved = locationService.getFormattedLocation();
          if (resolved.isNotEmpty && mounted) {
            _controller.setNewLocationData(
              resolved,
              _controller.newLatitude,
              _controller.newLongitude,
            );
            setState(() {});
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(l10n.locationUpdatedTo(
                        LocationService.formatLocationForDisplay(resolved)))),
              );
            }
            return;
          }
        }

        // 回退到直接调用 LocalGeocodingService
        final localeCode = l10n.localeName;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
          _controller.newLatitude!,
          _controller.newLongitude!,
          localeCode: localeCode,
        );
        if (addressInfo != null && mounted) {
          final country = addressInfo['country'] ?? '';
          final province = addressInfo['province'] ?? '';
          final city = addressInfo['city'] ?? '';
          final district = addressInfo['district'] ?? '';
          final standardAddress = '$country,$province,$city,$district';
          final hasAnyField =
              country.isNotEmpty || province.isNotEmpty || city.isNotEmpty;
          if (hasAnyField) {
            _controller.setNewLocationData(
              standardAddress,
              _controller.newLatitude,
              _controller.newLongitude,
            );
            setState(() {});
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(l10n.locationUpdatedTo(
                        LocationService.formatLocationForDisplay(
                            standardAddress)))),
              );
            }
          } else if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
          }
        } else if (mounted && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
        }
      } catch (e) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.updateFailed(e.toString()))));
        }
      }
    } else if (result == 'remove') {
      _cancelAutoAttachPlan(location: true);
      _controller.removeNewLocation();
      setState(() {});
    }
  }

  /// 新建模式下的天气信息对话框
  /// 支持查看当前天气、移除天气
  Future<void> _showNewNoteWeatherDialog(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    _ensureMetadataServices();
    final weatherService = _cachedWeatherService;
    final hasWeatherData = weatherService?.hasData ?? false;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasWeatherData) {
      // 没有天气数据（获取失败或离线）
      title = l10n.weatherFetchFailedTitle;
      content = l10n.weatherFetchFailedDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context, 'remove'),
          child: Text(l10n.remove),
        ),
        // 如果有坐标，允许重试获取天气
        if (_controller.newLatitude != null && _controller.newLongitude != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: Text(l10n.retry),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    } else {
      // 有天气数据
      title = l10n.weatherInfo2;
      final weatherDisplay = weatherService!.getFormattedWeather(l10n);
      content = l10n.weatherRemoveHint(weatherDisplay.isNotEmpty
          ? weatherDisplay
          : '${weatherService.currentWeather}');
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context, 'remove'),
          child: Text(l10n.remove),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'remove') {
      _cancelAutoAttachPlan(weather: true);
      _controller.removeNewWeather();
    } else if (result == 'retry') {
      _ensureMetadataServices();
      _controller.fetchWeatherForNewNote();
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _waitForMetadata(Duration maxWait) async {
    if (!_controller.isFetchingMetadata) return;
    final completer = Completer<void>();
    void listener() {
      if (!_controller.isFetchingMetadata && !completer.isCompleted) {
        completer.complete();
      }
    }

    _controller.addListener(listener);
    // 挂监听前的一瞬间可能刚好抓取完成（那次 notifyListeners 收不到），
    // 这里补一次检查，否则会白等满 maxWait 并误报超时。
    listener();
    try {
      await completer.future.timeout(maxWait);
    } catch (_) {
      // 超时处理
    } finally {
      _controller.removeListener(listener);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _finishDialogOpenTimeline('disposed');
    _dialogOpenTimelineTimeout?.cancel();
    _dialogPerfFinalizeTimer?.cancel();
    _dialogPerfKeyboardSettleTimer?.cancel();
    _deferredControlsTimer?.cancel();
    _autoFocusTimer?.cancel();
    _autoMetadataFallbackTimer?.cancel();
    _databaseListenerTimer?.cancel();
    // 两个采样标志都要在摘钩子前清掉，否则 _detachDialogPerfHooks 会以为还在录，
    // 帧回调就留在 binding 上了。
    _autoMetadataRecording = false;
    _autoMetadataStopwatch.stop();
    _dialogPerfRecording = false;
    _detachDialogPerfHooks();
    _dbChangeDebounceTimer?.cancel();
    _routeAnimation?.removeListener(_onRouteAnimationProgress);
    WidgetsBinding.instance.removeObserver(this);
    _contentFocusNode.removeListener(_onContentFocusChanged);
    _contentController.dispose();
    _authorController.dispose();
    _workController.dispose();
    _contentFocusNode.dispose();

    // 优化：移除数据库监听器，防止内存泄漏
    _databaseService?.removeListener(_onDatabaseChanged);

    // 优化：清理缓存，释放内存
    _availableTags.clear();

    super.dispose();
  }

  // 解析格式如"——作者《作品》"的字符串
  void _parseSource(
    String source,
    TextEditingController authorController,
    TextEditingController workController,
  ) {
    String author = '';
    String work = '';

    // 提取作者（在"——"之后，"《"之前）
    final authorMatch = RegExp(r'——([^《]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }

    // 提取作品（在《》之间）
    final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }

    authorController.text = author;
    workController.text = work;
  }

  // 格式化来源
  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$work》';
    }

    return result;
  }

  /// 检查是否有未保存的用户输入内容
  bool _hasUnsavedChanges() {
    // 检查正文内容是否有变化
    if (_contentController.text.trim() != _initialContent.trim()) {
      return true;
    }

    // 检查作者是否有变化
    if (_authorController.text.trim() != _initialAuthor.trim()) {
      return true;
    }

    // 检查作品是否有变化
    if (_workController.text.trim() != _initialWork.trim()) {
      return true;
    }

    // 检查标签是否有变化
    final currentTagSet = Set.from(_selectedTagIds);
    final initialTagSet = Set.from(_initialTagIds);
    if (!currentTagSet.containsAll(initialTagSet) ||
        !initialTagSet.containsAll(currentTagSet)) {
      return true;
    }

    // 检查颜色是否有变化
    if (_selectedColorHex != _initialColorHex) {
      return true;
    }

    return false;
  }

  /// 用户想要的位置/天气是否确实没写进这条笔记。
  ///
  /// 位置只要有坐标就算附上了——地址可能还在后台反查（`kAddressPending`），
  /// 笔记本身并不缺信息。
  bool _metadataMissingIn(Quote quote) {
    final locationMissing = _controller.includeLocation &&
        quote.latitude == null &&
        (quote.location == null || quote.location!.isEmpty);
    final weatherMissing = _controller.includeWeather &&
        (quote.weather == null || quote.weather!.isEmpty);
    return locationMissing || weatherMissing;
  }

  /// 保存笔记并退出
  /// 保存并关闭对话框。返回落库的笔记（含真实 id），失败或未保存时返回 null。
  Future<Quote?> _saveAndExit() async {
    if (_isSaving || _waitingForFetch) return null;

    // 如果内容为空，直接返回
    if (_contentController.text.isEmpty) {
      if (mounted) {
        Navigator.pop(context);
      }
      return null;
    }

    // 用户比自动附加更快：先把还没开跑的抓取踢起来，再转圈等它，
    // 否则会白等一个还躺在定时器里的任务。
    unawaited(_startAutoMetadataFetch('save'));

    // 如果位置/天气正在异步获取中，显示 loading 并等待完成（最多 5s）
    var metadataTimedOut = false;
    if (_controller.isFetchingMetadata) {
      if (mounted) setState(() => _waitingForFetch = true);
      await _waitForMetadata(const Duration(seconds: 5));
      if (!mounted) return null;
      // 仍在获取中说明是超时，需要告知用户
      metadataTimedOut = _controller.isFetchingMetadata;
      if (mounted) setState(() => _waitingForFetch = false);
    }

    _isSaving = true;

    final navigator = Navigator.of(context);

    try {
      // 获取当前时间段
      final String currentDayPeriodKey = TimeUtils.getCurrentDayPeriodKey();

      // 创建或更新笔记
      final isEditing = widget.initialQuote != null;
      final baseQuote = _fullInitialQuote ?? widget.initialQuote;
      // 抓取可能一次都没跑（内容写得快、偏好没开），服务引用未必缓存过，
      // 这里补一次读取，避免把已有的位置/天气当成没有。
      final locationService = _cachedLocationService ??
          _readServiceOrNull<LocationService>(context);
      final weatherService =
          _cachedWeatherService ?? _readServiceOrNull<WeatherService>(context);

      final Quote quote = Quote(
        id: widget.initialQuote?.id ?? const Uuid().v4(),
        content: _contentController.text,
        date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
        aiAnalysis: _aiSummary,
        source: _formatSource(
          _authorController.text,
          _workController.text,
        ),
        sourceAuthor: _authorController.text,
        sourceWork: _workController.text,
        tagIds: List.unmodifiable(_selectedTagIds),
        sentiment: baseQuote?.sentiment,
        keywords: baseQuote?.keywords,
        summary: baseQuote?.summary,
        categoryId:
            _controller.selectedCategory?.id ?? widget.initialQuote?.categoryId,
        colorHex: _selectedColorHex,
        location: _controller.includeLocation
            ? (isEditing
                ? _controller.originalLocation
                : () {
                    final loc = _controller.newLocation ??
                        locationService?.getFormattedLocation();
                    if ((loc == null || loc.isEmpty) &&
                        _controller.newLatitude != null) {
                      return LocationService.kAddressPending;
                    }
                    return loc;
                  }())
            : null,
        // 天气可临时使用坐标获取，但只有用户保留位置时才持久化坐标。
        latitude: _controller.includeLocation
            ? (isEditing
                ? _controller.originalLatitude
                : _controller.newLatitude)
            : null,
        longitude: _controller.includeLocation
            ? (isEditing
                ? _controller.originalLongitude
                : _controller.newLongitude)
            : null,
        weather: _controller.includeWeather
            ? (isEditing
                ? _controller.originalWeather
                : weatherService?.currentWeather)
            : null,
        temperature: _controller.includeWeather
            ? (isEditing
                ? _controller.originalTemperature
                : weatherService?.temperature)
            : null,
        dayPeriod: widget.initialQuote?.dayPeriod ?? currentDayPeriodKey,
        editSource: widget.initialQuote?.editSource,
        deltaContent: widget.initialQuote?.deltaContent,
      );

      if (mounted) {
        // 在 pop 前取好 messenger 引用（pop 后 context 失效）
        final messenger = ScaffoldMessenger.of(context);
        final l10n = AppLocalizations.of(context);
        navigator.pop();
        // 超时不等于没附上：等待期间位置可能已拿到坐标，天气也可能命中
        // WeatherService 已有的数据。只有真的落了空才提示，否则用户会看到
        // 「未能附加」但笔记上明明有天气/位置。
        if (metadataTimedOut && _metadataMissingIn(quote)) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.autoAttachMetadataUnavailable),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
      unawaited(Future<void>.sync(() => widget.onSave(quote)));
      return quote;
    } catch (e) {
      logDebug('创建非全屏笔记保存快照失败: $e');
      _isSaving = false;
    }
    return null;
  }

  /// AI 入口：与全屏编辑器 `_NoteEditorAIFeatures._openAiAssistant` 同一套流程——
  /// 先把内容落库，再关掉本对话框进入 Thoughter。
  ///
  /// 必须先保存的原因：Agent 要靠真实笔记 id 才能调用修改笔记的工具。
  /// 之前这里传的是空 id，Agent 收到的 note_id 是占位串，既没法改这条笔记，
  /// 又会把「未保存」当成事实汇报给用户。
  Future<void> _openAiAssistant(String? initialQuestion) async {
    final l10n = AppLocalizations.of(context);

    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterContent),
          duration: AppConstants.snackBarDurationNormal,
        ),
      );
      return;
    }

    // 保存会 pop 掉本对话框，导航器引用要提前取好
    final navigator = Navigator.of(context);
    Quote? noteForAgent = _fullInitialQuote ?? widget.initialQuote;

    if (_hasUnsavedChanges()) {
      final shouldSave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.saveRequired),
          content: Text(l10n.saveBeforeAiAssistant),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.saveAndContinue),
            ),
          ],
        ),
      );
      if (shouldSave != true || !mounted) return;
      noteForAgent = await _saveAndExit();
      // 保存失败时 _saveAndExit 已处理提示，这里不再跳转
      if (noteForAgent == null) return;
    } else if (navigator.canPop()) {
      // 没有改动，直接关掉对话框，避免返回后停在过期的编辑态
      navigator.pop();
    }

    if (noteForAgent == null) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => ThoughterPage(
          entrySource: ThoughterEntrySource.note,
          quote: noteForAgent,
          initialQuestion: initialQuestion,
        ),
      ),
    );
  }

  /// 显示未保存内容的确认对话框
  /// 返回值: null=继续编辑, true=放弃更改, 'save'=保存并退出
  Future<dynamic> _showUnsavedChangesDialog() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unsavedChangesTitle),
        content: Text(l10n.unsavedChangesDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.continueEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.discardChanges,
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(l10n.saveAndExit),
          ),
        ],
      ),
    );
    return result;
  }

  /// 关闭弹窗的统一入口。
  ///
  /// PopScope 只拦得住系统返回键：`Navigator.pop` 不走 popDisposition，
  /// 所以「取消」按钮以前是直接把路由弹掉的，未保存确认整个被绕过去。
  /// 两条路都改走这里。
  Future<void> _handleCloseRequest() async {
    // 确认框弹出前「取消」还点得到，返回键也还进得来。没有这道闸，
    // 连点两下就会叠两个未保存确认框，各自 await 各自的结果。
    if (!mounted || _closeRequestInFlight) return;
    _closeRequestInFlight = true;
    try {
      // 检查是否有未保存的更改
      if (!_hasUnsavedChanges()) {
        Navigator.pop(context);
        return;
      }

      // 显示确认对话框
      final dialogResult = await _showUnsavedChangesDialog();
      if (!mounted) return;
      if (dialogResult == true) {
        // 用户选择放弃更改
        Navigator.pop(context);
      } else if (dialogResult == 'save') {
        // 用户选择保存并退出
        await _saveAndExit();
      }
      // dialogResult == null: 继续编辑，不做任何操作
    } finally {
      _closeRequestInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dialogPerfRecording) {
      _dialogPerfBuildCount++;
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleCloseRequest());
      },
      child: KeyboardInsetPadding(
        onInsetBuild: _onKeyboardInsetBuild,
        child: _buildCachedDialogBody(() => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 16),
                  // 内容输入区，带全屏编辑按钮
                  SizedBox(height: 16),
                  Stack(
                    children: [
                      TextField(
                        key: const ValueKey('add_note_content_field'),
                        controller: _contentController,
                        focusNode: _contentFocusNode,
                        maxLength: 10000,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        buildCounter: (context,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        decoration: InputDecoration(
                          hintText:
                              AppLocalizations.of(context).writeYourThoughts,
                          border: const OutlineInputBorder(),
                          prefixIcon: Icon(Icons.edit),
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 16, 48, 16),
                        ),
                        maxLines: 3,
                        autofocus: false, // 延迟请求焦点，避免与 BottomSheet 动画竞争
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _contentController,
                          builder: (context, value, child) {
                            final isLongContent = value.text.length > 100;
                            return Stack(
                              children: [
                                // 如果是长文本，添加一个提示小红点
                                if (isLongContent)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(context).colorScheme.error,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.colorScheme.surface,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  key: _fullscreenButtonKey,
                                  tooltip: isLongContent
                                      ? l10n.fullscreenEditLongTextTip
                                      : l10n.fullscreenEditTooltip,
                                  icon: Icon(
                                    Icons.fullscreen,
                                    color: theme.colorScheme.primary,
                                  ),
                                  onPressed: () async {
                                    if (!context.mounted) return;
                                    try {
                                      // 获取所有标签数据
                                      final databaseService =
                                          Provider.of<DatabaseService>(
                                        context,
                                        listen: false,
                                      );
                                      final allTags =
                                          await databaseService.getTags();

                                      // 修复内存泄露：在异步操作后检查mounted状态
                                      if (!mounted) return;
                                      if (!context.mounted) return;

                                      // 创建包含当前元数据的临时Quote对象，确保全屏编辑器能继承所有元数据
                                      final locationService =
                                          Provider.of<LocationService>(
                                        context,
                                        listen: false,
                                      );
                                      final weatherService =
                                          Provider.of<WeatherService>(
                                        context,
                                        listen: false,
                                      );

                                      // 获取位置和天气信息
                                      String? currentLocation;
                                      String? currentWeather;
                                      String? currentTemperature;

                                      if (_controller.includeLocation) {
                                        currentLocation =
                                            _controller.originalLocation ??
                                                locationService
                                                    .getFormattedLocation();
                                      }

                                      if (_controller.includeWeather) {
                                        currentWeather =
                                            _controller.originalWeather ??
                                                weatherService.currentWeather;
                                        currentTemperature =
                                            _controller.originalTemperature ??
                                                weatherService.temperature;
                                      }

                                      // 创建包含当前所有元数据的临时Quote对象
                                      // 获取经纬度（编辑时用原始值，新建时用实时获取的值）
                                      final currentLat =
                                          widget.initialQuote != null
                                              ? _controller.originalLatitude
                                              : _controller.newLatitude ??
                                                  locationService
                                                      .currentPosition
                                                      ?.latitude;
                                      final currentLon =
                                          widget.initialQuote != null
                                              ? _controller.originalLongitude
                                              : _controller.newLongitude ??
                                                  locationService
                                                      .currentPosition
                                                      ?.longitude;

                                      final tempQuote = Quote(
                                        id: widget.initialQuote
                                            ?.id, // 保持原有ID（如果是编辑模式）
                                        content: _contentController.text,
                                        date: widget.initialQuote?.date ??
                                            DateTime.now().toIso8601String(),
                                        sourceAuthor: _authorController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : _authorController.text.trim(),
                                        sourceWork:
                                            _workController.text.trim().isEmpty
                                                ? null
                                                : _workController.text.trim(),
                                        tagIds: _selectedTagIds,
                                        colorHex: _selectedColorHex,
                                        location: currentLocation,
                                        latitude: _controller.includeLocation
                                            ? currentLat
                                            : null,
                                        longitude: _controller.includeLocation
                                            ? currentLon
                                            : null,
                                        weather: currentWeather,
                                        temperature: currentTemperature,
                                        aiAnalysis:
                                            widget.initialQuote?.aiAnalysis,
                                        sentiment:
                                            widget.initialQuote?.sentiment,
                                        keywords: widget.initialQuote?.keywords,
                                        summary: widget.initialQuote?.summary,
                                        categoryId:
                                            widget.initialQuote?.categoryId,
                                        editSource:
                                            widget.initialQuote?.editSource,
                                        deltaContent:
                                            widget.initialQuote?.deltaContent,
                                        dayPeriod:
                                            widget.initialQuote?.dayPeriod,
                                      );

                                      if (!context.mounted) return;
                                      final navigator = Navigator.of(context);
                                      final result = await navigator.push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              NoteFullEditorPage(
                                            initialContent:
                                                _contentController.text,
                                            initialQuote:
                                                tempQuote, // 传递包含当前元数据的临时Quote对象
                                            allTags: allTags,
                                          ),
                                        ),
                                      );

                                      if (!mounted) return;

                                      if (result != null && result == true) {
                                        // 如果笔记已在全屏编辑器中保存，关闭本对话框
                                        // 性能优化：延迟 300ms 等待全屏编辑器的退出动画执行完毕，避免动画冲突导致视觉上的中断
                                        if (mounted && context.mounted) {
                                          Future.delayed(
                                              const Duration(milliseconds: 300),
                                              () {
                                            if (mounted && context.mounted) {
                                              final route =
                                                  ModalRoute.of(context);
                                              if (route != null &&
                                                  route.isCurrent) {
                                                Navigator.pop(context);
                                              }
                                            }
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      if (mounted && context.mounted) {
                                        AppSnackBar.error(
                                          context,
                                          '${l10n.openFullEditorFailedSimple}: $e',
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_deferredControlsVisible) ...[
                    SizedBox(height: 16),
                    // 拆分来源输入为作者和作品
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _authorController,
                            decoration: InputDecoration(
                              hintText:
                                  AppLocalizations.of(context).authorPerson,
                              border: const OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                            maxLines: 1,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _workController,
                            decoration: InputDecoration(
                              hintText: AppLocalizations.of(context).workName,
                              border: const OutlineInputBorder(),
                              prefixIcon: Icon(Icons.book),
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: 8),
                    // 显示格式化后的来源预览
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _authorController,
                        _workController,
                      ]),
                      builder: (context, child) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.sourcePreviewFormat(_formatSource(
                              _authorController.text,
                              _workController.text,
                            )),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),

                    // 位置和天气选项
                    SizedBox(height: 16),
                    RepaintBoundary(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            l10n.addInfo,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          SizedBox(width: 16),
                          // 位置信息按钮
                          Builder(
                            builder: (context) {
                              // 仅在需要显示 tooltip 时读取服务，避免每次 build 都触发
                              final locationService = _cachedLocationService;
                              return Tooltip(
                                message: locationService != null
                                    ? '${l10n.addLocationPrefix}: ${_getLocationTooltipText(context)}'
                                    : l10n.locationServiceUnavailable,
                                child: Stack(
                                  children: [
                                    FilterChip(
                                      key: const ValueKey(
                                          'add_note_location_chip'),
                                      showCheckmark: false,
                                      avatar: Icon(
                                        Icons.location_on,
                                        color: _controller.includeLocation
                                            ? theme.colorScheme.primary
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                        size: 18,
                                      ),
                                      label: Text(l10n.location),
                                      selected: _controller.includeLocation,
                                      onSelected: (value) async {
                                        if (!value) {
                                          _cancelAutoAttachPlan(location: true);
                                        }
                                        // 编辑模式下统一弹对话框
                                        if (widget.initialQuote != null) {
                                          await _showLocationDialog(
                                              context, theme);
                                          return;
                                        }
                                        // 新建模式：已有坐标/地址时弹对话框（查看/转换/移除）
                                        if (_controller.includeLocation &&
                                            (_controller.newLatitude != null ||
                                                _controller.newLocation !=
                                                    null)) {
                                          await _showNewNoteLocationDialog(
                                              context, theme);
                                          return;
                                        }
                                        // 新建模式：首次勾选，获取位置
                                        if (value) {
                                          if (_controller.newLocation == null &&
                                              _controller.newLatitude == null) {
                                            _ensureMetadataServices();
                                            _controller
                                                .fetchLocationForNewNote();
                                          }
                                          setState(() {
                                            _controller.includeLocation = true;
                                          });
                                          return;
                                        }
                                        // 取消勾选：走 removeNewLocation 一并放掉在途标志。
                                        // 定位还没回来时（上面的弹窗分支进不去）只改勾选，
                                        // 保存会继续等一个结果已经不要了的请求，最多转 5 秒。
                                        _controller.removeNewLocation();
                                      },
                                      selectedColor:
                                          theme.colorScheme.primaryContainer,
                                    ),
                                    // 小红点：有坐标但没地址时提示可更新
                                    if (widget.initialQuote == null &&
                                        _controller.includeLocation &&
                                        _controller.newLocation == null &&
                                        _controller.newLatitude != null &&
                                        _controller.newLongitude != null)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.error,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    if (widget.initialQuote != null &&
                                        _controller.originalLocation == null &&
                                        _controller.originalLatitude != null &&
                                        _controller.originalLongitude != null)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.error,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          SizedBox(width: 8),
                          // 天气信息按钮
                          Builder(
                            builder: (context) {
                              // 仅在需要显示时读取服务，避免每次 build 都触发
                              final weatherService = _cachedWeatherService;
                              final weather = weatherService?.currentWeather;
                              final formattedWeather =
                                  weatherService?.getFormattedWeather(l10n);
                              return Tooltip(
                                message:
                                    weather != null && weatherService != null
                                        ? l10n.addWeatherWithValue(
                                            formattedWeather ?? weather)
                                        : l10n.addWeatherInfo,
                                child: FilterChip(
                                  key: const ValueKey('add_note_weather_chip'),
                                  showCheckmark: false,
                                  avatar: Icon(
                                    weather != null && weatherService != null
                                        ? weatherService.getWeatherIconData()
                                        : Icons.cloud,
                                    color: _controller.includeWeather
                                        ? theme.colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                    size: 18,
                                  ),
                                  label: Text(l10n.weather),
                                  selected: _controller.includeWeather,
                                  onSelected: (value) async {
                                    // 编辑模式下统一弹对话框
                                    if (widget.initialQuote != null) {
                                      await _showWeatherDialog(context, theme);
                                      return;
                                    }
                                    // 新建模式：已勾选天气时，点击弹出详情/移除对话框
                                    if (_controller.includeWeather) {
                                      await _showNewNoteWeatherDialog(
                                          context, theme);
                                      return;
                                    }
                                    // 新建模式：首次勾选
                                    if (value) {
                                      setState(() {
                                        _controller.includeWeather = true;
                                      });
                                      // 勾选时获取天气
                                      _ensureMetadataServices();
                                      _controller.fetchWeatherForNewNote();
                                    } else {
                                      // 同位置：取消勾选要连在途标志一起放掉
                                      _cancelAutoAttachPlan(weather: true);
                                      _controller.removeNewWeather();
                                    }
                                  },
                                  selectedColor:
                                      theme.colorScheme.primaryContainer,
                                ),
                              );
                            },
                          ),
                          SizedBox(width: 8),
                          // 颜色选择按钮
                          Tooltip(
                            message: _selectedColorHex != null
                                ? l10n.cardColorSet
                                : l10n.setCardColor,
                            child: FilterChip(
                              key: const ValueKey('add_note_color_chip'),
                              showCheckmark: false,
                              avatar: _selectedColorHex != null
                                  ? Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Color(
                                          int.parse(
                                                _selectedColorHex!.substring(1),
                                                radix: 16,
                                              ) |
                                              0xFF000000,
                                        ),
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(
                                            color: Colors.white, width: 1),
                                      ),
                                    )
                                  : Icon(
                                      Icons.color_lens,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              label: Text(l10n.color),
                              selected: _selectedColorHex != null,
                              onSelected: (value) {
                                if (value) {
                                  _showCustomColorPicker(context);
                                } else {
                                  setState(() {
                                    _selectedColorHex = null;
                                  });
                                }
                              },
                              selectedColor: theme.colorScheme.primaryContainer,
                            ),
                          ),
                          SizedBox(width: 8),
                        ],
                      ),
                    ), // 标签选择区域
                    SizedBox(height: 16),
                    // ✅ 使用独立组件，避免AddNoteDialog重建时重复构建标签列表
                    Container(
                      key: _tagGuideKey,
                      child: TagSelectionSection(
                        tags: _availableTags,
                        selectedTagIds: _selectedTagIds,
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _selectedTagIds
                              ..clear()
                              ..addAll(newSelection);
                          });
                        },
                        isLoading: _controller.isLoadingHitokotoTags,
                      ),
                    ),

                    // 显示已选标签
                    SelectedTagsDisplay(
                      selectedTagIds: _selectedTagIds,
                      allTags: _availableTags,
                      onRemoveTag: (tagId) {
                        setState(() {
                          _selectedTagIds.remove(tagId);
                        });
                      },
                    ),

                    // AI分析结果
                    if (_aiSummary != null)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(
                            AppShapeTokens.of(context).cardRadius,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  l10n.aiAnalysis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                          color: theme.colorScheme.primary),
                                ),
                                const Spacer(),
                                Tooltip(
                                  message: AppLocalizations.of(context).close,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                      AppShapeTokens.of(context).buttonRadius,
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _aiSummary = null;
                                      });
                                    },
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            MarkdownBody(
                              data: _aiSummary!,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet.fromTheme(
                                theme,
                              ).copyWith(p: theme.textTheme.bodyMedium),
                            ),
                          ],
                        ),
                      ),
                  ],
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // AI助手按钮
                      if (_deferredControlsVisible)
                        AddNoteAIMenu(
                          onOpenAiAssistant: _openAiAssistant,
                        ),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: () => unawaited(_handleCloseRequest()),
                        child: Text(l10n.cancel),
                      ),
                      SizedBox(width: 8),
                      FilledButton(
                        onPressed: (_isLoadingFullQuote || _waitingForFetch)
                            ? null
                            : () async {
                                if (_contentController.text.isNotEmpty) {
                                  await _saveAndExit();
                                }
                              },
                        child: (_isLoadingFullQuote || _waitingForFetch)
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                widget.initialQuote != null
                                    ? AppLocalizations.of(context).edit
                                    : AppLocalizations.of(context).save,
                              ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                ],
              ),
            )),
      ),
    );
  }

  // 自定义颜色选择器
  Future<void> _showCustomColorPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final Color initialColor = _selectedColorHex != null
        ? Color(
            int.parse(_selectedColorHex!.substring(1), radix: 16) | 0xFF000000,
          )
        : Colors.transparent;

    final Color? result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.selectCardColor),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预设颜色网格 - 使用新的无障碍组件
              AccessibleColorGrid(
                selectedColorHex: _selectedColorHex,
                onColorSelected: (color) {
                  if (!mounted) return;
                  Navigator.of(context).pop(color);
                },
              ),

              SizedBox(height: 16),

              // 高级颜色选择按钮
              OutlinedButton.icon(
                icon: Icon(Icons.color_lens),
                label: Text(l10n.customColor),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () async {
                  Navigator.pop(context); // 关闭当前对话框

                  // 打开高级颜色选择器
                  Color selectedColor = initialColor;
                  final Color? advancedColor = await showDialog<Color>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.customColor),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          color: initialColor != Colors.transparent
                              ? initialColor
                              : const Color(0xFFE1F5FE), // 默认蓝色
                          onColorChanged: (color) {
                            selectedColor = color;
                          },
                          width: 40,
                          height: 40,
                          spacing: 10,
                          runSpacing: 10,
                          borderRadius: 20,
                          wheelDiameter: 200,
                          enableShadesSelection: true,
                          pickersEnabled: const {
                            ColorPickerType.primary: true,
                            ColorPickerType.accent: false,
                            ColorPickerType.wheel: true,
                          },
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.cancel),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(selectedColor),
                          child: Text(l10n.select),
                        ),
                      ],
                    ),
                  );

                  if (advancedColor != null && mounted) {
                    setState(() {
                      _selectedColorHex = advancedColor == Colors.transparent
                          ? null
                          : '#${advancedColor.toARGB32().toRadixString(16).substring(2)}'; // MODIFIED
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedColorHex = result == Colors.transparent
            ? null
            : '#${result.toARGB32().toRadixString(16).substring(2)}'; // MODIFIED
      });
    }
  }
}

/// 一段时间窗口内的帧耗时统计。打开阶段和自动附加阶段各算一份。
class _FramePhaseSummary {
  const _FramePhaseSummary({
    required this.frames,
    required this.jank16,
    required this.jank32,
    required this.jank50,
    required this.avgMs,
    required this.worstMs,
    required this.buildAvgMs,
    required this.buildWorstMs,
    required this.rasterAvgMs,
    required this.rasterWorstMs,
  });

  final int frames;
  final int jank16;
  final int jank32;
  final int jank50;
  final double avgMs;
  final double worstMs;
  final double buildAvgMs;
  final double buildWorstMs;
  final double rasterAvgMs;
  final double rasterWorstMs;
}
