import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/ai_analysis_model.dart';
import '../services/ai_analysis_database_service.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../models/quote_model.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_loading_view.dart';
import '../utils/app_logger.dart';
import 'ai_annual_report_webview.dart';
import 'annual_report_page.dart';

/// AI 分析历史记录页面
class AIAnalysisHistoryPage extends StatefulWidget {
  const AIAnalysisHistoryPage({super.key});

  @override
  State<AIAnalysisHistoryPage> createState() => _AIAnalysisHistoryPageState();
}

class _AIAnalysisHistoryPageState extends State<AIAnalysisHistoryPage> {
  late AIAnalysisDatabaseService _aiAnalysisDatabaseService;
  List<AIAnalysis> _analyses = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _aiAnalysisDatabaseService = Provider.of<AIAnalysisDatabaseService>(
      context,
      listen: false,
    );
    _loadAnalyses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 加载AI分析历史记录
  Future<void> _loadAnalyses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final analyses = await _aiAnalysisDatabaseService.getAllAnalyses();
      if (mounted) {
        setState(() {
          _analyses = analyses;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.e('加载AI分析历史失败', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 搜索分析记录
  List<AIAnalysis> _searchAnalyses() {
    if (_searchQuery.isEmpty) {
      return _analyses;
    }
    return _analyses.where((analysis) {
      return analysis.content.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          analysis.title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  /// 删除分析记录
  Future<void> _deleteAnalysis(AIAnalysis analysis) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认删除'),
            content: const Text('确定要删除这条分析记录吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await _aiAnalysisDatabaseService.deleteAnalysis(analysis.id!);
        _loadAnalyses();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('删除成功')));
        }
      } catch (e) {
        AppLogger.e('删除分析记录失败', error: e);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('删除失败')));
        }
      }
    }
  }

  /// 删除所有分析记录
  Future<void> _deleteAllAnalyses() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认删除'),
            content: const Text('确定要删除所有分析记录吗？此操作不可恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        for (final analysis in _analyses) {
          if (analysis.id != null) {
            await _aiAnalysisDatabaseService.deleteAnalysis(analysis.id!);
          }
        }
        _loadAnalyses();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('所有记录已删除')));
        }
      } catch (e) {
        AppLogger.e('删除所有分析记录失败', error: e);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('删除失败')));
        }
      }
    }
  }

  /// 查看分析详情
  void _viewAnalysisDetails(AIAnalysis analysis) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'AI分析详情',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '分析时间',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          analysis.createdAt,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '分析内容',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            analysis.content,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'AI分析结果',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: MarkdownBody(
                            data: analysis.title,
                            styleSheet: MarkdownStyleSheet(
                              p: Theme.of(context).textTheme.bodyMedium,
                              h1: Theme.of(context).textTheme.titleLarge,
                              h2: Theme.of(context).textTheme.titleMedium,
                              h3: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  /// 获取分析类型图标
  IconData _getAnalysisTypeIcon(String type) {
    switch (type) {
      case 'emotional':
        return Icons.sentiment_satisfied;
      case 'comprehensive':
        return Icons.analytics;
      case 'mindmap':
        return Icons.account_tree;
      case 'growth':
        return Icons.trending_up;
      default:
        return Icons.psychology;
    }
  }

  /// 获取分析类型名称
  String _getAnalysisTypeName(String type) {
    switch (type) {
      case 'emotional':
        return '情感分析';
      case 'comprehensive':
        return '综合分析';
      case 'mindmap':
        return '思维导图';
      case 'growth':
        return '成长分析';
      default:
        return 'AI分析';
    }
  }

  /// 生成年度报告
  Future<void> _generateAnnualReport() async {
    try {
      // 显示选择对话框
      final choice = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('选择年度报告类型'),
              content: const Text('请选择要生成的年度报告类型：'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'ai'),
                  child: const Text('AI 生成报告'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'flutter'),
                  child: const Text('原生 Flutter 报告'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
      );

      if (choice == null) return;

      // 获取今年的笔记数据
      if (!mounted) return;
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final quotes = await databaseService.getUserQuotes();
      if (!mounted) return;
      
      final currentYear = DateTime.now().year;

      final thisYearQuotes =
          quotes.where((quote) {
            final quoteDate = DateTime.parse(quote.date);
            return quoteDate.year == currentYear;
          }).toList();

      if (choice == 'ai') {
        await _generateAIAnnualReport(thisYearQuotes, currentYear);
      } else {
        await _generateFlutterAnnualReport(thisYearQuotes, currentYear);
      }
    } catch (e) {
      AppLogger.e('生成年度报告失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成年度报告失败')));
      }
    }
  }

  /// 生成AI年度报告
  Future<void> _generateAIAnnualReport(List<Quote> quotes, int year) async {
    if (!mounted) return;

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('正在生成AI年度报告...'),
              ],
            ),
          ),
    );

    try {
      final aiService = Provider.of<AIService>(context, listen: false);

      // 准备数据摘要
      final totalNotes = quotes.length;
      final totalWords = quotes.fold<int>(
        0,
        (sum, quote) => sum + quote.content.length,
      );
      final averageWordsPerNote =
          totalNotes > 0 ? (totalWords / totalNotes).round() : 0;

      // 获取标签统计
      final Map<String, int> tagCounts = {};
      for (final quote in quotes) {
        for (final tagId in quote.tagIds) {
          tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
        }
      }

      // 获取积极的笔记内容示例（避免消极内容）
      final positiveKeywords = [
        '成长',
        '学习',
        '进步',
        '成功',
        '快乐',
        '感谢',
        '收获',
        '突破',
        '希望',
      ];
      final positiveQuotes = quotes
          .where(
            (quote) => positiveKeywords.any(
              (keyword) => quote.content.contains(keyword),
            ),
          )
          .take(5)
          .map((quote) => quote.content)
          .join('\n');

      final prompt = '''
你是一个年度报告生成助手。请基于以下用户的笔记数据，生成一份温暖、积极、有意义的年度总结报告。

用户数据：
- 年份：$year
- 总笔记数：$totalNotes 篇
- 总字数：$totalWords 字
- 平均每篇字数：$averageWordsPerNote 字
- 主要标签：${tagCounts.keys.take(5).join(', ')}

部分积极内容示例：
$positiveQuotes

请参考我提供的HTML模板结构，生成一份完整的HTML年度报告。要求：
1. 保持模板的美观设计和响应式布局
2. 用真实数据替换模板中的示例数据
3. 在精彩回顾部分，只选择积极、正面、有成长意义的内容
4. 生成鼓励性的洞察和建议
5. 保持语气温暖、积极向上
6. 确保HTML在移动端浏览器中能正常显示

请直接返回完整的HTML代码，不需要其他说明。
''';

      final result = await aiService.analyzeSource(prompt);
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (result.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    AIAnnualReportWebView(htmlContent: result, year: year),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
      }
      AppLogger.e('生成AI年度报告失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成AI年度报告失败')));
      }
    }
  }

  /// 生成Flutter年度报告
  Future<void> _generateFlutterAnnualReport(
    List<Quote> quotes,
    int year,
  ) async {
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnnualReportPage(year: year, quotes: quotes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredAnalyses = _searchAnalyses();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI分析历史'),
        actions: [
          IconButton(
            onPressed: _generateAnnualReport,
            icon: const Icon(Icons.analytics),
            tooltip: '年度报告',
          ),
          if (_analyses.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete_all') {
                  _deleteAllAnalyses();
                }
              },
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(
                      value: 'delete_all',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep),
                          SizedBox(width: 8),
                          Text('清空记录'),
                        ],
                      ),
                    ),
                  ],
            ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          if (_analyses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索分析记录...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon:
                      _searchQuery.isNotEmpty
                          ? IconButton(
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                              _loadAnalyses();
                            },
                            icon: const Icon(Icons.clear),
                          )
                          : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                  if (value.isEmpty) {
                    _loadAnalyses();
                  } else {
                    _searchAnalyses();
                  }
                },
              ),
            ),

          // 内容区域
          Expanded(
            child:
                _isLoading
                    ? const AppLoadingView()
                    : filteredAnalyses.isEmpty
                    ? AppEmptyView(
                      svgAsset: 'assets/empty/empty_state.svg',
                      text:
                          _analyses.isEmpty
                              ? '暂无AI分析记录\n在笔记页面点击AI分析按钮，开始你的第一次AI分析吧！'
                              : '未找到匹配的记录\n尝试使用其他关键词搜索',
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredAnalyses.length,
                      itemBuilder: (context, index) {
                        final analysis = filteredAnalyses[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.cardRadius,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _viewAnalysisDetails(analysis),
                            borderRadius: BorderRadius.circular(
                              AppTheme.cardRadius,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _getAnalysisTypeIcon(
                                          analysis.analysisType,
                                        ),
                                        size: 20,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _getAnalysisTypeName(
                                            analysis.analysisType,
                                          ),
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                        ),
                                      ),
                                      Text(
                                        analysis.createdAt,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'delete') {
                                            _deleteAnalysis(analysis);
                                          }
                                        },
                                        itemBuilder:
                                            (context) => [
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.delete,
                                                      size: 16,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text('删除'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    analysis.content,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      analysis.title,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
