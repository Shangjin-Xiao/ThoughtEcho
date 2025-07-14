import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:async';
import 'package:thoughtecho/utils/app_logger.dart';

class StreamingTextDialog extends StatefulWidget {
  final Stream<String> textStream;
  final String title;
  final String applyButtonText;
  final Function(String) onApply;
  final VoidCallback onCancel;
  final bool isMarkdown;

  const StreamingTextDialog({
    super.key,
    required this.textStream,
    required this.title,
    required this.applyButtonText,
    required this.onApply,
    required this.onCancel,
    this.isMarkdown = false,
  });

  @override
  State<StreamingTextDialog> createState() => _StreamingTextDialogState();
}

class _StreamingTextDialogState extends State<StreamingTextDialog> {
  String _currentText = '';
  bool _isStreamingComplete = false;
  StreamSubscription<String>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _streamSubscription = widget.textStream.listen(
      (chunk) {
        if (mounted) {
          setState(() {
            _currentText += chunk;
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isStreamingComplete = true;
          });
        }
      },
      onError: (error) {
        logDebug('流式传输错误: $error');
        if (mounted) {
          setState(() {
            _currentText += '\n\n[发生错误: ${error.toString()}]'; // 显示错误信息
            _isStreamingComplete = true; // 标记完成以显示按钮
          });
        }
      },
    );
  }

  @override
  void dispose() {
    // 取消流订阅
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: widget.isMarkdown
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
