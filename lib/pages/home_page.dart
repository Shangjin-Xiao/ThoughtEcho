import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/sliding_card.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import 'settings_page.dart';
import '../services/ai_service.dart';
import 'insights_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String dailyQuote = '加载中...';
  String? dailyPrompt;
  int _currentIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<NoteCategory> _categories = [];
  double? _startDragX;

  @override
  void initState() {
    super.initState();
    _fetchDailyQuote();
    _fetchDailyPrompt();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await context.read<DatabaseService>().getCategories();
    setState(() {
      _categories = categories;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDailyQuote() async {
    final quote = await ApiService.getDailyQuote();
    if (mounted) {
      setState(() {
        dailyQuote = quote;
      });
    }
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

  void _showAddQuoteDialog(BuildContext context, DatabaseService db) {
    final TextEditingController controller = TextEditingController();
    final aiService = context.read<AIService>();
    String? aiSummary;
    bool isAnalyzing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: '选择分类',
                  border: OutlineInputBorder(),
                ),
                items: _categories.map((category) {
                  return DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    // _selectedCategoryId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '写下你的感悟...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit),
                ),
                maxLines: 3,
                autofocus: true,
              ),
              if (aiSummary != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 20.0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AI分析',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(aiSummary!),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (controller.text.isNotEmpty && aiSummary == null)
                    TextButton.icon(
                      onPressed: isAnalyzing
                          ? null
                          : () async {
                              setState(() => isAnalyzing = true);
                              try {
                                final summary = await aiService.summarizeNote(
                                  Quote(
                                    id: '',
                                    content: controller.text,
                                    date: DateTime.now().toIso8601String(),
                                  ),
                                );
                                setState(() {
                                  aiSummary = summary;
                                  isAnalyzing = false;
                                });
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('AI分析失败: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                setState(() => isAnalyzing = false);
                              }
                            },
                      icon: isAnalyzing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(isAnalyzing ? '分析中...' : 'AI分析'),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        db.addQuote(
                          Quote(
                            content: controller.text,
                            date: DateTime.now().toIso8601String(),
                            aiAnalysis: aiSummary,
                            categoryId: 'general',
                          ),
                        );
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('保存成功！')),
                        );
                      }
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteList(DatabaseService db, ThemeData theme) {
    String? selectedValue;
    List<DropdownMenuItem<String>> dropdownItems = [
      const DropdownMenuItem<String>(
        value: null,
        child: Text('全部分类'),
      ),
      ..._categories.map((category) {
        return DropdownMenuItem(
          value: category.id,
          child: Text(category.name),
        );
      }).toList(),
    ];

    return Listener(
      onPointerDown: (event) {
        _startDragX = event.position.dx;
      },
      onPointerUp: (event) {
        final dragDistance = event.position.dx - _startDragX!;
        if (dragDistance < -50) {
          _showAddQuoteDialog(context, db);
        }
      },
      child: Column(
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
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: selectedValue,
                  items: dropdownItems,
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedValue = newValue;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Quote>>(
              future: db.getUserQuotes(categoryId: selectedValue),
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
                          color: theme.colorScheme.primary.withValues(red: 0.5, green: 0.5, blue: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '还没有笔记，开始记录吧！',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary.withValues(red: 0.5, green: 0.5, blue: 0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final quotes = snapshot.data!;
                if (_searchQuery.isNotEmpty) {
                  quotes.removeWhere((quote) => !quote.content.toLowerCase().contains(_searchQuery.toLowerCase()));
                }

                if (quotes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.primary.withValues(red: 0.5, green: 0.5, blue: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '没有找到匹配的笔记',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary.withValues(red: 0.5, green: 0.5, blue: 0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: quotes.length,
                  itemBuilder: (context, index) {
                    final quote = quotes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ListTile(
                        title: Text(quote.content),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateTime.parse(quote.date).toLocal().toString().split('.')[0],
                              style: theme.textTheme.bodySmall,
                            ),
                            if (quote.aiAnalysis != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        quote.aiAnalysis!,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'ask') {
                              _showAIQuestionDialog(context, quote);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'ask',
                              child: Row(
                                children: [
                                  Icon(Icons.question_answer),
                                  SizedBox(width: 8),
                                  Text('向AI提问'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _currentIndex == 1
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
            : const Text('每日一言'),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await Future.wait([
                  _fetchDailyQuote(),
                  _fetchDailyPrompt(),
                ]);
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
              await Future.wait([
                _fetchDailyQuote(),
                _fetchDailyPrompt(),
              ]);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Container(
                height: MediaQuery.of(context).size.height -
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
                            const Icon(Icons.format_quote, size: 40),
                            const SizedBox(height: 16),
                            Text(
                              dailyQuote,
                              style: theme.textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        onSlideComplete: () => _showAddQuoteDialog(context, db),
                      ),
                    ),
                    if (dailyPrompt != null)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.withOpacity(0.1),
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
          // AI洞察页
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
            label: 'AI洞察',
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
      builder: (context) => AlertDialog(
        title: const Text('问笔记'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '请输入你的问题',
          ),
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
                  builder: (context) => AlertDialog(
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
}