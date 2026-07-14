import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../controllers/home_page_controller.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/ai_service.dart';
import '../services/clipboard_service.dart';
import '../services/connectivity_service.dart';
import '../services/excerpt_intent_service.dart';
import '../controllers/search_controller.dart'; // 导入搜索控制器
import '../models/quote_model.dart';
import '../widgets/daily_quote_view.dart';
import '../widgets/note_list_view.dart';
import '../widgets/sentry_disclosure_dialog.dart';
import '../widgets/add_note_dialog.dart';
import 'ai_features_page.dart';
import 'settings_page.dart';
import 'ai_assistant_page.dart';
import '../models/ai_assistant_entry.dart';
import '../theme/app_theme.dart';
import 'note_full_editor_page.dart'; // 添加全屏编辑页面导入
import '../services/settings_service.dart'; // Import SettingsService
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../utils/color_utils.dart';
import '../services/ai_card_generation_service.dart';
import '../gen_l10n/app_localizations.dart';
import '../services/draft_service.dart';
import '../services/smart_push_service.dart';
import '../widgets/anniversary_animation_overlay.dart';
import '../utils/anniversary_display_utils.dart';
import '../utils/draft_restore_utils.dart';
import 'home/home_card_actions.dart';
import 'home/home_capture_actions.dart';
import 'home/daily_prompt_panel.dart';
import 'home/home_guide_coordinator.dart';
import 'home/home_refresh_coordinator.dart';
import 'home/home_target_navigation.dart';

