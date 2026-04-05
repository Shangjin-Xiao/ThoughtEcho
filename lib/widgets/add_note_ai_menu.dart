import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_assistant_entry.dart';
import '../services/ai_service.dart';
import '../models/quote_model.dart';
import '../widgets/streaming_text_dialog.dart';
import '../widgets/ai_options_menu.dart';
import '../widgets/source_analysis_result_dialog.dart';
import '../pages/ai_assistant_page.dart'; // 添加问笔记聊天页面导入
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class AddNoteAIMenu extends StatefulWidget {
  final TextEditingController contentController;
  final TextEditingController authorController;
  final TextEditingController workController;
  final Function(String) onAiAnalysisCompleted;
  final List<String>? tagNames; // 标签名称列表（用于 AI 分析）

  const AddNoteAIMenu({
    super.key,
    required this.contentController,
    required this.authorController,
    required this.workController,
    required this.onAiAnalysisCompleted,
    this.tagNames,
  });

  @override
  State<AddNoteAIMenu> createState() => _AddNoteAIMenuState();
}

class _AddNoteAIMenuState extends State<AddNoteAIMenu> {
  // 显示AI选项菜单
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

      // 调用AI分析来源（传递已有的作者/出处供 AI 验证）
      final existingAuthor = widget.authorController.text.trim();
      final existingWork = widget.workController.text.trim();
      final result = await aiService.analyzeSource(
        widget.contentController.text,
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
          authorController: widget.authorController,
          workController: widget.workController,
          onError: (error) {
            _showErrorDialog(
              l10n.parseResultFailedWithError(kDebugMode ? error : ''),
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
        _showErrorDialog(
          l10n.analysisFailedWithError(kDebugMode ? e.toString() : ''),
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
              Navigator.of(dialogContext).pop();
            },
            onCancel: () {
              Navigator.of(dialogContext).pop();
            },
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
              Navigator.of(dialogContext).pop();
            },
            onCancel: () {
              Navigator.of(dialogContext).pop();
            },
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
            textStream: aiService.streamSummarizeNote(
              quote,
              tagNames: widget.tagNames,
            ),
            applyButtonText: l10n.applyToNote,
            onApply: (analysisResult) {
              widget.onAiAnalysisCompleted(analysisResult);
              Navigator.of(dialogContext).pop();
            },
            onCancel: () {
              Navigator.of(dialogContext).pop();
            },
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
      MaterialPageRoute(
        builder: (context) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.note,
          quote: tempQuote,
        ),
      ),
    );
  }

  /// 在 BottomSheet 上下文中用 AlertDialog 显示错误（避免 SnackBar 被遮挡）
  void _showErrorDialog(String message) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.analysisResult),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
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
