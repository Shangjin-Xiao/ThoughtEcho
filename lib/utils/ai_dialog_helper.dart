import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../widgets/streaming_text_dialog.dart';
import '../theme/app_theme.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class AiDialogHelper {
  final BuildContext context;
  final AIService aiService;
  AppLocalizations get l10n => AppLocalizations.of(context);

  AiDialogHelper(this.context)
      : aiService = Provider.of<AIService>(context, listen: false);

  // 显示AI选项菜单
  void showAiOptions({
    required VoidCallback onAnalyzeSource,
    required VoidCallback onPolishText,
    required VoidCallback onContinueText,
    required VoidCallback onAnalyzeContent,
    VoidCallback? onAskQuestion, // 添加问笔记回调
  }) {
    final theme = Theme.of(context);

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
                      onAnalyzeSource();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: Text(l10n.polishText),
                    subtitle: Text(l10n.polishTextDesc),
                    onTap: () {
                      Navigator.pop(context);
                      onPolishText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(l10n.continueWriting),
                    subtitle: Text(l10n.continueWritingDesc),
                    onTap: () {
                      Navigator.pop(context);
                      onContinueText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics),
                    title: Text(l10n.deepAnalysis),
                    subtitle: Text(l10n.deepAnalysisDesc),
                    onTap: () {
                      Navigator.pop(context);
                      onAnalyzeContent();
                    },
                  ),
                  if (onAskQuestion != null)
                    ListTile(
                      leading: const Icon(Icons.chat),
                      title: Text(l10n.askNote),
                      subtitle: Text(l10n.askNoteDesc),
                      onTap: () {
                        Navigator.pop(context);
                        onAskQuestion();
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
  Future<void> analyzeSource(
    TextEditingController contentController,
    TextEditingController authorController,
    TextEditingController workController,
  ) async {
    if (contentController.text.isEmpty) {
      _showSnackBar(l10n.pleaseEnterContent);
      return;
    }

    _showLoadingDialog(l10n.analyzingSource);

    try {
      final result = await aiService.analyzeSource(contentController.text);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      _showSourceAnalysisResultDialog(result, authorController, workController);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showSnackBar(l10n.analysisFailedWithError(e.toString()));
    }
  }

  // 润色文本
  Future<void> polishText(TextEditingController contentController) async {
    if (contentController.text.isEmpty) {
      _showSnackBar(l10n.pleaseEnterContent);
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: l10n.polishResult,
            textStream: aiService.streamPolishText(contentController.text),
            applyButtonText: l10n.applyChanges,
            onApply: (polishedText) {
              contentController.text = polishedText;
            },
            onCancel: () {
              Navigator.of(dialogContext).pop();
            },
          );
        },
      );
    } catch (e) {
      _showSnackBar(l10n.polishFailedWithError(e.toString()));
    }
  }

  // 续写文本
  Future<void> continueText(TextEditingController contentController) async {
    if (contentController.text.isEmpty) {
      _showSnackBar(l10n.pleaseEnterContent);
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: l10n.continueResult,
            textStream: aiService.streamContinueText(contentController.text),
            applyButtonText: l10n.appendToNote,
            onApply: (continuedText) {
              contentController.text += continuedText;
            },
            onCancel: () {
              Navigator.of(dialogContext).pop();
            },
          );
        },
      );
    } catch (e) {
      _showSnackBar(l10n.continueFailedWithError(e.toString()));
    }
  }

  // 深入分析内容
  Future<void> analyzeContent(
    Quote quote, {
    required Function(String) onFinish,
  }) async {
    if (quote.content.isEmpty) {
      _showSnackBar(l10n.pleaseEnterContent);
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: l10n.noteAnalysis,
            textStream: aiService.streamSummarizeNote(quote),
            applyButtonText: l10n.applyToNote,
            onApply: onFinish,
            onCancel: () {
              Navigator.of(dialogContext).pop();
            },
            isMarkdown: true,
          );
        },
      );
    } catch (e) {
      _showSnackBar(l10n.analysisFailedWithError(e.toString()));
    }
  }

  void _showSourceAnalysisResultDialog(
    String result,
    TextEditingController authorController,
    TextEditingController workController,
  ) {
    try {
      final Map<String, dynamic> sourceData = json.decode(result);
      String? author = sourceData['author'] as String?;
      String? work = sourceData['work'] as String?;
      String confidence = sourceData['confidence'] as String? ?? '低';
      String explanation = sourceData['explanation'] as String? ?? '';

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
                    if (author != null && author.isNotEmpty) {
                      authorController.text = author;
                    }
                    if (work != null && work.isNotEmpty) {
                      workController.text = work;
                    }
                    Navigator.of(dialogContext).pop();
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
    } catch (e) {
      _showSnackBar(l10n.parseResultFailed(e.toString()));
    }
  }

  void _showLoadingDialog(String message) {
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
              Text(message),
            ],
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    }
  }
}
