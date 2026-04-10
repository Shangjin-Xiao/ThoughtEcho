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
    final lineColor =
        widget.accentColor ?? theme.colorScheme.primary.withValues(alpha: 0.3);
    final iconColor = widget.accentColor ?? theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏（可点击切换展开）
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // 思考图标
                  Icon(
                    widget.inProgress
                        ? Icons.psychology_outlined
                        : Icons.lightbulb_outline,
                    size: 20,
                    color: iconColor,
                  ),
                  const SizedBox(width: 8),
                  // 标题文字
                  Expanded(
                    child: Text(
                      widget.inProgress
                          ? l10n.aiThinking
                          : (_isExpanded
                              ? l10n.hideThinking
                              : l10n.showThinking),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: iconColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // 进行中指示器或展开/折叠图标
                  if (widget.inProgress)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  else
                    RotationTransition(
                      turns: Tween(begin: 0.0, end: 0.5)
                          .animate(_rotationController),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: iconColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 思考内容区域（可展开/折叠）
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Container(
                    margin: const EdgeInsets.only(left: 12, top: 8),
                    padding: const EdgeInsets.only(left: 16, right: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: lineColor,
                          width: 3,
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
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
