import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/ai_service.dart';
import '../services/clipboard_service.dart';
import '../controllers/search_controller.dart'; // 导入搜索控制器
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../widgets/daily_quote_view.dart';
import '../widgets/note_list_view.dart';
import '../widgets/add_note_dialog.dart';
import 'insights_page.dart';
import 'settings_page.dart';
import '../theme/app_theme.dart';
import 'note_full_editor_page.dart'; // 添加全屏编辑页面导入
import '../services/settings_service.dart'; // Import SettingsService
import '../utils/app_logger.dart';
import '../utils/daily_prompt_generator.dart';

class HomePage extends StatefulWidget {
  final int initialPage; // 添加初始页面参数

  const HomePage({super.key, this.initialPage = 0});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  List<NoteCategory> _tags = [];
  List<String> _selectedTagIds = [];
  bool _isLoadingTags = true; // 添加标签加载状态标志

  // 排序设置
  String _sortType = 'time';
  bool _sortAscending = false;

  // 搜索控制器
  final _searchController = NoteSearchController();

  late TabController _tabController; // 新增：NoteListView的全局Key
  final GlobalKey<NoteListViewState> _noteListViewKey =
      GlobalKey<NoteListViewState>();
  final GlobalKey<DailyQuoteViewState> _dailyQuoteViewKey =
      GlobalKey<DailyQuoteViewState>();

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

