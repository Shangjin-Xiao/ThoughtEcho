import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/icon_utils.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/sliding_card.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart'; // 添加 import NoteCategory
import 'settings_page.dart';
import '../services/ai_service.dart';
import 'insights_page.dart';
import '../utils/color_utils.dart'; // 新增导入，确保扩展方法可用
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../services/settings_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic> dailyQuote = {
    'content': '加载中...',
    'source': '',
    'author': '',
    'type': 'a'
  };
  String? dailyPrompt;
  int _currentIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<NoteCategory> _tags = []; // 修改 _tags 变量类型为 List<NoteCategory>
  final List<String> _selectedTagIds = [];
  double? _startDragX;
  
  // 排序设置
  String _sortType = 'time'; // 'time' 或 'name'
  bool _sortAscending = false; // false为降序（默认新到旧），true为升序
  
  // 存储笔记卡片的展开/折叠状态
  final Map<String, bool> _expandedItems = {};
  
  // 检查文本是否足够长需要展开/折叠功能
  bool _needsExpansion(String text) {
    // 简单估算，如果内容超过100个字符则提供展开/折叠功能
    return text.length > 100;
  }

  @override
  void initState() {
    super.initState();
    _loadDailyQuote();
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

  Future<void> _loadDailyQuote() async {
    final settingsService = Provider.of<SettingsService>(context, listen: false);
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
    if ((author == null || author.isEmpty) && (source == null || source.isEmpty)) {
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

  void _showAddQuoteDialog(BuildContext context, DatabaseService db, {String? prefilledContent, String? prefilledAuthor, String? prefilledWork}) {
    final TextEditingController controller = TextEditingController(text: prefilledContent ?? '');
    final TextEditingController authorController = TextEditingController(text: prefilledAuthor ?? '');
    final TextEditingController workController = TextEditingController(text: prefilledWork ?? '');
    final aiService = context.read<AIService>();
    String? aiSummary;
    bool isAnalyzing = false;
    List<String> selectedTagIds = [];
    
    // 添加颜色选择
    String? selectedColorHex;
    final List<Color> colorOptions = [
      Colors.red.shade100,
      Colors.orange.shade100,
      Colors.yellow.shade100,
      Colors.green.shade100,
      Colors.blue.shade100,
      Colors.purple.shade100,
      Colors.pink.shade100,
    ];

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
              // 拆分来源输入为作者和作品
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: authorController,
                      decoration: const InputDecoration(
                        hintText: '作者/人物',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: workController,
                      decoration: const InputDecoration(
                        hintText: '作品名称',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.book),
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '将显示为: ${_formatSource(authorController.text, workController.text)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // 颜色选择区域
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '卡片颜色',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      // 默认选项（无颜色）
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedColorHex = null;
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: selectedColorHex == null 
                                 ? Theme.of(context).colorScheme.primary 
                                 : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: selectedColorHex == null
                            ? Center(
                                child: Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            : null,
                        ),
                      ),
                      ...colorOptions.map((color) {
                        final colorHex = '#${color.value.toRadixString(16).substring(2)}';
                        final isSelected = selectedColorHex == colorHex;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedColorHex = colorHex;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(
                                color: isSelected 
                                   ? Theme.of(context).colorScheme.primary 
                                   : Colors.grey.shade300,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: isSelected
                              ? Center(
                                  child: Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                )
                              : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ],
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
                    children: _tags.map((NoteCategory tag) {
                      final isSelected = selectedTagIds.contains(tag.id);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(tag.name),
                        avatar: Icon(IconUtils.getIconData(tag.iconName)),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedTagIds.add(tag.id);
                            } else {
                              selectedTagIds.remove(tag.id); // 移除未使用的 tagChips 变量
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                              orElse: () => NoteCategory(id: tagId, name: '未知标签'),
                            );
                            return Chip(
                              label: Text(tag.name, style: const TextStyle(fontSize: 12)),
                              avatar: Icon(IconUtils.getIconData(tag.iconName), size: 14),
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
                    onPressed: () async {
                      if (controller.text.isNotEmpty) {
                        if (!mounted) return;
                        final aiService = context.read<AIService>();
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
                        
                        Quote quote = Quote(
                          id: const Uuid().v4(),
                          content: controller.text,
                          date: DateTime.now().toIso8601String(),
                          aiAnalysis: aiSummary,
                          source: _formatSource(authorController.text, workController.text),
                          sourceAuthor: authorController.text,
                          sourceWork: workController.text,
                          tagIds: selectedTagIds,
                          colorHex: selectedColorHex,
                        );
                        
                        await db.addQuote(quote);
                        // 关闭对话框
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
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
                const SizedBox(width: 8),
                // 排序按钮
                IconButton(
                  icon: const Icon(Icons.sort),
                  tooltip: '排序',
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
                                subtitle: Text(_sortAscending ? '从旧到新' : '从新到旧'),
                                value: 'time',
                                groupValue: _sortType,
                                onChanged: (value) {
                                  setModalState(() {
                                    setState(() {
                                      _sortType = value!;
                                    });
                                  });
                                },
                              ),
                              // 按名称排序
                              RadioListTile<String>(
                                title: const Text('按名称排序'),
                                subtitle: Text(_sortAscending ? '升序 A-Z' : '降序 Z-A'),
                                value: 'name',
                                groupValue: _sortType,
                                onChanged: (value) {
                                  setModalState(() {
                                    setState(() {
                                      _sortType = value!;
                                    });
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              // 排序方向
                              SwitchListTile(
                                title: const Text('排序方向'),
                                subtitle: Text(_sortAscending ? '升序' : '降序'),
                                value: _sortAscending,
                                onChanged: (value) {
                                  setModalState(() {
                                    setState(() {
                                      _sortAscending = value;
                                    });
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
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
                const SizedBox(width: 8),
                // 标签筛选按钮
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: '标签筛选',
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
                  quotes = quotes.where((quote) =>
                      quote.content.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      (quote.source != null && quote.source!.toLowerCase().contains(_searchQuery.toLowerCase()))).toList();
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
                        ? dateA.compareTo(dateB)  // 升序：从旧到新
                        : dateB.compareTo(dateA); // 降序：从新到旧
                  });
                } else if (_sortType == 'name') {
                  quotes.sort((a, b) {
                    return _sortAscending 
                        ? a.content.compareTo(b.content)  // 升序：A-Z
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
                    // 卡片颜色：优先使用自定义颜色，否则使用动态取色
                    final Color cardColor = quote.colorHex != null 
                        ? Color(int.parse(quote.colorHex!.substring(1), radix: 16) | 0xFF000000)
                        : index % 2 == 0 
                          ? theme.colorScheme.primary.withOpacity(0.1) 
                          : theme.colorScheme.secondary.withOpacity(0.1);
                    
                    // 格式化日期为年月日
                    final DateTime quoteDate = DateTime.parse(quote.date);
                    final String formattedDate = '${quoteDate.year}-${quoteDate.month.toString().padLeft(2, '0')}-${quoteDate.day.toString().padLeft(2, '0')} 摘录';
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Material(
                        elevation: 1,
                        borderRadius: BorderRadius.circular(16),
                        color: cardColor,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            // 展开/折叠卡片内容
                            setState(() {
                              _expandedItems[quote.id!] = !isExpanded;
                            });
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 头部日期显示
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      formattedDate,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // 笔记内容
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                child: Text(
                                  quote.content,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    height: 1.5,
                                  ),
                                  maxLines: isExpanded ? null : 3,
                                  overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                ),
                              ),
                              
                              // 来源信息（如果有）
                              if ((quote.sourceAuthor != null && quote.sourceAuthor!.isNotEmpty) || 
                                 (quote.sourceWork != null && quote.sourceWork!.isNotEmpty)) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                  child: Text(
                                    _formatSource(quote.sourceAuthor ?? '', quote.sourceWork ?? ''),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ] else if (quote.source != null && quote.source!.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                  child: Text(
                                    quote.source!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                              
                              // 展开/折叠按钮（如果内容较长）
                              if (_needsExpansion(quote.content)) ...[
                                Center(
                                  child: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _expandedItems[quote.id!] = !isExpanded;
                                      });
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          isExpanded ? '收起' : '展开全部',
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Icon(
                                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              
                              // 底部工具栏
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 0, 8),
                                child: Row(
                                  children: [
                                    // 标签信息
                                    if (quote.tagIds.isNotEmpty) ...[
                                      Icon(
                                        Icons.label_outline,
                                        size: 16,
                                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: quote.tagIds.map((tagId) {
                                              final tag = _tags.firstWhere(
                                                (t) => t.id == tagId,
                                                orElse: () => NoteCategory(id: tagId, name: '未知标签'),
                                              );
                                              return Container(
                                                margin: const EdgeInsets.only(right: 8),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  tag.name,
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: theme.colorScheme.primary,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ],
                                    
                                    // 操作按钮
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      onSelected: (value) async {
                                        if (value == 'ask') {
                                          _showAIQuestionDialog(context, quote);
                                        } else if (value == 'edit') {
                                          _showEditQuoteDialog(context, db, quote);
                                        } else if (value == 'delete') {
                                          _showDeleteConfirmDialog(context, db, quote);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, color: theme.colorScheme.primary),
                                              const SizedBox(width: 8),
                                              const Text('编辑笔记'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'ask',
                                          child: Row(
                                            children: [
                                              Icon(Icons.question_answer, color: theme.colorScheme.primary),
                                              const SizedBox(width: 8),
                                              const Text('向AI提问'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.delete, color: Colors.red),
                                              const SizedBox(width: 8),
                                              Text(
                                                '删除笔记',
                                                style: TextStyle(color: theme.colorScheme.error),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
                  _loadDailyQuote(),
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
                _loadDailyQuote(),
                _fetchDailyPrompt(),
              ]);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
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
                            Column(
                              children: [
                                Text(
                                  dailyQuote['content'],
                                  style: theme.textTheme.headlineSmall,
                                  textAlign: TextAlign.center,
                                ),
                                if (dailyQuote['from_who'] != null && dailyQuote['from_who'].isNotEmpty || 
                                   dailyQuote['from'] != null && dailyQuote['from'].isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: GestureDetector(
                                      onTap: () {
                                        // 单击复制内容
                                        final String formattedQuote = '${dailyQuote['content']}\n${dailyQuote['from_who'] != null && dailyQuote['from_who'].isNotEmpty ?
                                           '——${dailyQuote['from_who']}' : ''}${dailyQuote['from'] != null && dailyQuote['from'].isNotEmpty ?
                                           '「${dailyQuote['from']}」' : ''}';
                                        
                                        // 复制到剪贴板
                                        Clipboard.setData(ClipboardData(text: formattedQuote));
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
                                          prefilledWork: dailyQuote['from']
                                        );
                                      },
                                      child: Text(
                                        formatHitokotoSource(dailyQuote['from_who'], dailyQuote['from']),
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontStyle: FontStyle.italic,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
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
  void _showEditQuoteDialog(BuildContext context, DatabaseService db, Quote quote) {
    final TextEditingController controller = TextEditingController(text: quote.content);
    final TextEditingController authorController = TextEditingController(text: quote.sourceAuthor ?? '');
    final TextEditingController workController = TextEditingController(text: quote.sourceWork ?? '');
    
    // 仅当源字段为空时尝试解析旧数据（兼容已有数据）
    if ((quote.sourceAuthor == null || quote.sourceAuthor!.isEmpty) && 
        (quote.sourceWork == null || quote.sourceWork!.isEmpty) && 
        quote.source != null && quote.source!.isNotEmpty) {
      _parseSource(quote.source!, authorController, workController);
    }
    
    final aiService = context.read<AIService>();
    String? aiSummary = quote.aiAnalysis;
    bool isAnalyzing = false;
    List<String> selectedTagIds = List.from(quote.tagIds);
    
    // 添加颜色选择
    String? selectedColorHex = quote.colorHex;
    final List<Color> colorOptions = [
      Colors.red.shade100,
      Colors.orange.shade100,
      Colors.yellow.shade100,
      Colors.green.shade100,
      Colors.blue.shade100,
      Colors.purple.shade100,
      Colors.pink.shade100,
    ];

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
                  hintText: '编辑你的笔记...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit),
                ),
                maxLines: 3,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              // 拆分来源输入为作者和作品
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: authorController,
                      decoration: const InputDecoration(
                        hintText: '作者/人物',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: workController,
                      decoration: const InputDecoration(
                        hintText: '作品名称',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.book),
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '将显示为: ${_formatSource(authorController.text, workController.text)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // 颜色选择区域
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '卡片颜色',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      // 默认选项（无颜色）
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedColorHex = null;
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: selectedColorHex == null 
                                 ? Theme.of(context).colorScheme.primary 
                                 : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: selectedColorHex == null
                            ? Center(
                                child: Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            : null,
                        ),
                      ),
                      ...colorOptions.map((color) {
                        final colorHex = '#${color.value.toRadixString(16).substring(2)}';
                        final isSelected = selectedColorHex == colorHex;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedColorHex = colorHex;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(
                                color: isSelected 
                                   ? Theme.of(context).colorScheme.primary 
                                   : Colors.grey.shade300,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: isSelected
                              ? Center(
                                  child: Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                )
                              : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ],
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
                    children: _tags.map((NoteCategory tag) {
                      final isSelected = selectedTagIds.contains(tag.id);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(tag.name),
                        avatar: Icon(IconUtils.getIconData(tag.iconName)),
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
                ],
              ),

              // 显示已选标签的UI组件
              selectedTagIds.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                              orElse: () => NoteCategory(id: tagId, name: '未知标签'),
                            );
                            return Chip(
                              label: Text(tag.name, style: const TextStyle(fontSize: 12)),
                              avatar: Icon(IconUtils.getIconData(tag.iconName), size: 14),
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
                Container(
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
                      Text(aiSummary ?? ''),
                    ],
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
                                    id: quote.id,
                                    content: controller.text,
                                    date: quote.date,
                                    aiAnalysis: aiSummary,
                                    source: _formatSource(authorController.text, workController.text),
                                    sourceAuthor: authorController.text,
                                    sourceWork: workController.text,
                                    tagIds: selectedTagIds,
                                    sentiment: quote.sentiment,
                                    keywords: quote.keywords,
                                    summary: quote.summary,
                                    categoryId: quote.categoryId,
                                    colorHex: selectedColorHex,
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
                        if (!mounted) return;
                        final updatedQuote = Quote(
                          id: quote.id,
                          content: controller.text,
                          date: quote.date,
                          aiAnalysis: aiSummary,
                          source: _formatSource(authorController.text, workController.text),
                          sourceAuthor: authorController.text,
                          sourceWork: workController.text,
                          tagIds: selectedTagIds,
                          sentiment: quote.sentiment,
                          keywords: quote.keywords,
                          summary: quote.summary,
                          categoryId: quote.categoryId,
                          colorHex: selectedColorHex,
                        );
                        db.updateQuote(updatedQuote);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('笔记已更新！')),
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

  // 显示删除确认对话框
  void _showDeleteConfirmDialog(BuildContext context, DatabaseService db, Quote quote) {
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
              db.deleteQuote(quote.id!);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('笔记已删除')),
              );
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
      result += ' 「$work」';
    }
    
    return result;
  }

  void _parseSource(String source, TextEditingController authorController, TextEditingController workController) {
    // 尝试解析格式如"——作者「作品」"的字符串
    String author = '';
    String work = '';
    
    // 提取作者（在"——"之后，"「"之前）
    final authorMatch = RegExp(r'——([^「]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }
    
    // 提取作品（在「」之间）
    final workMatch = RegExp(r'「(.+?)」').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }
    
    authorController.text = author;
    workController.text = work;
  }
}