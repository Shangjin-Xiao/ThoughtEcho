import 'dart:async';
import 'dart:io' show File;
import 'dart:ui';

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
import '../services/insight_history_service.dart'; // Import InsightHistoryService
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../utils/color_utils.dart';
import '../utils/daily_prompt_generator.dart';
import '../services/ai_card_generation_service.dart';
import '../gen_l10n/app_localizations.dart';
import '../widgets/svg_card_widget.dart';
import '../models/generated_card.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/svg_to_image_service.dart';
import '../utils/feature_guide_helper.dart';
import '../services/draft_service.dart';
import '../widgets/anniversary_animation_overlay.dart';
import '../utils/anniversary_display_utils.dart';
import '../utils/draft_restore_utils.dart';

part 'home/home_page_guides.dart';
part 'home/home_page_dialogs.dart';

class HomePage extends StatefulWidget {
  final int initialPage; // 添加初始页面参数
  final String? initialHighlightedNoteId;

  const HomePage({
    super.key,
    this.initialPage = 0,
    this.initialHighlightedNoteId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
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
  bool _settingsGuidePending = false;
  String? _lastConsumedExcerptText;
  bool _isHandlingExcerptIntent = false;
  bool _hasConsumedInitialHighlightedNote = false;

  // AI卡片生成服务
  AICardGenerationService? _aiCardService;

  // 网络恢复监听
  ConnectivityService? _connectivityService;

  // --- 每日提示相关状态和逻辑 ---
  String _accumulatedPromptText = ''; // Accumulated text for daily prompt
  StreamSubscription<String>?
      _promptSubscription; // Stream subscription for daily prompt
  bool _isGeneratingDailyPrompt = false; // Loading state for daily prompt
  // 获取每日提示的方法
  Future<void> _fetchDailyPrompt({bool initialLoad = false}) async {
    // 如果是初始加载，并且已经有订阅或累积文本，则不重复加载
    if (initialLoad &&
        (_promptSubscription != null || _accumulatedPromptText.isNotEmpty)) {
      logDebug(
        'Daily prompt already loaded or loading, skipping initial fetch.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _accumulatedPromptText = ''; // Clear previous text
      _isGeneratingDailyPrompt = true; // Set loading state
      _promptSubscription?.cancel(); // Cancel previous subscription
      _promptSubscription = null;
    });

    try {
      final aiService = context.read<AIService>();
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();

      // 获取环境信息
      String? city = locationService.city;
      String? weather = weatherService.currentWeather;
      String? temperature = weatherService.temperature;

      // 检查是否启用今日思考AI，或是否有AI配置；不满足则使用本地生成
      final settingsService = context.read<SettingsService>();
      final aiEnabledForToday = settingsService.todayThoughtsUseAI;

      if (!aiEnabledForToday || !aiService.hasValidApiKey()) {
        // 使用本地的每日提示生成器
        final l10n = AppLocalizations.of(context);
        final localPrompt = DailyPromptGenerator.generatePromptBasedOnContext(
          l10n,
          city: city,
          weather: weather,
          temperature: temperature,
        );

        if (mounted) {
          setState(() {
            _accumulatedPromptText = localPrompt;
            _isGeneratingDailyPrompt = false;
          });
        }
        return;
      }

      // 获取最近的周期洞察（本周、上周、本月、上月）
      final insightHistoryService = context.read<InsightHistoryService>();
      final recentInsights =
          await insightHistoryService.formatRecentInsightsForDailyPrompt();
      logDebug('获取到 ${recentInsights.length} 条最近的周期洞察', source: 'HomePage');

      // Call the new stream method with environment context and historical insights
      if (!mounted) {
        return; // Ensure the widget is still mounted after async work
      }

      final l10n = AppLocalizations.of(context);
      final Stream<String> promptStream = aiService.streamGenerateDailyPrompt(
        l10n,
        city: city,
        weather: weather,
        temperature: temperature,
        historicalInsights: recentInsights,
      );

      if (!mounted) {
        return; // Ensure mounted before setting stream and listening
      }

      // Set the stream variable so StreamBuilder can react to connection state changes
      setState(() {});

      // Listen to the stream and accumulate text
      _promptSubscription = promptStream.listen(
        (String chunk) {
          // Append the new chunk and update state to trigger UI rebuild
          if (mounted) {
            setState(() {
              _accumulatedPromptText += chunk;
            });
          }
        },
        onError: (error) {
          // Handle errors - 提供降级策略
          logDebug('获取每日提示流出错: $error，使用本地生成的提示');
          if (mounted) {
            // 生成本地提示作为降级
            final l10n = AppLocalizations.of(context);
            final fallbackPrompt =
                DailyPromptGenerator.generatePromptBasedOnContext(
              l10n,
              city: city,
              weather: weather,
              temperature: temperature,
            );

            setState(() {
              _accumulatedPromptText = fallbackPrompt;
              _isGeneratingDailyPrompt = false; // Stop loading on error
            });

            // 不显示错误信息，只在debug中记录，用户看到的是降级提示
          }
        },
        onDone: () {
          // Stream finished, update loading state and trim the accumulated text
          if (mounted) {
            setState(() {
              _accumulatedPromptText =
                  _accumulatedPromptText.trim(); // 去除前后空白字符
              _isGeneratingDailyPrompt = false; // Stop loading on done
            });
            // 移除每日思考生成完成的弹窗通知
          }
        },
        cancelOnError: true, // Cancel subscription if an error occurs
      );
    } catch (e) {
      logDebug('获取每日提示失败 (setup): $e');
      if (mounted) {
        // 使用本地生成的提示作为降级策略
        final locationService = context.read<LocationService>();
        final weatherService = context.read<WeatherService>();
        final l10n = AppLocalizations.of(context);

        final fallbackPrompt =
            DailyPromptGenerator.generatePromptBasedOnContext(
          l10n,
          city: locationService.city,
          weather: weatherService.currentWeather,
          temperature: weatherService.temperature,
        );

        setState(() {
          _accumulatedPromptText = fallbackPrompt;
          _isGeneratingDailyPrompt = false; // Stop loading on setup error
        });

        // 只在debug模式下显示错误，普通用户看到降级提示即可
        logDebug('AI提示获取失败，已使用本地生成的提示');
      }
    }
  } // --- 每日提示相关状态和逻辑结束 ---

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
        _fetchDailyPrompt(),
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
        final allQuotes = await dbService.getAllQuotes();
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        int updatedCount = 0;

        for (final quote in allQuotes) {
          // 只更新 24 小时内、有坐标但地址为 pending/failed 的笔记
          final quoteDate = DateTime.tryParse(quote.date);
          if (quoteDate == null || quoteDate.isBefore(cutoff)) continue;

          if (LocationService.isNonDisplayMarker(quote.location) &&
              quote.latitude != null &&
              quote.longitude != null) {
            final updatedQuote = quote.copyWith(
              location: resolvedAddress,
            );
            final updateResult = await dbService.updateQuote(updatedQuote);
            switch (updateResult) {
              case QuoteUpdateResult.updated:
                updatedCount++;
                break;
              case QuoteUpdateResult.notFound:
                logWarning('回溯更新离线笔记位置时笔记不存在: ${quote.id}');
                break;
              case QuoteUpdateResult.skippedDeleted:
                logWarning('回溯更新离线笔记位置时笔记已删除: ${quote.id}');
                break;
            }
          }
        }

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
      // 如果初始页面是记录页，优先加载标签数据
      if (widget.initialPage == 1) {
        // 记录页启动时，先加载标签（高优先级）
        await _loadTags();
        _consumeInitialHighlightedNote();
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
    _aiTabController.dispose();
    // 移除生命周期观察器
    WidgetsBinding.instance.removeObserver(this);
    _promptSubscription?.cancel();
    _connectivityService?.removeListener(_onConnectivityChanged);
    super.dispose();
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
      _consumeInitialHighlightedNote();
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
      await _fetchDailyPrompt(initialLoad: true);
    } catch (e) {
      logDebug('初始化位置天气和获取每日提示失败: $e');
      // 即使初始化失败，也尝试获取默认提示
      await _fetchDailyPrompt(initialLoad: true);
    }
  }

  // 处理排序变更
  void _handleSortChanged(String sortType, bool sortAscending) {
    setState(() {
      _sortType = sortType;
      _sortAscending = sortAscending;
    });
  }

  /// 构建首页位置天气显示（保持原有样式，只改文字）
  Widget _buildLocationWeatherDisplay(
    BuildContext context,
    LocationService locationService,
    WeatherService weatherService,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final connectivityService = Provider.of<ConnectivityService>(context);
    final isConnected = connectivityService.isConnected;
    final hasPermission = locationService.hasLocationPermission;
    final isServiceEnabled = locationService.isLocationServiceEnabled;
    final hasCoordinates = locationService.hasCoordinates;
    final hasCity =
        locationService.city != null && locationService.city!.isNotEmpty;
    final hasWeather = weatherService.currentWeather != null &&
        weatherService.currentWeather != 'error' &&
        weatherService.currentWeather != 'unknown';

    String locationText;
    String weatherText;
    IconData weatherIcon;

    // --- 构建天气文本的辅助函数 ---
    String buildWeatherText() {
      return '${WeatherService.getLocalizedWeatherDescription(l10n, weatherService.currentWeather!)}'
          '${weatherService.temperature != null && weatherService.temperature!.isNotEmpty ? ' ${weatherService.temperature}' : ''}';
    }

    // --- 优先级链：位置显示 ---
    if (hasCity) {
      // 有城市信息（可能来自 GPS 解析或手动搜索城市）
      locationText = locationService.getDisplayLocation();
    } else if (hasCoordinates) {
      // 有坐标但没有城市名（离线 GPS 或解析中）
      locationText = LocationService.formatCoordinates(
        locationService.currentPosition!.latitude,
        locationService.currentPosition!.longitude,
      );
    } else if (!isServiceEnabled) {
      // P3: 位置服务未启用（优先于权限文案）
      locationText = l10n.tileLocationServiceOff;
    } else if (!hasPermission) {
      // 有位置服务但没有权限
      locationText = l10n.tileNoLocationPermission;
    } else if (!isConnected) {
      locationText = l10n.tileNoNetwork;
    } else {
      locationText = l10n.tileLoading;
    }

    // --- 优先级链：天气显示 ---
    // P5: 不再把天气显示绑死在权限上；只要有天气数据就显示
    if (hasWeather) {
      weatherText = buildWeatherText();
      weatherIcon = weatherService.getWeatherIconData();
    } else if (!hasCoordinates && !hasCity) {
      // 完全没有位置坐标，天气无法获取
      if (!isConnected) {
        weatherText = l10n.tileOffline;
        weatherIcon = Icons.cloud_off;
      } else {
        weatherText = '--';
        weatherIcon = Icons.cloud_off;
      }
    } else if (isConnected) {
      weatherText = l10n.tileLoading;
      weatherIcon = Icons.cloud_queue;
    } else {
      weatherText = l10n.tileNoWeather;
      weatherIcon = Icons.cloud_off;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
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
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              locationText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '|',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withAlpha(128),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              weatherIcon,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              weatherText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
                        if (isEnglish) {
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: titleWidget,
                          );
                        }
                        return titleWidget;
                      },
                    ),
                    actions: [
                      // 显示服务初始化状态指示器
                      if (!servicesInitialized)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),

