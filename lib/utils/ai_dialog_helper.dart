import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../widgets/streaming_text_dialog.dart';
import '../theme/app_theme.dart';

class AiDialogHelper {
  final BuildContext context;
  final AIService aiService;

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
      backgroundColor:
          theme.brightness == Brightness.light
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
                    title: const Text('智能分析来源'),
                    subtitle: const Text('分析文本中可能的作者和作品'),
                    onTap: () {
                      Navigator.pop(context);
                      onAnalyzeSource();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: const Text('润色文本'),
                    subtitle: const Text('优化文本表达，使其更加流畅、优美'),
                    onTap: () {
                      Navigator.pop(context);
                      onPolishText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('续写内容'),
                    subtitle: const Text('以相同的风格和语调延伸当前内容'),
                    onTap: () {
                      Navigator.pop(context);
                      onContinueText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics),
                    title: const Text('深度分析'),
                    subtitle: const Text('对笔记内容进行深入分析和解读'),
                    onTap: () {
                      Navigator.pop(context);
                      onAnalyzeContent();
                    },
                  ),
                  if (onAskQuestion != null)
                    ListTile(
                      leading: const Icon(Icons.chat),
                      title: const Text('问笔记'),
                      subtitle: const Text('与AI助手对话，深入探讨笔记内容'),
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
      _showSnackBar('请先输入内容');
      return;
    }

    _showLoadingDialog('正在分析来源...');

    try {
      final result = await aiService.analyzeSource(contentController.text);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      _showSourceAnalysisResultDialog(result, authorController, workController);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showSnackBar('分析失败: $e');
    }
  }

  // 润色文本
  Future<void> polishText(TextEditingController contentController) async {
    if (contentController.text.isEmpty) {
      _showSnackBar('请先输入内容');
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: '润色结果',
            textStream: aiService.streamPolishText(contentController.text),
            applyButtonText: '应用更改',
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
      _showSnackBar('润色失败: $e');
    }
  }

  // 续写文本
  Future<void> continueText(TextEditingController contentController) async {
    if (contentController.text.isEmpty) {
      _showSnackBar('请先输入内容');
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: '续写结果',
            textStream: aiService.streamContinueText(contentController.text),
            applyButtonText: '追加到笔记',
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
      _showSnackBar('续写失败: $e');
    }
  }

  // 深入分析内容
  Future<void> analyzeContent(
    Quote quote, {
    required Function(String) onFinish,
  }) async {
    if (quote.content.isEmpty) {
      _showSnackBar('请先输入内容');
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamingTextDialog(
            title: '笔记分析',
            textStream: aiService.streamSummarizeNote(quote),
            applyButtonText: '更新分析结果',
            onApply: onFinish,
            onCancel: () {
              Navigator.of(dialogContext).pop();
            },
            isMarkdown: true,
          );
        },
      );
    } catch (e) {
      _showSnackBar('分析失败: $e');
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
            title: Text('分析结果 (可信度: $confidence)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (author != null && author.isNotEmpty) ...[
                  const Text(
                    '可能的作者:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(author),
                  const SizedBox(height: 8),
                ],
                if (work != null && work.isNotEmpty) ...[
                  const Text(
                    '可能的作品:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(work),
                  const SizedBox(height: 8),
                ],
                if (explanation.isNotEmpty) ...[
                  const Text(
                    '分析说明:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(explanation, style: const TextStyle(fontSize: 13)),
                ],
                if ((author == null || author.isEmpty) &&
                    (work == null || work.isEmpty))
                  const Text('未能识别出明确的作者或作品'),
              ],
            ),
            actions: [
              if ((author != null && author.isNotEmpty) ||
                  (work != null && work.isNotEmpty))
                TextButton(
                  child: const Text('应用分析结果'),
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
                child: const Text('关闭'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _showSnackBar('解析结果失败: $e');
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
