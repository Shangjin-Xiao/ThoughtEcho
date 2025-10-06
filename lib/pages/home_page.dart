import 'dart:async';
import 'dart:io' show File;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/ai_service.dart';
import '../services/clipboard_service.dart';
import '../services/connectivity_service.dart';
import '../controllers/search_controller.dart'; // 导入搜索控制器
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../widgets/daily_quote_view.dart';
import '../widgets/note_list_view.dart';
import '../widgets/add_note_dialog.dart';
import 'ai_features_page.dart';
import 'settings_page.dart';
import 'note_qa_chat_page.dart'; // 添加问笔记聊天页面导入
import '../theme/app_theme.dart';
import 'note_full_editor_page.dart'; // 添加全屏编辑页面导入
import '../services/settings_service.dart'; // Import SettingsService
import '../services/insight_history_service.dart'; // Import InsightHistoryService
import '../utils/lottie_animation_manager.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../utils/daily_prompt_generator.dart';
import '../services/ai_card_generation_service.dart';
import '../widgets/svg_card_widget.dart';
import '../models/generated_card.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/svg_to_image_service.dart';
import '../utils/feature_guide_helper.dart';

class HomePage extends StatefulWidget {
  final int initialPage; // 添加初始页面参数

  const HomePage({super.key, this.initialPage = 0});

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
  final GlobalKey _noteFoldGuideKey = GlobalKey();
  final GlobalKey<SettingsPageState> _settingsPageKey =
    GlobalKey<SettingsPageState>();
  bool _homeGuidePending = false;
  bool _noteGuidePending = false;
  bool _settingsGuidePending = false;

