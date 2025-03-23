import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/icon_utils.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/sliding_card.dart';
import '../models/quote_model.dart';
import '../models/note_tag.dart';
import '../models/note_category.dart'; // 添加 import NoteCategory
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
  List<NoteCategory> _tags = []; // 修改 _tags 变量类型为 List<NoteCategory>
  List<String> _selectedTagIds = [];
  double? _startDragX;

  @override
  void initState() {
    super.initState();
    _fetchDailyQuote();
    _fetchDailyPrompt();
    _loadTags();
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
      debugPrint('获取每日提示失败: \$e');
    }
  }

  void _showAddQuoteDialog(BuildContext context, DatabaseService db) {
    final TextEditingController controller = TextEditingController();
    final aiService = context.read<AIService>();
    String? aiSummary;
    bool isAnalyzing = false;
    List<String> selectedTagIds = [];

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
              const SizedBox(height: 16),
              // 标签选择区域
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选择标签',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _tags.map((NoteCategory tag) { // 显式指定 tag 类型为 NoteCategory
                      final isSelected = selectedTagIds.contains(tag?.id);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(tag?.name ?? ''),
                        avatar: Icon(IconUtils.getIconData(tag?.iconName)),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedTagIds.add(tag?.id ?? '');
                            } else {
                              selectedTagIds.remove(tag?.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),

              // 显示已选标签的UI组件
              selectedTagIds.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '已选标签',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4.0,
                          runSpacing: 4.0,
                          children: selectedTagIds.map((tagId) {
                            final tag = _tags.firstWhere(
                              (t) => t.id == tagId,
                              orElse: () => NoteCategory(id: tagId, name: '未知标签'), // 修改 orElse 返回 NoteCategory
                            );
                            return Chip(
                              label: Text(tag.name, style: const TextStyle(fontSize: 12)), // tag 类型已变为 NoteCategory，name 属性存在
                              avatar: Icon(IconUtils.getIconData(tag.iconName), size: 14), // tag 类型已变为 NoteCategory，iconName 属性存在
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () {
                                setState(() {
                                  selectedTagIds.remove(tagId);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
              if (aiSummary != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 20.0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
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
                        // 利用非空断言，确保传入的字符串为非空
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
                                if (!mounted) return;
                                setState(() {
                                  aiSummary = summary;
                                  isAnalyzing = false;
                                });
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('AI分析失败: \$e'),
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
                        if (!mounted) return;
                        db.addQuote(
                          Quote(
                            content: controller.text,
                            date: DateTime.now().toIso8601String(),
                            aiAnalysis: aiSummary,
                            tagIds: selectedTagIds,
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
    // 多标签选择UI
    List<Widget> tagChips = _tags.map((tag) {
      final isSelected = _selectedTagIds.contains(tag.id);
      return FilterChip(
        selected: isSelected,
        label: Text(tag.name),
        avatar: Icon(IconUtils.getIconData(tag.iconName)),
        onSelected: (selected) {
          setState(() {
            if (selected) {
              _selectedTagIds.add(tag.id);
            } else {
              _selectedTagIds.remove(tag.id);
            }
          });
        },
      );
    }).toList();

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
                // 标签筛选按钮
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => StatefulBuilder(
                        builder: (context, setModalState) => Padding(
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
                                children: _tags.map((tag) {
                                  final isSelected = _selectedTagIds.contains(tag.id);
                                  return FilterChip(
                                    selected: isSelected,
                                    label: Text(tag.name),
                                    avatar: Icon(IconUtils.getIconData(tag.iconName)),
                                    onSelected: (selected) {
                                      setModalState(() {
                                        setState(() {
                                          if (selected) {
                                            _selectedTagIds.add(tag.id);
                                          } else {
                                            _selectedTagIds.remove(tag.id);
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
                                    onPressed: () => Navigator.pop(context),
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
              future: db.getUserQuotes(tagIds: _selectedTagIds.isNotEmpty ? _selectedTagIds : null),
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
                          color: theme.colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '还没有笔记，开始记录吧！',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                final quotes = snapshot.data!;
                if (_searchQuery.isNotEmpty) {
                  quotes.removeWhere((quote) =>
                      !quote.content.toLowerCase().contains(_searchQuery.toLowerCase()));
                }
                
                if (quotes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '没有找到匹配的笔记',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary.withOpacity(0.5),
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
                              DateTime.parse(quote.date)
                                  .toLocal()
                                  .toString()
                                  .split('.')[0],
                              style: theme.textTheme.bodySmall,
                            ),
                            if (quote.aiAnalysis != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
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
                            const PopupMenuItem<String>(
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
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.withAlpha(26),
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
          // AI侧边页
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
            label: 'AI侧边',
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
                    content: Text('获取回答失败：\$e'),
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
