import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../gen_l10n/app_localizations.dart';

/// 思考过程折叠组件 - 展示 AI 的思考过程
///
/// 参考 Google AI Gallery MessageBodyThinking 设计：
/// - 进行中时自动展开，完成后默认折叠
/// - 左侧竖线标识
/// - 可点击标题栏切换展开/折叠
/// - 使用 Markdown 渲染思考内容
class ThinkingWidget extends StatefulWidget {
  /// 思考过程文本内容
  final String thinkingText;

  /// 是否正在思考中（进行中自动展开）
  final bool inProgress;

  /// 可选的强调色（用于竖线和图标）
  final Color? accentColor;

  const ThinkingWidget({
    super.key,
    required this.thinkingText,
    this.inProgress = false,
    this.accentColor,
  });

  @override
  State<ThinkingWidget> createState() => _ThinkingWidgetState();
}

class _ThinkingWidgetState extends State<ThinkingWidget>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // 进行中时默认展开，完成后默认折叠
    _isExpanded = widget.inProgress;
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    if (_isExpanded) {
      _rotationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ThinkingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果从进行中变为完成，自动折叠
    if (oldWidget.inProgress && !widget.inProgress) {
      setState(() {
        _isExpanded = false;
        _rotationController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _rotationController.forward();
      } else {
        _rotationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏（可点击切换展开）
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.inProgress
                        ? l10n.aiThinking
                        : (_isExpanded
                            ? l10n.hideThinking
                            : l10n.showThinking),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          // 思考内容区域（可展开/折叠）
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: 4,
                      left: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                      ),
                      child: MarkdownBody(
                        data: widget.thinkingText,
                        styleSheet: MarkdownStyleSheet(
                          p: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                          code: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
