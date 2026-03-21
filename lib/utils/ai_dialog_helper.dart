import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../widgets/streaming_text_dialog.dart';
import '../widgets/ai_options_menu.dart';
import '../widgets/source_analysis_result_dialog.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class AiDialogHelper {
  final BuildContext context;
  final AIService aiService;
  AppLocalizations get l10n => AppLocalizations.of(context);

  AiDialogHelper(this.context)
      : aiService = Provider.of<AIService>(context, listen: false);

  // 显示AI选项菜单（使用统一组件）
  void showAiOptions({
    required VoidCallback onAnalyzeSource,
    required VoidCallback onPolishText,
    required VoidCallback onContinueText,
    required VoidCallback onAnalyzeContent,
    VoidCallback? onAskQuestion, // 添加问笔记回调
  }) {
    AiOptionsMenu.show(
      context: context,
      showAskNote: onAskQuestion != null,
      onAnalyzeSource: onAnalyzeSource,
      onPolishText: onPolishText,
      onContinueText: onContinueText,
      onAnalyzeContent: onAnalyzeContent,
      onAskNote: onAskQuestion,
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
      // 传递已有的作者/出处供 AI 验证
      final existingAuthor = authorController.text.trim();
      final existingWork = workController.text.trim();
      final result = await aiService.analyzeSource(
        contentController.text,
        existingAuthor: existingAuthor.isNotEmpty ? existingAuthor : null,
        existingWork: existingWork.isNotEmpty ? existingWork : null,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      SourceAnalysisResultDialog.show(
        context,
        result,
        authorController: authorController,
        workController: workController,
        onError: (error) => _showSnackBar(l10n.parseResultFailed(error)),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showSnackBar(
          l10n.analysisFailedWithError(kDebugMode ? e.toString() : ''));
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
    List<String>? tagNames,
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
            textStream:
                aiService.streamSummarizeNote(quote, tagNames: tagNames),
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
      _showSnackBar(
          l10n.analysisFailedWithError(kDebugMode ? e.toString() : ''));
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
