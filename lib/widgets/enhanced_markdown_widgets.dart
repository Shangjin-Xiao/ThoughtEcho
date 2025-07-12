import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 增强的代码块组件，支持语法高亮和复制功能
class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;
  final ThemeData theme;

  const CodeBlockWidget({
    super.key,
    required this.code,
    this.language,
    required this.theme,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _isCopied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 代码块头部
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.language?.toUpperCase() ?? 'CODE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                IconButton(
                  icon: Icon(_isCopied ? Icons.check : Icons.copy, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: _copyCode,
                  tooltip: _isCopied ? '已复制' : '复制代码',
                ),
              ],
            ),
          ),
          // 代码内容
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily:
                    'JetBrains Mono, SF Mono, Consolas, Monaco, Courier New, monospace',
                fontSize: 13,
                height: 1.4,
                color: widget.theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() {
      _isCopied = true;
    });

    // 2秒后重置图标
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isCopied = false;
        });
      }
    });

    // 显示提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('代码已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}

/// 增强的引用块组件
class QuoteBlockWidget extends StatelessWidget {
  final String text;
  final ThemeData theme;

  const QuoteBlockWidget({super.key, required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
            width: 4,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote,
            size: 20,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
