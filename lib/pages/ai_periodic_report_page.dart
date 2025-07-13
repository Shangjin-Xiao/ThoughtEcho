import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../services/database_service.dart';
import '../services/ai_card_generation_service.dart';
import '../services/ai_service.dart';
import '../services/settings_service.dart';
import '../widgets/svg_card_widget.dart';
import '../utils/app_logger.dart';

/// AI周期报告页面
class AIPeriodicReportPage extends StatefulWidget {
  const AIPeriodicReportPage({super.key});

  @override
  State<AIPeriodicReportPage> createState() => _AIPeriodicReportPageState();
}

class _AIPeriodicReportPageState extends State<AIPeriodicReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 时间范围选择
  String _selectedPeriod = 'week'; // week, month, year
  DateTime _selectedDate = DateTime.now();

  // 数据状态
  List<Quote> _periodQuotes = [];
  List<GeneratedCard> _featuredCards = [];
  bool _isLoadingData = false;
  bool _isGeneratingCards = false;
  String _insights = '';

  // 服务
  AICardGenerationService? _aiCardService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPeriodData();
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
    _tabController.dispose();
    super.dispose();
  }

  /// 加载周期数据
  Future<void> _loadPeriodData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      final databaseService = context.read<DatabaseService>();
      final quotes = await databaseService.getUserQuotes();

      // 根据选择的时间范围筛选笔记
      final filteredQuotes = _filterQuotesByPeriod(quotes);

      setState(() {
        _periodQuotes = filteredQuotes;
        _isLoadingData = false;
      });

      // 生成精选卡片
      if (filteredQuotes.isNotEmpty && _aiCardService != null) {
        _generateFeaturedCards();
      }

      // 生成AI洞察
      _generateInsights();
    } catch (e) {
      setState(() {
        _isLoadingData = false;
      });
      AppLogger.e('加载周期数据失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载数据失败: $e')));
      }
    }
  }

  /// 根据时间范围筛选笔记
  List<Quote> _filterQuotesByPeriod(List<Quote> quotes) {
    final now = _selectedDate;
    DateTime startDate;
    DateTime endDate;

    switch (_selectedPeriod) {
      case 'week':
        // 本周（周一到周日）
        final weekday = now.weekday;
        startDate = now.subtract(Duration(days: weekday - 1));
        endDate = startDate.add(const Duration(days: 6));
        break;
      case 'month':
        // 本月
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case 'year':
        // 本年
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        break;
      default:
        return quotes;
    }

    return quotes.where((quote) {
      final quoteDate = DateTime.parse(quote.date);
      return quoteDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
          quoteDate.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();
  }

  /// 生成精选卡片
  Future<void> _generateFeaturedCards() async {
    if (_aiCardService == null || _periodQuotes.isEmpty) return;

    setState(() {
      _isGeneratingCards = true;
    });

    try {
      // 选择最有代表性的笔记（最多6张卡片）
      final selectedQuotes = _selectRepresentativeQuotes(_periodQuotes);

      final cards = await _aiCardService!.generateFeaturedCards(
        selectedQuotes,
        maxCards: 6,
      );

      setState(() {
        _featuredCards = cards;
        _isGeneratingCards = false;
      });
    } catch (e) {
      setState(() {
        _isGeneratingCards = false;
      });
      AppLogger.e('生成精选卡片失败', error: e);
    }
  }

  /// 选择有代表性的笔记
  List<Quote> _selectRepresentativeQuotes(List<Quote> quotes) {
    // 按内容长度和多样性选择
    final sortedQuotes = List<Quote>.from(quotes);

    // 优先选择内容丰富的笔记
    sortedQuotes.sort((a, b) => b.content.length.compareTo(a.content.length));

    // 选择前6条，确保多样性
    final selected = <Quote>[];
    final usedKeywords = <String>{};

    for (final quote in sortedQuotes) {
      if (selected.length >= 6) break;

      // 简单的关键词去重逻辑
      final words = quote.content.toLowerCase().split(' ');
      final hasNewKeyword = words.any(
        (word) => word.length > 3 && !usedKeywords.contains(word),
      );

      if (hasNewKeyword || selected.isEmpty) {
        selected.add(quote);
        usedKeywords.addAll(words.where((word) => word.length > 3));
      }
    }

    return selected;
  }

  /// 生成AI洞察
  Future<void> _generateInsights() async {
    if (_periodQuotes.isEmpty) {
      setState(() {
        _insights = '本${_getPeriodName()}暂无笔记记录。';
      });
      return;
    }

    try {
      final aiService = context.read<AIService>();

      final prompt = '''
请分析用户在${_getPeriodName()}的笔记记录，生成简洁的洞察报告：

笔记数量：${_periodQuotes.length}条
时间范围：${_getDateRangeText()}

笔记内容摘要：
${_periodQuotes.take(5).map((q) => '- ${q.content.length > 100 ? '${q.content.substring(0, 100)}...' : q.content}').join('\n')}

请生成200字以内的洞察分析，包括：
1. 记录习惯分析
2. 内容主题总结
3. 积极的鼓励建议

保持温暖积极的语调。
''';

      final result = await aiService.polishText(prompt);

      setState(() {
        _insights = result;
      });
    } catch (e) {
      setState(() {
        _insights = '暂时无法生成洞察分析，请稍后再试。';
      });
      AppLogger.e('生成AI洞察失败', error: e);
    }
  }

  String _getPeriodName() {
    switch (_selectedPeriod) {
      case 'week':
        return '周';
      case 'month':
        return '月';
      case 'year':
        return '年';
      default:
        return '期间';
    }
  }

  String _getDateRangeText() {
    final now = _selectedDate;
    switch (_selectedPeriod) {
      case 'week':
        final weekday = now.weekday;
        final startDate = now.subtract(Duration(days: weekday - 1));
        final endDate = startDate.add(const Duration(days: 6));
        return '${startDate.month}月${startDate.day}日 - ${endDate.month}月${endDate.day}日';
      case 'month':
        return '${now.year}年${now.month}月';
      case 'year':
        return '${now.year}年';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 极简内部控制栏
        Container(
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _tabController.animateTo(0),
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: _tabController.index == 0 
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: _tabController.index == 0 
                          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '数据概览',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _tabController.index == 0 ? FontWeight.w600 : FontWeight.normal,
                          color: _tabController.index == 0 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: GestureDetector(
                  onTap: () => _tabController.animateTo(1),
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: _tabController.index == 1 
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: _tabController.index == 1 
                          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '精选卡片',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _tabController.index == 1 ? FontWeight.w600 : FontWeight.normal,
                          color: _tabController.index == 1 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: GestureDetector(
                  onTap: () => _tabController.animateTo(2),
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: _tabController.index == 2 
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: _tabController.index == 2 
                          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        'AI洞察',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _tabController.index == 2 ? FontWeight.w600 : FontWeight.normal,
                          color: _tabController.index == 2 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 时间选择器
        _buildTimeSelector(),
        // 内容区域
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDataOverview(),
              _buildFeaturedCards(),
              _buildInsights(),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建时间选择器
  Widget _buildTimeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'week', label: Text('本周')),
                ButtonSegment(value: 'month', label: Text('本月')),
                ButtonSegment(value: 'year', label: Text('本年')),
              ],
              selected: {_selectedPeriod},
              onSelectionChanged: (Set<String> selection) {
                setState(() {
                  _selectedPeriod = selection.first;
                });
                _loadPeriodData();
              },
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => _selectDate(),
            icon: const Icon(Icons.calendar_today),
            tooltip: '选择日期',
          ),
        ],
      ),
    );
  }

  /// 选择日期
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadPeriodData();
    }
  }

  /// 构建数据概览
  Widget _buildDataOverview() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalNotes = _periodQuotes.length;
    final totalWords = _periodQuotes.fold<int>(
      0,
      (sum, quote) => sum + quote.content.length,
    );
    final avgWords = totalNotes > 0 ? (totalWords / totalNotes).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_getDateRangeText()} 数据统计',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatCard('笔记数量', '$totalNotes', '条')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('总字数', '$totalWords', '字')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('平均字数', '$avgWords', '字/条')),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard('活跃天数', '${_getActiveDays()}', '天'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_periodQuotes.isNotEmpty) ...[
            Text('最近笔记', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ..._periodQuotes.take(3).map((quote) => _buildQuotePreview(quote)),
          ],
        ],
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatCard(String title, String value, String unit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Text(unit, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 获取活跃天数
  int _getActiveDays() {
    final dates =
        _periodQuotes.map((quote) {
          final date = DateTime.parse(quote.date);
          return DateTime(date.year, date.month, date.day);
        }).toSet();
    return dates.length;
  }

  /// 构建笔记预览
  Widget _buildQuotePreview(Quote quote) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          quote.content.length > 100
              ? '${quote.content.substring(0, 100)}...'
              : quote.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(DateTime.parse(quote.date).toString().substring(0, 16)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          // 可以添加跳转到笔记详情的逻辑
        },
      ),
    );
  }

  /// 构建精选卡片
  Widget _buildFeaturedCards() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_periodQuotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '本${_getPeriodName()}暂无笔记记录',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('精选卡片', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (_isGeneratingCards)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_featuredCards.isEmpty &&
                  _aiCardService?.isEnabled == true)
                TextButton.icon(
                  onPressed: _generateFeaturedCards,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('生成卡片'),
                ),
            ],
          ),
        ),
        Expanded(
          child:
              _featuredCards.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _aiCardService?.isEnabled == true
                              ? '点击上方按钮生成精美卡片'
                              : 'AI卡片生成功能未启用',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                  : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.7,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _featuredCards.length,
                    itemBuilder: (context, index) {
                      final card = _featuredCards[index];
                      return GeneratedCardWidget(
                        card: card,
                        showActions: false,
                        onTap: () => _showCardDetail(card),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  /// 显示卡片详情
  void _showCardDetail(GeneratedCard card) {
    showDialog(
      context: context,
      builder:
          (context) => CardPreviewDialog(
            card: card,
            onShare: () => _shareCard(card),
            onSave: () => _saveCard(card),
          ),
    );
  }

  /// 分享卡片
  void _shareCard(GeneratedCard card) async {
    // 复用home_page.dart中的分享逻辑
    Navigator.of(context).pop(); // 关闭对话框

    try {
      await card.toImageBytes();
      // 这里可以添加分享逻辑
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分享功能开发中')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
      }
    }
  }

  /// 保存卡片
  void _saveCard(GeneratedCard card) async {
    Navigator.of(context).pop(); // 关闭对话框

    if (_aiCardService == null) return;

    try {
      await _aiCardService!.saveCardAsImage(card);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('卡片已保存到相册'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  /// 构建AI洞察
  Widget _buildInsights() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI洞察分析', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _insights.isEmpty ? '正在生成洞察分析...' : _insights,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