                      // 开发者模式下：一周年动画预览按钮
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

                      // 显示位置和天气信息（支持多种状态）
                      _buildLocationWeatherDisplay(
                        context,
                        locationService,
                        weatherService,
                      ),
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
                          ), // 每日提示部分 - 固定在底部，紧凑布局
                          Consumer2<AIService, SettingsService>(
                            builder: (context, aiSvc, settingsSvc, _) {
                              final bool isAiConfigured = aiSvc
                                      .hasValidApiKey() &&
                                  settingsSvc.aiSettings.apiUrl.isNotEmpty &&
                                  settingsSvc.aiSettings.model.isNotEmpty;
                              return Container(
                                width: double.infinity,
                                margin: EdgeInsets.fromLTRB(
                                  screenWidth > 600
                                      ? 16.0
                                      : (isVerySmallScreen
                                          ? 8.0
                                          : 12.0), // 动态调整边距
                                  isVerySmallScreen ? 2.0 : 4.0, // 极小屏幕减少上边距
                                  screenWidth > 600
                                      ? 16.0
                                      : (isVerySmallScreen
                                          ? 8.0
                                          : 12.0), // 动态调整边距
                                  isVerySmallScreen ? 8.0 : 12.0, // 极小屏幕减少下边距
                                ),
                                padding: EdgeInsets.all(
                                  screenWidth > 600
                                      ? 18.0
                                      : (isVerySmallScreen
                                          ? 10.0
                                          : 14.0), // 动态调整内边距
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: AppTheme.defaultShadow,
                                  border: Border.all(
                                    color:
                                        theme.colorScheme.outline.withAlpha(30),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.lightbulb_outline,
                                          color: theme.colorScheme.primary,
                                          size: screenWidth > 600
                                              ? 22
                                              : (isVerySmallScreen
                                                  ? 16
                                                  : 18), // 动态调整图标大小
                                        ),
                                        SizedBox(
                                          width: isVerySmallScreen ? 4 : 6,
                                        ), // 动态调整间距
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).todayThoughts,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: screenWidth > 600
                                                ? 16
                                                : (isVerySmallScreen
                                                    ? 13
                                                    : 15), // 动态调整字体
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      height: isVerySmallScreen
                                          ? 4
                                          : (isSmallScreen ? 6 : 8),
                                    ), // 动态调整间距
                                    // 提示内容区域 - 更紧凑
                                    _isGeneratingDailyPrompt &&
                                            _accumulatedPromptText.isEmpty
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: isVerySmallScreen
                                                    ? 16
                                                    : 18, // 动态调整加载指示器大小
                                                height:
                                                    isVerySmallScreen ? 16 : 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ),
                                              SizedBox(
                                                height: isVerySmallScreen
                                                    ? 3
                                                    : (isSmallScreen ? 4 : 6),
                                              ), // 动态调整间距
                                              Text(
                                                isAiConfigured
                                                    ? AppLocalizations.of(
                                                        context,
                                                      ).loadingTodayThoughts
                                                    : AppLocalizations.of(
                                                        context,
                                                      ).fetchingDefaultPrompt,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withAlpha(160),
                                                  fontSize: screenWidth > 600
                                                      ? 13
                                                      : (isVerySmallScreen
                                                          ? 10
                                                          : 12), // 动态调整字体
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          )
                                        : Text(
                                            _accumulatedPromptText.isNotEmpty
                                                ? _accumulatedPromptText.trim()
                                                : (isAiConfigured
                                                    ? AppLocalizations.of(
                                                        context,
                                                      ).waitingForTodayThoughts
                                                    : AppLocalizations.of(
                                                        context,
                                                      ).noTodayThoughts),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              height: 1.4,
                                              fontSize: screenWidth > 600
                                                  ? 15
                                                  : (isVerySmallScreen
                                                      ? 12
                                                      : 14), // 动态调整字体
                                              color: _accumulatedPromptText
                                                      .isNotEmpty
                                                  ? theme.textTheme.bodyMedium
                                                      ?.color
                                                  : theme.colorScheme.onSurface
                                                      .withAlpha(120),
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: isVerySmallScreen
                                                ? 2
                                                : 3, // 极小屏幕最多2行
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ],
                                ),
                              );
                            },
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
                      onDelete: _showDeleteConfirmDialog,
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
