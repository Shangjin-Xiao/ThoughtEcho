import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/agent_memory.dart';
import '../../services/agent_memory_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_semantic_colors.dart';
import '../../theme/theme_style.dart';

/// 记忆系统概览与认知负荷卡片。
///
/// 展示 Thoughter 对当前用户的记忆全貌：
/// - 称呼与画像凝聚度
/// - 认知注入负荷计量（硬预算 24 条 / 1200 字符的实时占比）
/// - 记忆整理与压缩入口
class AgentMemoryOverviewCard extends StatelessWidget {
  const AgentMemoryOverviewCard({
    required this.activeProfiles,
    required this.activeSlices,
    required this.factCount,
    required this.onCompactTap,
    super.key,
  });

  final List<AgentMemoryProfileEntry> activeProfiles;
  final List<AgentMemoryRecentSlice> activeSlices;
  final int factCount;
  final VoidCallback onCompactTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final semanticColors = AppSemanticColors.of(context);
    final colorScheme = theme.colorScheme;
    final settingsService = context.watch<SettingsService>();

    final nickname = settingsService.userNickname.trim();
    final hasNickname = nickname.isNotEmpty;

    // 计算画像层注入字符负荷（指令字符 + 近况切片字符）
    final profileChars = activeProfiles.fold<int>(
      0,
      (sum, entry) => sum + entry.directive.length,
    );
    final sliceChars = activeSlices.fold<int>(
      0,
      (sum, slice) => sum + slice.content.length,
    );
    final totalUsedChars = profileChars + sliceChars;

    final charFraction =
        (totalUsedChars / AgentMemoryService.profileInjectionMaxChars)
            .clamp(0.0, 1.0);
    final isBudgetTight = charFraction > 0.85 ||
        activeProfiles.length >= AgentMemoryService.profileInjectionMaxEntries;

    final progressColor =
        isBudgetTight ? semanticColors.warning : colorScheme.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius:
                        BorderRadius.circular(shapeTokens.buttonRadius),
                  ),
                  child: Icon(
                    Icons.history_edu_outlined,
                    size: 22,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.agentMemoryPageTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (hasNickname) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(
                                  shapeTokens.buttonRadius,
                                ),
                              ),
                              child: Text(
                                nickname,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.agentMemoryResonanceSummary(
                          activeProfiles.length,
                          activeSlices.length,
                          factCount,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  onPressed: onCompactTap,
                  tooltip: l10n.agentMemoryCompactTitle,
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 20),
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        shapeTokens.buttonRadius,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 认知负荷条
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.speed_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.agentMemoryCognitiveLoad,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Text(
                  l10n.agentMemoryCharsCount(
                    totalUsedChars,
                    AgentMemoryService.profileInjectionMaxChars,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: progressColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
              child: LinearProgressIndicator(
                value: charFraction,
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isBudgetTight
                        ? l10n.agentMemoryBudgetNearFull
                        : l10n.agentMemoryBudgetNormal,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isBudgetTight
                          ? semanticColors.warning
                          : colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  l10n.agentMemoryEntriesCount(
                    activeProfiles.length,
                    AgentMemoryService.profileInjectionMaxEntries,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
