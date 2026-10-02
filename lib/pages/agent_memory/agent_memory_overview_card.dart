import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/agent_memory.dart';
import '../../services/settings_service.dart';
import '../../theme/theme_style.dart';

/// 记忆系统概览统计卡片。
///
/// 展示 Thoughter 对当前用户的记忆统计概貌：
/// - 称呼与画像统计摘要
class AgentMemoryOverviewCard extends StatelessWidget {
  const AgentMemoryOverviewCard({
    required this.activeProfiles,
    required this.activeSlices,
    required this.factCount,
    super.key,
  });

  final List<AgentMemoryProfileEntry> activeProfiles;
  final List<AgentMemoryRecentSlice> activeSlices;
  final int factCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final colorScheme = theme.colorScheme;
    final settingsService = context.watch<SettingsService>();

    final nickname = settingsService.userNickname.trim();
    final hasNickname = nickname.isNotEmpty;

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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
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
                mainAxisSize: MainAxisSize.min,
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
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(
                                shapeTokens.buttonRadius,
                              ),
                            ),
                            child: Text(
                              nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
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
          ],
        ),
      ),
    );
  }
}
