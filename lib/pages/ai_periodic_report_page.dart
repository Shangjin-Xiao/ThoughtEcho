import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
  bool _isGeneratingInsights = false;
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

      // 自动生成内容时，先检查是否已经有内容
      if (filteredQuotes.isNotEmpty &&
          _aiCardService != null &&
          _featuredCards.isEmpty) {
        _generateFeaturedCards();
      }

      // 自动生成洞察时，先检查是否已经有内容
      if (_insights.isEmpty) {
        _generateInsights();
      }
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
    if (_aiCardService == null || _periodQuotes.isEmpty || _isGeneratingCards) {
      return;
    }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成卡片失败: $e')),
        );
      }
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
    if (_isGeneratingInsights) return;

    if (_periodQuotes.isEmpty) {
      setState(() {
        _insights = '本${_getPeriodName()}暂无笔记记录。';
      });
      return;
    }

    setState(() {
      _isGeneratingInsights = true;
    });

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
        _isGeneratingInsights = false;
      });
    } catch (e) {
      setState(() {
        _insights = '暂时无法生成洞察分析，请稍后再试。';
        _isGeneratingInsights = false;
      });
      AppLogger.e('生成AI洞察失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成洞察失败: $e')),
        );
      }
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
        // 现代化标签栏
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildTabItem(0, '数据概览', Icons.analytics_outlined),
              _buildTabItem(1, '精选卡片', Icons.auto_awesome_outlined),
              _buildTabItem(2, 'AI洞察', Icons.insights),
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

  /// 构建标签项
  Widget _buildTabItem(int index, String title, IconData icon) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建时间选择器
  Widget _buildTimeSelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '时间范围',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () => _selectDate(),
                  icon: Icon(
                    Icons.calendar_today,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  tooltip: '选择具体日期',
                  iconSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'week',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.view_week, size: 16),
                    SizedBox(width: 4),
                    Text('本周'),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'month',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_view_month, size: 16),
                    SizedBox(width: 4),
                    Text('本月'),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'year',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.today, size: 16),
                    SizedBox(width: 4),
                    Text('本年'),
                  ],
                ),
              ),
            ],
            selected: {_selectedPeriod},
            onSelectionChanged: (Set<String> selection) {
              setState(() {
                _selectedPeriod = selection.first;
                // 切换时间范围时，重置生成的内容
                _featuredCards = [];
                _insights = '';
              });
              _loadPeriodData();
            },
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
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
        // 切换日期时，重置生成的内容
        _featuredCards = [];
        _insights = '';
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
          // 标题优化：添加图标和更好的视觉层次
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据概览',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    Text(
                      _getDateRangeText(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 统计卡片网格
          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      '笔记数量', '$totalNotes', '条', Icons.note_alt_outlined)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStatCard(
                      '总字数', '$totalWords', '字', Icons.text_fields)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      '平均字数', '$avgWords', '字/条', Icons.calculate_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard('活跃天数', '${_getActiveDays()}', '天',
                    Icons.calendar_today_outlined),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 最近笔记部分
          if (_periodQuotes.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '最近笔记',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._periodQuotes.take(3).map((quote) => _buildQuotePreview(quote)),
          ] else ...[
            // 空状态优化
            _buildEmptyState(),
          ],
        ],
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatCard(String title, String value, String unit,
      [IconData? icon]) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.note_add_outlined,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '本${_getPeriodName()}暂无笔记',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始记录您的思考吧',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }

  /// 获取活跃天数
  int _getActiveDays() {
    final dates = _periodQuotes.map((quote) {
      final date = DateTime.parse(quote.date);
      return DateTime(date.year, date.month, date.day);
    }).toSet();
    return dates.length;
  }

  /// 构建笔记预览
  Widget _buildQuotePreview(Quote quote) {
    final date = DateTime.parse(quote.date);
    final formattedDate =
        '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // 可以添加跳转到笔记详情的逻辑
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.content.length > 120
                      ? '${quote.content.substring(0, 120)}...'
                      : quote.content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${quote.content.length} 字',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
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
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '精选卡片',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_featuredCards.isNotEmpty)
                      Text(
                        '共 ${_featuredCards.length} 张卡片',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
              if (_isGeneratingCards)
                Container(
                  padding: const EdgeInsets.all(8),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_featuredCards.isEmpty &&
                  _aiCardService?.isEnabled == true)
                FilledButton.icon(
                  onPressed: _generateFeaturedCards,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('生成卡片'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                )
              else if (_featuredCards.isNotEmpty &&
                  _aiCardService?.isEnabled == true)
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _featuredCards = [];
                    });
                    _generateFeaturedCards();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新生成'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _featuredCards.isEmpty
              ? _buildFeaturedCardsEmptyState()
              : _buildFeaturedCardsGrid(),
        ),
      ],
    );
  }

  /// 构建精选卡片空状态
  Widget _buildFeaturedCardsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _aiCardService?.isEnabled == true
                    ? Icons.auto_awesome_outlined
                    : Icons.settings_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _aiCardService?.isEnabled == true ? '暂无精选卡片' : 'AI功能未启用',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              _aiCardService?.isEnabled == true
                  ? '基于您的笔记内容，AI将为您生成精美的分享卡片'
                  : '请在设置中配置AI服务以使用此功能',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (_aiCardService?.isEnabled != true) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  // 跳转到设置页面
                  Navigator.pushNamed(context, '/settings');
                },
                icon: const Icon(Icons.settings),
                label: const Text('前往设置'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建精选卡片网格
  Widget _buildFeaturedCardsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _featuredCards.length,
      itemBuilder: (context, index) {
        final card = _featuredCards[index];
        return AnimatedContainer(
          duration: Duration(milliseconds: 200 + (index * 50)),
          curve: Curves.easeOutCubic,
          child: GeneratedCardWidget(
            card: card,
            showActions: false,
            onTap: () => _showCardDetail(card),
          ),
        );
      },
    );
  }

  /// 显示卡片详情
  void _showCardDetail(GeneratedCard card) {
    showDialog(
      context: context,
      builder: (context) => CardPreviewDialog(
        card: card,
        onShare: () => _shareCard(card),
        onSave: () => _saveCard(card),
      ),
    );
  }

  /// 分享卡片
  void _shareCard(GeneratedCard card) async {
    Navigator.of(context).pop(); // 关闭对话框

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
      );

      final tempDir = await getTemporaryDirectory();
      final fileName =
          '心迹_Report_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // 分享文件
      await SharePlus.instance.share(
        ShareParams(
          text:
              '来自心迹周期报告的精美卡片\n\n"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
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

  /// 保存卡片
  void _saveCard(GeneratedCard card) async {
    Navigator.of(context).pop(); // 关闭对话框

    if (_aiCardService == null) return;

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
        customName:
            '心迹_Report_Card_${DateTime.now().millisecondsSinceEpoch}',
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
          // 标题栏优化
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.insights,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI洞察分析',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '基于您的笔记内容生成的智能分析',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (_isGeneratingInsights)
                Container(
                  padding: const EdgeInsets.all(8),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_insights.isNotEmpty && _periodQuotes.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _insights = '';
                    });
                    _generateInsights();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新生成'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // 洞察内容卡片
          if (_insights.isEmpty && _isGeneratingInsights)
            _buildInsightsLoadingCard()
          else if (_insights.isEmpty && _periodQuotes.isEmpty)
            _buildInsightsEmptyState()
          else if (_insights.isNotEmpty)
            _buildInsightsContentCard()
          else
            _buildInsightsGenerateButton(),
        ],
      ),
    );
  }

  /// 构建洞察加载卡片
  Widget _buildInsightsLoadingCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在分析您的笔记内容...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'AI正在深度理解您的思考模式',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建洞察内容卡片
  Widget _buildInsightsContentCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '智能洞察',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _insights,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '由 AI 智能生成',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建洞察空状态
  Widget _buildInsightsEmptyState() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.note_alt_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '本${_getPeriodName()}暂无笔记记录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '记录一些思考和感悟，AI将为您提供智能洞察',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建洞察生成按钮
  Widget _buildInsightsGenerateButton() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.insights,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '生成AI洞察分析',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI将深度分析您的笔记内容，提供个性化洞察',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _generateInsights,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('生成洞察'),
            ),
          ],
        ),
      ),
    );
  }
}
