import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import '../../theme/theme_style.dart';

/// 首次进入 Thoughter 时说明「它会记住你」。
///
/// 记忆默认开启，而且会影响每日提示和洞察——默认开启的、跨会话留存的东西必须
/// 先告知，所以这条提示只在用户实际打开 Thoughter 时出现一次，而不是塞进设置页
/// 等人自己发现。这里同时给了当场关掉的出口。
Future<void> showAgentMemoryNoticeDialog(BuildContext context) async {
  final settingsService = context.read<SettingsService>();
  // 先落标记再弹窗：用户直接划走也算看过，不要下次再拦一遍。
  await settingsService.setAgentMemoryNoticeShown(true);
  if (!context.mounted) {
    return;
  }

  final disable = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppShapeTokens.of(dialogContext).dialogRadius,
          ),
        ),
        icon: const Icon(Icons.psychology_outlined),
        title: Text(l10n.agentMemoryNoticeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.agentMemoryNoticeBody,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.agentMemoryNoticeHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.agentMemoryNoticeDisable),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.agentMemoryNoticeGotIt),
          ),
        ],
      );
    },
  );

  if (disable == true) {
    await settingsService.setAgentMemoryEnabled(false);
  }
}
