import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/agent_memory.dart';
import '../../theme/app_semantic_colors.dart';
import '../../theme/theme_style.dart';
import 'agent_memory_evidence_sheet.dart';

/// 画像层条目卡片。
class ProfileEntryCard extends StatelessWidget {
  const ProfileEntryCard({
    required this.entry,
    required this.onEdit,
    required this.onForget,
    super.key,
  });

  final AgentMemoryProfileEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final colorScheme = theme.colorScheme;

    final (kindIcon, kindLabel) = _resolveKindInfo(entry.kind, l10n);
    final sourceLabel = _resolveSourceLabel(entry.source, l10n);

    final cardBorder = shapeTokens.borderWidth > 0
        ? BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: shapeTokens.borderWidth,
          )
        : BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        side: cardBorder,
      ),
      color: entry.isActive
          ? colorScheme.surfaceContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        kindIcon,
                        size: 14,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        kindLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: entry.isActive
                        ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                  ),
                  child: Text(
                    entry.isActive
                        ? l10n.agentMemoryStatusActive
                        : l10n.agentMemoryStatusSuperseded,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: entry.isActive
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.outline,
                    ),
                  ),
                ),
                const Spacer(),
                if (entry.isActive)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: l10n.agentMemoryEditDirectiveTitle,
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: l10n.agentMemoryForgetAction,
                  onPressed: onForget,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              entry.directive,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: entry.isActive
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            if (entry.sourceNoteIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
                onTap: () => showAgentMemoryEvidenceSheet(
                  context,
                  noteIds: entry.sourceNoteIds,
                  traitDirective: entry.directive,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 14,
                        color: colorScheme.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.agentMemoryEvidenceTitle(
                          entry.sourceNoteIds.length,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: colorScheme.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _formatDate(entry.observedAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
                if (sourceLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '·  $sourceLabel',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  (IconData, String) _resolveKindInfo(
    AgentMemoryKind kind,
    AppLocalizations l10n,
  ) {
    return switch (kind) {
      AgentMemoryKind.identity => (
          Icons.badge_outlined,
          l10n.agentMemoryKindIdentity
        ),
      AgentMemoryKind.preference => (
          Icons.favorite_outline,
          l10n.agentMemoryKindPreference
        ),
      AgentMemoryKind.style => (
          Icons.format_paint_outlined,
          l10n.agentMemoryKindStyle
        ),
      AgentMemoryKind.feedback => (
          Icons.rate_review_outlined,
          l10n.agentMemoryKindFeedback
        ),
      AgentMemoryKind.taste => (
          Icons.auto_stories_outlined,
          l10n.agentMemoryKindTaste
        ),
      AgentMemoryKind.voice => (
          Icons.record_voice_over_outlined,
          l10n.agentMemoryKindVoice
        ),
    };
  }

  String? _resolveSourceLabel(String? source, AppLocalizations l10n) {
    if (source == null || source.isEmpty) return null;
    if (source.contains('dreaming')) {
      return l10n.agentMemorySourceDreaming;
    }
    if (source.contains('thoughter') || source.contains('chat')) {
      return l10n.agentMemorySourceThoughter;
    }
    if (source.contains('user')) {
      return l10n.agentMemorySourceUser;
    }
    return source;
  }
}

/// 近况切片卡片。
class RecentSliceCard extends StatelessWidget {
  const RecentSliceCard({
    required this.slice,
    required this.onForget,
    super.key,
  });

  final AgentMemoryRecentSlice slice;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final semanticColors = AppSemanticColors.of(context);
    final colorScheme = theme.colorScheme;

    final now = DateTime.now();
    final remainingDays = slice.expiresAt.difference(now).inDays;
    final isExpired = slice.isExpiredAt(now);

    final expiryText = isExpired
        ? l10n.agentMemoryPulseExpiresToday
        : (remainingDays <= 0
            ? l10n.agentMemoryPulseExpiresToday
            : l10n.agentMemoryPulseExpiresIn(remainingDays));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        side: BorderSide(
          color: colorScheme.tertiary.withValues(alpha: 0.3),
          width: shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1,
        ),
      ),
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.hourglass_bottom_outlined,
                        size: 14,
                        color: colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.agentMemoryTabPulse,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: remainingDays <= 2
                        ? semanticColors.warning.withValues(alpha: 0.2)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                  ),
                  child: Text(
                    expiryText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: remainingDays <= 2
                          ? semanticColors.warning
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: l10n.agentMemoryForgetAction,
                  onPressed: onForget,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              slice.content,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.agentMemoryPulseTtlNotice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (slice.sourceNoteIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
                onTap: () => showAgentMemoryEvidenceSheet(
                  context,
                  noteIds: slice.sourceNoteIds,
                  traitDirective: slice.content,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 14,
                        color: colorScheme.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.agentMemoryEvidenceTitle(
                          slice.sourceNoteIds.length,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: colorScheme.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 事实层条目卡片。
class FactCard extends StatelessWidget {
  const FactCard({
    required this.fact,
    required this.onForget,
    super.key,
  });

  final AgentMemoryFact fact;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final colorScheme = theme.colorScheme;

    final category = fact.category?.trim();
    final hasCategory = category != null && category.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1,
        ),
      ),
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        colorScheme.secondaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_border_outlined,
                        size: 14,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasCategory ? category : l10n.agentMemoryTabFacts,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      shapeTokens.buttonRadius,
                    ),
                  ),
                  child: Text(
                    l10n.agentMemoryFactImportance(fact.importance),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: l10n.agentMemoryForgetAction,
                  onPressed: onForget,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              fact.content,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _formatDate(fact.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
                if (fact.recallCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '·  ${l10n.agentMemoryFactRecalledTimes(fact.recallCount)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
