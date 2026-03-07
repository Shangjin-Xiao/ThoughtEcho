import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../gen_l10n/app_localizations.dart';
import '../constants/app_constants.dart';
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
  AIAnalysisDatabaseService? _aiAnalysisDatabaseService;
  List<AIAnalysis> _analyses = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 延迟初始化AIAnalysisDatabaseService，避免在initState中使用context
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在didChangeDependencies中安全地获取AIAnalysisDatabaseService实例
    if (_aiAnalysisDatabaseService == null) {
      _aiAnalysisDatabaseService = Provider.of<AIAnalysisDatabaseService>(
        context,
        listen: false,
      );
      AppLogger.i('AI分析历史页面：数据库服务已初始化', source: 'AIAnalysisHistory');
      _loadAnalyses();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 加载AI分析历史记录
  Future<void> _loadAnalyses() async {
    if (_aiAnalysisDatabaseService == null) {
      AppLogger.e('AI分析数据库服务未初始化');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final analyses = await _aiAnalysisDatabaseService!.getAllAnalyses();
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
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).confirmDelete),
        content: Text(AppLocalizations.of(context).confirmDeleteAnalysis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_aiAnalysisDatabaseService == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)
                  .serviceNotInitializedDeleteFailed),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
        return;
      }

      try {
        await _aiAnalysisDatabaseService!.deleteAnalysis(analysis.id!);
        _loadAnalyses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).deleteSuccess),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
        }
      } catch (e) {
        AppLogger.e('删除分析记录失败', error: e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).deleteFailed(e.toString()),
              ),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
      }
    }
  }

  /// 删除所有分析记录
  Future<void> _deleteAllAnalyses() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).confirmDeleteAll),
        content: Text(AppLocalizations.of(context).deleteAllConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_aiAnalysisDatabaseService == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)
                  .serviceNotInitializedDeleteFailed),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
        return;
      }

      try {
        await Future.wait(_analyses.map((analysis) async {
          try {
            if (analysis.id != null) {
              await _aiAnalysisDatabaseService!.deleteAnalysis(analysis.id!);
            }
          } catch (itemErr) {
            AppLogger.e('删除单个AI分析记录失败: ${analysis.id}', error: itemErr);
          }
        }));
        _loadAnalyses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).allRecordsDeleted),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
        }
      } catch (e) {
        AppLogger.e('删除所有分析记录失败', error: e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).deleteFailedSimple),
              duration: AppConstants.snackBarDurationError,
            ),
          );
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
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85, // Slightly taller
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.dialogRadius), // Use AppTheme
          ),
          boxShadow: AppTheme.defaultShadow, // Add shadow
        ),
        child: Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).aiAnalysisDetails,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              analysis
                                  .createdAt, // Consider formatting date nicer
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24), // More padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Analysis Content Section
                    _buildSectionHeader(
                      context,
                      AppLocalizations.of(context).analysisContent,
                      Icons.article_outlined,
                    ),
                    const SizedBox(height: 12),
                    MarkdownBody(
                      data: analysis.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ).copyWith(
                        p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                              fontSize: 16,
                            ),
                        h1: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        h2: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        blockquote:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                        blockquoteDecoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 4,
                            ),
                          ),
                        ),
                        code: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            ),
                        codeblockDecoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32), // Spacing at bottom
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ],
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
        return AppLocalizations.of(context).emotionalAnalysis;
      case 'comprehensive':
        return AppLocalizations.of(context).comprehensiveAnalysis;
      case 'mindmap':
        return AppLocalizations.of(context).mindMapAnalysis;
      case 'growth':
        return AppLocalizations.of(context).growthAnalysis;
      default:
        return AppLocalizations.of(context).aiAnalysis;
    }
  }

  /// 构建报告选项卡片
  Widget _buildReportOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  /// 生成年度报告
  Future<void> _generateAnnualReport() async {
    try {
      // 显示选择对话框
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  AppLocalizations.of(context).selectAnnualReportType,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).selectReportTypePrompt,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              _buildReportOption(
                context,
                icon: Icons.psychology,
                title: AppLocalizations.of(context).aiSmartReport,
                description: AppLocalizations.of(context).aiSmartReportDesc,
                color: Colors.purple,
                onTap: () => Navigator.pop(context, 'ai'),
              ),
              const SizedBox(height: 12),
              _buildReportOption(
                context,
                icon: Icons.dashboard,
                title: AppLocalizations.of(context).nativeFlutterReport,
                description:
                    AppLocalizations.of(context).nativeFlutterReportDesc,
                color: Colors.blue,
                onTap: () => Navigator.pop(context, 'flutter'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).cancel),
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

      final thisYearQuotes = quotes.where((quote) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).generateAnnualReportFailed),
            duration: AppConstants.snackBarDurationError,
          ),
        );
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
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(l10n.generatingAIAnnualReport),
            ],
          ),
        );
      },
    );

    try {
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final aiService = Provider.of<AIService>(context, listen: false);

      // 读取HTML模板
      String htmlTemplate;
      try {
        htmlTemplate = await rootBundle.loadString(
          'assets/annual_report_ai_template.html',
        );
      } catch (e) {
        AppLogger.e('读取HTML模板失败', error: e);
        throw Exception('无法读取报告模板');
      }

      // 准备数据摘要
      final totalNotes = quotes.length;
      final totalWords = quotes.fold<int>(
        0,
        (sum, quote) => sum + quote.content.split('').length,
      );
      final averageWordsPerNote =
          totalNotes > 0 ? (totalWords / totalNotes).round() : 0;

      // 计算活跃天数
      final uniqueDates = quotes.map((quote) {
        final date = DateTime.parse(quote.date);
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }).toSet();
      final activeDays = uniqueDates.length;

      // 获取分类统计（转换为分类名称）
      final Map<String, int> categoryCounts = {};
      for (final quote in quotes) {
        if (quote.categoryId != null && quote.categoryId!.isNotEmpty) {
          try {
            final category = await databaseService.getCategoryById(
              quote.categoryId!,
            );
            if (category != null) {
              categoryCounts[category.name] =
                  (categoryCounts[category.name] ?? 0) + 1;
            }
          } catch (e) {
            // 忽略无效的分类ID
            continue;
          }
        }
      }

      // 获取月度统计
      final Map<int, int> monthlyStats = {};
      for (final quote in quotes) {
        final date = DateTime.parse(quote.date);
        monthlyStats[date.month] = (monthlyStats[date.month] ?? 0) + 1;
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
        '开心',
        '满足',
        '充实',
        '美好',
        '温暖',
        '感动',
        '惊喜',
        '兴奋',
        '自豪',
        '坚持',
        '努力',
        '奋斗',
        '梦想',
        '目标',
        '计划',
        '改变',
        '提升',
        '优秀',
      ];

      final positiveQuotes = quotes
          .where(
            (quote) => positiveKeywords.any(
              (keyword) => quote.content.contains(keyword),
            ),
          )
          .take(8)
          .toList();

      // 构建详细的数据摘要
      final monthlyStatsText = List.generate(
        12,
        (i) => '${i + 1}月: ${monthlyStats[i + 1] ?? 0}篇',
      ).join('\n');
      final positiveQuotesText = positiveQuotes
          .map(
            (quote) =>
                '- ${quote.content.length > 100 ? '${quote.content.substring(0, 100)}...' : quote.content}',
          )
          .join('\n');
      final categoryText = categoryCounts.entries
          .take(10)
          .map((e) => '${e.key}(${e.value}次)')
          .join(', ');

      // 尝试AI生成，如果失败则使用备用方案
      String result;
      try {
        final prompt = '''
请基于以下数据生成一个完整的HTML年度报告。

数据统计：
- 年份：$year
- 总笔记数：$totalNotes 篇
- 总字数：$totalWords 字
- 平均每篇字数：$averageWordsPerNote 字
- 活跃记录天数：$activeDays 天
- 使用分类数：${categoryCounts.length} 个
- 最常用分类：$categoryText

月度分布：
$monthlyStatsText

精选积极内容（${positiveQuotes.length}条）：
$positiveQuotesText

请生成一个包含以下元素的完整HTML年度报告：
1. 精美的头部区域，显示年份和主要统计数据
2. 月度笔记数量的可视化图表
3. 分类标签云展示
4. 精选笔记内容展示
5. 成长洞察和总结
6. 现代化的移动端适配样式

请直接返回完整的HTML代码，不要包含任何解释文字。
''';

        final aiResult = await aiService.generateAnnualReportHTML(prompt);

        // 检查AI返回的内容是否为HTML
        if (aiResult.trim().toLowerCase().startsWith('<!doctype') ||
            aiResult.trim().toLowerCase().startsWith('<html')) {
          result = aiResult;
        } else {
          // AI返回的不是HTML，使用备用方案
          result = await _generateFallbackReport(
            htmlTemplate,
            quotes,
            year,
            activeDays,
            totalNotes,
            totalWords,
            averageWordsPerNote,
            categoryCounts,
            monthlyStats,
            positiveQuotes,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(AppLocalizations.of(context).aiReturnFormatAbnormal),
                duration: AppConstants.snackBarDurationImportant,
              ),
            );
          }
        }
      } catch (aiError) {
        // AI调用失败，使用备用方案
        result = await _generateFallbackReport(
          htmlTemplate,
          quotes,
          year,
          activeDays,
          totalNotes,
          totalWords,
          averageWordsPerNote,
          categoryCounts,
          monthlyStats,
          positiveQuotes,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).aiServiceAbnormal),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (result.isNotEmpty) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  AIAnnualReportWebView(htmlContent: result, year: year),
            ),
          );
        }
      } else {
        throw Exception('生成报告失败');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
      }
      AppLogger.e('生成AI年度报告失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${AppLocalizations.of(context).generateAnnualReportFailed}: ${e.toString()}'),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 生成备用HTML报告
  Future<String> _generateFallbackReport(
    String template,
    List<Quote> quotes,
    int year,
    int activeDays,
    int totalNotes,
    int totalWords,
    int averageWordsPerNote,
    Map<String, int> categoryCounts,
    Map<int, int> monthlyStats,
    List<Quote> positiveQuotes,
  ) async {
    // 生成月度图表HTML
    final monthlyChart = List.generate(12, (i) {
      final month = i + 1;
      final count = monthlyStats[month] ?? 0;
      final monthNames = [
        AppLocalizations.of(context).monthJan,
        AppLocalizations.of(context).monthFeb,
        AppLocalizations.of(context).monthMar,
        AppLocalizations.of(context).monthApr,
        AppLocalizations.of(context).monthMay,
        AppLocalizations.of(context).monthJun,
        AppLocalizations.of(context).monthJul,
        AppLocalizations.of(context).monthAug,
        AppLocalizations.of(context).monthSep,
        AppLocalizations.of(context).monthOct,
        AppLocalizations.of(context).monthNov,
        AppLocalizations.of(context).monthDec,
      ];
      return '<div class="month-item"><div class="month-name">${monthNames[i]}</div><div class="month-count">$count</div></div>';
    }).join('\n');

    // 生成分类标签云HTML
    final tagCloud = categoryCounts.entries.take(10).map((entry) {
      final isPopular = entry.value > (totalNotes * 0.1);
      return '<span class="tag${isPopular ? ' popular' : ''}">${entry.key}</span>';
    }).join('');

    // 生成精选笔记HTML
    final featuredQuotes = positiveQuotes.take(3).map((quote) {
      final content = quote.content.length > 150
          ? '${quote.content.substring(0, 150)}...'
          : quote.content;
      final date = DateTime.parse(quote.date).toString().substring(0, 10);
      return '<div class="quote-card"><div class="quote-content">$content</div><div class="quote-date">$date</div></div>';
    }).join('\n');

    // 生成成就HTML
    final achievements = [
      if (totalNotes >= 50)
        '<div class="achievement"><div class="achievement-icon">🏆</div><div class="achievement-title">记录达人</div><div class="achievement-desc">记录了$totalNotes条笔记</div></div>',
      if (activeDays >= 30)
        '<div class="achievement"><div class="achievement-icon">📅</div><div class="achievement-title">坚持不懈</div><div class="achievement-desc">活跃记录$activeDays天</div></div>',
      if (totalWords >= 10000)
        '<div class="achievement"><div class="achievement-icon">✍️</div><div class="achievement-title">文字创作者</div><div class="achievement-desc">累计写作$totalWords字</div></div>',
      if (categoryCounts.isNotEmpty)
        '<div class="achievement"><div class="achievement-icon">🎯</div><div class="achievement-title">分类整理</div><div class="achievement-desc">使用了${categoryCounts.length}个分类</div></div>',
    ].join('\n');

    // 替换模板中的占位符
    return template
        .replaceAll('{{YEAR}}', year.toString())
        .replaceAll('{{ACTIVE_DAYS}}', activeDays.toString())
        .replaceAll('{{TOTAL_NOTES}}', totalNotes.toString())
        .replaceAll('{{TOTAL_TAGS}}', categoryCounts.length.toString())
        .replaceAll('{{TOTAL_WORDS}}', totalWords.toString())
        .replaceAll('{{AVERAGE_WORDS}}', averageWordsPerNote.toString())
        .replaceAll('{{NEXT_YEAR}}', (year + 1).toString())
        .replaceAll('{{GROWTH_PERCENTAGE}}', '持续成长中')
        .replaceAll('{{MONTHLY_CHART}}', monthlyChart)
        .replaceAll('{{TAG_CLOUD}}', tagCloud)
        .replaceAll(
          '{{TAG_INSIGHT}}',
          '您在${categoryCounts.keys.take(3).join('、')}等方面记录较多，体现了丰富的思考维度。',
        )
        .replaceAll('{{PEAK_TIME}}', '全天候')
        .replaceAll('{{PEAK_TIME_DESC}}', '您的记录时间分布均匀，体现了良好的记录习惯。')
        .replaceAll(
          '{{WRITING_HABITS}}',
          '您保持着规律的记录习惯，平均每篇笔记$averageWordsPerNote字，内容丰富且有深度。',
        )
        .replaceAll('{{FEATURED_QUOTES}}', featuredQuotes)
        .replaceAll('{{ACHIEVEMENTS}}', achievements)
        .replaceAll(
          '{{FUTURE_SUGGESTIONS}}',
          '继续保持记录的好习惯，可以尝试在不同时间段记录，丰富内容的多样性。建议定期回顾过往记录，从中获得成长的启发。',
        );
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
        // ignore: deprecated_member_use_from_same_package
        builder: (context) => AnnualReportPage(year: year, quotes: quotes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredAnalyses = _searchAnalyses();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).aiAnalysis),
        actions: [
          IconButton(
            onPressed: _loadAnalyses,
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).refresh,
          ),
          IconButton(
            onPressed: _generateAnnualReport,
            icon: const Icon(Icons.analytics),
            tooltip: AppLocalizations.of(context).annualReport,
          ),
          if (_analyses.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete_all') {
                  _deleteAllAnalyses();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep),
                      SizedBox(width: 8),
                      Text(AppLocalizations.of(context).clearRecords),
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
                  hintText: AppLocalizations.of(context).searchAnalysisRecords,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
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
            child: _isLoading
                ? const AppLoadingView()
                : filteredAnalyses.isEmpty
                    ? AppEmptyView(
                        svgAsset: 'assets/empty/empty_state.svg',
                        text: _analyses.isEmpty
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
                            elevation: 2,
                            shadowColor: Theme.of(context)
                                .colorScheme
                                .shadow
                                .withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.cardRadius,
                              ),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.1),
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
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.3),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            _getAnalysisTypeIcon(
                                              analysis.analysisType,
                                            ),
                                            size: 20,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _getAnalysisTypeName(
                                                  analysis.analysisType,
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                              Text(
                                                analysis.createdAt,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: Icon(
                                            Icons.more_vert,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          onSelected: (value) {
                                            if (value == 'delete') {
                                              _deleteAnalysis(analysis);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline,
                                                    size: 20,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    AppLocalizations.of(context)
                                                        .delete,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        analysis.content,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              height: 1.5,
                                            ),
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
