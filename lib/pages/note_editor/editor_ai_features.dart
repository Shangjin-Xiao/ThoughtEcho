part of '../note_full_editor_page.dart';

/// AI assistant features: source analysis, text polishing,
/// continuation, deep analysis, and note Q&A.
extension NoteEditorAIFeatures on _NoteFullEditorPageState {
  void _showAIOptions(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12), // 使用圆角
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI助手',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: theme.colorScheme.outline),
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: Text(
                      AppLocalizations.of(context).smartAnalyzeSource,
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).smartAnalyzeSourceDesc,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeSource();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: Text(AppLocalizations.of(context).polishText),
                    subtitle: Text(AppLocalizations.of(context).polishTextDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _polishText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(AppLocalizations.of(context).continueWriting),
                    subtitle: Text(
                      AppLocalizations.of(context).continueWritingDesc,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _continueText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics),
                    title: Text(AppLocalizations.of(context).deepAnalysis),
                    subtitle: Text(
                      AppLocalizations.of(context).deepAnalysisDesc,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeContent();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: Text(AppLocalizations.of(context).askNote),
                    subtitle: Text(AppLocalizations.of(context).askNoteDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _askNoteQuestion();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

      // 调用AI分析来源
      final result = await aiService.analyzeSource(plainText);

      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop();

      // 解析JSON结果
      try {
        final Map<String, dynamic> sourceData = json.decode(result);

        String? author = sourceData['author'] as String?;
        String? work = sourceData['work'] as String?;
        String confidence = sourceData['confidence'] as String? ?? '低';
        String explanation = sourceData['explanation'] as String? ?? '';

        // 显示结果对话框
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          showDialog(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text(l10n.analysisResultWithConfidence(confidence)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (author != null && author.isNotEmpty) ...[
                      Text(
                        l10n.possibleAuthor,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(author),
                      const SizedBox(height: 8),
                    ],
                    if (work != null && work.isNotEmpty) ...[
                      Text(
                        l10n.possibleWork,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(work),
                      const SizedBox(height: 8),
                    ],
                    if (explanation.isNotEmpty) ...[
                      Text(
                        l10n.analysisExplanation,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(explanation, style: const TextStyle(fontSize: 13)),
                    ],
                    if ((author == null || author.isEmpty) &&
                        (work == null || work.isEmpty))
                      Text(l10n.noAuthorWorkIdentified),
                  ],
                ),
                actions: [
                  if ((author != null && author.isNotEmpty) ||
                      (work != null && work.isNotEmpty))
                    TextButton(
                      child: Text(l10n.applyAnalysisResult),
                      onPressed: () {
                        setState(() {
                          if (author != null && author.isNotEmpty) {
                            _authorController.text = author;
                          }
                          if (work != null && work.isNotEmpty) {
                            _workController.text = work;
                          }
                        });
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                  TextButton(
                    child: Text(l10n.close),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
              );
            },
          );
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.parseResultFailedWithError(e.toString())),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
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

    // 显示流式文本对话框
    // 注意：这里await showDialog会等待对话框关闭并返回结果
    final l10n = AppLocalizations.of(context);
    String? finalResult = await showDialog<String?>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        return StreamingTextDialog(
          title: l10n.polishingText,
          textStream: aiService.streamPolishText(plainText), // 调用流式方法，使用正确的参数名
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
      setState(() {
        _controller.document = quill.Document.fromJson([
          {"insert": finalResult},
        ]);
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
      final int length = _controller.document.length;
      // 在文档末尾插入续写内容，确保在最后一行
      _controller.document.insert(length, '\n\n$finalResult');
      // 移动光标到文档末尾
      _controller.updateSelection(
        TextSelection.collapsed(offset: _controller.document.length),
        quill.ChangeSource.local,
      );
    }
  }

  // 深度分析内容 (使用流式传输)
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

    // 显示流式文本对话框
    // 对于分析功能，我们只关心对话框的显示，不需要await返回值来更新编辑器
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        // 创建临时Quote对象进行分析
        final quote = Quote(
          id: widget.initialQuote?.id ?? const Uuid().v4(),
          content: plainText,
          date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
          location: _showLocation ? _location : null,
          weather: _showWeather ? _weather : null,
          temperature: _showWeather ? _temperature : null,
        );

        return StreamingTextDialog(
          title: l10n.analyzingNote,
          textStream: aiService.streamSummarizeNote(quote), // 调用流式方法，使用正确的参数名
          applyButtonText: l10n.copyResult, // 分析结果的应用按钮可以是复制
          onApply: (fullText) {
            // 用户点击"复制结果"时调用
            Clipboard.setData(ClipboardData(text: fullText)).then((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.analysisResultCopied),
                    duration: AppConstants.snackBarDurationImportant,
                  ),
                );
              }
            });
            Navigator.of(dialogContext).pop(); // 关闭对话框
          },
          onCancel: () {
            // 用户点击"关闭"时调用
            Navigator.of(dialogContext).pop();
          },
          isMarkdown: true, // 分析结果通常是Markdown格式
          // StreamingTextDialog 内部处理 onError 和 onComplete
        );
      },
    );
    // showDialog 返回后，如果用户点击了应用按钮，复制逻辑已经在onApply中处理了
    // 如果用户点击了取消或关闭对话框，这里不需要做额外处理
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
    );

    // 导航到聊天页面
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: tempQuote)),
    );
  }
}
