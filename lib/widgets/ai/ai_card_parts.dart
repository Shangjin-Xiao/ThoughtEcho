// AI 结果卡片共享部件：让 NoteProposalCard 与 SmartResultCard
// 保持同一副骨架（卡头徽章、来源行、标签胶囊、限高内容、元数据开关）。

import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/note_category.dart';
import '../../utils/string_utils.dart';
import '../quote_card_helpers.dart';

/// 统一的卡片外壳：圆角、描边与底色两张卡保持一致。
class AiCardShell extends StatelessWidget {
  const AiCardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 卡头：动作徽章（✚新建 / ✎修改）+ 标题，可追加《目标笔记标题》。
class AiCardHeader extends StatelessWidget {
  const AiCardHeader({
    super.key,
    required this.isCreate,
    required this.title,
    this.targetNoteTitle,
    this.showBadge = true,
  });

  final bool isCreate;
  final String title;
  final String? targetNoteTitle;

  /// 分析类等无动作卡片传 false，只显示标题。
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final target = targetNoteTitle?.trim();
    final displayTitle =
        target != null && target.isNotEmpty ? '$title《$target》' : title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          if (showBadge) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCreate ? Icons.add : Icons.edit_outlined,
                    size: 13,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isCreate ? l10n.aiCardBadgeCreate : l10n.aiCardBadgeEdit,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              displayTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 来源行：——作者《出处》，与笔记列表同一格式（StringUtils.formatSource）。
class AiCardSourceLine extends StatelessWidget {
  const AiCardSourceLine({super.key, this.author, this.source});

  final String? author;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final text = StringUtils.formatSource(
      author?.trim().isEmpty == true ? null : author?.trim(),
      source?.trim().isEmpty == true ? null : source?.trim(),
    );
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 标签胶囊行：复用笔记列表同款 [QuoteTagChip]，保证视觉一致。
class AiCardTagList extends StatelessWidget {
  const AiCardTagList({super.key, required this.tags});

  final List<NoteCategory> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          QuoteTagChip(
            tag: tag,
            secondaryTextColor: theme.colorScheme.onSurfaceVariant,
            baseContentColor: theme.colorScheme.onSurface,
          ),
      ],
    );
  }
}

/// 内容限高容器：折叠 220 / 展开 520，与重设计稿一致。
/// 只有内容在折叠高度下真的溢出时才显示展开/收起按钮。
class AiCardExpandableContent extends StatefulWidget {
  const AiCardExpandableContent({super.key, required this.child});

  final Widget child;

  @override
  State<AiCardExpandableContent> createState() =>
      _AiCardExpandableContentState();
}

class _AiCardExpandableContentState extends State<AiCardExpandableContent> {
  static const double _collapsedMaxHeight = 220;
  static const double _expandedMaxHeight = 520;

  final ScrollController _scrollController = ScrollController();
  bool _expanded = false;
  bool _overflows = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 折叠态下测量是否溢出：maxScrollExtent > 0 说明内容被截断。
  /// 展开态不测量（能展开就说明折叠时溢出过），保证收起按钮不会消失。
  void _scheduleOverflowCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _expanded || !_scrollController.hasClients) return;
      final overflows = _scrollController.position.maxScrollExtent > 0.5;
      if (overflows != _overflows) {
        setState(() => _overflows = overflows);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _scheduleOverflowCheck();
    final showToggle = _expanded || _overflows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: _expanded ? _expandedMaxHeight : _collapsedMaxHeight,
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: showToggle
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: widget.child,
          ),
        ),
        if (showToggle)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? l10n.noteProposalCollapse : l10n.noteProposalExpand,
              ),
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

/// 位置/天气元数据开关：AddNoteDialog 同款 FilterChip 样式。
class AiMetaChip extends StatelessWidget {
  const AiMetaChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 18,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      selected: selected,
      onSelected: enabled && onTap != null ? (_) => onTap!() : null,
      selectedColor: theme.colorScheme.primaryContainer,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 快编入口：ActionChip，点击后由页面弹出快速编辑对话框。
class AiQuickEditChip extends StatelessWidget {
  const AiQuickEditChip({super.key, required this.enabled, this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.aiCardQuickEditTooltip,
      child: ActionChip(
        avatar: const Icon(Icons.edit_outlined, size: 18),
        label: Text(l10n.aiCardQuickEdit),
        onPressed: enabled ? onTap : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 保存完成后的出口：✓已保存 · 查看笔记。
class AiCardSavedViewButton extends StatelessWidget {
  const AiCardSavedViewButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.check_circle_outline, size: 18),
      label: Text(l10n.aiCardSavedViewNote),
    );
  }
}
