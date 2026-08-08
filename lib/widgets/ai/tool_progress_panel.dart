import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../theme/theme_style.dart';

/// 工具调用进度状态
enum ToolProgressStatus {
  /// 等待执行
  pending,

  /// 正在执行
  running,

  /// 已完成
  completed,

  /// 执行失败
  failed,
}

/// 工具调用进度项
class ToolProgressItem {
  /// 工具调用 ID（用于精确匹配结果）
  final String? toolCallId;

  /// 工具名称
  final String toolName;

  /// 工具描述或参数摘要
  final String? description;

  /// 执行状态
  final ToolProgressStatus status;

  /// 执行结果摘要
  final String? result;

  /// 该工具调用之后、下一次工具调用之前 AI 输出的过渡叙述文本，
  /// 用于让"让我看看…"这类描述与工具调用按时间顺序穿插展示。
  final String? narrationText;

  /// 这次工具调用**之后**模型继续想的那段思考。
  ///
  /// 查完东西再想一轮是常态，而思考只有一个字段时那段会被并进开头那坨，
  /// 读起来像模型在动手之前就已经知道了查询结果。挂在各自的工具下面，
  /// 抽屉里才是一条按时间走的线。
  final String? thinkingText;

  const ToolProgressItem({
    this.toolCallId,
    required this.toolName,
    this.description,
    required this.status,
    this.result,
    this.narrationText,
    this.thinkingText,
  });

  ToolProgressItem copyWith({
    String? toolCallId,
    String? toolName,
    String? description,
    ToolProgressStatus? status,
    String? result,
    String? narrationText,
    String? thinkingText,
  }) {
    return ToolProgressItem(
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      description: description ?? this.description,
      status: status ?? this.status,
      result: result ?? this.result,
      narrationText: narrationText ?? this.narrationText,
      thinkingText: thinkingText ?? this.thinkingText,
    );
  }
}

/// 一次工具调用过程的完整快照。
///
/// 抽屉是独立路由，父组件重建不会带着它一起刷新；用可监听的快照传进去，
/// 用户在 Agent 还在跑的时候拉开抽屉才能看到进度继续走。
@immutable
class ToolProgressSnapshot {
  final String title;
  final List<ToolProgressItem> items;
  final bool inProgress;
  final String? thinkingText;

  const ToolProgressSnapshot({
    required this.title,
    required this.items,
    this.inProgress = false,
    this.thinkingText,
  });
}

/// 按状态给出图标。
///
/// 这里曾经是一个恒定 `secondaryContainer` 的圆点：四个状态长得完全一样，
/// 工具调用失败和成功在界面上无法区分。
Widget _statusIcon(BuildContext context, ToolProgressStatus status) {
  final theme = Theme.of(context);
  switch (status) {
    case ToolProgressStatus.pending:
      return Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    case ToolProgressStatus.running:
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor:
              AlwaysStoppedAnimation<Color>(theme.colorScheme.onSurfaceVariant),
        ),
      );
    case ToolProgressStatus.completed:
      return Icon(
        Icons.check,
        size: 16,
        color: theme.colorScheme.primary,
      );
    case ToolProgressStatus.failed:
      return Icon(
        Icons.close,
        size: 16,
        color: theme.colorScheme.error,
      );
  }
}

String _statusLabel(AppLocalizations l10n, ToolProgressStatus status) {
  switch (status) {
    case ToolProgressStatus.pending:
      return l10n.toolCallStatusPending;
    case ToolProgressStatus.running:
      return l10n.toolCallStatusExecuting;
    case ToolProgressStatus.completed:
      return l10n.toolCallStatusCompleted;
    case ToolProgressStatus.failed:
      return l10n.toolCallStatusError;
  }
}

