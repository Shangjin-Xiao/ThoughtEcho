import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/ai_service.dart';
import '../models/quote_model.dart';
import '../theme/app_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../widgets/streaming_text_dialog.dart';

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

    showModalBottomSheet(
      context: context,
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
                      _analyzeSource();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: const Text('润色文本'),
                    subtitle: const Text('优化文本表达，使其更加流畅、优美'),
                    onTap: () {
                      Navigator.pop(context);
                      _polishText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('续写内容'),
                    subtitle: const Text('以相同的风格和语调延伸当前内容'),
                    onTap: () {
                      Navigator.pop(context);
                      _continueText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics),
                    title: const Text('深度分析'),
                    subtitle: const Text('对笔记内容进行深入分析和解读'),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeContent();
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
    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
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
        String confidence = sourceData['confidence'] as String? ?? '低';
        String explanation = sourceData['explanation'] as String? ?? '';

        // 显示结果对话框
        if (mounted) {
          showDialog(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text('分析结果 (可信度: $confidence)'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (explanation.isNotEmpty) Text(explanation),
                    const SizedBox(height: 8),
                    if (author != null && author.isNotEmpty)
                      Text('作者: $author'),
                    if (work != null && work.isNotEmpty) Text('作品: $work'),
                  ],
                ),
                actions: [
                  if ((author != null && author.isNotEmpty) ||
                      (work != null && work.isNotEmpty))
                    TextButton(
                      child: const Text('应用结果'),
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
                    child: const Text('关闭'),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('解析结果失败: $e')));
        }
      }
    } catch (e) {
      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分析失败: $e')));
      }
    }
  }

  // 润色文本
  Future<void> _polishText() async {
    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
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
            title: '润色结果',
            textStream: aiService.streamPolishText(
              widget.contentController.text,
            ),
            applyButtonText: '应用更改',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('润色失败: $e')));
      }
    }
  }

  // 续写文本
  Future<void> _continueText() async {
    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
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
            title: '续写结果',
            textStream: aiService.streamContinueText(
              widget.contentController.text,
            ),
            applyButtonText: '追加到笔记',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('续写失败: $e')));
      }
    }
  }

  // 深入分析内容
  Future<void> _analyzeContent() async {
    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
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
            title: '笔记分析',
            textStream: aiService.streamSummarizeNote(quote),
            applyButtonText: '应用到笔记', // 或者其他合适的文本
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分析完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分析失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiService = Provider.of<AIService>(context, listen: false);
    final bool aiConfigured = aiService.hasValidApiKey();

    if (!aiConfigured) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.auto_awesome),
      tooltip: 'AI助手',
      onPressed: () => _showAIOptions(context),
    );
  }
}

class _StreamingTextDialog extends StatefulWidget {
  final Stream<String> textStream;
  final String title;
  final String applyButtonText;
  final Function(String) onApply;
  final VoidCallback onCancel;
  final bool isMarkdown;

  const _StreamingTextDialog({
    required this.textStream,
    required this.title,
    required this.applyButtonText,
    required this.onApply,
    required this.onCancel,
    this.isMarkdown = false,
  });

  @override
  State<_StreamingTextDialog> createState() => _StreamingTextDialogState();
}

class _StreamingTextDialogState extends State<_StreamingTextDialog> {
  String _currentText = '';
  bool _isStreamingComplete = false;

  @override
  void initState() {
    super.initState();
    widget.textStream.listen(
      (chunk) {
        setState(() {
          _currentText += chunk;
        });
      },
      onDone: () {
        setState(() {
          _isStreamingComplete = true;
        });
      },
      onError: (error) {
        debugPrint('流式传输错误: $error');
        setState(() {
          _currentText += '\n\n[发生错误: ${error.toString()}]'; // 显示错误信息
          _isStreamingComplete = true; // 标记完成以显示按钮
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child:
            widget.isMarkdown
                ? MarkdownBody(
                  data: _currentText.isEmpty ? '等待AI生成内容...' : _currentText,
                  selectable: true,
                )
                : SelectableText(
                  _currentText.isEmpty ? '等待AI生成内容...' : _currentText,
                ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancel();
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        if (_isStreamingComplete &&
            _currentText.isNotEmpty &&
            !_currentText.contains('[发生错误:')) // 完成且有内容且无错误时显示应用按钮
          TextButton(
            onPressed: () {
              widget.onApply(_currentText);
              Navigator.of(context).pop();
            },
            child: Text(widget.applyButtonText),
          ),
      ],
    );
  }
}
