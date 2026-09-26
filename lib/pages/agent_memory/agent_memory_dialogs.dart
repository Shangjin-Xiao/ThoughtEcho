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
}

/// 弹出添加画像特质对话框。
Future<bool> showAddMemoryDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final shapeTokens = AppShapeTokens.of(context);
  final controller = TextEditingController();
  var selectedKind = AgentMemoryKind.preference;

  final result = await showDialog<({AgentMemoryKind kind, String directive})>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(shapeTokens.dialogRadius),
            ),
            title: Text(l10n.agentMemoryAddTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<AgentMemoryKind>(
                  initialValue: selectedKind,
                  decoration: InputDecoration(
                    labelText: l10n.agentMemoryAddKind,
                    border: const OutlineInputBorder(),
                  ),
                  items: AgentMemoryKind.values.map((kind) {
                    return DropdownMenuItem(
                      value: kind,
                      child: Text(_resolveKindName(kind, l10n)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedKind = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLength: AgentMemoryService.directiveMaxChars,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.agentMemoryAddDirective,
                    hintText: l10n.agentMemoryAddHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
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
                    Navigator.of(dialogContext).pop((
                      kind: selectedKind,
                      directive: text,
                    ));
                  }
                },
                child: Text(l10n.save),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == null) return false;

  if (!context.mounted) return false;
  final memoryService = context.read<AgentMemoryService>();
  await memoryService.rememberProfile(
    kind: result.kind,
    directive: result.directive,
    source: 'user_add',
  );

  if (!context.mounted) return true;
  AppSnackBar.success(context, l10n.agentMemoryAddSuccess);
  return true;
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

String _resolveKindName(AgentMemoryKind kind, AppLocalizations l10n) {
  return switch (kind) {
    AgentMemoryKind.identity => l10n.agentMemoryKindIdentity,
    AgentMemoryKind.preference => l10n.agentMemoryKindPreference,
    AgentMemoryKind.style => l10n.agentMemoryKindStyle,
    AgentMemoryKind.feedback => l10n.agentMemoryKindFeedback,
    AgentMemoryKind.taste => l10n.agentMemoryKindTaste,
    AgentMemoryKind.voice => l10n.agentMemoryKindVoice,
  };
}
