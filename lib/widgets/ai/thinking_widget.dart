import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../theme/theme_style.dart';

/// 思考过程折叠组件 - 展示 AI 的思考过程
///
/// - 进行中时自动展开，完成后默认折叠
/// - 折叠态是一行状态文字，展开后内容靠左侧竖线归组
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
    final muted = theme.colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 折叠标题：一行状态文字，不是一块卡片。
          //
          // 这里原来是填充底色 + 整圈描边 + 气泡形状的一张卡，思考——模型的
          // 草稿——因此在对话流里比回答本身还重。现在只留图标、一行字和箭头，
          // 靠内容区左边那条竖线表示"这段是引下来的过程"。
          Material(
            color: Colors.transparent,
            child: Semantics(
              button: true,
              label: widget.inProgress ? l10n.aiThinking : l10n.thinking,
              expanded: _isExpanded,
              child: InkWell(
                onTap: _toggleExpanded,
                borderRadius: BorderRadius.circular(
                  AppShapeTokens.of(context).buttonRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 进行中是脉冲圆点，结束后换成静态图标
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
                            Icons.lightbulb_outline,
                            size: 16,
                            color: muted,
                          ),
                        ),
                      // 标题文本。收起时是个名词标签（「思考」），不是
                      // showThinking（「查看思考过程」）那种祈使句——它读起来
                      // 像用户在对自己下指令。
                      Flexible(
                        child: ExcludeSemantics(
                          child: Text(
                            widget.inProgress ? l10n.aiThinking : l10n.thinking,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      // 旋转箭头
                      RotationTransition(
                        turns: Tween<double>(begin: 0, end: 0.5)
                            .animate(_rotationController),
                        child: Icon(
                          Icons.expand_more,
                          size: 18,
                          color: muted.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
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
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: widget.thinkingText.isEmpty
                          ? Text(
                              l10n.thinkingInProgress,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : SingleChildScrollView(
                              child: MarkdownBody(
                                data: widget.thinkingText,
                                selectable: true,
                                onTapLink: (text, href, title) async {
                                  if (href == null || href.isEmpty) return;
                                  try {
                                    final uri = Uri.tryParse(href);
                                    if (uri != null &&
                                        await canLaunchUrl(uri)) {
                                      await launchUrl(uri,
                                          mode: LaunchMode.externalApplication);
                                    }
                                  } catch (_) {}
                                },
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
