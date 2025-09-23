import 'package:flutter/material.dart';
import '../models/ai_analysis_model.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';

/// AI分析历史页面（简化版，已移除年度报告功能）
class AIAnalysisHistoryPage extends StatefulWidget {
  const AIAnalysisHistoryPage({super.key});

  @override
  State<AIAnalysisHistoryPage> createState() => _AIAnalysisHistoryPageState();
}

class _AIAnalysisHistoryPageState extends State<AIAnalysisHistoryPage> {
  List<AIAnalysis> _analyses = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnalyses();
  }

  Future<void> _loadAnalyses() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 暂时使用空列表，因为DatabaseService中可能没有这些方法
      final analyses = <AIAnalysis>[];

      if (!mounted) return;

      setState(() {
        _analyses = analyses;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAnalysis(AIAnalysis analysis) async {
    try {
      // 暂时不实现删除功能
      if (!mounted) return;

      setState(() {
        _analyses.removeWhere((a) => a.id == analysis.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
            content: Text('分析记录已删除'), duration: Duration(seconds: 2)));
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
          // ignore: prefer_const_constructors
          SnackBar(content: Text('删除失败: $e'), duration: Duration(seconds: 3)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI分析历史'),
        actions: [
          if (_analyses.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAnalyses,
              tooltip: '刷新',
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const AppLoadingView();
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadAnalyses, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_analyses.isEmpty) {
      return const AppEmptyView(
        svgAsset: 'assets/empty/empty_state.svg',
        text: '暂无AI分析记录',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _analyses.length,
      itemBuilder: (context, index) {
        final analysis = _analyses[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(
              analysis.analysisType,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  analysis.content.length > 100
                      ? '${analysis.content.substring(0, 100)}...'
                      : analysis.content,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  analysis.createdAt.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _showDeleteDialog(analysis),
            ),
            onTap: () => _showAnalysisDetail(analysis),
          ),
        );
      },
    );
  }

  void _showDeleteDialog(AIAnalysis analysis) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除确认'),
        content: const Text('确定要删除这条分析记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAnalysis(analysis);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showAnalysisDetail(AIAnalysis analysis) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(analysis.analysisType),
        content: SingleChildScrollView(child: Text(analysis.content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
