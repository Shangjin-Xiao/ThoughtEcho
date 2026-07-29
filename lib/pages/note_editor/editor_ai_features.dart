part of '../note_full_editor_page.dart';

/// AI assistant features — all actions navigate to Thoughter (AIAssistantPage)
/// with a natural-language prompt. The editor is replaced in the navigation
/// stack so that after the agent session the user returns to the note list.
extension _NoteEditorAIFeatures on _NoteFullEditorPageState {
  void _showAIOptions(BuildContext context) {
    AiOptionsMenu.show(
      context: context,
      showAskNote: true,
      onAnalyzeSource: _analyzeSource,
      onPolishText: _polishText,
      onContinueText: _continueText,
      onAnalyzeContent: _analyzeContent,
      onAskNote: _askNoteQuestion,
    );
  }

  // 分析来源 → 跳转 Thoughter
  Future<void> _analyzeSource() async {
    final l10n = AppLocalizations.of(context);
    await _openAiAssistant(l10n.aiPromptSourceAnalysis);
  }

  // 润色文本 → 跳转 Thoughter
  Future<void> _polishText() async {
    final l10n = AppLocalizations.of(context);
    await _openAiAssistant(l10n.aiPromptPolish);
  }

  // 续写文本 → 跳转 Thoughter
  Future<void> _continueText() async {
    final l10n = AppLocalizations.of(context);
    await _openAiAssistant(l10n.aiPromptContinue);
  }

  // 深度分析 → 跳转 Thoughter
  Future<void> _analyzeContent() async {
    final l10n = AppLocalizations.of(context);
    await _openAiAssistant(l10n.aiPromptDeepAnalysis);
  }

  // 问笔记功能 → 跳转 Thoughter（无初始提示）
  Future<void> _askNoteQuestion() async {
    await _openAiAssistant(null);
  }

  /// 统一入口：保存未提交更改后跳转 Thoughter，并关闭编辑器。
  Future<void> _openAiAssistant(String? initialQuestion) async {
    final plainText = StringUtils.removeObjectReplacementChar(
      _editorState.controller.document.toPlainText(),
    ).trim();
    if (plainText.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pleaseInputContent),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      return;
    }

    // 如果有未保存的更改，提示用户先保存
    if (_hasUnsavedChanges()) {
      final l10n = AppLocalizations.of(context);
      final shouldSave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.saveRequired),
          content: Text(l10n.saveBeforeAiAssistant),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.saveAndContinue),
            ),
          ],
        ),
      );
      if (shouldSave != true) return;
      await _saveContent();
      if (!mounted) return;
    }

    // 创建包含元数据的临时 Quote，为 Agent 提供更丰富的上下文
    final tempQuote = Quote(
      id: widget.initialQuote?.id,
      content: plainText,
      date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
      dayPeriod: widget.initialQuote?.dayPeriod,
      sourceAuthor: _metadataState.authorController.text.trim().isNotEmpty
          ? _metadataState.authorController.text.trim()
          : null,
      sourceWork: _metadataState.workController.text.trim().isNotEmpty
          ? _metadataState.workController.text.trim()
          : null,
    );

    // 用 pushReplacement 替换编辑器，进入 Agent 后编辑器关闭
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.note,
          quote: tempQuote,
          initialQuestion: initialQuestion,
        ),
      ),
    );
  }
}
