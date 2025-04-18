import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/ai_service.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../widgets/daily_quote_view.dart';
import '../widgets/note_list_view.dart';
import '../widgets/add_note_dialog.dart';
import 'insights_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  String _searchQuery = '';
  List<NoteCategory> _tags = [];
  List<String> _selectedTagIds = [];

  // 排序设置
  String _sortType = 'time';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
    _initLocationAndWeather();
  }

  Future<void> _loadTags() async {
    final categories = await context.read<DatabaseService>().getCategories();
    setState(() {
      _tags = categories;
    });
  }

  // 初始化位置和天气服务
  Future<void> _initLocationAndWeather() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    await locationService.init();

    if (locationService.hasLocationPermission &&
        locationService.isLocationServiceEnabled) {
      final position = await locationService.getCurrentLocation();
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
    } else if (mounted) {
      // 修复 BuildContext 跨异步使用问题
      _showLocationPermissionDialog();
    }
  }

  // 显示位置权限对话框
  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('需要位置权限'),
            content: const Text('心迹需要访问位置信息以显示天气和在笔记中添加位置。如果不授予权限，相关功能将被禁用。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('稍后再说'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final locationService = Provider.of<LocationService>(
                    context,
                    listen: false,
                  );
                  final granted =
                      await locationService.requestLocationPermission();
                  if (granted && mounted) {
                    // 修复 BuildContext 跨异步使用问题
                    _initLocationAndWeather();
                  }
                },
                child: const Text('授予权限'),
              ),
            ],
          ),
    );
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
            },
          ),
    );
  }

  // 显示编辑笔记对话框
  void _showEditQuoteDialog(Quote quote) {
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
          (context) => AlertDialog(
            title: const Text('问笔记'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '请输入你的问题'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  if (controller.text.isEmpty) return;
                  Navigator.pop(context);

                  try {
                    final answer = await aiService.askQuestion(
                      quote,
                      controller.text,
                    );

                    if (!mounted) return; // 添加 mounted 检查

                    showDialog(
                      context: context,
                      builder:
                          (dialogContext) => AlertDialog(
                            // 使用新的 BuildContext 避免使用旧的跨异步上下文
                            title: const Text('回答'),
                            content: Text(answer),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                    );
                  } catch (e) {
                    if (!mounted) return; // 添加 mounted 检查
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

  @override
  Widget build(BuildContext context) {
    final weatherService = Provider.of<WeatherService>(context);
    final locationService = Provider.of<LocationService>(context);

    return Scaffold(
      appBar: AppBar(
        title:
            _currentIndex == 1
                ? TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索...',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                )
                : const Text('心迹'),
        actions: [
          // 显示位置和天气信息
          if (_currentIndex == 0 &&
              locationService.city != null &&
              !locationService.city!.contains("Throttled!") &&
              weatherService.currentWeather != null &&
              locationService.hasLocationPermission)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      locationService.city ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '|',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer
                            .withAlpha(128), // 替换 withOpacity
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      weatherService.getWeatherIconData(),
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${weatherService.currentWeather ?? ""} ${weatherService.temperature ?? ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
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
          NoteListView(
            tags: _tags,
            selectedTagIds: _selectedTagIds,
            onTagSelectionChanged: (tagIds) {
              setState(() {
                _selectedTagIds = tagIds;
              });
            },
            searchQuery: _searchQuery,
            sortType: _sortType,
            sortAscending: _sortAscending,
            onSortChanged: (type, ascending) {
              setState(() {
                _sortType = type;
                _sortAscending = ascending;
              });
            },
            onEdit: _showEditQuoteDialog,
            onDelete: _showDeleteConfirmDialog,
            onAskAI: _showAIQuestionDialog,
          ),
          // AI页
          const InsightsPage(),
          // 设置页
          const SettingsPage(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddQuoteDialog(),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
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
    );
  }
}
