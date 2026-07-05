import 'dart:async';
import 'dart:io' show File;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/ai_service.dart';
import '../services/clipboard_service.dart';
import '../services/connectivity_service.dart';
import '../services/excerpt_intent_service.dart';
import '../controllers/search_controller.dart'; // 导入搜索控制器
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../widgets/daily_quote_view.dart';
import '../widgets/note_list_view.dart';
import '../widgets/sentry_disclosure_dialog.dart';
import '../widgets/add_note_dialog.dart';
import '../widgets/local_ai/ocr_capture_page.dart';
import '../widgets/local_ai/ocr_result_sheet.dart';
import '../widgets/local_ai/voice_input_overlay.dart';
import 'ai_features_page.dart';
import 'settings_page.dart';
import 'note_qa_chat_page.dart'; // 添加问笔记聊天页面导入
import '../theme/app_theme.dart';
import 'note_full_editor_page.dart'; // 添加全屏编辑页面导入
import '../services/settings_service.dart'; // Import SettingsService
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../utils/color_utils.dart';
import '../services/ai_card_generation_service.dart';
import '../gen_l10n/app_localizations.dart';
import '../widgets/svg_card_widget.dart';
import '../models/generated_card.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/svg_to_image_service.dart';
import '../utils/feature_guide_helper.dart';
import '../services/draft_service.dart';
import '../services/smart_push_service.dart';
import '../widgets/anniversary_animation_overlay.dart';
import '../utils/anniversary_display_utils.dart';
import '../utils/draft_restore_utils.dart';
import 'home/daily_prompt_panel.dart';

// TODO(refactor): Continue splitting high-churn home features into smaller
// widgets or mixins (e.g., home_header, home_content, home_actions).
class HomePage extends StatefulWidget {
  final int initialPage; // 添加初始页面参数
  final String? initialTargetNoteId;

