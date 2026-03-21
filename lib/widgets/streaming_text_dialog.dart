import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:async';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/color_utils.dart';
import 'package:thoughtecho/theme/app_theme.dart';

/// 流式文本对话框
///
/// 用于显示 AI 流式响应的统一对话框组件，支持：
/// - 深度分析、润色文本、续写文本
/// - Markdown 渲染
/// - 流式加载动画
/// - 复制/应用操作
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

class _StreamingTextDialogState extends State<StreamingTextDialog>
    with SingleTickerProviderStateMixin {
  AppLocalizations get l10n => AppLocalizations.of(context);
  String _currentText = '';
  bool _isStreamingComplete = false;
  bool _hasError = false;
  StreamSubscription<String>? _streamSubscription;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // 脉动动画控制器
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _streamSubscription = widget.textStream.listen(
      (chunk) {
        if (mounted) {
          setState(() {
            _currentText += chunk;
          });
          // 自动滚动到底部
          _scrollToBottom();
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isStreamingComplete = true;
          });
          _pulseController.stop();
        }
      },
      onError: (error) {
        logDebug('流式传输错误: $error');
        if (mounted) {
          setState(() {
            _currentText += '\n\n${l10n.occurredError(error.toString())}';
            _isStreamingComplete = true;
            _hasError = true;
          });
          _pulseController.stop();
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.of(context).size;

    // 计算对话框尺寸：宽度最大 600，高度最大 70%
    final dialogWidth = screenSize.width > 700 ? 600.0 : screenSize.width * 0.9;
    final dialogHeight = screenSize.height * 0.7;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.dialogRadius),
      ),
      elevation: 8,
      backgroundColor: colorScheme.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.dialogRadius),
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: dialogHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              _buildHeader(theme, colorScheme),
              // 内容区域
              Flexible(child: _buildContent(theme, colorScheme)),
              // 底部操作栏
              _buildActions(theme, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建标题栏
  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.applyOpacity(0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // AI 图标容器
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer,
                  colorScheme.primaryContainer.applyOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: _isStreamingComplete
                      ? colorScheme.primary
                      : colorScheme.primary.applyOpacity(_pulseAnimation.value),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (!_isStreamingComplete) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.aiGenerating,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 关闭按钮
          IconButton(
            icon: Icon(
              Icons.close,
              color: colorScheme.onSurfaceVariant,
              size: 20,
            ),
            onPressed: () {
              widget.onCancel();
              Navigator.of(context).pop();
            },
            tooltip: l10n.close,
          ),
        ],
      ),
    );
  }

  /// 构建内容区域
  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    if (_currentText.isEmpty && !_isStreamingComplete) {
      // 加载状态
      return Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 加载动画
            _buildLoadingIndicator(colorScheme),
            const SizedBox(height: 20),
            Text(
              l10n.waitingForAIContent,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.applyOpacity(0.3),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.isMarkdown
                  ? MarkdownBody(
                      data: _currentText,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          height: 1.6,
                        ),
                        h1: theme.textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: theme.textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        h3: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        listBullet: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.primary,
                        ),
                        blockquote: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: colorScheme.primary.applyOpacity(0.5),
                              width: 3,
                            ),
                          ),
                        ),
                        blockquotePadding:
                            const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                        code: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          color: colorScheme.onSurface,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: colorScheme.outlineVariant,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    )
                  : SelectableText(
                      _currentText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.6,
                      ),
                    ),
              // 流式加载时显示光标
              if (!_isStreamingComplete)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        width: 8,
                        height: 16,
                        decoration: BoxDecoration(
                          color: colorScheme.primary
                              .applyOpacity(_pulseAnimation.value),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建加载指示器
  Widget _buildLoadingIndicator(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                colorScheme.primary.applyOpacity(_pulseAnimation.value * 0.3),
                colorScheme.primary.applyOpacity(_pulseAnimation.value * 0.1),
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 24,
                color: colorScheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建底部操作栏
  Widget _buildActions(ThemeData theme, ColorScheme colorScheme) {
    final canApply =
        _isStreamingComplete && _currentText.isNotEmpty && !_hasError;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.applyOpacity(0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 状态指示
          if (_isStreamingComplete && !_hasError)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer.applyOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: colorScheme.tertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.complete,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          // 取消按钮
          TextButton(
            onPressed: () {
              widget.onCancel();
              Navigator.of(context).pop();
            },
            child: Text(l10n.cancelLabel),
          ),
          const SizedBox(width: 8),
          // 应用按钮
          FilledButton.icon(
            onPressed: canApply
                ? () {
                    widget.onApply(_currentText);
                    Navigator.of(context).pop();
                  }
                : null,
            icon: Icon(
              _getApplyButtonIcon(),
              size: 18,
            ),
            label: Text(widget.applyButtonText),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 根据按钮文本推断图标
  IconData _getApplyButtonIcon() {
    final text = widget.applyButtonText.toLowerCase();
    if (text.contains('copy') || text.contains('复制')) {
      return Icons.copy_outlined;
    } else if (text.contains('append') || text.contains('附加')) {
      return Icons.add_outlined;
    } else if (text.contains('apply') || text.contains('应用')) {
      return Icons.check_outlined;
    }
    return Icons.done_outlined;
  }
}
