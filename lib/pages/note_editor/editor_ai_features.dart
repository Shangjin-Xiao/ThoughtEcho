part of '../note_full_editor_page.dart';

/// AI assistant features: source analysis, text polishing,
/// continuation, deep analysis, and note Q&A.
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

  // 分析来源
  Future<void> _analyzeSource() async {
    final plainText = StringUtils.removeObjectReplacementChar(
      _controller.document.toPlainText(),
    ).trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pleaseEnterContent),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context).analyzing),
              ],
            ),
          );
        },
      );

      // 调用AI分析来源（传递已有的作者/出处供 AI 验证）
      final existingAuthor = _authorController.text.trim();
      final existingWork = _workController.text.trim();
      final result = await aiService.analyzeSource(
        plainText,
        existingAuthor: existingAuthor.isNotEmpty ? existingAuthor : null,
        existingWork: existingWork.isNotEmpty ? existingWork : null,
      );

      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop();

      // 显示来源分析结果对话框
      if (mounted) {
        SourceAnalysisResultDialog.show(
          context,
          result,
          authorController: _authorController,
          workController: _workController,
          onError: (error) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.parseResultFailedWithError(error)),
                duration: AppConstants.snackBarDurationError,
              ),
            );
          },
        );
      }
    } catch (e) {
      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.analysisFailedWithError(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 润色文本 (使用流式传输)
  Future<void> _polishText() async {
    final plainText = StringUtils.removeObjectReplacementChar(
      _controller.document.toPlainText(),
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

    final aiService = Provider.of<AIService>(context, listen: false);
    final polishInput = QuillAiApplyUtils.buildPolishInputText(
      _controller.document,
    );

    // 显示流式文本对话框
    // 注意：这里await showDialog会等待对话框关闭并返回结果
    final l10n = AppLocalizations.of(context);
    String? finalResult = await showDialog<String?>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        return StreamingTextDialog(
          title: l10n.polishingText,
          textStream: aiService.streamPolishText(
            polishInput,
          ), // 调用流式方法，使用正确的参数名
          applyButtonText: '应用更改', // 应用按钮文本
          onApply: (fullText) {
            // 用户点击"应用更改"时调用
            // 返回结果给showDialog的await调用
            Navigator.of(dialogContext).pop(fullText); // 通过pop将结果返回
          },
          onCancel: () {
            // 用户点击"取消"时调用
            Navigator.of(dialogContext).pop(null); // 返回null表示取消
          },
          // StreamingTextDialog 内部处理 onError 和 onComplete
        );
      },
    );

    // 如果showDialog返回了结果 (用户点击了应用)，更新编辑器内容
    if (finalResult != null && mounted) {
      _updateState(() {
        _controller.document = QuillAiApplyUtils.applyPolishedText(
          originalDocument: _controller.document,
          polishedText: finalResult,
        );
      });
    }
  }

  // 续写文本 (使用流式传输)
  Future<void> _continueText() async {
    final plainText = StringUtils.removeObjectReplacementChar(
      _controller.document.toPlainText(),
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

    final aiService = Provider.of<AIService>(context, listen: false);

    // 显示流式文本对话框
    final l10n = AppLocalizations.of(context);
    String? finalResult = await showDialog<String?>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        return StreamingTextDialog(
          title: l10n.continuingText,
          textStream: aiService.streamContinueText(
            plainText,
          ), // 调用流式方法，使用正确的参数名
          applyButtonText: '附加到原文', // 应用按钮文本
          onApply: (fullText) {
            // 用户点击"附加到原文"时调用
            // 返回结果给showDialog的await调用
            Navigator.of(dialogContext).pop(fullText); // 通过pop将结果返回
          },
          onCancel: () {
            // 用户点击"取消"时调用
            Navigator.of(dialogContext).pop(null); // 返回null表示取消
          },
          // StreamingTextDialog 内部处理 onError 和 onComplete
        );
      },
    );

    // 如果showDialog返回了结果 (用户点击了应用)，附加到编辑器内容
    if (finalResult != null && mounted) {
      // Quill 文档的 length 包含末尾换行符，所以需要在 length - 1 位置插入
      // 这样可以在原文末尾（换行符之前）插入续写内容
      final int insertPosition = _controller.document.length - 1;
      if (insertPosition >= 0) {
        _controller.document.insert(insertPosition, '\n\n$finalResult');
      }
      // 移动光标到文档末尾
      _controller.updateSelection(
        TextSelection.collapsed(offset: _controller.document.length - 1),
        quill.ChangeSource.local,
      );
    }
  }

  // 深度分析内容 (使用流式传输，保存结果到 _currentAiAnalysis)
  Future<void> _analyzeContent() async {
    final plainText = StringUtils.removeObjectReplacementChar(
      _controller.document.toPlainText(),
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

    final aiService = Provider.of<AIService>(context, listen: false);

    // 创建临时Quote对象进行分析，包含完整元数据
    final quote = Quote(
      id: widget.initialQuote?.id ?? const Uuid().v4(),
      content: plainText,
      date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
      sourceAuthor: _authorController.text.trim().isNotEmpty
          ? _authorController.text.trim()
          : null,
      sourceWork: _workController.text.trim().isNotEmpty
          ? _workController.text.trim()
          : null,
      location: _showLocation ? _location : null,
      weather: _showWeather ? _weather : null,
      temperature: _showWeather ? _temperature : null,
      dayPeriod: widget.initialQuote?.dayPeriod,
    );

    // 获取选中标签的名称列表
    final List<String> tagNames = [];
    if (_selectedTagIds.isNotEmpty && widget.allTags != null) {
      for (final tagId in _selectedTagIds) {
        final tag = widget.allTags!.where((t) => t.id == tagId).firstOrNull;
        if (tag != null) {
          tagNames.add(tag.name);
        }
      }
    }

    // 显示流式文本对话框
    final l10n = AppLocalizations.of(context);
    final String? analysisResult = await showDialog<String?>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        return StreamingTextDialog(
          title: l10n.analyzingNote,
          textStream: aiService.streamSummarizeNote(
            quote,
            tagNames: tagNames.isNotEmpty ? tagNames : null,
          ),
          applyButtonText: l10n.applyToNote, // 应用到笔记
          onApply: (fullText) {
            // 返回分析结果
            Navigator.of(dialogContext).pop(fullText);
          },
          onCancel: () {
            Navigator.of(dialogContext).pop(null);
          },
          isMarkdown: true,
        );
      },
    );

    // 如果用户点击了"应用到笔记"，保存分析结果
    if (analysisResult != null && mounted) {
      _updateState(() {
        _currentAiAnalysis = analysisResult;
      });

      // 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.aiAnalysisSaved),
            duration: AppConstants.snackBarDurationImportant,
          ),
        );
      }
    }
  }

  // 问笔记功能
  Future<void> _askNoteQuestion() async {
    final plainText = StringUtils.removeObjectReplacementChar(
      _controller.document.toPlainText(),
    ).trim();
    if (plainText.isEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseInputContent),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    // 创建临时Quote对象用于问答
    final tempQuote = Quote(
      id: widget.initialQuote?.id ?? '',
      content: plainText,
      date: DateTime.now().toIso8601String(),
      dayPeriod: widget.initialQuote?.dayPeriod,
    );

    // 导航到聊天页面
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: tempQuote)),
    );
  }
}
