import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../gen_l10n/app_localizations.dart';

/// 思考过程折叠组件 - 展示 AI 的思考过程
///
/// 参考 Google AI Gallery MessageBodyThinking 设计：
/// - 进行中时自动展开，完成后默认折叠
/// - 左侧竖线标识，带脉冲动画
/// - 可点击标题栏切换展开/折叠
/// - 使用 Markdown 渲染思考内容
/// - 支持流式增量内容更新
class ThinkingWidget extends StatefulWidget {
  /// 思考过程文本内容
  final String thinkingText;

  /// 是否正在思考中（进行中自动展开且显示脉冲）
  final bool inProgress;

  /// 可选的强调色（用于竖线和图标）
  final Color? accentColor;

  /// 思考内容是否为空
  bool get isEmpty => thinkingText.isEmpty;

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
    with TickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _rotationController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // 思考中展开，完成后折叠
    _isExpanded = widget.inProgress;

    // 箭头旋转动画
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    if (_isExpanded) {
      _rotationController.value = 1.0;
    }

    // 脉冲动画（仅在进行中时显示）
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    if (widget.inProgress) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(ThinkingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果进度状态改变，自动折叠/展开
    if (oldWidget.inProgress != widget.inProgress) {
      if (widget.inProgress) {
        _pulseController.repeat();
        if (!_isExpanded) {
          _isExpanded = true;
          _rotationController.forward();
        }
      } else {
        _pulseController.stop();
        if (_isExpanded) {
          _isExpanded = false;
          _rotationController.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
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
    final isDark = theme.brightness == Brightness.dark;

    // 根据主题调整背景色
    final backgroundColor = isDark
        ? theme.colorScheme.surfaceContainerLow
        : theme.colorScheme.surfaceContainerLowest;
    final borderColor = widget.inProgress
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    const borderWidth = 2.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏（可点击切换展开）
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpanded,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // 动画脉冲指示器（仅在进行中时显示）
                    if (widget.inProgress)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 1.0, end: 1.2)
                              .animate(_pulseController),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.psychology_outlined,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    // 标题文本
                    Expanded(
                      child: Text(
                        widget.inProgress
                            ? l10n.aiThinking
                            : (_isExpanded
                                ? l10n.hideThinking
                                : l10n.showThinking),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    // 旋转箭头
                    RotationTransition(
                      turns: Tween<double>(begin: 0, end: 0.5)
                          .animate(_rotationController),
                      child: Icon(
                        Icons.expand_more,
                        size: 24,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 思考内容区域（可展开/折叠）
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: borderColor,
                            width: borderWidth,
                          ),
                        ),
                      ),
                      child: widget.thinkingText.isEmpty
                          ? Text(
                              l10n.thinkingInProgress,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : SingleChildScrollView(
                              child: MarkdownBody(
                                data: widget.thinkingText,
                                selectable: true,
                                styleSheet: MarkdownStyleSheet.fromTheme(theme)
                                    .copyWith(
                                  p: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    height: 1.5,
                                  ),
                                  listBullet:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  code: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurfaceVariant,
                                    backgroundColor: theme
                                        .colorScheme.surfaceContainerHighest,
                                  ),
                                  codeblockDecoration: BoxDecoration(
                                    color:
                                        theme.colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  blockquote:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
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
