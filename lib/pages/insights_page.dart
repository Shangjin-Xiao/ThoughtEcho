import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_loading_view.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String _insights = '';
  late TabController _tabController;
  final TextEditingController _customPromptController = TextEditingController();
  bool _showCustomPrompt = false;

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customPromptController.dispose();
    super.dispose();
  }

  Future<void> _generateInsights() async {
    final aiService = context.read<AIService>();
    if (!aiService.hasValidApiKey()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置 API Key')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
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
        });
        return;
      }

      String insights;
      if (_showCustomPrompt && _customPromptController.text.isNotEmpty) {
        insights = await aiService.generateCustomInsights(
          quotes,
          _customPromptController.text,
        );
      } else {
        insights = await aiService.generateInsights(
          quotes,
          analysisType: _selectedAnalysisType,
          analysisStyle: _selectedAnalysisStyle,
        );
      }

      if (!mounted) return;

      setState(() {
        _insights = insights;
        // 自动切换到结果标签页
        _tabController.animateTo(1);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成洞察时出错：$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
                  _isLoading
                      ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primaryColor,
                        ),
                      )
                      : IconButton(
                        icon: Icon(Icons.refresh, color: theme.primaryColor),
                        tooltip: '重新生成',
                        onPressed: _insights.isEmpty ? null : _generateInsights,
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
              children: _analysisStyles.map((style) {
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
                    color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
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
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
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
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Icon(
                  type['icon'] as IconData,
                  color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSecondaryContainer,
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
                        color: isSelected ? theme.primaryColor : theme.textTheme.titleMedium?.color,
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
    if (_isLoading) {
      return const AppLoadingView();
    }

    if (_insights.isEmpty) {
      return const AppEmptyView(
        svgAsset: 'assets/empty/empty_state.svg',
        text: '选择分析类型并点击"开始分析"\n洞察将帮助你发现笔记中的思维模式和规律',
      );
    }

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
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: '复制到剪贴板',
                        onPressed: () {
                          // 复制分析结果
                          Clipboard.setData(ClipboardData(text: _insights)).then((_) {
                            if (!mounted) return;
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('分析结果已复制')),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  // 这里使用 SelectableText 让用户可以选择文本
                  MarkdownBody(
                    data: _insights,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium,
                      // 可以根据需要自定义其他 Markdown 元素的样式
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 分享和保存按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  // 实现保存为笔记的功能
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已保存为新笔记')));
                },
                icon: const Icon(Icons.save),
                label: const Text('保存为笔记'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // 实现分享功能
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已分享')));
                },
                icon: const Icon(Icons.share),
                label: const Text('分享洞察'),
              ),
            ],
          ),
        ],
      ),
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
    return _analysisTypeKeyToLabel[_selectedAnalysisType] ?? _selectedAnalysisType;
  }
}
