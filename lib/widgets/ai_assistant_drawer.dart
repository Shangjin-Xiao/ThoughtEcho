import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../widgets/streaming_text_dialog.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../pages/note_qa_chat_page.dart';
import '../constants/app_constants.dart';

/// AI助手功能选项枚举
enum AIOption {
  analyzeSource,
  polishText,
  continueText,
  analyzeContent,
  askQuestion,
}

/// AI助手抽屉组件 - 可复用
class AIAssistantDrawer extends StatelessWidget {
  final Quote quote;
  final Function(Quote updatedQuote)? onContentUpdated;
  final Function()? onNavigateToEditor;

  const AIAssistantDrawer({
    super.key,
    required this.quote,
    this.onContentUpdated,
    this.onNavigateToEditor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              _buildOptionTile(
                context,
                icon: Icons.text_fields,
                title: '智能分析来源',
                subtitle: '分析文本中可能的作者和作品',
                onTap: () => _handleAIOption(context, AIOption.analyzeSource),
              ),
              _buildOptionTile(
                context,
                icon: Icons.brush,
                title: '润色文本',
                subtitle: '优化文本表达，使其更加流畅、优美',
                onTap: () => _handleAIOption(context, AIOption.polishText),
              ),
              _buildOptionTile(
                context,
                icon: Icons.add_circle_outline,
                title: '续写内容',
                subtitle: '以相同的风格和语调延伸当前内容',
                onTap: () => _handleAIOption(context, AIOption.continueText),
              ),
              _buildOptionTile(
                context,
                icon: Icons.analytics,
                title: '深度分析',
                subtitle: '对笔记内容进行深入分析和解读',
                onTap: () => _handleAIOption(context, AIOption.analyzeContent),
              ),
              _buildOptionTile(
                context,
                icon: Icons.chat,
                title: '问笔记',
                subtitle: '与AI助手对话，深入探讨笔记内容',
                onTap: () => _handleAIOption(context, AIOption.askQuestion),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  void _handleAIOption(BuildContext context, AIOption option) {
    Navigator.pop(context); // 关闭抽屉

    switch (option) {
      case AIOption.analyzeSource:
        _analyzeSource(context);
        break;
      case AIOption.polishText:
        _polishText(context);
        break;
      case AIOption.continueText:
        _continueText(context);
        break;
      case AIOption.analyzeContent:
        _analyzeContent(context);
        break;
      case AIOption.askQuestion:
        _askQuestion(context);
        break;
    }
  }

  void _analyzeSource(BuildContext context) async {
    final plainText = quote.content.trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先输入内容'),
        duration: AppConstants.snackBarDurationError,
      ));
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在分析来源...'),
              ],
            ),
          );
        },
      );

      final result = await aiService.analyzeSource(plainText);

      if (!context.mounted) return;
      Navigator.of(context).pop();

      try {
        final Map<String, dynamic> sourceData = json.decode(result);
        String? author = sourceData['author'] as String?;
        String? work = sourceData['work'] as String?;
        String confidence = sourceData['confidence'] as String? ?? '低';
        String explanation = sourceData['explanation'] as String? ?? '';

        if (context.mounted) {
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
                      const Text('可能的作者:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(author),
                      const SizedBox(height: 8),
                    ],
                    if (work != null && work.isNotEmpty) ...[
                      const Text('可能的作品:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(work),
                      const SizedBox(height: 8),
                    ],
                    if (explanation.isNotEmpty) ...[
                      const Text('分析说明:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        final updatedQuote = quote.copyWith(
                          sourceAuthor: author,
                          sourceWork: work,
                        );
                        onContentUpdated?.call(updatedQuote);
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
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('解析结果失败: $e'),
            duration: AppConstants.snackBarDurationError,
          ));
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('分析失败: $e'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
    }
  }

  void _polishText(BuildContext context) async {
    final plainText = quote.content.trim();
    if (plainText.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请先输入内容'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      if (context.mounted) {
        await showDialog<String?>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StreamingTextDialog(
              title: '润色结果',
              textStream: aiService.streamPolishText(plainText),
              applyButtonText: '应用更改',
              onApply: (polishedText) {
                final updatedQuote = quote.copyWith(content: polishedText);
                onContentUpdated?.call(updatedQuote);
                Navigator.of(dialogContext).pop(polishedText);
              },
              onCancel: () => Navigator.of(dialogContext).pop(null),
              isMarkdown: false,
            );
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('润色失败: $e'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
    }
  }

  void _continueText(BuildContext context) async {
    final plainText = quote.content.trim();
    if (plainText.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请先输入内容'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      if (context.mounted) {
        await showDialog<String?>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StreamingTextDialog(
              title: '续写结果',
              textStream: aiService.streamContinueText(plainText),
              applyButtonText: '追加到笔记',
              onApply: (continuedText) {
                final updatedQuote = quote.copyWith(
                  content: '$plainText\n\n$continuedText',
                );
                onContentUpdated?.call(updatedQuote);
                Navigator.of(dialogContext).pop(continuedText);
              },
              onCancel: () => Navigator.of(dialogContext).pop(null),
              isMarkdown: false,
            );
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('续写失败: $e'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
    }
  }

  void _analyzeContent(BuildContext context) async {
    final plainText = quote.content.trim();
    if (plainText.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请先输入内容'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StreamingTextDialog(
              title: '笔记分析',
              textStream: aiService.streamSummarizeNote(quote),
              applyButtonText: '复制结果',
              onApply: (analysisResult) {
                Clipboard.setData(ClipboardData(text: analysisResult)).then((_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('分析结果已复制到剪贴板'),
                      duration: AppConstants.snackBarDurationImportant,
                    ));
                  }
                });
                Navigator.of(dialogContext).pop();
              },
              onCancel: () => Navigator.of(dialogContext).pop(),
              isMarkdown: true,
            );
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('分析失败: $e'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
    }
  }

  void _askQuestion(BuildContext context) {
    if (quote.content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先输入内容'),
        duration: AppConstants.snackBarDurationNormal,
      ));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: quote)),
    );
  }

  /// 显示AI助手抽屉的静态方法
  static void show(BuildContext context, Quote quote, {
    Function(Quote updatedQuote)? onContentUpdated,
    Function()? onNavigateToEditor,
  }) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (BuildContext context) {
        return AIAssistantDrawer(
          quote: quote,
          onContentUpdated: onContentUpdated,
          onNavigateToEditor: onNavigateToEditor,
        );
      },
    );
  }
}