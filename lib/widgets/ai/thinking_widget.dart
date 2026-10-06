import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../theme/theme_style.dart';
import '../app_loading_view.dart';

/// 思考过程折叠组件 - 展示 AI 的思考过程
///
/// - 进行中时自动展开，完成后默认折叠
/// - 折叠态是一行状态文字，展开后内容靠左侧竖线归组
/// - 可点击标题栏切换展开/折叠
/// - 使用 Markdown 渲染思考内容
/// - 支持流式增量内容更新与防抖缓冲
class ThinkingWidget extends StatefulWidget {
  /// 思考过程文本内容
  final String thinkingText;

  /// 是否正在思考中（进行中自动展开并显示转圈）
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
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _expandController;
  late final ValueNotifier<String> _displayedThinkingTextNotifier;
  Timer? _debounceTimer;

  static const Duration _debounceInterval = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    // 思考中展开，完成后折叠
    _isExpanded = widget.inProgress;
    _displayedThinkingTextNotifier = ValueNotifier<String>(widget.thinkingText);

    // 展开/折叠与箭头旋转动画
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    if (_isExpanded) {
      _expandController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ThinkingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果进度状态改变，自动折叠/展开
    if (oldWidget.inProgress != widget.inProgress) {
      if (widget.inProgress) {
        if (!_isExpanded) {
          setState(() {
            _isExpanded = true;
          });
          _expandController.forward();
        }
      } else {
        if (_isExpanded) {
          setState(() {
            _isExpanded = false;
          });
          _expandController.reverse();
        }
      }
    }

    // 处理思考文本增量更新与防抖
    final textChanged = oldWidget.thinkingText != widget.thinkingText;
    final inProgressChanged = oldWidget.inProgress != widget.inProgress;

    if (textChanged || inProgressChanged) {
      _scheduleTextUpdate();
    }
  }

  void _scheduleTextUpdate() {
    if (!widget.inProgress) {
      // 流式输出结束，立即清空 Timer 并刷新最终完整文本
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _displayedThinkingTextNotifier.value = widget.thinkingText;
      return;
    }

    // 从空文本到有内容时，立即刷新首字保证交互响应
    if (_displayedThinkingTextNotifier.value.isEmpty &&
        widget.thinkingText.isNotEmpty) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _displayedThinkingTextNotifier.value = widget.thinkingText;
      return;
    }

    // 文本变短或非前缀增长（例如多轮对话重用同一个 State），立即同步
    final isPrefixExtension =
        widget.thinkingText.startsWith(_displayedThinkingTextNotifier.value);
    if (!isPrefixExtension) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _displayedThinkingTextNotifier.value = widget.thinkingText;
      return;
    }

    // 100ms 帧防抖缓冲：无活跃 Timer 时启动防抖 Timer
    // 依据：100ms 相当于约 10 FPS 的 UI 增量刷帧频率，在 LLM 高频 Token 流（如 >50 tokens/s）下
    // 能大幅降低 Markdown AST 重建与 Widget 节点树构建开销，同时符合人眼流畅流式感知的时延阈值。
    if (_debounceTimer == null || !_debounceTimer!.isActive) {
      _debounceTimer = Timer(_debounceInterval, () {
        if (mounted) {
          _displayedThinkingTextNotifier.value = widget.thinkingText;
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _displayedThinkingTextNotifier.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
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
                      // 进行中是转圈，结束后换成静态图标。
                      //
                      // 这里原来是一颗 8px 的脉冲圆点。8px 在高 DPI 屏上就是
                      // 正文前面的一个小点，1.0→1.2 的缩放幅度也小到看不出在
                      // 动——读起来不是"正在进行"，是"这行前面有个 bullet"。
                      // 圈的重量跟完成态的 16 号图标对齐（尺寸由
                      // AppInlineLoadingIndicator 的默认值定），换状态时这一列不跳。
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          // Center 是必须的：外面这只 SizedBox 给的是紧约束，
                          // 直接塞进去的话转圈会被撑到 16，
                          // AppInlineLoadingIndicator 那个"比图标小一号才等重"
                          // 的默认尺寸就被作废了。
                          child: Center(
                            child: widget.inProgress
                                ? AppInlineLoadingIndicator(
                                    color: theme.colorScheme.primary,
                                  )
                                : Icon(
                                    Icons.lightbulb_outline,
                                    size: 16,
                                    color: muted,
                                  ),
                          ),
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
                            .animate(_expandController),
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
          // 思考内容区域（平滑过渡 + 防抖缓冲 + 重绘图层隔离）
          SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: _expandController,
              curve: Curves.easeInOutCubic,
            ),
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: _expandController,
              builder: (context, child) {
                final isFullyCollapsed =
                    !_isExpanded && _expandController.isDismissed;
                return Offstage(
                  offstage: isFullyCollapsed,
                  child: TickerMode(
                    enabled: !isFullyCollapsed,
                    child: child!,
                  ),
                );
              },
              child: Padding(
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
                  child: ValueListenableBuilder<String>(
                    valueListenable: _displayedThinkingTextNotifier,
                    builder: (context, thinkingText, child) {
                      if (thinkingText.isEmpty) {
                        return Text(
                          l10n.thinkingInProgress,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      }
                      return RepaintBoundary(
                        child: SingleChildScrollView(
                          child: MarkdownBody(
                            data: thinkingText,
                            // 推理还在流的时候不开可选：selectable 会给每
                            // 个块套 SelectableText，而这段文字每来一批
                            // token 就整篇重建一次，越想越贵。想完就恢复。
                            selectable: !widget.inProgress,
                            onTapLink: (text, href, title) async {
                              if (href == null || href.isEmpty) return;
                              try {
                                final uri = Uri.tryParse(href);
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              } catch (_) {}
                            },
                            styleSheet:
                                MarkdownStyleSheet.fromTheme(theme).copyWith(
                              p: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                height: 1.5,
                              ),
                              listBullet: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              code: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              blockquote: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
