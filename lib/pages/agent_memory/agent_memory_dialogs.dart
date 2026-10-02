import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/agent_memory.dart';
import '../../services/agent_memory_service.dart';
import '../../theme/theme_style.dart';
import '../../widgets/app_snackbar.dart';

/// 弹出编辑画像指令对话框。
Future<bool> showEditDirectiveDialog(
  BuildContext context, {
  required AgentMemoryProfileEntry entry,
}) async {
  final l10n = AppLocalizations.of(context);
  final shapeTokens = AppShapeTokens.of(context);
  final controller = TextEditingController(text: entry.directive);

  final updatedDirective = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeTokens.dialogRadius),
        ),
        title: Text(l10n.agentMemoryEditDirectiveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: AgentMemoryService.directiveMaxChars,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            hintText: l10n.agentMemoryEditDirectiveHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.of(dialogContext).pop(text);
              }
            },
            child: Text(l10n.agentMemoryEditSave),
          ),
        ],
      );
    },
  );

  if (updatedDirective == null || updatedDirective == entry.directive) {
    return false;
  }

  if (!context.mounted) return false;
  final memoryService = context.read<AgentMemoryService>();
  try {
    final success = await memoryService.editProfileDirective(
      id: entry.id,
      directive: updatedDirective,
    );

    if (!context.mounted) return success;
    if (success) {
      AppSnackBar.success(context, l10n.agentMemoryEditSuccess);
    } else {
      AppSnackBar.error(context, l10n.operationFailedSimple);
    }
    return success;
  } catch (_) {
    if (context.mounted) {
      AppSnackBar.error(context, l10n.operationFailedSimple);
    }
    return false;
  }
}

/// 弹出确认遗忘对话框。
Future<bool> showForgetMemoryConfirmDialog(
  BuildContext context, {
  required String previewText,
}) async {
  final l10n = AppLocalizations.of(context);
  final shapeTokens = AppShapeTokens.of(context);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeTokens.dialogRadius),
        ),
        title: Text(l10n.agentMemoryForgetConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
              ),
              child: Text(
                previewText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.agentMemoryForgetConfirmBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.agentMemoryForgetAction),
          ),
        ],
      );
    },
  );

  return result == true;
}

/// 弹出记忆整理与压缩确认对话框。
Future<bool> showCompactConfirmDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final shapeTokens = AppShapeTokens.of(context);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeTokens.dialogRadius),
        ),
        icon: const Icon(Icons.auto_fix_high_outlined),
        title: Text(l10n.agentMemoryCompactTitle),
        content: Text(l10n.agentMemoryCompactConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      );
    },
  );

  return result == true;
}