// TODO(refactor): Move the remaining note mutation/editor flows into their
// own module. Refresh, targeting, guides, card export and capture already use
// state-owned seams under pages/home/.
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final HomePageController _pageController;

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
  // 通知定位：监听 SmartPushService.pendingTargetNoteId
  SmartPushService? _smartPushService;

  late HomeCardActions _cardActions;
  late final HomeCaptureActions _captureActions;
  late final HomeGuideCoordinator _guideCoordinator;
  late final HomeRefreshCoordinator _refreshCoordinator;
  late final HomeTargetNavigation _targetNavigation;

  // 网络恢复监听
  ConnectivityService? _connectivityService;

  @override
  void initState() {
    super.initState();
    _pageController = HomePageController(initialPage: widget.initialPage)
      ..addListener(_onPageStateChanged);
    _cardActions = HomeCardActions(
      context: context,
      isMounted: () => mounted,
      cardService: null,
    );
    _captureActions = HomeCaptureActions(
      context: context,
      isMounted: () => mounted,
      onInsertText: (text) => _showAddQuoteDialog(prefilledContent: text),
    );
    _guideCoordinator = HomeGuideCoordinator(
      context: context,
      isMounted: () => mounted,
      currentPage: () => _pageController.currentIndex,
      dailyQuoteKey: _dailyQuoteGuideKey,
      noteListKey: _noteListViewKey,
      noteFilterKey: _noteFilterGuideKey,
      noteFavoriteKey: _noteFavoriteGuideKey,
      noteMoreKey: _noteMoreGuideKey,
      noteFoldKey: _noteFoldGuideKey,
      settingsTabKey: _settingsTabGuideKey,
      settingsPageKey: _settingsPageKey,
    );
    _refreshCoordinator = HomeRefreshCoordinator(
      context: context,
      isMounted: () => mounted,
      refreshQuote: () async {
        await _dailyQuoteViewKey.currentState?.refreshQuote();
      },
      refreshPrompt: ({bool initialLoad = false}) async {
        await _dailyPromptPanelKey.currentState?.refreshPrompt(
          initialLoad: initialLoad,
        );
      },
    );
    _targetNavigation = HomeTargetNavigation(
      initialTargetNoteId: widget.initialTargetNoteId,
      currentPage: () => _pageController.currentIndex,
      selectNotesPage: () => _pageController.selectPage(1),
      isTagsLoading: () => _pageController.isLoadingTags,
      ensureTagsLoaded: _loadTags,
      scrollToNote: (noteId) async {
        context.read<NoteSearchController>().clearSearch();
        return await _noteListViewKey.currentState?.scrollToQuoteById(noteId) ??
            false;
      },
    );

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
        _targetNavigation.onNotesReady();
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
      unawaited(_refreshCoordinator.initialize());

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

    final aiService = context.read<AIService>();
    final settingsService = context.read<SettingsService>();
    _cardActions.configure(
      AICardGenerationService(aiService, settingsService),
    );
  }

  @override
  void dispose() {
    // 移除生命周期观察器
    WidgetsBinding.instance.removeObserver(this);
    _connectivityService?.removeListener(_onConnectivityChanged);
    _smartPushService?.removeListener(_onSmartPushServiceChanged);
    _guideCoordinator.dispose();
    _targetNavigation.dispose();
    _pageController
      ..removeListener(_onPageStateChanged)
      ..dispose();
    super.dispose();
  }

  void _onPageStateChanged() {
    if (mounted) setState(() {});
  }

  /// 响应 SmartPushService 的通知定位请求（暖启动路径，无页面重建）
  void _onSmartPushServiceChanged() {
    if (!mounted || _smartPushService == null) return;
    final noteId = _smartPushService!.consumePendingTargetNoteId();
    if (noteId == null || noteId.isEmpty) return;
    logDebug('收到通知定位请求（原地导航）: $noteId', source: 'HomePage');
    unawaited(_targetNavigation.acceptNotificationTarget(noteId));
  }

  /// 网络状态变化回调：恢复联网时自动刷新位置和天气
  void _onConnectivityChanged() {
    final isConnected = _connectivityService?.isConnected ?? false;
    if (isConnected && mounted) {
      logDebug('网络已恢复，自动刷新位置和天气...');
      unawaited(_refreshCoordinator.refreshEnvironment());
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
    if (!mounted || _pageController.isHandlingExcerptIntent) {
      return;
    }

    final settingsService = context.read<SettingsService>();
    if (!settingsService.excerptIntentEnabled) {
      return;
    }

    _pageController.isHandlingExcerptIntent = true;
    try {
      const excerptIntentService = ExcerptIntentService();
      final excerptText =
          await excerptIntentService.consumePendingExcerptText();
      if (!mounted || excerptText == null) {
        return;
      }

      if (_pageController.lastConsumedExcerptText == excerptText) {
        return;
      }

      _pageController.lastConsumedExcerptText = excerptText;
      _showAddQuoteDialog(prefilledContent: excerptText);
    } catch (e) {
      logError('消费外部摘录失败', error: e, source: 'HomePage');
    } finally {
      _pageController.isHandlingExcerptIntent = false;
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
    _pageController.selectPage(index);

    // 当切换到笔记列表页时，重新加载标签
    if (_pageController.currentIndex == 1) {
      _refreshTags();
      _targetNavigation.onNotesReady();
    }

    _triggerGuideForCurrentIndex();
  }

  // 刷新标签列表
  Future<void> _refreshTags() async {
    logDebug('刷新标签列表');
    await _loadTags();
  }

  // 改进标签加载逻辑
  Future<void> _loadTags() async {
    try {
      logDebug('加载标签数据...');
      if (!context.mounted) return; // 添加 mounted 检查
      await _pageController.loadTags(
        context.read<DatabaseService>().getCategories,
      );
      if (mounted) logDebug('标签加载完成，共 ${_pageController.tags.length} 个标签');
    } catch (e) {
      logDebug('加载标签时出错: $e');
    }
  }

  // 预加载标签数据，确保AddNoteDialog打开时数据已准备好
  Future<void> _preloadTags() async {
    try {
      // 使用Future.microtask避免阻塞UI初始化
      await Future.microtask(() async {
        await _loadTags();
      });
    } catch (e) {
      logDebug('预加载标签失败: $e');
    }
  }

  void _triggerGuideForCurrentIndex() {
    _guideCoordinator.triggerForCurrentPage();
  }

  void _handleNoteGuideTargetsReady() {
    _guideCoordinator.onNoteTargetsReady(
      onConsumeTarget: _targetNavigation.onNotesReady,
    );
  }

  void _releaseNoteSearchFocus() {
    _guideCoordinator.unfocusNoteSearch();
  }

  void _scheduleTrashLocationGuide() {
    _guideCoordinator.scheduleTrashLocationGuide();
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
    if (_pageController.isLoadingTags || _pageController.tags.isEmpty) {
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
      if (_pageController.tags.isEmpty) {
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

    logDebug('显示添加笔记对话框，可用标签数: ${_pageController.tags.length}');

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
        tags: _pageController.tags, // 使用预加载的标签数据
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
            allTags: _pageController.tags,
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

  // FAB 长按由捕获模块处理语音与 OCR 的完整交互。
  void _onFABLongPress() {
    unawaited(_captureActions.startVoiceCapture());
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
              allTags: _pageController.tags,
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
          tags: _pageController.tags,
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
      _pageController.trashSnackBarTimer?.cancel();
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
              _pageController.trashSnackBarTimer?.cancel();
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
      _pageController.trashSnackBarTimer = Timer(trashSnackBarDuration, () {
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
      MaterialPageRoute(
        builder: (context) => AIAssistantPage(
          quote: quote,
          entrySource: AIAssistantEntrySource.note,
        ),
      ),
    );
  }

  // AI 卡片模块隐藏生成、预览、分享和保存的完整流程。
  void _generateAICard(Quote quote) {
    unawaited(_cardActions.generateCard(quote));
  }

  // 处理排序变更
  void _handleSortChanged(String sortType, bool sortAscending) {
    _pageController.setSort(type: sortType, ascending: sortAscending);
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
    final scaffoldBackgroundColor = _pageController.currentIndex == 1
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
        appBar: _pageController.currentIndex == 1
            ? null // 记录页不需要标题栏
            : _pageController.currentIndex == 0
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
                : _pageController.currentIndex == 2
                    ? null // 探索页自行处理顶部安全区，避免额外 AppBar 形成色带
                    : AppBar(toolbarHeight: 0),
        body: IndexedStack(
          index: _pageController.currentIndex,
          children: [
            // 首页 - 每日一言和每日提示
            RefreshIndicator(
              onRefresh: _refreshCoordinator.refresh,
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
                      tags: _pageController.tags,
                      selectedTagIds: _pageController.selectedTagIds,
                      onTagSelectionChanged: (tagIds) {
                        _pageController.setSelectedTagIds(tagIds);
                      },
                      searchQuery: searchController.searchQuery,
                      sortType: _pageController.sortType,
                      sortAscending: _pageController.sortAscending,
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
                      isLoadingTags: _pageController.isLoadingTags, // 传递标签加载状态
                      selectedWeathers: _pageController.selectedWeathers,
                      selectedDayPeriods: _pageController.selectedDayPeriods,
                      onFilterChanged: (weathers, dayPeriods) {
                        _pageController.setFilters(
                          weathers: weathers,
                          dayPeriods: dayPeriods,
                        );
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
                selectedIndex: _pageController.currentIndex,
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
                    label: AppLocalizations.of(context).explore,
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