      // 检查是否有AI配置，如果没有则使用本地生成的提示
      if (!aiService.hasValidApiKey()) {
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

      // Call the new stream method with environment context
      final Stream<String> promptStream = aiService.streamGenerateDailyPrompt(
        city: city,
        weather: weather,
        temperature: temperature,
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
    _tabController = TabController(length: 2, vsync: this);

    // 使用传入的初始页面参数
    _currentIndex = widget.initialPage;

    // 初始化时标记为加载中
    setState(() {
      _isLoadingTags = true;
    });

    // 加载标签数据
    _loadTags();

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 保留didChangeDependencies以便将来可能需要监听其他依赖项的变化
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  // 初始化位置和天气服务，然后获取每日提示
  Future<void> _initLocationAndWeatherThenFetchPrompt() async {
    try {
      logDebug('开始初始化位置和天气服务...');

      // 先初始化位置和天气
      await _initLocationAndWeather();

      // 等待位置和天气服务完全初始化
      await Future.delayed(const Duration(milliseconds: 1000));

      logDebug('位置和天气服务初始化完成，开始获取每日提示...');

      // 然后获取每日提示（包含位置和天气信息）
      await _fetchDailyPrompt(initialLoad: true);
    } catch (e) {
      logDebug('初始化位置天气和获取每日提示失败: $e');
      // 即使初始化失败，也尝试获取默认提示
      await _fetchDailyPrompt(initialLoad: true);
    }
  }

  // 初始化位置和天气服务
  Future<void> _initLocationAndWeather() async {
    if (!mounted) return;

    try {
      logDebug('开始初始化位置服务...');
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      await locationService.init();

      logDebug('位置服务初始化完成，权限状态: ${locationService.hasLocationPermission}');

      // 再次确保组件仍然挂载
      if (!mounted) return;

      // 只有在已有位置权限的情况下才尝试获取位置信息，避免再次弹出权限申请
      if (locationService.hasLocationPermission &&
          locationService.isLocationServiceEnabled) {
        logDebug('开始获取当前位置...');
        final position = await locationService.getCurrentLocation(
          skipPermissionRequest: true,
        );

        // 再次确保组件仍然挂载
        if (!mounted) return;

        if (position != null) {
          logDebug('位置获取成功: ${position.latitude}, ${position.longitude}');
          logDebug('开始获取天气数据...');

          final weatherService = Provider.of<WeatherService>(
            context,
            listen: false,
          );
          await weatherService.getWeatherData(
            position.latitude,
            position.longitude,
          );

          logDebug('天气数据获取完成: ${weatherService.currentWeather}');
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

  // 显示添加笔记对话框
  void _showAddQuoteDialog({
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    dynamic hitokotoData,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => AddNoteDialog(
            prefilledContent: prefilledContent,
            prefilledAuthor: prefilledAuthor,
            prefilledWork: prefilledWork,
            hitokotoData: hitokotoData,
            tags: _tags,
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

  // 显示编辑笔记对话框
  void _showEditQuoteDialog(Quote quote) {
    // 检查笔记是否来自全屏编辑器
    if (quote.editSource == 'fullscreen') {
      // 如果是来自全屏编辑器的笔记，则直接打开全屏编辑页面
      try {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => NoteFullEditorPage(
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
        builder:
            (context) => AddNoteDialog(
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
      builder:
          (context) => AlertDialog(
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

  // 显示AI问答对话框
  void _showAIQuestionDialog(Quote quote) {
    final controller = TextEditingController();
    final aiService = context.read<AIService>();
    String currentAnswer = '';
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('问笔记'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: '请输入你的问题'),
                      enabled: !isLoading, // 提问过程中禁用输入框
                    ),
                    if (isLoading) ...[
                      const SizedBox(height: 16),
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 8),
                      const Center(child: Text('正在获取回答...')),
                    ] else if (currentAnswer.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '回答:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(currentAnswer), // 使用 SelectableText 允许复制
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
                TextButton(
                  onPressed:
                      isLoading
                          ? null
                          : () async {
                            // 提问过程中禁用按钮
                            if (controller.text.isEmpty) return;
                            setDialogState(() {
                              isLoading = true;
                              currentAnswer = ''; // 清空之前的回答
                            });
                            try {
                              final stream = aiService.streamAskQuestion(
                                quote,
                                controller.text,
                              );
                              stream.listen(
                                (chunk) {
                                  setDialogState(() {
                                    currentAnswer += chunk;
                                  });
                                },
                                onDone: () {
                                  setDialogState(() {
                                    isLoading = false;
                                  });
                                },
                                onError: (error) {
                                  logDebug('流式问答错误: $error');
                                  setDialogState(() {
                                    isLoading = false;
                                    currentAnswer +=
                                        '\n\n[发生错误: ${error.toString()}]'; // 显示错误信息
                                  });
                                },
                              );
                            } catch (e) {
                              logDebug('提问失败: $e');
                              setDialogState(() {
                                isLoading = false;
                                currentAnswer =
                                    '获取回答失败: ${e.toString()}'; // 显示错误信息
                              });
                            }
                          },
                  child: Text(isLoading ? '' : '提问'), // 提问中不显示文本
                ),
              ],
            );
          },
        );
      },
    );
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
    final settingsService =
        context
            .watch<
              SettingsService
            >(); // Watch SettingsService for settings changes

    // 直接用context.watch<bool>()获取服务初始化状态
    final bool servicesInitialized = context.watch<bool>();

    // Determine if AI is configured (including checking for valid API Key)
    final bool isAiConfigured =
        aiService.hasValidApiKey() &&
        settingsService.aiSettings.apiUrl.isNotEmpty &&
        settingsService.aiSettings.model.isNotEmpty;

    // 使用Provider包装搜索控制器，使其子组件可以访问
    return ChangeNotifierProvider.value(
      value: _searchController,
      child: Scaffold(
        appBar:
            _currentIndex == 1
                ? null // 记录页不需要标题栏
                : AppBar(
                  title: const Text('心迹'),
                  actions: [
                    // 显示标签加载状态
                    if (_isLoadingTags && _currentIndex == 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        ),
                      ),

                    // 显示服务初始化状态指示器
                    if (!servicesInitialized)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        ),
                      ),

                    // 显示位置和天气信息
                    if (_currentIndex == 0 &&
                        locationService.city != null &&
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
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                locationService.getDisplayLocation(),
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '|',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
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
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${WeatherService.getWeatherDescription(weatherService.currentWeather ?? 'unknown')}'
                                '${weatherService.temperature != null && weatherService.temperature!.isNotEmpty ? ' ${weatherService.temperature}' : ''}',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
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

                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: screenHeight, // 确保占满整个屏幕高度
                      child: Column(
                        children: [
                          // 每日一言部分 - 占用大部分空间，但保留足够空间给今日思考
                          Expanded(
                            child: Container(
                              constraints: BoxConstraints(
                                minHeight: screenHeight * 0.45, // 最小45%高度
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

                          // 每日提示部分 - 固定在底部，紧凑布局
                          Container(
                            width: double.infinity,
                            margin: EdgeInsets.fromLTRB(
                              screenWidth > 600 ? 16.0 : 12.0, // 与每日一言左右边距对齐
                              4.0, // 减少上边距
                              screenWidth > 600 ? 16.0 : 12.0, // 与每日一言左右边距对齐
                              12.0, // 减少下边距
                            ),
                            padding: EdgeInsets.all(
                              screenWidth > 600 ? 18.0 : 14.0, // 减少内边距
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
                                      size: screenWidth > 600 ? 22 : 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '今日思考',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize:
                                                screenWidth > 600 ? 16 : 15,
                                          ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: isSmallScreen ? 6 : 8),

                                // 提示内容区域 - 更紧凑
                                _isGeneratingDailyPrompt &&
                                        _accumulatedPromptText.isEmpty
                                    ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        SizedBox(height: isSmallScreen ? 4 : 6),
                                        Text(
                                          isAiConfigured
                                              ? '正在加载今日思考...'
                                              : '正在获取默认提示...',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withAlpha(160),
                                                fontSize:
                                                    screenWidth > 600 ? 13 : 12,
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
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            height: 1.4,
                                            fontSize:
                                                screenWidth > 600 ? 15 : 14,
                                            color:
                                                _accumulatedPromptText
                                                        .isNotEmpty
                                                    ? theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.color
                                                    : theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withAlpha(120),
                                          ),
                                      textAlign: TextAlign.center,
                                      maxLines: 3, // 限制最大行数
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
            Consumer<NoteSearchController>(
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
                  onEdit: _showEditQuoteDialog,
                  onDelete: _showDeleteConfirmDialog,
                  onAskAI: _showAIQuestionDialog,
                  isLoadingTags: _isLoadingTags, // 传递标签加载状态
                );
              },
            ),
            // AI页
            const InsightsPage(),
            // 设置页
            const SettingsPage(),
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
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
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
                    label: 'AI',
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
      ),
    );
  }
}
