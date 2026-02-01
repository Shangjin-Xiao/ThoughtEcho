import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../gen_l10n/app_localizations.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/ai_analysis_database_service.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_loading_view.dart';
import '../models/ai_analysis_model.dart';
import '../models/quote_model.dart';
import 'ai_analysis_history_page_clean.dart';
import 'ai_settings_page.dart';
import '../theme/app_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import 'dart:async'; // Import for StreamSubscription
import '../utils/app_logger.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  bool _isLoading = false;
  Stream<String>?
      _insightsStream; // Used only to provide stream to StreamBuilder for connection state
  bool _isGenerating = false; // 新增状态变量表示是否正在生成
  bool _showAnalysisSelection = true; // 控制显示分析选择还是结果
  final TextEditingController _customPromptController = TextEditingController();
  bool _showCustomPrompt = false;
  AIAnalysisDatabaseService? _aiAnalysisDatabaseService;
  String _accumulatedInsightsText =
      ''; // Added state variable for accumulated insights text
  StreamSubscription<String>?
      _insightsSubscription; // Stream subscription for manual accumulation

  // 分析类型
  List<Map<String, dynamic>> _getAnalysisTypes(AppLocalizations l10n) {
    return [
      {
        'title': l10n.analysisTypeComprehensive,
        'icon': Icons.all_inclusive,
        'description': l10n.analysisTypeComprehensiveDesc,
        'prompt': 'comprehensive',
      },
      {
        'title': l10n.analysisTypeEmotional,
        'icon': Icons.mood,
        'description': l10n.analysisTypeEmotionalDesc,
        'prompt': 'emotional',
      },
      {
        'title': l10n.analysisTypeMindmap,
        'icon': Icons.account_tree,
        'description': l10n.analysisTypeMindmapDesc,
        'prompt': 'mindmap',
      },
      {
        'title': l10n.analysisTypeGrowth,
        'icon': Icons.trending_up,
        'description': l10n.analysisTypeGrowthDesc,
        'prompt': 'growth',
      },
    ];
  }

  // 分析风格
  List<Map<String, dynamic>> _getAnalysisStyles(AppLocalizations l10n) {
    return [
      {
        'title': l10n.analysisStyleProfessional,
        'description': l10n.analysisStyleProfessionalDesc,
        'style': 'professional',
      },
      {
        'title': l10n.analysisStyleFriendly,
        'description': l10n.analysisStyleFriendlyDesc,
        'style': 'friendly',
      },
      {
        'title': l10n.analysisStyleHumorous,
        'description': l10n.analysisStyleHumorousDesc,
        'style': 'humorous',
      },
      {
        'title': l10n.analysisStyleLiterary,
        'description': l10n.analysisStyleLiteraryDesc,
        'style': 'literary',
      },
    ];
  }

  String _selectedAnalysisType = 'comprehensive';
  String _selectedAnalysisStyle = 'professional';

  // 1. 静态key-label映射
  late Map<String, String> _analysisTypeKeyToLabel;
  late Map<String, String> _analysisStyleKeyToLabel;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    _analysisTypeKeyToLabel = {
      'comprehensive': l10n.analysisTypeComprehensive,
      'emotional': l10n.analysisTypeEmotional,
      'mindmap': l10n.analysisTypeMindmap,
      'growth': l10n.analysisTypeGrowth,
    };
    _analysisStyleKeyToLabel = {
      'professional': l10n.analysisStyleProfessional,
      'friendly': l10n.analysisStyleFriendly,
      'humorous': l10n.analysisStyleHumorous,
      'literary': l10n.analysisStyleLiterary,
    };

    if (_aiAnalysisDatabaseService == null) {
      _aiAnalysisDatabaseService = Provider.of<AIAnalysisDatabaseService>(
        context,
        listen: false,
      );
      logDebug('AIAnalysisDatabaseService initialized');
      _testDatabaseConnection();
    }
  }

  /// 测试数据库连接
  Future<void> _testDatabaseConnection() async {
    try {
      if (_aiAnalysisDatabaseService != null) {
        await _aiAnalysisDatabaseService!.database;
        logDebug('AI analysis database connection test successful');

        final analyses = await _aiAnalysisDatabaseService!.getAllAnalyses();
        logDebug('Current number of saved AI analyses: ${analyses.length}');

        await _testSaveAnalysis();
      }
    } catch (e) {
      logDebug('AI analysis database connection test failed: $e');
    }
  }

  Future<void> _testSaveAnalysis() async {
    final l10n = AppLocalizations.of(context);
    try {
      final testAnalysis = AIAnalysis(
        title: l10n.testAnalysis,
        content: l10n.testAnalysisDesc,
        analysisType: 'comprehensive',
        analysisStyle: 'professional',
        createdAt: DateTime.now().toIso8601String(),
        quoteCount: 0,
      );

      final savedAnalysis = await _aiAnalysisDatabaseService!.saveAnalysis(
        testAnalysis,
      );
      logDebug('Test save successful, ID: ${savedAnalysis.id}');

      final verifyAnalysis = await _aiAnalysisDatabaseService!.getAnalysisById(
        savedAnalysis.id!,
      );
      if (verifyAnalysis != null) {
        logDebug('Test verification successful');
        await _aiAnalysisDatabaseService!.deleteAnalysis(savedAnalysis.id!);
        logDebug('Test data cleaned up');
      } else {
        logDebug('Test verification failed');
      }
    } catch (e) {
      logDebug('Test save analysis failed: $e');
    }
  }

  @override
  void dispose() {
    _customPromptController.dispose();
    _insightsSubscription?.cancel(); // Cancel the subscription
    super.dispose();
  }

  /// 将当前分析结果保存为AI分析记录
  Future<void> _saveAnalysis(String content) async {
    final l10n = AppLocalizations.of(context);
    if (content.isEmpty) {
      logDebug('Save analysis failed: content is empty');
      return;
    }

    try {
      logDebug(
        'Starting to save AI analysis, content length: ${content.length}',
      );

      if (_aiAnalysisDatabaseService == null) {
        logDebug(
          'AIAnalysisDatabaseService not initialized, trying to re-fetch',
        );
        _aiAnalysisDatabaseService = Provider.of<AIAnalysisDatabaseService>(
          context,
          listen: false,
        );
      }

      final quoteCount = await context.read<DatabaseService>().getQuotesCount();
      logDebug('Current number of notes: $quoteCount');

      final analysis = AIAnalysis(
        title: _getAnalysisTitle(),
        content: content,
        analysisType: _selectedAnalysisType,
        analysisStyle: _selectedAnalysisStyle,
        customPrompt: _showCustomPrompt ? _customPromptController.text : null,
        createdAt: DateTime.now().toIso8601String(),
        quoteCount: quoteCount,
      );

      logDebug(
        'Creating AI analysis object: ${analysis.title}, type: ${analysis.analysisType}',
      );

      if (_aiAnalysisDatabaseService == null) {
        throw Exception('AI analysis database service not initialized');
      }

      try {
        await _aiAnalysisDatabaseService!.database;
        logDebug('Database connection test successful');
      } catch (dbError) {
        logDebug('Database connection test failed: $dbError');
        throw Exception('Database connection failed: $dbError');
      }

      final savedAnalysis = await _aiAnalysisDatabaseService!.saveAnalysis(
        analysis,
      );
      logDebug('AI analysis saved successfully, ID: ${savedAnalysis.id}');

      final verifyAnalysis = await _aiAnalysisDatabaseService!.getAnalysisById(
        savedAnalysis.id!,
      );
      if (verifyAnalysis != null) {
        logDebug(
          'Save verification successful, title: ${verifyAnalysis.title}',
        );
      } else {
        logDebug('Save verification failed, could not find the saved analysis');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.analysisSaved),
          duration: AppConstants.snackBarDurationImportant,
          action: SnackBarAction(
            label: l10n.viewHistory,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AIAnalysisHistoryPage(),
                ),
              );
            },
          ),
        ),
      );
    } catch (e, stackTrace) {
      logDebug('Failed to save AI analysis: $e');
      logDebug('Stack trace: $stackTrace');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.saveAnalysisError(e.toString())),
          backgroundColor: Colors.red,
          duration: AppConstants.snackBarDurationError,
          action: SnackBarAction(
            label: l10n.retry,
            textColor: Colors.white,
            onPressed: () => _saveAnalysis(content),
          ),
        ),
      );
    }
  }

  /// 将分析结果保存为笔记
  Future<void> _saveAsNote(String content) async {
    final l10n = AppLocalizations.of(context);
    if (content.isEmpty) return;

    try {
      final databaseService = context.read<DatabaseService>();

      // 创建一个Quote对象
      final quote = Quote(
        content: l10n.analysisNoteTitle(content, _getAnalysisTitle()),
        date: DateTime.now().toIso8601String(),
        source: l10n.aiAnalysisSource,
        sourceAuthor: l10n.thoughtechoAI,
        sourceWork: _getAnalysisTitle(),
        aiAnalysis: null, // 笔记本身就是分析，不需要再保存分析
      );

      // 使用DatabaseService保存为笔记
      await databaseService.addQuote(quote);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.savedAsNote),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.saveAsNoteError(e.toString())),
          duration: AppConstants.snackBarDurationError,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 分享分析结果
  Future<void> _shareAnalysis(String content) async {
    final l10n = AppLocalizations.of(context);
    if (content.isEmpty) return;

    try {
      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: content));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.analysisCopied),
          duration: AppConstants.snackBarDurationNormal,
        ),
      );

      // 使用share_plus分享
      await SharePlus.instance.share(ShareParams(text: content));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.shareError(e.toString())),
          duration: AppConstants.snackBarDurationError,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _generateInsights() async {
    final l10n = AppLocalizations.of(context);
    final aiService = context.read<AIService>();
    if (!aiService.hasValidApiKey()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.configureApiKey),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isGenerating = true;
      _accumulatedInsightsText = ''; // Clear accumulated text
      _accumulatedInsightsText = ''; // Clear accumulated text
      _insightsStream = null; // Clear previous stream to reset StreamBuilder
      _insightsSubscription?.cancel(); // Cancel previous subscription
      _insightsSubscription = null; // Clear previous subscription reference
    });

    try {
      final databaseService = context.read<DatabaseService>();

      final quotes = await databaseService.getUserQuotes();
      if (!mounted) return;

      if (quotes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noNotesFound),
            duration: AppConstants.snackBarDurationNormal,
          ),
        );
        setState(() {
          _isLoading = false;
          _isGenerating = false;
        });
        return;
      }

      // Get the stream
      final Stream<String> insightsStream = aiService.streamGenerateInsights(
        quotes,
        analysisType: _selectedAnalysisType,
        analysisStyle: _selectedAnalysisStyle,
        customPrompt:
            _showCustomPrompt && _customPromptController.text.isNotEmpty
                ? _customPromptController.text
                : null,
      );

      if (!mounted) {
        return; // Ensure mounted before setting stream and listening
      }

      // Set the stream variable so StreamBuilder can track connection state
      // 由于我们使用了广播流，可以让StreamBuilder和手动监听共同使用
      setState(() {
        _insightsStream =
            insightsStream; // Set the new stream for StreamBuilder
        _showAnalysisSelection = false; // 切换到结果展示
      });

      // Listen to the stream and accumulate text manually
      _insightsSubscription = insightsStream.listen(
        (String chunk) {
          if (mounted) {
            setState(() {
              _accumulatedInsightsText += chunk;
            });
          }
        },
        onError: (error) {
          logDebug('Error in insights stream: $error');
          if (mounted) {
            String errorMessage = l10n.generateInsightsError(error.toString());
            String actionText = l10n.retry;

            if (error.toString().contains('500')) {
              errorMessage = l10n.serverInternalError;
              actionText = l10n.checkSettings;
            } else if (error.toString().contains('401')) {
              errorMessage = l10n.invalidApiKey;
              actionText = l10n.checkApiKey;
            } else if (error.toString().contains('429')) {
              errorMessage = l10n.rateLimitExceeded;
              actionText = l10n.tryLater;
            } else if (error.toString().contains('Network') ||
                error.toString().contains('Connection')) {
              errorMessage = l10n.networkError;
              actionText = l10n.retry;
            }

            setState(() {
              _accumulatedInsightsText = errorMessage;
              _isGenerating = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: actionText,
                  textColor: Colors.white,
                  onPressed: () {
                    if (actionText == l10n.checkSettings ||
                        actionText == l10n.checkApiKey) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AISettingsPage(),
                        ),
                      );
                    } else {
                      _generateInsights();
                    }
                  },
                ),
              ),
            );
          }
        },
        onDone: () {
          logDebug('Insights stream finished');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isGenerating = false;
            });
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      logDebug('Failed to generate insights (setup): $e');
      if (mounted) {
        String errorMessage = l10n.generateInsightsSetupError(e.toString());

        if (e.toString().contains('500')) {
          errorMessage = l10n.serverInternalErrorConfig;
        } else if (e.toString().contains('401')) {
          errorMessage = l10n.invalidApiKeyUpdate;
        } else if (e.toString().contains('API Key')) {
          errorMessage = l10n.configureValidApiKey;
        }

        setState(() {
          _accumulatedInsightsText = errorMessage;
          _isLoading = false;
          _isGenerating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.goToSettings,
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AISettingsPage(),
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: _showAnalysisSelection
            ? _buildAnalysisSelectionView(theme)
            : _buildAnalysisResultView(theme),
      ),
      floatingActionButton: _showAnalysisSelection
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_isGenerating ||
                    (_accumulatedInsightsText.isNotEmpty && !_isLoading)) {
                  setState(() {
                    _showAnalysisSelection = false;
                  });
                } else {
                  _generateInsights();
                }
              },
              label: Text(
                _isGenerating
                    ? l10n.viewing
                    : (_accumulatedInsightsText.isNotEmpty && !_isLoading)
                        ? l10n
                            .viewHistory // Reuse "View History" or similar, or just "View Result"
                        : l10n.startAnalysis,
              ),
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white, // Ensure visibility on FAB
                      ),
                    )
                  : Icon(
                      (_accumulatedInsightsText.isNotEmpty && !_isLoading)
                          ? Icons.visibility
                          : Icons.auto_awesome,
                    ),
            )
          : null,
    );
  }

  Widget _buildAnalysisSelectionView(ThemeData theme) {
    return _buildAnalysisSelectionTab(theme);
  }

  Widget _buildAnalysisResultView(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        // 顶部操作按钮栏
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // 返回按钮
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _showAnalysisSelection = true;
                    // Fix: Do not clear state here to allow returning to ongoing generation or result
                  });
                },
              ),
              const Spacer(),
              // 历史记录按钮
              IconButton(
                icon: const Icon(Icons.history),
                color: theme.primaryColor,
                tooltip: l10n.analysisHistory,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AIAnalysisHistoryPage(),
                    ),
                  );
                },
              ),
              // 重新生成按钮
              if (!_isGenerating && _accumulatedInsightsText.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  color: theme.primaryColor,
                  tooltip: l10n.regenerate,
                  onPressed: _generateInsights,
                ),
            ],
          ),
        ),
        // 结果内容
        Expanded(child: _buildAnalysisResultTab(theme)),
      ],
    );
  }

  Widget _buildAnalysisSelectionTab(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 收藏功能移至周期报告页，智能洞察页专注AI分析
          // _buildWeeklyFavoritesSection(theme),

          // const SizedBox(height: 24),
          Text(
            l10n.selectAnalysisMethod,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // 分析类型卡片
          ..._getAnalysisTypes(
            AppLocalizations.of(context),
          ).map((type) => _buildAnalysisTypeCard(theme, type)),

          const SizedBox(height: 24),

          Text(
            l10n.selectAnalysisStyle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // 分析风格选择
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _getAnalysisStyles(AppLocalizations.of(context)).map((
                style,
              ) {
                final isSelected = _selectedAnalysisStyle == style['style'];
                final String key = style['style'];
                return ChoiceChip(
                  label: Text(_analysisStyleKeyToLabel[key] ?? key),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedAnalysisStyle = key;
                      });
                    }
                  },
                  showCheckmark: false,
                  avatar: isSelected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: theme.colorScheme.onSecondaryContainer,
                        )
                      : null,
                  selectedColor: theme.colorScheme.secondaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.transparent
                          : theme.colorScheme.outline.withOpacity(0.3),
                    ),
                  ),
                  tooltip: style['description'],
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // 自定义提示词选项
          Container(
            decoration: BoxDecoration(
              color: _showCustomPrompt
                  ? theme.colorScheme.surfaceContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: _showCustomPrompt
                  ? Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.2))
                  : null,
            ),
            padding:
                _showCustomPrompt ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _showCustomPrompt = !_showCustomPrompt;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showCustomPrompt
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          color: theme.primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.advancedOptions,
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 自定义提示词输入框
                if (_showCustomPrompt) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customPromptController,
                    decoration: InputDecoration(
                      labelText: l10n.customPrompt,
                      hintText: l10n.customPromptHint,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.inputRadius),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.inputRadius),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                    maxLines: 3,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 历史记录栏
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 0, // Flat style for history link
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              side: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
            color: theme.colorScheme.surface, // Clean surface
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              ),
              title: Text(
                l10n.analysisHistoryRecord,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(l10n.viewPreviousAnalysis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AIAnalysisHistoryPage(),
                  ),
                );
              },
            ),
          ),

          // 提示说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.analysisDescriptionTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.analysisDescription,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // AI 警告提示
          Container(
            padding: const EdgeInsets.all(16.0),
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.aiAnalysisUsageInstructionsTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.aiAnalysisUsageInstructions,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 收藏功能已移至周期报告页，保持页面专注AI分析

  Widget _buildAnalysisTypeCard(ThemeData theme, Map<String, dynamic> type) {
    final isSelected = _selectedAnalysisType == type['prompt'];
    final String key = type['prompt'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12), // Increased spacing
      elevation: isSelected ? 4 : 0.5, // Better elevation
      shadowColor: theme.shadowColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(AppTheme.cardRadius), // Use AppTheme
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withOpacity(0.1), // Subtle border
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withOpacity(0.3)
          : theme.cardColor,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedAnalysisType = key;
            _showCustomPrompt = false;
          });
        },
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(16), // Increased padding
          child: Row(
            children: [
              // Icon with container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  type['icon'],
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _analysisTypeKeyToLabel[key] ?? key,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type['description'],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        // detailed body text
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    color: theme.colorScheme.onPrimary,
                    size: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisResultTab(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    // Use StreamBuilder to listen to connection state changes of _insightsStream and display content based on _accumulatedInsightsText
    return StreamBuilder<String>(
      stream:
          _insightsStream, // Listen to stream for connection state and errors
      builder: (context, snapshot) {
        // Display different content based on generation state and accumulated text
        if (_accumulatedInsightsText.isNotEmpty) {
          // Display result card when there is accumulated text
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Analysis result card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_getAnalysisIcon(), color: theme.primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              _getAnalysisTitle(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.primaryColor,
                              ),
                            ),
                            const Spacer(),
                            // Show copy button only after generation is complete
                            if (!_isGenerating &&
                                _accumulatedInsightsText.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: l10n.copyToClipboard,
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: _accumulatedInsightsText,
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.analysisResultCopied),
                                      duration: AppConstants
                                          .snackBarDurationImportant,
                                    ),
                                  );
                                },
                              ), // Show loading indicator during generation
                            if (_isGenerating)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        // Use MarkdownBody to render accumulated text
                        MarkdownBody(
                          data:
                              _accumulatedInsightsText, // Use accumulated text
                          selectable: true,
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                              fontSize: 16,
                            ),
                            h1: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                              height: 1.5,
                            ),
                            h2: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                              height: 1.5,
                            ),
                            h3: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                            listBullet: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.primaryColor,
                            ),
                            blockquote: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                            blockquoteDecoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(
                                  color: theme.primaryColor,
                                  width: 4,
                                ),
                              ),
                            ),
                            code: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // Show share and save buttons only after generation is complete
                if (!_isGenerating && _accumulatedInsightsText.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          _saveAsNote(_accumulatedInsightsText);
                        },
                        icon: const Icon(Icons.note_add),
                        label: Text(l10n.saveAsNoteButton),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          _saveAnalysis(_accumulatedInsightsText);
                        },
                        icon: const Icon(Icons.save),
                        label: Text(l10n.saveAnalysisButton),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          _shareAnalysis(_accumulatedInsightsText);
                        },
                        icon: const Icon(Icons.share),
                        label: Text(l10n.shareInsightsButton),
                      ),
                    ],
                  ),
              ],
            ),
          );
        } else if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n.generateInsightsErrorSnapshot(snapshot.error.toString()),
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        } else if (_isGenerating) {
          return const AppLoadingView();
        } else {
          // Show empty state in initial state or when not generating and no accumulated text
          return AppEmptyView(
            svgAsset: 'assets/empty/empty_state.svg',
            text: l10n.insightsPageEmpty,
          );
        }
      },
    );
  }

  IconData _getAnalysisIcon() {
    // 如果是自定义提示词，也显示一个通用图标
    if (_showCustomPrompt && _customPromptController.text.isNotEmpty) {
      return Icons.auto_awesome; // 或者其他合适的图标
    }

    switch (_selectedAnalysisType) {
      case 'emotional':
        return Icons.mood; // 更新图标
      case 'mindmap':
        return Icons.account_tree; // 更新图标
      case 'growth':
        return Icons.trending_up; // 更新图标
      case 'comprehensive':
      default:
        return Icons.all_inclusive; // 保持不变
    }
  }

  String _getAnalysisTitle() {
    final l10n = AppLocalizations.of(context);
    if (_showCustomPrompt && _customPromptController.text.isNotEmpty) {
      return l10n.customAnalysis;
    }
    return _analysisTypeKeyToLabel[_selectedAnalysisType] ??
        _selectedAnalysisType;
  }
}