  const HomePage({
    super.key,
    this.initialPage = 0,
    this.initialTargetNoteId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class HomeLocationWeatherDisplay extends StatelessWidget {
  static const Key chipKey = ValueKey('home.location_weather_chip');

  final String locationText;
  final String weatherText;
  final IconData weatherIcon;

  const HomeLocationWeatherDisplay({
    super.key,
    required this.locationText,
    required this.weatherText,
    required this.weatherIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              boxShadow: AppTheme.defaultShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  locationText,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  '|',
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.withAlpha(128),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  weatherIcon,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  weatherText,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  late TabController _aiTabController; // AI页面的TabController
  List<NoteCategory> _tags = [];
  List<String> _selectedTagIds = [];
  bool _isLoadingTags = true; // 添加标签加载状态标志

  // 排序设置
  String _sortType = 'time';
  bool _sortAscending = false;

  // 筛选设置
  List<String> _selectedWeathers = [];
  List<String> _selectedDayPeriods = [];

  // 新增：NoteListView的全局Key
  final GlobalKey<NoteListViewState> _noteListViewKey =
      GlobalKey<NoteListViewState>();
  final GlobalKey<DailyQuoteViewState> _dailyQuoteViewKey =
      GlobalKey<DailyQuoteViewState>();

  // 功能引导：每日一言的 Key
  final GlobalKey _dailyQuoteGuideKey = GlobalKey();
  final GlobalKey<HomeDailyPromptPanelState> _dailyPromptPanelKey =
      GlobalKey<HomeDailyPromptPanelState>();

  // 功能引导：记录页的 Keys
  final GlobalKey _noteFilterGuideKey = GlobalKey();
  final GlobalKey _noteFavoriteGuideKey = GlobalKey();
  final GlobalKey _noteMoreGuideKey = GlobalKey(); // 功能引导：更多按钮 Key
  final GlobalKey _noteFoldGuideKey = GlobalKey();
  final GlobalKey _settingsTabGuideKey = GlobalKey(); // 功能引导：设置标签 Key（用于回收站引导）
  final GlobalKey<SettingsPageState> _settingsPageKey =
      GlobalKey<SettingsPageState>();
  bool _homeGuidePending = false;
  bool _noteGuidePending = false;
  Timer? _trashSnackBarTimer;
  bool _settingsGuidePending = false;
  bool _trashGuideScheduled = false;
  String? _lastConsumedExcerptText;
  bool _isHandlingExcerptIntent = false;
  bool _hasConsumedInitialTargetNote = false;
  bool _isConsumingInitialTargetNote = false;
  int _initialTargetScrollRetryCount = 0;
  static const int _maxInitialTargetScrollRetries = 8;

  // 通知定位：监听 SmartPushService.pendingTargetNoteId
  SmartPushService? _smartPushService;

  /// 暖启动通知定位的目标 noteId（与 widget.initialTargetNoteId 隔离）
  String? _pendingNotificationNoteId;

  // AI卡片生成服务
  AICardGenerationService? _aiCardService;

  // 网络恢复监听
  ConnectivityService? _connectivityService;

  // 统一刷新方法 - 先刷新位置天气，再同时刷新每日一言和每日提示
  Future<void> _handleRefresh() async {
    try {
      logDebug('开始刷新：先更新位置和天气信息...');

      // 第一步：重新获取位置和天气信息
      await _refreshLocationAndWeather();

      // 等待一下确保位置和天气信息已更新
      await Future.delayed(const Duration(milliseconds: 500));

      logDebug('位置和天气信息更新完成，开始刷新内容...');

      // 第二步：并行刷新每日一言和每日提示（现在有最新的位置天气信息）
      await Future.wait([
        // 刷新每日一言
        if (_dailyQuoteViewKey.currentState != null)
          _dailyQuoteViewKey.currentState!.refreshQuote(),
        // 刷新每日提示（现在会使用最新的位置和天气信息）
        if (_dailyPromptPanelKey.currentState != null)
          _dailyPromptPanelKey.currentState!.refreshPrompt(),
      ]);

      logDebug('刷新完成');
    } catch (e) {
      logDebug('刷新失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).refreshFailed(e.toString()),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 刷新位置和天气信息
  Future<void> _refreshLocationAndWeather() async {
    if (!mounted) return;

    try {
      logDebug('开始刷新位置和天气信息...');

      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final weatherService = Provider.of<WeatherService>(
        context,
        listen: false,
      );
      final connectivityService = Provider.of<ConnectivityService>(
        context,
        listen: false,
      );

      // 先刷新网络状态
      final isConnected = await connectivityService.checkConnectionNow();

      // P4: 动态刷新位置服务和权限状态，防止初始化时的过期值
      await locationService.refreshServiceStatus();

      // 如果有位置权限，重新获取位置和天气
      if (locationService.hasLocationPermission &&
          locationService.isLocationServiceEnabled) {
        logDebug('重新获取当前位置...');
        final position = await locationService.getCurrentLocation(
          skipPermissionRequest: true,
        );

        if (!mounted) return;

        if (position != null) {
          // 联网时尝试解析离线坐标的地址
          if (isConnected && locationService.isOfflineLocation) {
            logDebug('尝试解析离线位置的地址...');
            final resolved = await locationService.resolveOfflineLocation();

            // P1: 地址解析成功后，回溯更新近期离线笔记的位置字段
            if (resolved && mounted) {
              _retroUpdateOfflineNoteLocations(locationService);
            }
          }

          logDebug('位置获取成功，开始刷新天气数据...');
          // 仅联网时强制刷新天气，离线时使用缓存避免冲掉已有数据
          await weatherService.getWeatherData(
            position.latitude,
            position.longitude,
            forceRefresh: isConnected,
          );
          logDebug('天气数据刷新完成: ${weatherService.currentWeather}');
        } else {
          logDebug('位置获取失败');
        }
      } else {
        logDebug('位置权限未授予或位置服务未启用，跳过位置和天气刷新');
      }
    } catch (e) {
      logDebug('刷新位置和天气信息时发生错误: $e');
      // 不抛出异常，让调用方继续执行
    }
  }

  /// P1: 回溯更新近期离线笔记的位置字段
  /// 当网络恢复并成功解析出地址后，更新最近 24 小时内
  /// 带有 pending/failed 位置标记的笔记
  void _retroUpdateOfflineNoteLocations(LocationService locationService) {
    if (!mounted) return;

    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final resolvedAddress = locationService.getLocationDisplayText();
    if (resolvedAddress.isEmpty) return;

    Future.microtask(() async {
      try {
        final updatedCount = await dbService.batchUpdatePendingLocations(
          resolvedAddress: resolvedAddress,
        );

        if (updatedCount > 0) {
          logDebug('P1: 回溯更新了 $updatedCount 条离线笔记的位置信息');
        }
      } catch (e) {
        logDebug('回溯更新离线笔记位置失败: $e');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _aiTabController = TabController(length: 2, vsync: this);

    // 使用传入的初始页面参数
    _currentIndex = widget.initialPage;

    // 注册生命周期观察器
    WidgetsBinding.instance.addObserver(this);

    // 使用延迟方法来确保在UI构建完成后执行初始化
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 注册 SmartPushService 通知定位监听（暖启动路径）
      if (mounted) {
        _smartPushService = Provider.of<SmartPushService>(
          context,
          listen: false,
        );
        _smartPushService!.addListener(_onSmartPushServiceChanged);
        // 检查是否已有待处理的通知定位（可能在 initState 之前就到达了）
        _onSmartPushServiceChanged();
      }

      // 如果初始页面是记录页，优先加载标签数据
      if (widget.initialPage == 1) {
        // 记录页启动时，先加载标签（高优先级）
        await _loadTags();
        _consumeInitialTargetNote();
      } else {
        // 其他页面启动时，使用预加载方式
        _preloadTags();
      }

      // 1. 检查是否有未保存的草稿（最高优先级，阻塞后续弹窗）
      final draftRecovered = await _checkDraftRecovery();

      // 2. 如果没有恢复草稿，再检查剪贴板
      if (!draftRecovered) {
        _checkClipboard();
        _consumePendingExcerptIntent();
      }

      // 如果不是记录页启动，确保标签也被加载
      if (widget.initialPage != 1) {
        _refreshTags();
      }

      // 先初始化位置和天气，然后再获取每日提示
      _initLocationAndWeatherThenFetchPrompt();

      // 监听网络恢复，自动刷新位置和天气
      if (mounted) {
        _connectivityService = Provider.of<ConnectivityService>(
          context,
          listen: false,
        );
        _connectivityService!.addListener(_onConnectivityChanged);
      }

      // 检查是否应该显示一周年庆典动画（在其他检查之后，优先级最低）
      await _checkAndShowAnniversaryAnimation();

      // 检查是否需要显示 Sentry 错误上报提示
      if (mounted) {
        await SentryDisclosureDialog.checkAndShow(context);
      }
    });

    // 根据初始页面尝试触发对应的功能引导
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _triggerGuideForCurrentIndex();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 初始化AI卡片生成服务
    if (_aiCardService == null) {
      final aiService = context.read<AIService>();
      final settingsService = context.read<SettingsService>();
      _aiCardService = AICardGenerationService(aiService, settingsService);
    }
  }

  @override
  void dispose() {
    _trashSnackBarTimer?.cancel();
    _aiTabController.dispose();
    // 移除生命周期观察器
    WidgetsBinding.instance.removeObserver(this);
    _connectivityService?.removeListener(_onConnectivityChanged);
    _smartPushService?.removeListener(_onSmartPushServiceChanged);
    super.dispose();
  }

  /// 响应 SmartPushService 的通知定位请求（暖启动路径，无页面重建）
  void _onSmartPushServiceChanged() {
    if (!mounted || _smartPushService == null) return;
    final noteId = _smartPushService!.consumePendingTargetNoteId();
    if (noteId == null || noteId.isEmpty) return;

    logDebug('收到通知定位请求（原地导航）: $noteId', source: 'HomePage');

    // 切换到记录页 tab
    if (_currentIndex != 1) {
      setState(() {
        _currentIndex = 1;
      });
    }

    // 重置定位状态，触发定位
    _hasConsumedInitialTargetNote = false;
    _isConsumingInitialTargetNote = false;
    _initialTargetScrollRetryCount = 0;
    _pendingNotificationNoteId = noteId;

    // 等标签加载完再定位
    if (_isLoadingTags) {
      _loadTags().then((_) {
        if (mounted) _consumePendingNotificationNote();
      });
    } else {
      // postFrameCallback 确保 tab 切换帧已渲染
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumePendingNotificationNote();
      });
    }
  }

  /// 网络状态变化回调：恢复联网时自动刷新位置和天气
  void _onConnectivityChanged() {
    final isConnected = _connectivityService?.isConnected ?? false;
    if (isConnected && mounted) {
      logDebug('网络已恢复，自动刷新位置和天气...');
      _refreshLocationAndWeather();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用从后台恢复时检查剪贴板
    if (state == AppLifecycleState.resumed) {
      // 确保在Resume状态下使用延迟执行剪贴板检查，避免在UI更新前调用
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkClipboard();
          _consumePendingExcerptIntent();
        }
      });
    }
  }

  Future<void> _consumePendingExcerptIntent() async {
    if (!mounted || _isHandlingExcerptIntent) {
      return;
    }

    final settingsService = context.read<SettingsService>();
    if (!settingsService.excerptIntentEnabled) {
      return;
    }

    _isHandlingExcerptIntent = true;
    try {
      const excerptIntentService = ExcerptIntentService();
      final excerptText =
          await excerptIntentService.consumePendingExcerptText();
      if (!mounted || excerptText == null) {
        return;
      }

      if (_lastConsumedExcerptText == excerptText) {
        return;
      }

      _lastConsumedExcerptText = excerptText;
      _showAddQuoteDialog(prefilledContent: excerptText);
    } catch (e) {
      logError('消费外部摘录失败', error: e, source: 'HomePage');
    } finally {
      _isHandlingExcerptIntent = false;
    }
  }

  // 检查是否应该显示一周年庆典动画（整个周期内只播放一次）
  Future<void> _checkAndShowAnniversaryAnimation() async {
    if (!mounted) return;
    final settingsService = context.read<SettingsService>();
    final settings = settingsService.appSettings;

    final now = DateTime.now();
    final shouldShow = AnniversaryDisplayUtils.shouldAutoShowAnimation(
      now: now,
      developerMode: settings.developerMode,
      anniversaryShown: settings.anniversaryShown,
      anniversaryAnimationEnabled: settings.anniversaryAnimationEnabled,
    );
    if (!shouldShow) {
      return;
    }

    // 标记为已显示
    await settingsService.setAnniversaryShown(true);

    if (!mounted) return;

    // 显示全屏覆盖动画
    await showAnniversaryAnimationOverlay(context);
  }

  /*
  /// 开发者模式预览一周年动画
  /// 一周年开发者模式预览入口已临时关闭，保留给两周年复用。
  void _showAnniversaryPreview(BuildContext context) {
    showAnniversaryAnimationOverlay(context);
  }
  */

  // 检查是否有未保存的草稿
  Future<bool> _checkDraftRecovery() async {
    if (!mounted) return false;

    try {
      final draftData = await DraftService().getLatestDraft();
      if (draftData == null) return false;

      if (!mounted) return false;

      final l10n = AppLocalizations.of(context);
      final shouldRestore = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.draftRecoverTitle),
          content: Text(l10n.draftRecoverMessage),
          actions: [
            TextButton(
              onPressed: () {
                // 用户选择丢弃，删除所有草稿，避免重复提示
                DraftService().deleteAllDrafts();
                Navigator.pop(ctx, false);
              },
              child: Text(
                l10n.discard,
                style: TextStyle(color: Colors.red.shade400),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.restore),
            ),
          ],
        ),
      );

      if (shouldRestore == true && mounted) {
        final draftId = draftData['id'] as String;
        final isNew = draftId.startsWith('new_');

        Quote? initialQuote;
        Quote? original;

        if (!isNew) {
          // 如果是现有笔记，尝试从数据库获取原始信息
          try {
            final db = context.read<DatabaseService>();
            original = await db.getQuoteById(draftId);
            if (original != null) {
              initialQuote = buildRestoredDraftQuote(
                draftData: draftData,
                original: original,
              );
            } else {
              logDebug('恢复草稿时发现原始笔记已删除，将作为新笔记处理');
            }
          } catch (e) {
            logDebug('恢复草稿时获取原始笔记失败: $e');
          }
        }

        initialQuote ??= buildRestoredDraftQuote(
          draftData: draftData,
          original: original,
        );

        // 导航到全屏编辑器
        if (mounted) {
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => NoteFullEditorPage(
                initialContent: initialQuote!.content,
                initialQuote: initialQuote,
                isRestoredDraft: true, // 标记为恢复的草稿
                restoredDraftId: draftId, // 传递恢复草稿的原始ID，确保 key 稳定
                // 如果有标签信息，也可以传递 allTags，但这通常由编辑器自己加载
              ),
            ),
          );

          // 如果保存成功返回，强制刷新列表
          if (saved == true && mounted) {
            logDebug('编辑器保存成功返回，触发列表刷新');
            context.read<DatabaseService>().refreshQuotes();
          }
          return true; // 已处理恢复
        }
      }
    } catch (e) {
      logError('检查草稿恢复失败', error: e, source: 'HomePage');
    }
    return false;
  }

