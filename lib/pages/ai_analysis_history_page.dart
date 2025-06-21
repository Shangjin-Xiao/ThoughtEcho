import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/ai_analysis_model.dart';
import '../services/ai_analysis_database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_loading_view.dart';
import '../utils/time_utils.dart';

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
      setState(() {
        _analyses = analyses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载分析历史记录失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 搜索分析历史记录
  Future<void> _searchAnalyses() async {
    if (_searchQuery.isEmpty) {
      _loadAnalyses();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final analyses = await _aiAnalysisDatabaseService.searchAnalyses(
        _searchQuery,
      );
      setState(() {
        _analyses = analyses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索分析记录失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 删除单个分析记录
  Future<void> _deleteAnalysis(AIAnalysis analysis) async {
    // 确认删除对话框
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认删除'),
            content: const Text('确定要删除此分析记录吗？此操作不可撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final success = await _aiAnalysisDatabaseService.deleteAnalysis(
        analysis.id!,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分析记录已删除')));
        _loadAnalyses(); // 重新加载列表
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 清空所有分析记录
  Future<void> _deleteAllAnalyses() async {
    // 确认删除对话框
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认删除全部'),
            content: const Text('确定要删除所有AI分析记录吗？此操作不可撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('全部删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final success = await _aiAnalysisDatabaseService.deleteAllAnalyses();

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所有分析记录已删除')));
        _loadAnalyses(); // 重新加载列表
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 显示分析详情
  void _viewAnalysisDetails(AIAnalysis analysis) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 这使得底部表可以占据更多的屏幕空间
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.dialogRadius),
        ),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85, // 初始高度为屏幕的85%
          minChildSize: 0.5, // 最小高度为屏幕的50%
          maxChildSize: 0.95, // 最大高度为屏幕的95%
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                // 顶部拖动条
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              analysis.title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'AI分析记录 · ${TimeUtils.formatDateFromIso(analysis.createdAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: '复制内容',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: analysis.content),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('内容已复制到剪贴板')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: '删除',
                        onPressed: () {
                          Navigator.pop(context); // 先关闭底部表
                          _deleteAnalysis(analysis);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // 内容区域
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 使用Markdown组件显示内容
                        MarkdownBody(
                          data: analysis.content,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(
                            Theme.of(context),
                          ).copyWith(p: Theme.of(context).textTheme.bodyMedium),
                        ),
                        const SizedBox(height: 16),
                        // 元数据
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '分析信息',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '类型: ${_getAnalysisTypeName(analysis.analysisType)}',
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                ),
                              ),
                              Text(
                                '风格: ${_getAnalysisStyleName(analysis.analysisStyle)}',
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                ),
                              ),
                              if (analysis.quoteCount != null)
                                Text(
                                  '分析笔记数量: ${analysis.quoteCount}',
                                  style: TextStyle(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              Text(
                                '创建时间: ${TimeUtils.formatDateTimeFromIso(analysis.createdAt)}',
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 获取分析类型的中文名称
  String _getAnalysisTypeName(String type) {
    switch (type) {
      case 'comprehensive':
        return '全面分析';
      case 'emotional':
        return '情感洞察';
      case 'mindmap':
        return '思维导图';
      case 'growth':
        return '成长建议';
      case 'custom':
        return '自定义分析';
      default:
        return type;
    }
  }

  /// 获取分析风格的中文名称
  String _getAnalysisStyleName(String style) {
    switch (style) {
      case 'professional':
        return '专业分析';
      case 'friendly':
        return '友好导师';
      case 'humorous':
        return '风趣幽默';
      case 'literary':
        return '文学风格';
      default:
        return style;
    }
  }

  /// 获取分析类型的图标
  IconData _getAnalysisTypeIcon(String type) {
    switch (type) {
      case 'emotional':
        return Icons.mood;
      case 'mindmap':
        return Icons.account_tree;
      case 'growth':
        return Icons.trending_up;
      case 'comprehensive':
        return Icons.all_inclusive;
      case 'custom':
        return Icons.auto_awesome;
      default:
        return Icons.analytics;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI分析历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
            onPressed: _analyses.isEmpty ? null : _deleteAllAnalyses,
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索分析内容',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchQuery.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                            _loadAnalyses();
                          },
                        )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.colorScheme.outline),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                if (value.isEmpty) {
                  _loadAnalyses();
                }
              },
              onSubmitted: (_) => _searchAnalyses(),
            ),
          ),

          // 内容列表
          Expanded(
            child:
                _isLoading
                    ? const AppLoadingView()
                    : _analyses.isEmpty
                    ? const AppEmptyView(
                      svgAsset: 'assets/empty/empty_state.svg',
                      text: '没有找到AI分析历史记录\n可以在"AI洞察"页面生成并保存分析',
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      itemCount: _analyses.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final analysis = _analyses[index];
                        return _buildAnalysisCard(analysis, theme);
                      },
                    ),
          ),
        ],
      ),
    );
  }

  /// 构建分析记录卡片
  Widget _buildAnalysisCard(AIAnalysis analysis, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        onTap: () => _viewAnalysisDetails(analysis),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和图标
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getAnalysisTypeIcon(analysis.analysisType),
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          analysis.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          TimeUtils.formatDateFromIso(analysis.createdAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppTheme.dialogRadius),
                          ),
                        ),
                        builder: (context) {
                          return SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.copy),
                                  title: const Text('复制内容'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    Clipboard.setData(
                                      ClipboardData(text: analysis.content),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('内容已复制到剪贴板'),
                                      ),
                                    );
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: const Text('删除'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _deleteAnalysis(analysis);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),

              // 内容预览
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  analysis.content.replaceAll(
                    RegExp(r'#+ |==+|--+|\*\*|__'),
                    '',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),

              // 底部标签
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getAnalysisTypeName(analysis.analysisType),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (analysis.quoteCount != null)
                      Text(
                        '包含${analysis.quoteCount}条笔记',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
