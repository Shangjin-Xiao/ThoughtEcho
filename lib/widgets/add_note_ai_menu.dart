import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/ai_service.dart';
import '../models/quote_model.dart';
import '../theme/app_theme.dart';
import '../widgets/streaming_text_dialog.dart';
import '../pages/note_qa_chat_page.dart'; // 添加问笔记聊天页面导入
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class AddNoteAIMenu extends StatefulWidget {
  final TextEditingController contentController;
  final TextEditingController authorController;
  final TextEditingController workController;
  final Function(String) onAiAnalysisCompleted;

  const AddNoteAIMenu({
    super.key,
    required this.contentController,
    required this.authorController,
    required this.workController,
    required this.onAiAnalysisCompleted,
  });

  @override
  State<AddNoteAIMenu> createState() => _AddNoteAIMenuState();
}

class _AddNoteAIMenuState extends State<AddNoteAIMenu> {
  // 显示AI选项菜单
  void _showAIOptions(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.brightness == Brightness.light
          ? Colors.white
          : theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.dialogRadius),
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
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.aiAssistant,
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
                    title: Text(l10n.smartAnalyzeSource),
                    subtitle: Text(l10n.smartAnalyzeSourceDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeSource();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: Text(l10n.polishText),
                    subtitle: Text(l10n.polishTextDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _polishText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(l10n.continueWriting),
                    subtitle: Text(l10n.continueWritingDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _continueText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics),
                    title: Text(l10n.deepAnalysis),
                    subtitle: Text(l10n.deepAnalysisDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeContent();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: Text(l10n.askNote),
                    subtitle: Text(l10n.askNoteDesc),
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
    final l10n = AppLocalizations.of(context);

    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterContent),
          duration: AppConstants.snackBarDurationNormal,
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
                Text(l10n.analyzingSource),
              ],
            ),
          );
        },
      );

      // 调用AI分析来源
      final result = await aiService.analyzeSource(
        widget.contentController.text,
      );

      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop(); // 解析JSON结果
      try {
        final Map<String, dynamic> sourceData =
            result is Map<String, dynamic> ? result : jsonDecode(result);

        String? author = sourceData['author'] as String?;
        String? work = sourceData['work'] as String?;
        String confidence = sourceData['confidence'] as String? ?? l10n.unknown;
        String explanation = sourceData['explanation'] as String? ?? '';

        // 显示结果对话框
        if (mounted) {
          showDialog(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text(l10n.analysisResult),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.confidenceLevel(confidence)),
                    if (explanation.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(explanation),
                    ],
                    const SizedBox(height: 8),
                    if (author != null && author.isNotEmpty)
                      Text(l10n.authorLabel(author)),
                    if (work != null && work.isNotEmpty)
                      Text(l10n.workLabel(work)),
                  ],
                ),
                actions: [
                  if ((author != null && author.isNotEmpty) ||
                      (work != null && work.isNotEmpty))
                    TextButton(
                      child: Text(l10n.applyResult),
                      onPressed: () {
                        if (author != null && author.isNotEmpty) {
                          widget.authorController.text = author;
                        }
                        if (work != null && work.isNotEmpty) {
                          widget.workController.text = work;
                        }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.analysisFailedWithError(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 润色文本
  Future<void> _polishText() async {
    final l10n = AppLocalizations.of(context);

    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterContent),
          duration: AppConstants.snackBarDurationNormal,
        ),
      );
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示流式结果对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: l10n.polishResult,
            textStream: aiService.streamPolishText(
              widget.contentController.text,
            ),
            applyButtonText: l10n.applyChanges,
            onApply: (polishedText) {
              widget.contentController.text = polishedText;
            },
            onCancel: () {},
            isMarkdown: false,
          );
        },
      );
    } catch (e) {
      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 如果流式对话框已显示，无需手动关闭加载框
      // Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.polishFailedWithError(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 续写文本
  Future<void> _continueText() async {
    final l10n = AppLocalizations.of(context);

    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterContent),
          duration: AppConstants.snackBarDurationNormal,
        ),
      );
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示流式结果对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: l10n.continueResult,
            textStream: aiService.streamContinueText(
              widget.contentController.text,
            ),
            applyButtonText: l10n.appendToNote,
            onApply: (continuedText) {
              widget.contentController.text += continuedText;
            },
            onCancel: () {},
            isMarkdown: false,
          );
        },
      );
    } catch (e) {
      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 如果流式对话框已显示，无需手动关闭加载框
      // Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.continueFailedWithError(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 深入分析内容
  Future<void> _analyzeContent() async {
    final l10n = AppLocalizations.of(context);

    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterContent),
          duration: AppConstants.snackBarDurationNormal,
        ),
      );
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示流式结果对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final quote = Quote(
            id: '',
            content: widget.contentController.text,
            date: DateTime.now().toIso8601String(),
          );
          return StreamingTextDialog(
            title: l10n.noteAnalysis,
            textStream: aiService.streamSummarizeNote(quote),
            applyButtonText: l10n.applyToNote,
            onApply: (analysisResult) {
              widget.onAiAnalysisCompleted(analysisResult);
            },
            onCancel: () {},
            isMarkdown: true, // 分析结果通常是Markdown格式
          );
        },
      );

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.analysisComplete),
            duration: AppConstants.snackBarDurationImportant,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.analysisFailedWithError(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 问笔记功能
  Future<void> _askNoteQuestion() async {
    final l10n = AppLocalizations.of(context);

    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterContent),
          duration: AppConstants.snackBarDurationNormal,
        ),
      );
      return;
    }

    // 创建临时Quote对象用于问答
    final tempQuote = Quote(
      id: '',
      content: widget.contentController.text,
      date: DateTime.now().toIso8601String(),
      sourceAuthor: widget.authorController.text.trim().isNotEmpty
          ? widget.authorController.text.trim()
          : null,
      sourceWork: widget.workController.text.trim().isNotEmpty
          ? widget.workController.text.trim()
          : null,
    );

    // 导航到聊天页面
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: tempQuote)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    AIService? aiService;
    try {
      aiService = Provider.of<AIService>(context, listen: false);
    } catch (_) {
      aiService = null;
    }

    final bool aiConfigured = aiService != null && aiService.hasValidApiKey();

    if (!aiConfigured) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.auto_awesome),
      tooltip: l10n.aiAssistant,
      onPressed: () => _showAIOptions(context),
    );
  }
}
