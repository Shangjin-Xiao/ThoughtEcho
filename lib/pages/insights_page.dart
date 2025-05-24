import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/ai_analysis_database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_loading_view.dart';
import '../models/ai_analysis_model.dart';
import '../models/quote_model.dart';
import 'ai_analysis_history_page.dart';
import 'ai_settings_page.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'dart:async'; // Import for StreamSubscription

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  Stream<String>?
  _insightsStream; // Used only to provide stream to StreamBuilder for connection state
  String _currentInsightsText = ''; // Not used for display anymore
  bool _isGenerating = false; // 新增状态变量表示是否正在生成
  late TabController _tabController;
  final TextEditingController _customPromptController = TextEditingController();
  bool _showCustomPrompt = false;
  late AIAnalysisDatabaseService _aiAnalysisDatabaseService;
  String _accumulatedInsightsText =
      ''; // Added state variable for accumulated insights text
  StreamSubscription<String>?
  _insightsSubscription; // Stream subscription for manual accumulation

  // 分析类型
  final List<Map<String, dynamic>> _analysisTypes = [
    {
      'title': '全面分析',
      'icon': Icons.all_inclusive, // 保持不变
      'description': '综合分析您所有笔记，探索主题、情感和思维模式',
      'prompt': 'comprehensive',
    },
    {
      'title': '情感洞察',
      'icon': Icons.mood, // 更新图标
      'description': '分析您的情绪状态和变化趋势',
      'prompt': 'emotional',
    },
    {
      'title': '思维导图',
      'icon': Icons.account_tree, // 更新图标
      'description': '构建您思考的结构和思维习惯分析',
      'prompt': 'mindmap',
    },
    {
      'title': '成长建议',
      'icon': Icons.trending_up, // 更新图标
      'description': '根据您的笔记提供个性化成长和进步建议',
      'prompt': 'growth',
    },
  ];

  // 分析风格
  final List<Map<String, dynamic>> _analysisStyles = [
    {
      'title': '专业分析',
      'description': '以专业、客观的方式分析您的笔记',
      'style': 'professional',
    },
    {'title': '友好导师', 'description': '像一位友好的导师给予温和的建议', 'style': 'friendly'},
    {'title': '风趣幽默', 'description': '以幽默风趣的方式解读您的思考', 'style': 'humorous'},
    {'title': '文学风格', 'description': '以优美的文学语言描述您的思考旅程', 'style': 'literary'},
  ];

  String _selectedAnalysisType = 'comprehensive';
  String _selectedAnalysisStyle = 'professional';

  // 1. 静态key-label映射
  static const Map<String, String> _analysisTypeKeyToLabel = {
    'comprehensive': '全面分析',
    'emotional': '情感洞察',
    'mindmap': '思维导图',
    'growth': '成长建议',
  };
  static const Map<String, String> _analysisStyleKeyToLabel = {
    'professional': '专业分析',
    'friendly': '友好导师',
    'humorous': '风趣幽默',
    'literary': '文学风格',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _aiAnalysisDatabaseService = AIAnalysisDatabaseService();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customPromptController.dispose();
    _insightsSubscription?.cancel(); // Cancel the subscription
    super.dispose();
  }

  /// 将当前分析结果保存为AI分析记录
  Future<void> _saveAnalysis(String content) async {
    if (content.isEmpty) return;

    try {
      // 创建一个新的AI分析对象
      final analysis = AIAnalysis(
        title: _getAnalysisTitle(), // 使用当前选择的分析类型作为标题
        content: content,
        analysisType: _selectedAnalysisType,
        analysisStyle: _selectedAnalysisStyle,
        customPrompt: _showCustomPrompt ? _customPromptController.text : null,
        createdAt: DateTime.now().toIso8601String(),
        quoteCount: await context.read<DatabaseService>().getUserQuotesCount(),
      );

      // 保存到数据库
      await _aiAnalysisDatabaseService.saveAnalysis(analysis);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('分析结果已保存'),
          action: SnackBarAction(
            label: '查看历史',
            onPressed: () {
              // 导航到分析历史记录页面
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存分析失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 将分析结果保存为笔记
  Future<void> _saveAsNote(String content) async {
    if (content.isEmpty) return;

    try {
      final databaseService = context.read<DatabaseService>();

      // 创建一个Quote对象
      final quote = Quote(
        content: "# ${_getAnalysisTitle()}\n\n$content",
        date: DateTime.now().toIso8601String(),
        source: "AI分析",
        sourceAuthor: "心迹AI",
        sourceWork: _getAnalysisTitle(),
        aiAnalysis: null, // 笔记本身就是分析，不需要再保存分析
      );

      // 使用DatabaseService保存为笔记
      await databaseService.addQuote(quote);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存为新笔记')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存为笔记失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 分享分析结果
  Future<void> _shareAnalysis(String content) async {
    if (content.isEmpty) return;

    try {
      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: content));

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分析结果已复制到剪贴板，可以粘贴分享')));

      // TODO: 如果需要使用分享插件，可以在这里添加
      // 目前先简化为复制到剪贴板
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _generateInsights() async {
    final aiService = context.read<AIService>();
    if (!aiService.hasValidApiKey()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置中配置 API Key')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isGenerating = true;
      _currentInsightsText = ''; // Clear previous text (not used for display)
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有找到笔记，请先添加一些笔记')));
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
        _tabController.animateTo(1); // Switch to result tab
      });

      // Listen to the stream and accumulate text manually
      _insightsSubscription = insightsStream.listen(
        (String chunk) {
          // Append the new chunk and update state to trigger UI rebuild
          if (mounted) {
            setState(() {
              _accumulatedInsightsText += chunk;
            });
          }
        },        onError: (error) {
          // Handle errors
          debugPrint('生成洞察流出错: $error');
          if (mounted) {
            String errorMessage = '生成洞察失败: ${error.toString()}';
            String actionText = '重试';
            
            // 处理特定的错误类型
            if (error.toString().contains('500')) {
              errorMessage = '服务器内部错误，可能是模型配置问题';
              actionText = '检查设置';
            } else if (error.toString().contains('401')) {
              errorMessage = 'API密钥无效，请检查设置';
              actionText = '检查API密钥';
            } else if (error.toString().contains('429')) {
              errorMessage = '请求频率过高，请稍后重试';
              actionText = '稍后重试';
            } else if (error.toString().contains('网络') || error.toString().contains('连接')) {
              errorMessage = '网络连接问题，请检查网络';
              actionText = '重试';
            }
            
            setState(() {
              _accumulatedInsightsText = errorMessage;
              _isGenerating = false; // Stop generating state on error
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: actionText,
                  textColor: Colors.white,                  onPressed: () {
                    if (actionText == '检查设置' || actionText == '检查API密钥') {
                      // 导航到AI设置页面
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AISettingsPage(),
                        ),
                      );
                    } else {
                      // 重试生成洞察
                      _generateInsights();
                    }
                  },
                ),
              ),
            );
          }
        },        onDone: () {
          debugPrint('生成洞察流完成');
          // Stream finished, update loading state
          if (mounted) {
            setState(() {
              _isLoading = false; // Stop full loading state on done
              _isGenerating = false; // Stop generating state on done
            });
            // 移除洞察生成完成的弹窗通知
          }
        },
        cancelOnError: true, // Cancel subscription if an error occurs
      );    } catch (e) {
      debugPrint('生成洞察失败 (setup): $e');
      if (mounted) {
        String errorMessage = '生成洞察失败: ${e.toString()}';
        
        // 处理特定的错误类型
        if (e.toString().contains('500')) {
          errorMessage = '服务器内部错误，请检查AI模型配置是否正确';
        } else if (e.toString().contains('401')) {
          errorMessage = 'API密钥无效，请在设置中更新API密钥';
        } else if (e.toString().contains('API Key')) {
          errorMessage = '请先在设置中配置有效的API密钥';
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
              label: '去设置',
              textColor: Colors.white,              onPressed: () {
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题和标签选择
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text(
                    'AI 思维洞察',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                    ),
                  ),
                  const Spacer(),
                  _isGenerating
                      ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primaryColor,
                        ),
                      )
                      : IconButton(
                        icon: const Icon(Icons.refresh),
                        color: theme.primaryColor,
                        tooltip: '重新生成',
                        onPressed:
                            _isGenerating || _currentInsightsText.isEmpty
                                ? null
                                : _generateInsights, // 生成中或无内容时禁用
                      ),
                ],
              ),
            ),

            // 标签页选择器
            TabBar(
              controller: _tabController,
              tabs: const [Tab(text: '分析模式'), Tab(text: '结果展示')],
              labelColor: theme.primaryColor,
              indicatorColor: theme.primaryColor,
            ),

            // 标签页内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 第一个标签页：选择分析类型
                  _buildAnalysisSelectionTab(theme),

                  // 第二个标签页：显示分析结果
                  _buildAnalysisResultTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          _tabController.index == 0
              ? FloatingActionButton.extended(
                onPressed: _isLoading ? null : _generateInsights,
                label: Text(_isLoading ? '分析中...' : '开始分析'),
                icon:
                    _isLoading
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Icon(Icons.auto_awesome),
              )
              : null,
    );
  }

  Widget _buildAnalysisSelectionTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择分析方式',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // 分析类型卡片
          ..._analysisTypes.map((type) => _buildAnalysisTypeCard(theme, type)),

          const SizedBox(height: 24),

          Text(
            '选择分析风格',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // 分析风格选择
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _analysisStyles.map((style) {
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
                      selectedColor: theme.colorScheme.primaryContainer,
                      labelStyle: TextStyle(
                        color:
                            isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      tooltip: style['description'],
                    );
                  }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // 自定义提示词选项
          InkWell(
            onTap: () {
              setState(() {
                _showCustomPrompt = !_showCustomPrompt;
              });
            },
            child: Row(
              children: [
                Icon(
                  _showCustomPrompt ? Icons.arrow_drop_down : Icons.arrow_right,
                  color: theme.primaryColor,
                ),
                Text(
                  '高级选项',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // 自定义提示词输入框
          if (_showCustomPrompt) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _customPromptController,
              decoration: InputDecoration(
                labelText: '自定义分析提示词',
                hintText: '例如：分析我的笔记中提到的人物和地点',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
              maxLines: 3,
            ),
          ],

          const SizedBox(height: 24),

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
                    Text(
                      '分析说明',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'AI 分析会综合您所有的笔记内容，发现潜在的思维模式和规律。可以选择不同的分析风格来获取多样的洞察视角。这可能需要一些时间，请耐心等待。',
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'AI 分析使用说明',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '1. AI可能会生成不准确或误导性内容，请谨慎评估分析结果\n'
                  '2. 使用此功能时，您的所有笔记信息（包括内容、日期、位置、天气和温度等）'
                  '都会发送给AI进行全面分析\n'
                  '3. 分析结果仅供参考，最终解释权归您自己\n'
                  '4. 建议在网络良好的环境下使用此功能，以获得最佳体验',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisTypeCard(ThemeData theme, Map<String, dynamic> type) {
    final isSelected = _selectedAnalysisType == type['prompt'];
    final String key = type['prompt'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color:
              isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
          width: isSelected ? 2 : 0.5,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedAnalysisType = key;
            _showCustomPrompt = false;
          });
        },
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Icon(
                  type['icon'] as IconData,
                  color:
                      isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSecondaryContainer,
                  size: 28,
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
                        color:
                            isSelected
                                ? theme.primaryColor
                                : theme.textTheme.titleMedium?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(type['description'], style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: theme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisResultTab(ThemeData theme) {
    // 使用 StreamBuilder 监听 _insightsStream 的连接状态变化，并根据 _accumulatedInsightsText 显示内容
    return StreamBuilder<String>(
      stream:
          _insightsStream, // Listen to stream for connection state and errors
      builder: (context, snapshot) {
        // 根据生成状态和累积文本显示不同内容
        if (_isGenerating && _accumulatedInsightsText.isEmpty) {
          // 正在生成且还没有收到任何文本时，显示加载动画
          return const AppLoadingView();
        } else if (_accumulatedInsightsText.isNotEmpty) {
          // 已经有累积文本时，显示结果卡片
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 分析结果卡片
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
                            // 复制按钮只在生成完成后显示
                            if (!_isGenerating &&
                                _accumulatedInsightsText.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: '复制到剪贴板',
                                onPressed: () {                                  Clipboard.setData(
                                    ClipboardData(
                                      text: _accumulatedInsightsText,
                                    ),
                                  ).then((_) {
                                    if (!mounted) return;
                                    final scaffoldMessenger =
                                        ScaffoldMessenger.of(context);
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(content: Text('分析结果已复制')),
                                    );
                                  });
                                },
                              ),
                            // 加载指示器在生成过程中显示
                            if (_isGenerating)
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.primaryColor,
                                ),
                              ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        // 这里使用 MarkdownBody 渲染累积的文本
                        MarkdownBody(
                          data: _accumulatedInsightsText, // 使用累积的文本
                          selectable: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(
                            theme,
                          ).copyWith(p: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // 分享和保存按钮只在生成完成后显示
                if (!_isGenerating && _accumulatedInsightsText.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          // 保存为笔记
                          _saveAsNote(_accumulatedInsightsText);
                        },
                        icon: const Icon(Icons.note_add),
                        label: const Text('保存为笔记'),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          // 保存分析结果
                          _saveAnalysis(_accumulatedInsightsText);
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('保存分析'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          // 实现分享功能
                          _shareAnalysis(_accumulatedInsightsText);
                        },
                        icon: const Icon(Icons.share),
                        label: const Text('分享洞察'),
                      ),
                    ],
                  ),
              ],
            ),
          );
        } else if (snapshot.hasError) {
          // 处理错误，只在没有累积文本时显示错误信息
          // Error handling will be managed by the listener now, updating _accumulatedInsightsText directly.
          // We can just check if _accumulatedInsightsText contains an error message.
          // However, if the error occurs immediately before any data is received, snapshot.hasError will be true.
          // Let's keep this error handling for initial errors.
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '生成洞察时出错: ${snapshot.error.toString()}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        } else {
          // 初始状态或没有生成且没有累积文本时显示空状态
          return const AppEmptyView(
            svgAsset: 'assets/empty/empty_state.svg',
            text: '选择分析类型并点击"开始分析"\n洞察将帮助你发现笔记中的思维模式和规律',
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
    if (_showCustomPrompt && _customPromptController.text.isNotEmpty) {
      return "自定义分析";
    }
    return _analysisTypeKeyToLabel[_selectedAnalysisType] ??
        _selectedAnalysisType;
  }
}