/// 打开工具调用过程抽屉。
///
/// 消息里的折叠行和 AI 回复下方的「查看过程」按钮走的是同一个入口。
Future<void> showToolProgressSheet(
  BuildContext context,
  ValueListenable<ToolProgressSnapshot> snapshot,
) {
  // 抽屉一开，输入框的焦点被让给抽屉、键盘收起；抽屉 pop 时 Flutter 会把
  // 焦点还回去，键盘二次弹出，输入框跟着从底部窜上来一次。开之前主动清掉
  // 焦点，pop 时就没有可恢复的目标。
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (sheetContext) => ValueListenableBuilder<ToolProgressSnapshot>(
      valueListenable: snapshot,
      builder: (context, data, _) => _ToolProgressSheetBody(data: data),
    ),
  );
}

class _ToolProgressSheetBody extends StatelessWidget {
  final ToolProgressSnapshot data;

  const _ToolProgressSheetBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final thinking = data.thinkingText?.trim();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (data.inProgress)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // 抽屉是一条时间线：动手前想的 → 查了什么 → 查完又想的。
              // 思考和工具共用同一条竖线和同一个左边距，读下来是一串顺序发生
              // 的事，而不是"一坨思考"外加"一列工具"两块拼在一起。
              if (thinking != null && thinking.isNotEmpty)
                _ProcessThinkingBlock(
                  text: thinking,
                  // 只思考、没调工具的那轮，抽屉标题本身就是「思考」，块上再挂
                  // 一个同名小标题就是把同一个词说两遍。有工具项时才需要它，
                  // 那时候「思考」是用来和工具名区分的。
                  showLabel: data.items.isNotEmpty,
                ),
              for (final item in data.items) ...[
                _ToolProgressDetailItem(item: item, l10n: l10n),
                if (item.thinkingText?.trim().isNotEmpty == true)
                  _ProcessThinkingBlock(text: item.thinkingText!.trim()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 过程里的一段思考。
///
/// 带标题的一段引文，不是正文：思考是模型的草稿，字号比工具名小一档、颜色
/// 退到 onSurfaceVariant，和上下的工具项共用左侧那条竖线。
class _ProcessThinkingBlock extends StatelessWidget {
  final String text;

  /// 挂不挂「思考」小标题。抽屉标题已经是「思考」时挂上就是重复。
  final bool showLabel;

  const _ProcessThinkingBlock({required this.text, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 1,
            margin: const EdgeInsets.only(right: 16, left: 7),
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showLabel)
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16, color: muted),
                        const SizedBox(width: 8),
                        Text(
                          l10n.thinking,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  Padding(
                    padding: EdgeInsets.only(top: showLabel ? 6 : 0, left: 24),
                    child: SelectableText(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolProgressDetailItem extends StatelessWidget {
  final ToolProgressItem item;
  final AppLocalizations l10n;

  const _ToolProgressDetailItem({required this.item, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.5,
    );
    final narration = item.narrationText?.trim();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 1,
            margin: const EdgeInsets.only(right: 16, left: 7),
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Tooltip(
                        message: _statusLabel(l10n, item.status),
                        child: _statusIcon(context, item.status),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.toolName,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: item.status == ToolProgressStatus.failed
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.description?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 24),
                      child: Text(item.description!, style: detailStyle),
                    ),
                  // 抽屉里空间管够，结果不再截断到 5 行
                  if (item.result?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 24),
                      child: Text(item.result!, style: detailStyle),
                    ),
                  if (narration != null && narration.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(narration, style: detailStyle),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 工具调用折叠行。
///
/// 折叠态是一行轻填充的元数据，详情走底部抽屉——工具调用不是内容，
/// 它不该在正文旁边立一块比回答本身还重的卡片，也不该把三层填充容器
/// 直接展开在对话流里。
class ToolProgressPanel extends StatefulWidget {
  /// 面板标题
  final String title;

  /// 工具调用列表
  final List<ToolProgressItem> items;

  /// 是否正在执行中
  final bool inProgress;

  /// 完成时的图标（默认 Icons.check_circle）
  final IconData? doneIcon;

  /// 可选的强调色（用于图标和指示器）
  final Color? accentColor;

  /// 工具调用前的简短思考说明
  final String? thinkingText;

  const ToolProgressPanel({
    super.key,
    required this.title,
    required this.items,
    this.inProgress = false,
    this.doneIcon,
    this.accentColor,
    this.thinkingText,
  });

  @override
  State<ToolProgressPanel> createState() => _ToolProgressPanelState();
}

class _ToolProgressPanelState extends State<ToolProgressPanel> {
  /// 抽屉的数据源。标题只有 [_getDisplayTitle] 一个出处，而它要 context；
  /// 这里先拿原始标题占位，`didChangeDependencies` 会在任何一次 build 之前
  /// （抽屉更是要等用户点开）同步成真正的标题。
  late final ValueNotifier<ToolProgressSnapshot> _snapshot =
      ValueNotifier(_snapshotWith(widget.title));

  ToolProgressSnapshot _snapshotWith(String title) => ToolProgressSnapshot(
        title: title,
        items: widget.items,
        inProgress: widget.inProgress,
        thinkingText: widget.thinkingText,
      );

  /// 抽屉开着的时候 Agent 还在跑，快照要跟着走。
  ///
  /// 推到帧后再发通知：抽屉是另一条路由上的 ValueListenableBuilder，在本
  /// widget 的 build 阶段直接改值等于在 build 里把别人标脏。
  void _syncSnapshot() {
    final next = _snapshotWith(_getDisplayTitle(context));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _snapshot.value = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSnapshot();
  }

  @override
  void didUpdateWidget(covariant ToolProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSnapshot();
  }

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  /// 当前正在跑的那枚工具，没有就是 null。
  ///
  /// 「没有工具在跑」和「最后一枚工具」是两回事：模型查完东西常常再想一轮，
  /// 那段时间一枚工具都没在跑。把最后那枚顶上来，界面就会一直说"正在搜索
  /// 笔记"，而它早就搜完了。
  ToolProgressItem? get _runningItem {
    for (var i = widget.items.length - 1; i >= 0; i--) {
      if (widget.items[i].status == ToolProgressStatus.running) {
        return widget.items[i];
      }
    }
    return null;
  }

  String _getDisplayTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.inProgress) {
      final activeTitle = _runningItem?.toolName.trim() ?? '';
      if (activeTitle.isNotEmpty) return activeTitle;
      // 还在进行中却没有工具在跑：模型在想——可能是开口之前，也可能是工具
      // 跑完之后又想了一轮。两种都该说"正在思考"。
      return l10n.aiThinking;
    }
    if (widget.items.isEmpty) {
      // 这一轮只有思考没有工具。折叠态标题是个名词标签，不是按钮文案：
      // showThinking（"查看思考过程"）是祈使句，放在这里读起来像用户在对
      // 自己下指令；executedNOperations(0)（"执行了 0 个操作"）则是在报
      // 一件没发生的事。
      return l10n.thinking;
    }
    return l10n.executedNOperations(widget.items.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _getDisplayTitle(context);
    final shape = BorderRadius.circular(
      AppShapeTokens.of(context).buttonRadius,
    );

    // 底色和整宽都撤掉：工具调用是过程不是内容，它在对话流里应该是一行
    // 顺着正文左边缘走的状态文字，而不是一块和回答抢注意力的卡片。
    final foreground = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.85,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => showToolProgressSheet(context, _snapshot),
        borderRadius: shape,
        child: Padding(
          // 左边不留内边距，让图标和上下文的正文起始位置对齐
          padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Center(
                  child: widget.inProgress
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(foreground),
                          ),
                        )
                      : Icon(
                          // 只思考没调工具的那轮不打勾：勾是"做完了几件事"的
                          // 收条，而这一轮什么都没做，只是想了想。
                          widget.doneIcon ??
                              (widget.items.isEmpty
                                  ? Icons.lightbulb_outline
                                  : Icons.check),
                          size: 15,
                          color: foreground,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    title,
                    // 执行中标题会随当前工具变化，key 要跟着文案走，
                    // 否则中途换名字是硬切、只有最后完成那一下有动画
                    key: ValueKey(title),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: foreground.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
