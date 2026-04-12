import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../gen_l10n/app_localizations.dart';

class SmartResultCard extends StatelessWidget {
  final String title;
  final String content;
  final VoidCallback onReplace;
  final VoidCallback onAppend;
  final VoidCallback? onOpenInEditor;
  final VoidCallback? onSaveDirectly;
  final String? replaceButtonText;
  final String? appendButtonText;

  const SmartResultCard({
    super.key,
    required this.title,
    required this.content,
    required this.onReplace,
    required this.onAppend,
    this.onOpenInEditor,
    this.onSaveDirectly,
    this.replaceButtonText,
    this.appendButtonText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (onOpenInEditor != null)
                  TextButton.icon(
                    onPressed: onOpenInEditor,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('打开编辑器'),
                  ),
                if (onSaveDirectly != null)
                  TextButton.icon(
                    onPressed: onSaveDirectly,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('直接保存'),
                  ),
                TextButton.icon(
                  onPressed: onAppend,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: Text(appendButtonText ?? l10n.appendToNote),
                ),
                FilledButton.icon(
                  onPressed: onReplace,
                  icon: const Icon(Icons.find_replace, size: 18),
                  label: Text(replaceButtonText ?? l10n.applyChanges),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
