import 'dart:async';
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

  late TabController _tabController;

  // 新增：NoteListView的全局Key
  final GlobalKey<NoteListViewState> _noteListViewKey =
      GlobalKey<NoteListViewState>();

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
    _initLocationAndWeather();

    // 注册生命周期观察器
    WidgetsBinding.instance.addObserver(this);

    // 使用延迟方法来确保在UI构建完成后执行剪贴板检查，避免冷启动问题
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 首次进入应用时检查剪贴板
      _checkClipboard();

      // 确保标签在应用完全初始化后加载
      _refreshTags();
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
      debugPrint('剪贴板监控已禁用，跳过检查');
      return;
    }

    debugPrint('执行剪贴板检查');
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
    debugPrint('刷新标签列表');
    setState(() {
      _isLoadingTags = true;
    });
    await _loadTags();
  }

  // 改进标签加载逻辑
  Future<void> _loadTags() async {
    try {
      debugPrint('加载标签数据...');
      if (!context.mounted) return; // 添加 mounted 检查
      final categories = await context.read<DatabaseService>().getCategories();

      if (mounted) {
        setState(() {
          _tags = categories;
          _isLoadingTags = false;
        });
        debugPrint('标签加载完成，共 ${categories.length} 个标签');
      }
    } catch (e) {
      debugPrint('加载标签时出错: $e');
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }

  // 初始化位置和天气服务
  Future<void> _initLocationAndWeather() async {
    if (!mounted) return;

    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    await locationService.init();

    // 确保组件仍然挂载
    if (!mounted) return;

    // 只有在已有位置权限的情况下才尝试获取位置信息，避免再次弹出权限申请
    if (locationService.hasLocationPermission &&
        locationService.isLocationServiceEnabled) {
      final position = await locationService.getCurrentLocation(
        skipPermissionRequest: true,
      );

      // 再次确保组件仍然挂载
      if (!mounted) return;

      if (position != null) {
        final weatherService = Provider.of<WeatherService>(
          context,
          listen: false,
        );
        await weatherService.getWeatherData(
          position.latitude,
          position.longitude,
        );
      }
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
        ).then((value) {
          if (value == true) {
            // 编辑成功后强制刷新列表
            if (_noteListViewKey.currentState != null) {
              _noteListViewKey.currentState!.resetAndLoad();
            }
          }
        });
      } catch (e) {
        // 显示错误信息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法打开全屏编辑器: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: '重试',
              onPressed: () => _showEditQuoteDialog(quote),
              textColor: Colors.white,
            ),
          ),
        );
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('笔记已删除')));
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
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('问笔记'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '请输入你的问题'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  if (controller.text.isEmpty) return;
                  Navigator.pop(dialogContext);
                  try {
                    final answer = await aiService.askQuestion(
                      quote,
                      controller.text,
                    );
                    if (!mounted) return;
                    showDialog(
                      context: context,
                      builder:
                          (answerDialogContext) => AlertDialog(
                            title: const Text('回答'),
                            content: Text(answer),
                            actions: [
                              TextButton(
                                onPressed:
                                    () => Navigator.pop(answerDialogContext),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('获取回答失败：$e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('提问'),
              ),
            ],
          ),
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

    // 直接用context.watch<bool>()获取服务初始化状态
    final bool servicesInitialized = context.watch<bool>();

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
            // 首页 - 每日一言
            DailyQuoteView(
              onAddQuote:
                  (content, author, work, hitokotoData) => _showAddQuoteDialog(
                    prefilledContent: content,
                    prefilledAuthor: author,
                    prefilledWork: work,
                    hitokotoData: hitokotoData,
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
        floatingActionButton: FloatingActionButton(
          heroTag: 'homePageFAB', // 添加唯一的hero标签
          onPressed: () => _showAddQuoteDialog(),
          child: const Icon(Icons.add),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            _onTabChanged(index); // 使用新的方法处理标签切换
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.book_outlined),
              selectedIcon: Icon(Icons.book),
              label: '记录',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'AI',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
