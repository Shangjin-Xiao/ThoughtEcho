import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/color_utils.dart';
import '../utils/icon_utils.dart';
import '../widgets/city_search_widget.dart';
import '../widgets/quote_item_widget.dart';
import '../widgets/sliding_card.dart';
import 'insights_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 初始化基本变量
  final TextEditingController _searchController = TextEditingController();
  int _currentIndex = 0;
  String _searchQuery = '';
  List<String> _selectedTagIds = [];
  String _sortType = 'time';
  bool _sortAscending = false;
  Map<String, bool> _expandedItems = {};
  List<NoteCategory> _tags = [];
  String? _selectedColorHex;

  // 服务相关变量
  final LocationService _locationService = LocationService();
  final WeatherService _weatherService = WeatherService();
  bool _includeLocation = false;
  bool _includeWeather = false;

  // AI相关状态
  bool _isAnalyzing = false;
  String? _aiSummary;

  // 一言相关变量
  Map<String, dynamic> dailyQuote = {
    'content': '加载中...',
    'source': '',
    'from_who': '',
    'from': '',
    'type': 'a',
  };
  String? dailyPrompt;

  @override
  void initState() {
    super.initState();
    _loadDailyQuote();
    _fetchDailyPrompt();
    _loadTags();
    _initLocationAndWeather();
  }

  Future<void> _loadTags() async {
    final categories = await context.read<DatabaseService>().getCategories();
    setState(() {
      _tags = categories;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDailyQuote() async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final hitokotoType = settingsService.appSettings.hitokotoType;

    final quote = await ApiService.getDailyQuote(hitokotoType);
    setState(() {
      dailyQuote = quote;
    });
  }

  Future<void> _fetchDailyPrompt() async {
    try {
      final aiService = context.read<AIService>();
      final prompt = await aiService.generateDailyPrompt();
      if (mounted) {
        setState(() {
          dailyPrompt = prompt;
        });
      }
    } catch (e) {
      debugPrint('获取每日提示失败: $e');
    }
  }

  // 格式化一言的来源显示
  String formatHitokotoSource(String? author, String? source) {
    if ((author == null || author.isEmpty) &&
        (source == null || source.isEmpty)) {
      return '';
    }

    String result = '';
    if (author != null && author.isNotEmpty) {
      result += '——$author';
    }

    if (source != null && source.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$source》';
    }

    return result;
  }

  Future<void> _showAddQuoteDialog(
    BuildContext context,
    DatabaseService db, {
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
  }) async {
    final TextEditingController _controller = TextEditingController(
      text: prefilledContent ?? '',
    );
    final TextEditingController _authorController = TextEditingController(
      text: prefilledAuthor ?? '',
    );
    final TextEditingController _workController = TextEditingController(
      text: prefilledWork ?? '',
    );

    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);
    final aiService = Provider.of<AIService>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: '编辑你的笔记...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _authorController,
                                decoration: const InputDecoration(
                                  hintText: '作者',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _workController,
                                decoration: const InputDecoration(
                                  hintText: '作品',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 位置和天气开关
                        if (locationService.hasLocationPermission)
                          SwitchListTile(
                            title: const Text('包含位置信息'),
                            value: _includeLocation,
                            onChanged: (bool value) {
                              setState(() {
                                _includeLocation = value;
                              });
                            },
                          ),
                        if (weatherService.currentWeather != null)
                          SwitchListTile(
                            title: const Text('包含天气信息'),
                            value: _includeWeather,
                            onChanged: (bool value) {
                              setState(() {
                                _includeWeather = value;
                              });
                            },
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                if (_controller.text.isNotEmpty) {
                                  final quote = Quote(
                                    id: const Uuid().v4(),
                                    content: _controller.text,
                                    date: DateTime.now().toIso8601String(),
                                    source: _formatSource(
                                      _authorController.text,
                                      _workController.text,
                                    ),
                                    sourceAuthor: _authorController.text,
                                    sourceWork: _workController.text,
                                    tagIds: _selectedTagIds,
                                    colorHex: _selectedColorHex,
                                    aiAnalysis: _aiSummary,
                                    location:
                                        _includeLocation
                                            ? locationService
                                                .getFormattedLocation()
                                            : null,
                                    weather:
                                        _includeWeather
                                            ? weatherService.currentWeather
                                            : null,
                                    temperature:
                                        _includeWeather
                                            ? weatherService.temperature
                                            : null,
                                  );

                                  await db.addQuote(quote);
                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('笔记已保存')),
                                    );
                                  }
                                }
                              },
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  Widget _buildQuoteList(DatabaseService db, ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索笔记...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 排序按钮
              IconButton(
                icon: const Icon(Icons.sort),
                tooltip: '排序',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder:
                        (context) => StatefulBuilder(
                          builder:
                              (context, setModalState) => Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '排序方式',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // 按时间排序
                                    RadioListTile<String>(
                                      title: const Text('按时间排序'),
                                      subtitle: Text(
                                        _sortAscending ? '从旧到新' : '从新到旧',
                                      ),
                                      value: 'time',
                                      groupValue: _sortType,
                                      onChanged: _handleSortTypeChange,
                                    ),
                                    // 按名称排序
                                    RadioListTile<String>(
                                      title: const Text('按名称排序'),
                                      subtitle: Text(
                                        _sortAscending ? '升序 A-Z' : '降序 Z-A',
                                      ),
                                      value: 'name',
                                      groupValue: _sortType,
                                      onChanged: _handleSortTypeChange,
                                    ),
                                    const SizedBox(height: 8),
                                    // 排序方向
                                    SwitchListTile(
                                      title: const Text('排序方向'),
                                      subtitle: Text(
                                        _sortAscending ? '升序' : '降序',
                                      ),
                                      value: _sortAscending,
                                      onChanged: _handleAscendingChange,
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        ElevatedButton(
                                          onPressed:
                                              () => Navigator.pop(context),
                                          child: const Text('确定'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                        ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // 标签筛选按钮
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: '标签筛选',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder:
                        (context) => StatefulBuilder(
                          builder:
                              (context, setModalState) => Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '按标签筛选',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 8.0,
                                      runSpacing: 8.0,
                                      children:
                                          _tags.map((tag) {
                                            final isSelected = _selectedTagIds
                                                .contains(tag.id);
                                            return FilterChip(
                                              selected: isSelected,
                                              label: Text(tag.name),
                                              avatar: Icon(
                                                IconUtils.getIconData(
                                                  tag.iconName,
                                                ),
                                              ),
                                              onSelected: (selected) {
                                                setModalState(() {
                                                  setState(() {
                                                    if (selected) {
                                                      _selectedTagIds.add(
                                                        tag.id,
                                                      );
                                                    } else {
                                                      _selectedTagIds.remove(
                                                        tag.id,
                                                      );
                                                    }
                                                  });
                                                });
                                              },
                                            );
                                          }).toList(),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _selectedTagIds.clear();
                                            });
                                            setModalState(() {});
                                          },
                                          child: const Text('清除筛选'),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed:
                                              () => Navigator.pop(context),
                                          child: const Text('确定'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                        ),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Quote>>(
            future: db.getUserQuotes(
              tagIds: _selectedTagIds.isNotEmpty ? _selectedTagIds : null,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.note_alt_outlined,
                        size: 64,
                        color: theme.colorScheme.primary.applyOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '还没有笔记，开始记录吧！',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary.applyOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                );
              }

              var quotes = snapshot.data!;
              if (_searchQuery.isNotEmpty) {
                quotes =
                    quotes
                        .where(
                          (quote) =>
                              quote.content.toLowerCase().contains(
                                _searchQuery.toLowerCase(),
                              ) ||
                              (quote.source != null &&
                                  quote.source!.toLowerCase().contains(
                                    _searchQuery.toLowerCase(),
                                  )),
                        )
                        .toList();
              }

              if (quotes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: theme.colorScheme.primary.applyOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '没有找到匹配的笔记',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary.applyOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // 根据排序类型和排序方向对笔记进行排序
              if (_sortType == 'time') {
                quotes.sort((a, b) {
                  final dateA = DateTime.parse(a.date);
                  final dateB = DateTime.parse(b.date);
                  return _sortAscending
                      ? dateA.compareTo(dateB) // 升序：从旧到新
                      : dateB.compareTo(dateA); // 降序：从新到旧
                });
              } else if (_sortType == 'name') {
                quotes.sort((a, b) {
                  return _sortAscending
                      ? a.content.compareTo(b.content) // 升序：A-Z
                      : b.content.compareTo(a.content); // 降序：Z-A
                });
              }

              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: quotes.length,
                itemBuilder: (context, index) {
                  final quote = quotes[index];
                  // 获取展开状态，如果不存在则默认为折叠状态
                  final bool isExpanded = _expandedItems[quote.id] ?? false;

                  return QuoteItemWidget(
                    quote: quote,
                    tags: _tags,
                    isExpanded: isExpanded,
                    onToggleExpanded: (expanded) {
                      setState(() {
                        _expandedItems[quote.id!] = expanded;
                      });
                    },
                    onEdit: () => _showEditQuoteDialog(context, db, quote),
                    onDelete:
                        () => _showDeleteConfirmDialog(context, db, quote),
                    onAskAI: () => _showAIQuestionDialog(context, quote),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final theme = Theme.of(context);
    final weatherService = Provider.of<WeatherService>(context);
    final locationService = Provider.of<LocationService>(context);

    return Scaffold(
      appBar: AppBar(
        title:
            _currentIndex == 1
                ? TextField(
                  controller: _searchController,
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
          if (_currentIndex == 0 &&
              weatherService.currentWeather != null &&
              locationService.hasLocationPermission)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      weatherService.getWeatherIconData(),
                      size: 16,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${weatherService.currentWeather ?? ""} ${weatherService.temperature ?? ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await Future.wait([_loadDailyQuote(), _fetchDailyPrompt()]);
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // 首页 - 每日一言
          RefreshIndicator(
            onRefresh: () async {
              await Future.wait([_loadDailyQuote(), _fetchDailyPrompt()]);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Container(
                height:
                    MediaQuery.of(context).size.height -
                    kToolbarHeight -
                    MediaQuery.of(context).padding.top -
                    kBottomNavigationBarHeight,
                child: Column(
                  children: [
                    Expanded(
                      child: SlidingCard(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                // 单击复制内容
                                final String formattedQuote =
                                    '${dailyQuote['content']}\n' +
                                    (dailyQuote['from_who'] != null &&
                                            dailyQuote['from_who'].isNotEmpty
                                        ? '——${dailyQuote['from_who']}'
                                        : '') +
                                    (dailyQuote['from'] != null &&
                                            dailyQuote['from'].isNotEmpty
                                        ? '《${dailyQuote['from']}》'
                                        : '');

                                // 复制到剪贴板
                                Clipboard.setData(
                                  ClipboardData(text: formattedQuote),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制到剪贴板')),
                                );
                              },
                              onDoubleTap: () {
                                // 双击添加到笔记
                                _showAddQuoteDialog(
                                  context,
                                  db,
                                  prefilledContent: dailyQuote['content'],
                                  prefilledAuthor: dailyQuote['from_who'],
                                  prefilledWork: dailyQuote['from'],
                                );
                              },
                              child: Column(
                                children: [
                                  Text(
                                    dailyQuote['content'],
                                    style: theme.textTheme.headlineSmall,
                                    textAlign: TextAlign.center,
                                  ),
                                  if (dailyQuote['from_who'] != null &&
                                          dailyQuote['from_who'].isNotEmpty ||
                                      dailyQuote['from'] != null &&
                                          dailyQuote['from'].isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        formatHitokotoSource(
                                          dailyQuote['from_who'],
                                          dailyQuote['from'],
                                        ),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontStyle: FontStyle.italic,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (dailyPrompt != null)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.applyOpacity(0.26),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.psychology,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '今日思考',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              dailyPrompt!,
                              style: theme.textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 记录页
          _buildQuoteList(db, theme),
          // AI页
          const InsightsPage(),
          // 设置页
          const SettingsPage(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddQuoteDialog(context, db),
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
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
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

  void _showAIQuestionDialog(BuildContext context, Quote quote) async {
    final controller = TextEditingController();
    final aiService = context.read<AIService>();

    if (!mounted) return;

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

                  if (!mounted) return;

                  try {
                    final answer = await aiService.askQuestion(
                      quote,
                      controller.text,
                    );

                    if (!mounted) return;

                    showDialog(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('回答'),
                            content: Text(answer),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
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

  // 显示编辑笔记对话框
  void _showEditQuoteDialog(
    BuildContext context,
    DatabaseService db,
    Quote quote,
  ) {
    final TextEditingController controller = TextEditingController(
      text: quote.content,
    );
    final TextEditingController authorController = TextEditingController(
      text: quote.sourceAuthor ?? '',
    );
    final TextEditingController workController = TextEditingController(
      text: quote.sourceWork ?? '',
    );
    final List<String> selectedTagIds = List.from(quote.tagIds);

    // 仅当源字段为空时尝试解析旧数据（兼容已有数据）
    if ((quote.sourceAuthor == null || quote.sourceAuthor!.isEmpty) &&
        (quote.sourceWork == null || quote.sourceWork!.isEmpty) &&
        quote.source != null &&
        quote.source!.isNotEmpty) {
      _parseSource(quote.source!, authorController, workController);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _showBottomSheet(
            query: quote.content,
            lat: 0.0,
            lon: 0.0,
            locationService: Provider.of<LocationService>(
              context,
              listen: false,
            ),
            controller: controller,
            authorController: authorController,
            workController: workController,
            location: quote.location,
            weather: quote.weather,
            temperature: quote.temperature,
            includeLocation: quote.location != null,
            includeWeather: quote.weather != null,
            selectedTagIds: selectedTagIds,
            onLocationChanged: (value) {
              // 不直接修改quote的location属性
              setState(() {});
            },
            onWeatherChanged: (value) {
              // 不直接修改quote的weather属性
              setState(() {});
            },
          ),
    );
  }

  // 显示删除确认对话框
  void _showDeleteConfirmDialog(
    BuildContext context,
    DatabaseService db,
    Quote quote,
  ) {
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

  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      result += ' 《$work》';
    }

    return result;
  }

  void _parseSource(
    String source,
    TextEditingController authorController,
    TextEditingController workController,
  ) {
    // 尝试解析格式如"——作者《作品》"的字符串
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
    } else {
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
                  if (granted) {
                    _initLocationAndWeather();
                  }
                },
                child: const Text('授予权限'),
              ),
            ],
          ),
    );
  }

  // 根据天气描述获取图标
  IconData _getWeatherIcon(String weather) {
    if (weather.contains('晴')) return Icons.wb_sunny;
    if (weather.contains('云') || weather.contains('阴')) return Icons.cloud;
    if (weather.contains('雾') || weather.contains('霾')) return Icons.cloud;
    if (weather.contains('雨') && weather.contains('雷')) return Icons.flash_on;
    if (weather.contains('雨')) return Icons.water_drop;
    if (weather.contains('雪')) return Icons.ac_unit;
    if (weather.contains('风')) return Icons.air;
    return Icons.cloud_queue;
  }

  // 添加城市搜索对话框方法
  void _showCitySearchDialog(BuildContext context) {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.7,
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.all(8.0),
              child: CitySearchWidget(
                initialCity: locationService.city,
                onCitySelected: (city) {
                  setState(() {
                    // 不需要使用变量来存储返回值，只需调用方法刷新位置信息
                    locationService.getFormattedLocation();
                  });
                },
              ),
            ),
          ),
    );
  }

  Widget _showBottomSheet({
    required String query,
    required double lat,
    required double lon,
    LocationService? locationService,
    TextEditingController? controller,
    TextEditingController? authorController,
    TextEditingController? workController,
    String? location,
    String? weather,
    String? temperature,
    bool includeLocation = false,
    bool includeWeather = false,
    List<String> selectedTagIds = const [],
    required Function(bool) onLocationChanged,
    required Function(bool) onWeatherChanged,
  }) {
    return StatefulBuilder(
      builder:
          (context, setState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: '编辑你的笔记...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: authorController,
                          decoration: const InputDecoration(
                            hintText: '作者',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: workController,
                          decoration: const InputDecoration(
                            hintText: '作品',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 标签选择
                  if (_tags.isNotEmpty) ...[
                    const Text('选择标签'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children:
                          _tags.map((tag) {
                            final isSelected = selectedTagIds.contains(tag.id);
                            return FilterChip(
                              label: Text(tag.name),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    selectedTagIds.add(tag.id);
                                  } else {
                                    selectedTagIds.remove(tag.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // 位置开关
                  if (locationService?.hasLocationPermission ?? false)
                    SwitchListTile(
                      title: const Text('包含位置信息'),
                      subtitle: Text(location ?? '当前位置'),
                      value: includeLocation,
                      onChanged: onLocationChanged,
                    ),
                  // 天气开关
                  if (weather != null)
                    SwitchListTile(
                      title: const Text('包含天气信息'),
                      subtitle: Text('$weather ${temperature ?? ""}'),
                      value: includeWeather,
                      onChanged: onWeatherChanged,
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (controller?.text.isNotEmpty ?? false) {
                            final quote = Quote(
                              id: const Uuid().v4(),
                              content: controller!.text,
                              date: DateTime.now().toIso8601String(),
                              source: _formatSource(
                                authorController?.text ?? '',
                                workController?.text ?? '',
                              ),
                              sourceAuthor: authorController?.text,
                              sourceWork: workController?.text,
                              tagIds: selectedTagIds,
                              colorHex: _selectedColorHex,
                              aiAnalysis: _aiSummary,
                              location:
                                  includeLocation
                                      ? locationService?.getFormattedLocation()
                                      : null,
                              weather: includeWeather ? weather : null,
                              temperature: includeWeather ? temperature : null,
                            );

                            Provider.of<DatabaseService>(
                              context,
                              listen: false,
                            ).addQuote(quote).then((_) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('笔记已保存')),
                              );
                            });
                          }
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _handleSortTypeChange(String? value) {
    if (value != null) {
      setState(() {
        _sortType = value;
      });
    }
  }

  void _handleAscendingChange(bool value) {
    setState(() {
      _sortAscending = value;
    });
  }
}
