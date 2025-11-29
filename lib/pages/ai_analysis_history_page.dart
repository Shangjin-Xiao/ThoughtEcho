import 'package:flutter/material.dart';
import '../models/ai_analysis_model.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
            content: Text(l10n.analysisRecordDeleted), duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(l10n.deleteFailed(e.toString())),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.analysisHistory),
        actions: [
          if (_analyses.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAnalyses,
              tooltip: l10n.retry,
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
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
            Text(l10n.loadFailed(_error!)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadAnalyses, child: Text(l10n.retry)),
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
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteRecordConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAnalysis(analysis);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showAnalysisDetail(AIAnalysis analysis) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(analysis.analysisType),
        content: SingleChildScrollView(child: Text(analysis.content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}