  // AI卡片生成服务
  AICardGenerationService? _aiCardService;

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
        final localPrompt = DailyPromptGenerator.generatePromptBasedOnContext(
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
      final Stream<String> promptStream = aiService.streamGenerateDailyPrompt(
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
            final fallbackPrompt =
                DailyPromptGenerator.generatePromptBasedOnContext(
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

        final fallbackPrompt =
            DailyPromptGenerator.generatePromptBasedOnContext(
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
            content: Text('刷新失败: ${e.toString()}'),
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

      // 如果有位置权限，重新获取位置和天气
      if (locationService.hasLocationPermission &&
          locationService.isLocationServiceEnabled) {
        logDebug('重新获取当前位置...');
        final position = await locationService.getCurrentLocation(
          skipPermissionRequest: true,
        );

        if (!mounted) return;

        if (position != null) {
          logDebug('位置获取成功，开始刷新天气数据...');
          // 强制刷新天气数据
          await weatherService.getWeatherData(
            position.latitude,
            position.longitude,
            forceRefresh: true,
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

  @override
  void initState() {
    super.initState();
    _aiTabController = TabController(length: 2, vsync: this);

    // 使用传入的初始页面参数
    _currentIndex = widget.initialPage;

    // 预先加载标签数据，确保点击加号按钮时数据已准备好
    _preloadTags();

    // 注册生命周期观察器
    WidgetsBinding.instance.addObserver(this);

    // 使用延迟方法来确保在UI构建完成后执行剪贴板检查，避免冷启动问题
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 首次进入应用时检查剪贴板
      _checkClipboard();

      // 确保标签在应用完全初始化后加载
      _refreshTags();

      // 先初始化位置和天气，然后再获取每日提示
      _initLocationAndWeatherThenFetchPrompt();
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
    _promptSubscription?.cancel(); // Cancel daily prompt subscription
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用从后台恢复时检查剪贴板
    if (state == AppLifecycleState.resumed) {
      // 确保在Resume状态下使用延迟执行剪贴板检查，避免在UI更新前调用
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkClipboard();
        }
      });
    }
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

  void _scheduleNoteGuideIfNeeded({
    Duration delay = Duration.zero,
  }) {
    if (_noteGuidePending) return;

    final filterShown =
        FeatureGuideHelper.hasShown(context, 'note_page_filter');
    final favoriteShown =
        FeatureGuideHelper.hasShown(context, 'note_page_favorite');
    final expandShown =
        FeatureGuideHelper.hasShown(context, 'note_page_expand');

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

    _scheduleNoteGuideIfNeeded(delay: const Duration(milliseconds: 150));
  }

  void _scheduleSettingsGuideIfNeeded() {
    if (_settingsGuidePending) return;

    final allShown = FeatureGuideHelper.hasShown(context, 'settings_preferences') &&
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

          // 异步获取天气，不阻塞主流程
          Future.microtask(() async {
            try {
              await weatherService.getWeatherData(
                position.latitude,
                position.longitude,
                timeout: const Duration(seconds: 10),
              );
              logDebug('天气数据更新完成: ${weatherService.currentWeather}');
            } catch (e) {
              logDebug('天气数据更新失败: $e');
            }
          });
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
    // 确保标签数据已经加载
    if (_isLoadingTags || _tags.isEmpty) {
      logDebug('标签数据未准备好，重新加载标签数据...');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在加载数据，请稍等...'),
          duration: Duration(seconds: 1),
        ),
      );

      // 强制重新加载标签数据
      await _loadTags();

      // 如果仍然没有标签数据，提示用户
      if (_tags.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('暂无标签数据，请检查网络连接或稍后重试'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    logDebug('显示添加笔记对话框，可用标签数: ${_tags.length}');

    // 使用延迟显示，确保动画流畅
    Future.microtask(() {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          builder: (context) => AddNoteDialog(
            prefilledContent: prefilledContent,
            prefilledAuthor: prefilledAuthor,
            prefilledWork: prefilledWork,
            hitokotoData: hitokotoData,
            tags: _tags, // 使用预加载的标签数据
            onSave: (_) {
              // 笔记保存后刷新标签列表
              _loadTags();
              // 新增：强制刷新NoteListView
              if (_noteListViewKey.currentState != null) {
                _noteListViewKey.currentState!.resetAndLoad();
              }
            },
          ),
        );
      }
    });
  }

  // 显示编辑笔记对话框
  void _showEditQuoteDialog(Quote quote) {
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
              content: Text('无法打开全屏编辑器: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: '重试',
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
        builder: (context) => AddNoteDialog(
          initialQuote: quote,
          tags: _tags,
          onSave: (_) {
            // 笔记更新后刷新标签列表
            _loadTags();
          },
        ),
      );
    }
  }

  // 显示删除确认对话框
  void _showDeleteConfirmDialog(Quote quote) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: const Text('确定要删除这条笔记吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              final db = Provider.of<DatabaseService>(
                context,
                listen: false,
              );
              db.deleteQuote(quote.id!);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('笔记已删除'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // 处理心形按钮点击
  void _handleFavoriteClick(Quote quote) async {
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.incrementFavoriteCount(quote.id!);

      // 检查mounted以确保widget还在树中
      if (!mounted) return;

      // 显示简洁的反馈
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.favorite,
                color: Colors.red,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text('已珍藏 (${quote.favoriteCount + 1})'),
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
        const SnackBar(
          content: Text('收藏失败，请重试'),
          duration: Duration(seconds: 2),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(
        content: Text('AI卡片服务未初始化'),
        duration: AppConstants.snackBarDurationError,
      ));
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
      final card = await _aiCardService!.generateCard(note: quote);

      // 关闭加载对话框
      if (mounted) Navigator.of(context).pop();

      // 显示卡片预览对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => CardPreviewDialog(
            card: card,
            onShare: () => _shareCard(card),
            onSave: () => _saveCard(card),
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
            content: Text('生成卡片失败: $e'),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 分享卡片
  void _shareCard(GeneratedCard card) async {
    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('正在生成分享图片...'),
              ],
            ),
            duration: Duration(seconds: 3),
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
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('卡片分享成功'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
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
                Expanded(child: Text('分享失败: $e')),
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
  void _saveCard(GeneratedCard card) async {
    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('正在保存卡片到相册...'),
              ],
            ),
            duration: Duration(seconds: 3),
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
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('卡片已保存到相册: $filePath')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '查看',
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
                Expanded(child: Text('保存失败: $e')),
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

  @override
  Widget build(BuildContext context) {
    final weatherService = Provider.of<WeatherService>(context);
    final locationService = Provider.of<LocationService>(context);
    final theme = Theme.of(context);
    final aiService =
        context.watch<AIService>(); // Watch AIService for key changes
    final settingsService = context
        .watch<SettingsService>(); // Watch SettingsService for settings changes

    // 直接用context.watch<bool>()获取服务初始化状态
    final bool servicesInitialized = context.watch<bool>();

    // Determine if AI is configured (including checking for valid API Key)
    final bool isAiConfigured = aiService.hasValidApiKey() &&
        settingsService.aiSettings.apiUrl.isNotEmpty &&
        settingsService.aiSettings.model.isNotEmpty;

    // 使用Provider包装搜索控制器，使其子组件可以访问
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surface,
      appBar: _currentIndex == 1
          ? null // 记录页不需要标题栏
          : _currentIndex == 0
              ? AppBar(
                  title: Consumer<ConnectivityService>(
                    builder: (context, connectivityService, child) {
                      if (!connectivityService.isConnected) {
                        return const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off, size: 16, color: Colors.red),
                            SizedBox(width: 4),
                            Text('心迹 - 无网络'),
                          ],
                        );
                      }
                      return const Text('心迹');
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
                          child: EnhancedLottieAnimation(
                            type: LottieAnimationType.pulseLoading,
                            width: 20,
                            height: 20,
                            semanticLabel: '初始化服务',
                          ),
                        ),
                      ),

                    // 显示位置和天气信息
                    if (locationService.city != null &&
                        !locationService.city!.contains("Throttled!") &&
                        weatherService.currentWeather != null &&
                        locationService.hasLocationPermission)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(
                              AppTheme.cardRadius,
                            ),
                            boxShadow: AppTheme.defaultShadow,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                locationService.getDisplayLocation(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '|',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer
                                          .withAlpha(128),
                                    ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                weatherService.getWeatherIconData(),
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${WeatherService.getWeatherDescription(weatherService.currentWeather ?? 'unknown')}'
                                '${weatherService.temperature != null && weatherService.temperature!.isNotEmpty ? ' ${weatherService.temperature}' : ''}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
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
                                  (isVerySmallScreen ? 0.55 : 0.50), // 极小屏幕调整比例
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
                        Container(
                          width: double.infinity,
                          margin: EdgeInsets.fromLTRB(
                            screenWidth > 600
                                ? 16.0
                                : (isVerySmallScreen ? 8.0 : 12.0), // 动态调整边距
                            isVerySmallScreen ? 2.0 : 4.0, // 极小屏幕减少上边距
                            screenWidth > 600
                                ? 16.0
                                : (isVerySmallScreen ? 8.0 : 12.0), // 动态调整边距
                            isVerySmallScreen ? 8.0 : 12.0, // 极小屏幕减少下边距
                          ),
                          padding: EdgeInsets.all(
                            screenWidth > 600
                                ? 18.0
                                : (isVerySmallScreen ? 10.0 : 14.0), // 动态调整内边距
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.defaultShadow,
                            border: Border.all(
                              color: theme.colorScheme.outline.withAlpha(30),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
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
                                      width:
                                          isVerySmallScreen ? 4 : 6), // 动态调整间距
                                  Text(
                                    '今日思考',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
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
                                      : (isSmallScreen ? 6 : 8)), // 动态调整间距

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
                                          height: isVerySmallScreen ? 16 : 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        SizedBox(
                                            height: isVerySmallScreen
                                                ? 3
                                                : (isSmallScreen
                                                    ? 4
                                                    : 6)), // 动态调整间距
                                        Text(
                                          isAiConfigured
                                              ? '正在加载今日思考...'
                                              : '正在获取默认提示...',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme.colorScheme.onSurface
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
                                              ? '等待今日思考...'
                                              : '暂无今日思考'),
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        height: 1.4,
                                        fontSize: screenWidth > 600
                                            ? 15
                                            : (isVerySmallScreen
                                                ? 12
                                                : 14), // 动态调整字体
                                        color: _accumulatedPromptText.isNotEmpty
                                            ? theme.textTheme.bodyMedium?.color
                                            : theme.colorScheme.onSurface
                                                .withAlpha(120),
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines:
                                          isVerySmallScreen ? 2 : 3, // 极小屏幕最多2行
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ],
                          ),
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
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.accentShadow,
        ),
        child: FloatingActionButton(
          heroTag: 'homePageFAB',
          onPressed: () => _showAddQuoteDialog(),
          elevation: 0,
          backgroundColor:
              theme.floatingActionButtonTheme.backgroundColor, // 使用主题定义的颜色
          foregroundColor:
              theme.floatingActionButtonTheme.foregroundColor, // 使用主题定义的颜色
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0), // 毛玻璃模糊效果
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.8), // 半透明背景
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
                  label: '首页',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.book_outlined),
                  selectedIcon: Icon(
                    Icons.book,
                    color: theme.colorScheme.primary,
                  ),
                  label: '记录',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(
                    Icons.auto_awesome,
                    color: theme.colorScheme.primary,
                  ),
                  label: '洞察',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: Icon(
                    Icons.settings,
                    color: theme.colorScheme.primary,
                  ),
                  label: '设置',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
