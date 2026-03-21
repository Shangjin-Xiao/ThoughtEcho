part of '../note_full_editor_page.dart';

/// AI analysis section of the metadata dialog.
extension _NoteEditorMetadataAiSection on _NoteFullEditorPageState {
  /// Builds the AI analysis section for the metadata dialog.
  ///
  /// Shows the AI analysis result if available, with options to view, copy, or delete.
  Widget _buildMetadataAiAnalysisSection(
    ThemeData theme,
    AppLocalizations l10n,
    StateSetter setDialogState,
  ) {
    // 如果没有 AI 分析结果，不显示此区域
    if (_currentAiAnalysis == null || _currentAiAnalysis!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.aiAnalysis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            // 删除按钮
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              tooltip: l10n.deleteAiAnalysis,
              onPressed: () {
                _showDeleteAiAnalysisConfirmation(
                  context,
                  theme,
                  l10n,
                  setDialogState,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        // AI 分析内容容器
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 分析内容预览（最多显示 3 行）
              Text(
                _currentAiAnalysis!,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              // 操作按钮行
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 查看完整内容按钮
                  TextButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(l10n.viewFull),
                    onPressed: () {
                      _showFullAiAnalysisDialog(context, theme, l10n);
                    },
                  ),
                  const SizedBox(width: 8),
                  // 复制按钮
                  TextButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(l10n.copy),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _currentAiAnalysis!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.copiedToClipboard),
                          duration: AppConstants.snackBarDurationNormal,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 显示完整的 AI 分析内容对话框
  void _showFullAiAnalysisDialog(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(l10n.aiAnalysis),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                _currentAiAnalysis!,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_outlined),
              label: Text(l10n.copy),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _currentAiAnalysis!),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.copiedToClipboard),
                    duration: AppConstants.snackBarDurationNormal,
                  ),
                );
              },
            ),
            TextButton(
              child: Text(l10n.close),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  /// 显示删除 AI 分析的确认对话框
  void _showDeleteAiAnalysisConfirmation(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    StateSetter setDialogState,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deleteAiAnalysis),
          content: Text(l10n.deleteAiAnalysisConfirm),
          actions: [
            TextButton(
              child: Text(l10n.cancel),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(l10n.delete),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _updateState(() {
                  _currentAiAnalysis = null;
                });
                setDialogState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.aiAnalysisDeleted),
                    duration: AppConstants.snackBarDurationNormal,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