  // 检查剪贴板内容并处理
  Future<void> _checkClipboard() async {
    if (!mounted) return;

    final clipboardService = Provider.of<ClipboardService>(
      context,
      listen: false,
    );

    // 如果剪贴板监控功能未启用，则不进行检查
    if (!clipboardService.enableClipboardMonitoring) {
      logDebug('剪贴板监控已禁用，跳过检查');
      return;
    }

    logDebug('执行剪贴板检查');
    // 检查剪贴板内容
    final clipboardData = await clipboardService.checkClipboard();
    if (clipboardData != null && mounted) {
      // 显示确认对话框
      clipboardService.showClipboardConfirmationDialog(context, clipboardData);
    }
  }

  // 切换到笔记列表时刷新标签
  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // 当切换到笔记列表页时，重新加载标签
    if (_currentIndex == 1) {
      _refreshTags();
      _consumeInitialTargetNote();
    }

    _triggerGuideForCurrentIndex();
  }

  // 刷新标签列表
  Future<void> _refreshTags() async {
    logDebug('刷新标签列表');
    setState(() {
      _isLoadingTags = true;
    });
    await _loadTags();
  }

  // 改进标签加载逻辑
  Future<void> _loadTags() async {
    try {
      logDebug('加载标签数据...');
      if (!context.mounted) return; // 添加 mounted 检查
      final categories = await context.read<DatabaseService>().getCategories();

      if (mounted) {
        setState(() {
          _tags = categories;
          _isLoadingTags = false;
        });
        logDebug('标签加载完成，共 ${categories.length} 个标签');
      }
    } catch (e) {
      logDebug('加载标签时出错: $e');
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }

  // 预加载标签数据，确保AddNoteDialog打开时数据已准备好
  Future<void> _preloadTags() async {
    setState(() {
      _isLoadingTags = true;
    });

    try {
      // 使用Future.microtask避免阻塞UI初始化
      await Future.microtask(() async {
        await _loadTags();
      });
    } catch (e) {
      logDebug('预加载标签失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }

  // 初始化位置和天气服务，然后获取每日提示
  Future<void> _initLocationAndWeatherThenFetchPrompt() async {
    try {
      logDebug('开始初始化位置和天气服务...');

      // 先初始化位置和天气
      await _initLocationAndWeather();

      // 减少等待时间，因为已经优化了并行初始化
      await Future.delayed(const Duration(milliseconds: 300));

      logDebug('位置和天气服务初始化完成，开始获取每日提示...');

      // 然后获取每日提示（包含位置和天气信息）
      await _dailyPromptPanelKey.currentState?.refreshPrompt(
        initialLoad: true,
      );
    } catch (e) {
      logDebug('初始化位置天气和获取每日提示失败: $e');
      // 即使初始化失败，也尝试获取默认提示
      await _dailyPromptPanelKey.currentState?.refreshPrompt(
        initialLoad: true,
      );
    }
  }

  /// 根据当前选中的标签页触发对应的功能引导
  void _triggerGuideForCurrentIndex() {
    switch (_currentIndex) {
      case 0:
        _scheduleHomeGuideIfNeeded();
        break;
      case 1:
        _scheduleNoteGuideIfNeeded();
        break;
      case 3:
        _scheduleSettingsGuideIfNeeded();
        break;
      default:
        break;
    }
  }

  void _scheduleHomeGuideIfNeeded() {
    if (_homeGuidePending) return;
    if (FeatureGuideHelper.hasShown(context, 'homepage_daily_quote')) {
      return;
    }

    _homeGuidePending = true;
    // 立即显示，不等待
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _homeGuidePending = false;
        return;
      }

      if (_currentIndex != 0) {
        _homeGuidePending = false;
        return;
      }

      await _showHomePageGuides();
      _homeGuidePending = false;
    });
  }

  void _scheduleNoteGuideIfNeeded({Duration delay = Duration.zero}) {
    if (_noteGuidePending) return;

    final filterShown = FeatureGuideHelper.hasShown(
      context,
      'note_page_filter',
    );
    final favoriteShown = FeatureGuideHelper.hasShown(
      context,
      'note_page_favorite',
    );
    final expandShown = FeatureGuideHelper.hasShown(
      context,
      'note_page_expand',
    );

    if (filterShown && favoriteShown && expandShown) {
      return;
    }

    _noteGuidePending = true;
    if (delay == Duration.zero) {
      // 立即显示
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _noteGuidePending = false;
          return;
        }

        if (_currentIndex != 1) {
          _noteGuidePending = false;
          return;
        }

        await _showNotePageGuides();
        _noteGuidePending = false;
      });
    } else {
      Future.delayed(delay, () async {
        if (!mounted) {
          _noteGuidePending = false;
          return;
        }

        if (_currentIndex != 1) {
          _noteGuidePending = false;
          return;
        }

        await _showNotePageGuides();
        _noteGuidePending = false;
      });
    }
  }

  void _handleNoteGuideTargetsReady() {
    if (!mounted) return;
    if (_currentIndex != 1) {
      return;
    }

    _consumeInitialTargetNote();
    _scheduleNoteGuideIfNeeded(delay: const Duration(milliseconds: 150));
  }

  void _releaseNoteSearchFocus() {
    _noteListViewKey.currentState?.unfocusSearchField();
  }

  void _consumeInitialTargetNote() {
    if (!mounted ||
        _hasConsumedInitialTargetNote ||
        _isConsumingInitialTargetNote ||
        _currentIndex != 1) {
      return;
    }

    final noteId = widget.initialTargetNoteId;
    if (noteId == null || noteId.isEmpty) {
      return;
    }

    context.read<NoteSearchController>().clearSearch();

    final noteListState = _noteListViewKey.currentState;
    if (noteListState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _consumeInitialTargetNote();
      });
      return;
    }

    _isConsumingInitialTargetNote = true;
    unawaited(_attemptInitialTargetNote(noteListState, noteId));
  }

  Future<void> _attemptInitialTargetNote(
    NoteListViewState noteListState,
    String noteId,
  ) async {
    final success = await noteListState.scrollToQuoteById(noteId);
    if (!mounted || widget.initialTargetNoteId != noteId) {
      _isConsumingInitialTargetNote = false;
      return;
    }

    if (success) {
      _hasConsumedInitialTargetNote = true;
      _initialTargetScrollRetryCount = 0;
      _isConsumingInitialTargetNote = false;
      return;
    }

    _isConsumingInitialTargetNote = false;
    _initialTargetScrollRetryCount++;
    if (_initialTargetScrollRetryCount >= _maxInitialTargetScrollRetries) {
      logDebug(
        '初始目标笔记定位失败，已达到最大重试次数: $noteId',
        source: 'HomePage',
      );
      return;
    }

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || _currentIndex != 1 || _hasConsumedInitialTargetNote) {
        return;
      }
      _consumeInitialTargetNote();
    });
  }

  /// 暖启动通知定位：原地滚动到 [_pendingNotificationNoteId]，不重建页面
  void _consumePendingNotificationNote() {
    final noteId = _pendingNotificationNoteId;
    if (!mounted ||
        _isConsumingInitialTargetNote ||
        noteId == null ||
        noteId.isEmpty ||
        _currentIndex != 1) {
      return;
    }

    context.read<NoteSearchController>().clearSearch();

    final noteListState = _noteListViewKey.currentState;
    if (noteListState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _consumePendingNotificationNote();
      });
      return;
    }

    _isConsumingInitialTargetNote = true;
    unawaited(_attemptPendingNotificationNote(noteListState, noteId));
  }

  Future<void> _attemptPendingNotificationNote(
    NoteListViewState noteListState,
    String noteId,
  ) async {
    final success = await noteListState.scrollToQuoteById(noteId);
    if (!mounted || _pendingNotificationNoteId != noteId) {
      _isConsumingInitialTargetNote = false;
      return;
    }

    if (success) {
      _pendingNotificationNoteId = null;
      _hasConsumedInitialTargetNote = true;
      _initialTargetScrollRetryCount = 0;
      _isConsumingInitialTargetNote = false;
      return;
    }

    _isConsumingInitialTargetNote = false;
    _initialTargetScrollRetryCount++;
    if (_initialTargetScrollRetryCount >= _maxInitialTargetScrollRetries) {
      logDebug(
        '通知定位失败，已达到最大重试次数: $noteId',
        source: 'HomePage',
      );
      _pendingNotificationNoteId = null;
      return;
    }

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || _currentIndex != 1) return;
      _consumePendingNotificationNote();
    });
  }

  void _scheduleSettingsGuideIfNeeded() {
    if (_settingsGuidePending) return;

    final allShown =
        FeatureGuideHelper.hasShown(context, 'settings_preferences') &&
            FeatureGuideHelper.hasShown(context, 'settings_startup') &&
            FeatureGuideHelper.hasShown(context, 'settings_theme');
    if (allShown) {
      return;
    }

    _settingsGuidePending = true;
    // 立即显示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _settingsGuidePending = false;
        return;
      }

      if (_currentIndex != 3) {
        _settingsGuidePending = false;
        return;
      }

      _settingsPageKey.currentState?.showGuidesIfNeeded(
        shouldShow: () => mounted && _currentIndex == 3,
      );
      _settingsGuidePending = false;
    });
  }

  void _scheduleTrashLocationGuide() {
    if (!mounted) return;
    if (_trashGuideScheduled) return;
    if (FeatureGuideHelper.hasShown(context, 'trash_location_guide')) {
      return;
    }

    _trashGuideScheduled = true;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) {
        _trashGuideScheduled = false;
        return;
      }
      FeatureGuideHelper.show(
        context: context,
        guideId: 'trash_location_guide',
        targetKey: _settingsTabGuideKey,
        autoDismissDuration: const Duration(milliseconds: 3000),
        shouldShow: () => mounted,
      );
      _trashGuideScheduled = false;
    });
  }

  /// 显示首页功能引导
  Future<void> _showHomePageGuides() {
    return FeatureGuideHelper.show(
      context: context,
      guideId: 'homepage_daily_quote',
      targetKey: _dailyQuoteGuideKey,
      shouldShow: () => mounted && _currentIndex == 0,
    );
  }

  /// 显示记录页功能引导
  Future<void> _showNotePageGuides() async {
    final noteListState = _noteListViewKey.currentState;
    if (noteListState == null) {
      return;
    }

    final guides = <(String, GlobalKey?)>[];

    if (!FeatureGuideHelper.hasShown(context, 'note_page_filter') &&
        noteListState.isFilterGuideReady) {
      guides.add(('note_page_filter', _noteFilterGuideKey));
    }

    if (!FeatureGuideHelper.hasShown(context, 'note_page_favorite') &&
        noteListState.canShowFavoriteGuide) {
      guides.add(('note_page_favorite', _noteFavoriteGuideKey));
    }

    if (!FeatureGuideHelper.hasShown(context, 'note_page_expand') &&
        noteListState.canShowExpandGuide) {
      guides.add(('note_page_expand', _noteFoldGuideKey));
    }

    if (!FeatureGuideHelper.hasShown(context, 'note_item_more_share') &&
        noteListState.hasQuotes) {
      guides.add(('note_item_more_share', _noteMoreGuideKey));
    }

    if (guides.isEmpty) {
      return;
    }

    await FeatureGuideHelper.showSequence(
      context: context,
      guides: guides,
      shouldShow: () => mounted && _currentIndex == 1,
    );
  }

  // 初始化位置和天气服务 - 简化优化版本
  Future<void> _initLocationAndWeather() async {
    if (!mounted) return;

    try {
      logDebug('开始初始化位置和天气服务...');

      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final weatherService = Provider.of<WeatherService>(
        context,
        listen: false,
      );

      // 并行初始化位置服务（天气服务在WeatherService构造时已经初始化）
      await locationService.init();

      if (!mounted) return;

      logDebug('位置服务初始化完成，权限状态: ${locationService.hasLocationPermission}');

      // 如果有权限，获取位置和天气
      if (locationService.hasLocationPermission &&
          locationService.isLocationServiceEnabled) {
        logDebug('开始获取位置（低精度模式）...');

        final position = await locationService
            .getCurrentLocation(
          highAccuracy: false, // 使用低精度模式，更快
          skipPermissionRequest: true,
        )
            .timeout(
          const Duration(seconds: 8), // 设置超时
          onTimeout: () {
            logDebug('位置获取超时');
            return null;
          },
        );

        if (!mounted) return;

        if (position != null) {
          logDebug('位置获取成功: ${position.latitude}, ${position.longitude}');

          // P10: 冷启动时检查网络状态，联网则强刷天气获取实时数据
          final connectivityService = Provider.of<ConnectivityService>(
            context,
            listen: false,
          );
          final isConnected = connectivityService.isConnected;

          // 异步获取天气，不阻塞主流程（使用事件队列调度，避免 microtask 抢占 UI）
          unawaited(
            weatherService
                .getWeatherData(
                  position.latitude,
                  position.longitude,
                  forceRefresh: isConnected,
                  timeout: const Duration(seconds: 10),
                )
                .then((_) =>
                    logDebug('天气数据更新完成: ${weatherService.currentWeather}'))
                .catchError((e) => logDebug('天气数据更新失败: $e')),
          );
        } else {
          logDebug('位置获取失败');
        }
      } else {
        logDebug('位置权限未授予或位置服务未启用');
      }
    } catch (e) {
      logDebug('初始化位置和天气服务时发生错误: $e');
      // 不抛出异常，让调用方继续执行
    }
  }

  // 显示添加笔记对话框（优化性能）
  void _showAddQuoteDialog({
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    dynamic hitokotoData,
  }) async {
    _releaseNoteSearchFocus();
    FocusScope.of(context).unfocus();
    await _loadTags();
    if (!mounted) return;

    // 确保标签数据已经加载
    if (_isLoadingTags || _tags.isEmpty) {
      logDebug('标签数据未准备好，重新加载标签数据...');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).loadingDataPleaseWait),
          duration: const Duration(seconds: 1),
        ),
      );

      // 强制重新加载标签数据
      await _loadTags();

      // 如果仍然没有标签数据，提示用户
      if (_tags.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noTagsAvailable),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // 检查是否启用跳过非全屏编辑器
    final settingsService = context.read<SettingsService>();
    if (settingsService.skipNonFullscreenEditor) {
      logDebug('跳过非全屏编辑器，直接打开全屏编辑器');
      await _openFullscreenEditorDirectly(
        prefilledContent: prefilledContent,
        prefilledAuthor: prefilledAuthor,
        prefilledWork: prefilledWork,
        hitokotoData: hitokotoData,
      );
      return;
    }

    logDebug('显示添加笔记对话框，可用标签数: ${_tags.length}');

    // 使用延迟显示，确保动画流畅
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      requestFocus: false,
      builder: (context) => AddNoteDialog(
        prefilledContent: prefilledContent,
        prefilledAuthor: prefilledAuthor,
        prefilledWork: prefilledWork,
        hitokotoData: hitokotoData,
        tags: _tags, // 使用预加载的标签数据
        onSave: (quote) => _saveNonFullscreenQuote(
          quote,
          isEditing: false,
        ),
      ),
    );
    if (!mounted) return;
    _releaseNoteSearchFocus();
  }

  Future<void> _saveNonFullscreenQuote(
    Quote quote, {
    required bool isEditing,
  }) async {
    if (!mounted) return;

    final db = context.read<DatabaseService>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    try {
      if (isEditing) {
        final result = await db.updateQuote(quote);
        if (result != QuoteUpdateResult.updated) {
          if (!mounted) return;
          _showNonFullscreenSaveFailure(
            quote,
            isEditing: true,
            message: switch (result) {
              QuoteUpdateResult.notFound => l10n.noteNotFound,
              QuoteUpdateResult.skippedDeleted => l10n.noteUpdateSkippedDeleted,
              QuoteUpdateResult.updated => l10n.noteUpdated,
            },
          );
          return;
        }
      } else {
        await db.addQuote(quote);
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isEditing ? l10n.noteUpdated : l10n.noteSaved),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
      _loadTags();
      // 触发新增/修改笔记卡片的平滑入场动画
      if (quote.id != null) {
        _noteListViewKey.currentState?.triggerInsertAnimation(
          quote.id!,
          animateListInsertion: !isEditing,
        );
      }
    } catch (e, stack) {
      logError(
        '非全屏编辑器保存失败: id=${quote.id}, isEditing=$isEditing',
        error: e,
        stackTrace: stack,
        source: 'HomePage',
      );
      if (!mounted) return;
      _showNonFullscreenSaveFailure(
        quote,
        isEditing: isEditing,
        message: l10n.saveFailedWithError(e.toString()),
      );
    }
  }

  void _showNonFullscreenSaveFailure(
    Quote quote, {
    required bool isEditing,
    required String message,
  }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AppConstants.snackBarDurationError,
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: l10n.retry,
          onPressed: () {
            unawaited(
              _saveNonFullscreenQuote(quote, isEditing: isEditing),
            );
          },
        ),
      ),
    );
  }

  /// 直接打开全屏编辑器（跳过非全屏编辑器）
  Future<void> _openFullscreenEditorDirectly({
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    dynamic hitokotoData,
  }) async {
    try {
      final settingsService = context.read<SettingsService>();
      String content = prefilledContent ?? '';
      String? author = prefilledAuthor;
      String? work = prefilledWork;

      // 处理一言数据
      final isHitokotoQuickAdd = hitokotoData is Map<String, dynamic>;
      if (isHitokotoQuickAdd) {
        content = hitokotoData['hitokoto'] ?? content;
        author = hitokotoData['from_who'] ?? author;
        work = hitokotoData['from'] ?? work;
      }

      final hasExplicitAuthorOrWork = author != null || work != null;

      // 如果没有指定作者/出处，使用默认值
      if (author == null &&
          settingsService.defaultAuthor != null &&
          settingsService.defaultAuthor!.isNotEmpty) {
        author = settingsService.defaultAuthor;
      }
      if (work == null &&
          settingsService.defaultSource != null &&
          settingsService.defaultSource!.isNotEmpty) {
        work = settingsService.defaultSource;
      }

      if (!mounted) return;

      // 导航到全屏编辑器
      // 全屏编辑器会处理自动位置/天气
      // 如果我们传递了作者/出处，跳过编辑器内的默认元数据自动填充
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => NoteFullEditorPage(
            initialContent: content,
            initialQuote: null, // 新建笔记
            allTags: _tags,
            initialAuthor: author,
            initialWork: work,
            skipDefaultMetadataAutofill: hasExplicitAuthorOrWork,
            isFromDailyQuote: isHitokotoQuickAdd, // 标记来自每日一言
          ),
        ),
      );

      // 如果保存成功，通过数据流自动刷新列表
      if (saved == true && mounted) {
        logDebug('全屏编辑器保存成功返回，触发列表刷新');
        _loadTags();
      }
    } catch (e) {
      logError('打开全屏编辑器失败', error: e, source: 'HomePage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).openFullEditorFailedSimple),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // FAB 短按处理
  void _onFABTap() {
    _showAddQuoteDialog();
  }

  // FAB 长按处理 - 显示语音录制浮层
  void _onFABLongPress() {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final localAISettings = settingsService.localAISettings;

    // 检查是否启用了本地AI和语音转文字功能，未启用则直接返回无反应
    if (!localAISettings.enabled || !localAISettings.speechToTextEnabled) {
      return;
    }

    _showVoiceInputOverlay();
  }

  Future<void> _showVoiceInputOverlay() async {
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'voice_input_overlay',
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return VoiceInputOverlay(
          transcribedText: null,
          onSwipeUpForOCR: () async {
            Navigator.of(context).pop();
            await _openOCRFlow();
          },
          onRecordComplete: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(this.context).featureComingSoon,
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(opacity: curved, child: child);
      },
      transitionDuration: const Duration(milliseconds: 180),
    );
  }

  Future<void> _openOCRFlow() async {
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const OCRCapturePage()),
    );

    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    String resultText = l10n.featureComingSoon;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return OCRResultSheet(
          recognizedText: resultText,
          onTextChanged: (text) {
            resultText = text;
          },
          onInsertToEditor: () {
            Navigator.of(context).pop();
            _showAddQuoteDialog(prefilledContent: resultText);
          },
          onRecognizeSource: () {},
        );
      },
    );
  }

  // 显示编辑笔记对话框
  void _showEditQuoteDialog(Quote quote) {
    _releaseNoteSearchFocus();
    FocusScope.of(context).unfocus();
    // 检查笔记是否来自全屏编辑器
    if (quote.editSource == 'fullscreen') {
      // 如果是来自全屏编辑器的笔记，则直接打开全屏编辑页面
      try {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoteFullEditorPage(
              initialContent: quote.content,
              initialQuote: quote,
              allTags: _tags,
            ),
          ),
        );
      } catch (e) {
        // 显示错误信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).cannotOpenFullEditor(e.toString()),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: AppLocalizations.of(context).retry,
                onPressed: () => _showEditQuoteDialog(quote),
                textColor: Colors.white,
              ),
            ),
          );
        }
      }
    } else {
      // 否则，打开常规编辑对话框
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : Theme.of(context).colorScheme.surface,
        requestFocus: false,
        builder: (context) => AddNoteDialog(
          initialQuote: quote,
          tags: _tags,
          onSave: (updatedQuote) => _saveNonFullscreenQuote(
            updatedQuote,
            isEditing: true,
          ),
        ),
      ).whenComplete(() {
        if (mounted) {
          _releaseNoteSearchFocus();
        }
      });
    }
  }

  // 直接将笔记移入回收站（有回收站保障，无需二次确认）
  Future<void> _deleteQuote(Quote quote) async {
    if (!mounted || quote.id == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final db = Provider.of<DatabaseService>(context, listen: false);
    final quoteId = quote.id!;
    try {
      await db.deleteQuote(quoteId);
      if (!mounted) return;
      // 先清除旧 SnackBar，避免多次删除时堆叠
      _trashSnackBarTimer?.cancel();
      const trashSnackBarDuration = Duration(seconds: 3);
      messenger.clearSnackBars();
      final snackBarController = messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.noteMovedToTrash),
          duration: trashSnackBarDuration,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.undoDelete,
            onPressed: () async {
              _trashSnackBarTimer?.cancel();
              try {
                await db.restoreQuote(quoteId);
                if (!mounted) return;
                _noteListViewKey.currentState?.triggerInsertAnimation(
                  quoteId,
                  animateListInsertion: true,
                );
              } catch (e, stack) {
                logError(
                  '撤销删除失败: $e',
                  error: e,
                  stackTrace: stack,
                  source: 'HomePage',
                );
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.restoreFailed),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ),
      );
      _trashSnackBarTimer = Timer(trashSnackBarDuration, () {
        if (mounted) {
          snackBarController.close();
        }
      });
      // 显示回收站位置引导（仅第一次删除笔记时）
      _scheduleTrashLocationGuide();
    } catch (e, stackTrace) {
      logError(
        '移动笔记到回收站失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'HomePage',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.deleteFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 处理心形按钮点击
  void _handleFavoriteClick(Quote quote) async {
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.incrementFavoriteCount(quote.id!);

      // 检查mounted以确保widget还在树中
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      // 显示简洁的反馈
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Text(l10n.favoriteCountWithNum(quote.favoriteCount + 1)),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade400,
        ),
      );
    } catch (e) {
      // 检查mounted以确保widget还在树中
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).favoriteFailed),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 处理心形按钮长按（清除收藏）
  void _handleLongPressFavorite(Quote quote) async {
    if (quote.favoriteCount <= 0) return;

    final l10n = AppLocalizations.of(context);

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearFavoriteTitle),
        content: Text(l10n.clearFavoriteMessage(quote.favoriteCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.resetFavoriteCount(quote.id!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(l10n.clearFavoriteSuccess),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.clearFavoriteFailed),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 显示AI问答聊天界面
  void _showAIQuestionDialog(Quote quote) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: quote)),
    );
  }

  // 生成AI卡片
  void _generateAICard(Quote quote) async {
    if (_aiCardService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).aiCardServiceNotInitialized,
          ),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CardGenerationLoadingDialog(),
    );

    try {
      // 生成卡片
      final card = await _aiCardService!.generateCard(
        note: quote,
        brandName: AppLocalizations.of(context).appTitle,
      );

      // 关闭加载对话框
      if (mounted) Navigator.of(context).pop();

      // 显示卡片预览对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => CardPreviewDialog(
            card: card,
            onShare: (selected) => _shareCard(selected),
            onSave: (selected) => _saveCard(selected),
            onRegenerate: () => _aiCardService!.generateCard(
              note: quote,
              isRegeneration: true,
              brandName: AppLocalizations.of(context).appTitle,
            ),
          ),
        );
      }
    } catch (e) {
      // 关闭加载对话框
      if (mounted) Navigator.of(context).pop();

      // 显示错误信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).generateCardFailed(e.toString()),
            ),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 分享卡片
  Future<void> _shareCard(GeneratedCard card) async {
    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(AppLocalizations.of(context).generatingShareImage),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 生成高质量图片
      final imageBytes = await card.toImageBytes(
        width: 800,
        height: 1200,
        context: context,
        scaleFactor: 2.0,
        renderMode: ExportRenderMode.contain,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = '心迹_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // 分享文件
      await SharePlus.instance.share(
        ShareParams(
          text:
              '来自心迹的精美卡片\n\n"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
          files: [XFile(file.path)],
        ),
      );

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context).cardSharedSuccessfully),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).shareFailed(e.toString()),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 保存卡片
  Future<void> _saveCard(GeneratedCard card) async {
    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(AppLocalizations.of(context).savingCardToGallery),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 保存高质量图片
      final filePath = await _aiCardService!.saveCardAsImage(
        card,
        width: 800,
        height: 1200,
        scaleFactor: 2.0,
        renderMode: ExportRenderMode.contain,
        context: context,
        fileNamePrefix: AppLocalizations.of(context).cardFileNamePrefix,
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.cardSavedToGallery(filePath))),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: l10n.view,
              textColor: Colors.white,
              onPressed: () {
                // 这里可以添加打开相册的逻辑
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).saveFailed(e.toString()),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 处理排序变更
  void _handleSortChanged(String sortType, bool sortAscending) {
    setState(() {
      _sortType = sortType;
      _sortAscending = sortAscending;
    });
  }

  /// 构建首页位置天气显示。
  /// chip 在位置与天气同时就绪后才显示，保持 AppBar 干净：
  /// - 联网时：位置（城市/坐标）AND 天气数据同时可用才淡入
  /// - 离线时：有位置即可显示（无法获取天气，不能永久隐藏）
  /// AnimatedSwitcher 保证 chip 首次出现时淡入一次，页面切回不重复动画。
  Widget _buildLocationWeatherDisplay(
    BuildContext context,
    LocationService locationService,
    WeatherService weatherService,
  ) {
    final l10n = AppLocalizations.of(context);
    final connectivityService = Provider.of<ConnectivityService>(context);
    final isConnected = connectivityService.isConnected;
    final hasCoordinates = locationService.hasCoordinates;
    final hasCity =
        locationService.city != null && locationService.city!.isNotEmpty;
    final hasWeather = weatherService.currentWeather != null &&
        weatherService.currentWeather != 'error' &&
        weatherService.currentWeather != 'unknown';

    final hasRealLocation = hasCity || hasCoordinates;

    // 联网时：位置和天气都就绪才显示，避免天气加载中出现 '--' 中间态；
    // 离线时：有位置即可显示（离线本来就获取不到天气，不能永远不显示）。
    final shouldShow = hasRealLocation && (hasWeather || !isConnected);

    Widget chip;
    if (!shouldShow) {
      // 无 key → AnimatedSwitcher 视为"空"，两者就绪后 chipKey 出现触发一次淡入
      chip = const SizedBox.shrink();
    } else {
      // 位置文字：优先城市名，其次坐标
      final locationText = hasCity
          ? locationService.getDisplayLocation()
          : LocationService.formatCoordinates(
              locationService.currentPosition!.latitude,
              locationService.currentPosition!.longitude,
            );

      // 天气文字：有数据就显示；离线时显示 '--' + 断网图标
      final String weatherText;
      final IconData weatherIcon;
      if (hasWeather) {
        final desc = WeatherService.getLocalizedWeatherDescription(
          l10n,
          weatherService.currentWeather!,
        );
        final temp = (weatherService.temperature?.isNotEmpty ?? false)
            ? ' ${weatherService.temperature}'
            : '';
        weatherText = '$desc$temp';
        weatherIcon = weatherService.getWeatherIconData();
      } else {
        // 离线且无天气缓存
        weatherText = '--';
        weatherIcon = Icons.cloud_off;
      }

      chip = HomeLocationWeatherDisplay(
        key: HomeLocationWeatherDisplay.chipKey,
        locationText: locationText,
        weatherText: weatherText,
        weatherIcon: weatherIcon,
      );
    }

    // key 变化时（null → chipKey）AnimatedSwitcher 触发淡入；
    // 页面切回时 key 不变，直接复用，无动画。
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: chip,
    );
  }

  @override
  Widget build(BuildContext context) {
    final weatherService = Provider.of<WeatherService>(context);
    final locationService = Provider.of<LocationService>(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 直接用context.watch<bool>()获取服务初始化状态（仅变化一次）
    final bool servicesInitialized = context.watch<bool>();

    // 修复：根据当前页面动态设置背景色，确保底部安全区域颜色正确
    // 记录页使用专属背景色，其他页面使用通用页面背景色
    final scaffoldBackgroundColor = _currentIndex == 1
        ? ColorUtils.getNoteListBackgroundColor(
            theme.colorScheme.surface,
            theme.brightness,
          )
        : ColorUtils.getPageBackgroundColor(
            theme.colorScheme.surface,
            theme.brightness,
          );

    final systemUiOverlayStyle = _buildSystemUiOverlayStyle(
      theme,
      scaffoldBackgroundColor,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiOverlayStyle,
      child: Scaffold(
        // BottomSheet 已自行处理键盘 inset，关闭 Scaffold 级重排，
        // 避免首页背景（如每日一言）在非全屏编辑器弹出/收起时跟随位移。
        resizeToAvoidBottomInset: false,
        backgroundColor: scaffoldBackgroundColor,
        appBar: _currentIndex == 1
            ? null // 记录页不需要标题栏
            : _currentIndex == 0
                ? AppBar(
                    automaticallyImplyLeading: false,
                    leadingWidth: NavigationToolbar.kMiddleSpacing,
                    leading: const SizedBox.shrink(),
                    titleSpacing: 0, // 左侧保留默认留白，且让标题充分利用空间
                    title: Consumer<ConnectivityService>(
                      builder: (context, connectivityService, child) {
                        final locale = Localizations.localeOf(context);
                        final isEnglish = locale.languageCode == 'en';

                        Widget titleWidget;
                        if (!connectivityService.isConnected) {
                          titleWidget = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.wifi_off,
                                size: 16,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                  AppLocalizations.of(context).appTitleOffline),
                            ],
                          );
                        } else {
                          titleWidget =
                              Text(AppLocalizations.of(context).appTitle);
                        }

                        // 英文标题使用 FittedBox 自动缩放以完整显示，不显示省略号
                        // 中文标题本身很短，不需要特殊处理
                        final Widget titleContent;
                        if (isEnglish) {
                          titleContent = FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: titleWidget,
                          );
                        } else {
                          titleContent = titleWidget;
                        }

                        return Row(
                          children: [
                            titleContent,
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildLocationWeatherDisplay(
                                context,
                                locationService,
                                weatherService,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    actions: [
                      if (!servicesInitialized && kDebugMode)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),

                      /*
                      // 一周年开发者模式预览入口已临时关闭，保留给两周年复用。
                      Consumer<SettingsService>(
                        builder: (context, settingsSvc, _) {
                          if (!settingsSvc.appSettings.developerMode) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            icon: const Icon(Icons.cake_outlined),
                            tooltip: l10n.developerAnniversaryPreview,
                            onPressed: () => _showAnniversaryPreview(context),
                          );
                        },
                      ),
                      */
                    ],
                  )
                : AppBar(toolbarHeight: 0),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            // 首页 - 每日一言和每日提示
            RefreshIndicator(
              onRefresh: _handleRefresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenHeight = constraints.maxHeight;
                  final screenWidth = constraints.maxWidth;
                  final isSmallScreen = screenHeight < 600;
                  final isVerySmallScreen = screenHeight < 550;

                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: screenHeight, // 确保占满整个屏幕高度
                      child: Column(
                        children: [
                          // 每日一言部分 - 占用大部分空间，但保留足够空间给今日思考
                          Expanded(
                            child: Container(
                              key: _dailyQuoteGuideKey, // 功能引导 key
                              constraints: BoxConstraints(
                                minHeight: screenHeight *
                                    (isVerySmallScreen
                                        ? 0.55
                                        : 0.50), // 极小屏幕调整比例
                              ),
                              child: DailyQuoteView(
                                key: _dailyQuoteViewKey,
                                onAddQuote:
                                    (content, author, work, hitokotoData) =>
                                        _showAddQuoteDialog(
                                  prefilledContent: content,
                                  prefilledAuthor: author,
                                  prefilledWork: work,
                                  hitokotoData: hitokotoData,
                                ),
                              ),
                            ),
                          ),
                          HomeDailyPromptPanel(
                            key: _dailyPromptPanelKey,
                            screenWidth: screenWidth,
                            isSmallScreen: isSmallScreen,
                            isVerySmallScreen: isVerySmallScreen,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // 笔记列表页
            Consumer<SettingsService>(
              builder: (context, settingsService, child) {
                return Consumer<NoteSearchController>(
                  builder: (context, searchController, child) {
                    return NoteListView(
                      key: _noteListViewKey, // 绑定全局Key
                      tags: _tags,
                      selectedTagIds: _selectedTagIds,
                      onTagSelectionChanged: (tagIds) {
                        setState(() {
                          _selectedTagIds = tagIds;
                        });
                      },
                      searchQuery: searchController.searchQuery,
                      sortType: _sortType,
                      sortAscending: _sortAscending,
                      onSortChanged: _handleSortChanged,
                      onSearchChanged: (query) {
                        searchController.updateSearch(query);
                      },
                      onEdit: _showEditQuoteDialog,
                      onDelete: _deleteQuote,
                      onAskAI: _showAIQuestionDialog,
                      onGenerateCard: _generateAICard,
                      onFavorite: settingsService.showFavoriteButton
                          ? _handleFavoriteClick
                          : null, // 根据设置控制心形按钮显示
                      onLongPressFavorite: settingsService.showFavoriteButton
                          ? _handleLongPressFavorite
                          : null, // 长按清除收藏
                      isLoadingTags: _isLoadingTags, // 传递标签加载状态
                      selectedWeathers: _selectedWeathers,
                      selectedDayPeriods: _selectedDayPeriods,
                      onFilterChanged: (weathers, dayPeriods) {
                        setState(() {
                          _selectedWeathers = weathers;
                          _selectedDayPeriods = dayPeriods;
                        });
                      },
                      filterButtonKey: _noteFilterGuideKey, // 功能引导 key
                      favoriteButtonGuideKey: _noteFavoriteGuideKey,
                      moreButtonGuideKey: _noteMoreGuideKey,
                      foldToggleGuideKey: _noteFoldGuideKey,
                      onGuideTargetsReady: _handleNoteGuideTargetsReady,
                    );
                  },
                );
              },
            ),
            // AI页
            const AIFeaturesPage(),
            // 设置页
            SettingsPage(key: _settingsPageKey),
          ],
        ),
        floatingActionButton: Semantics(
          button: true,
          label: '${l10n.add} / ${l10n.voiceInputTitle}',
          child: GestureDetector(
            onLongPressStart: (_) => _onFABLongPress(),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.accentShadow,
              ),
              child: FloatingActionButton(
                heroTag: 'homePageFAB',
                tooltip: '${l10n.add} / ${l10n.voiceInputTitle}',
                onPressed: _onFABTap,
                elevation: 0,
                backgroundColor: theme
                    .floatingActionButtonTheme.backgroundColor, // 使用主题定义的颜色
                foregroundColor: theme
                    .floatingActionButtonTheme.foregroundColor, // 使用主题定义的颜色
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0), // 毛玻璃模糊效果
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(
                  alpha: 0.8,
                ), // 半透明背景
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  _onTabChanged(index);
                },
                elevation: 0,
                backgroundColor: Colors.transparent, // 透明背景以显示模糊效果
                surfaceTintColor: Colors.transparent, // 移除表面着色
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: Icon(
                      Icons.home,
                      color: theme.colorScheme.primary,
                    ),
                    label: AppLocalizations.of(context).navHome,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.book_outlined),
                    selectedIcon: Icon(
                      Icons.book,
                      color: theme.colorScheme.primary,
                    ),
                    label: AppLocalizations.of(context).navNotes,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(
                      Icons.auto_awesome,
                      color: theme.colorScheme.primary,
                    ),
                    label: AppLocalizations.of(context).navInsights,
                  ),
                  NavigationDestination(
                    key: _settingsTabGuideKey, // 功能引导 key
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: Icon(
                      Icons.settings,
                      color: theme.colorScheme.primary,
                    ),
                    label: AppLocalizations.of(context).navSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  SystemUiOverlayStyle _buildSystemUiOverlayStyle(
    ThemeData theme,
    Color navColor,
  ) {
    final navBrightness = ThemeData.estimateBrightnessForColor(navColor);
    final bool navIconsShouldBeDark = navBrightness == Brightness.light;
    final bool statusIconsShouldBeDark = theme.brightness == Brightness.light;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          statusIconsShouldBeDark ? Brightness.dark : Brightness.light,
      statusBarBrightness:
          statusIconsShouldBeDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: navColor,
      systemNavigationBarIconBrightness:
          navIconsShouldBeDark ? Brightness.dark : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
  }
}
