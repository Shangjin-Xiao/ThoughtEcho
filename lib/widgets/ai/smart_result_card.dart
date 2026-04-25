import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../gen_l10n/app_localizations.dart';

class SmartResultCard extends StatefulWidget {
  final String title;
  final String content;
  final void Function(bool includeLocation, bool includeWeather)? onOpenInEditor;
  final void Function(bool includeLocation, bool includeWeather)? onSaveDirectly;
  final String editorSource;
  final bool initialIncludeLocation;
  final bool initialIncludeWeather;

  const SmartResultCard({
    super.key,
    required this.title,
    required this.content,
    this.onOpenInEditor,
    this.onSaveDirectly,
    this.editorSource = 'fullscreen',
    this.initialIncludeLocation = false,
    this.initialIncludeWeather = false,
  });

  @override
  State<SmartResultCard> createState() => _SmartResultCardState();
}

class _SmartResultCardState extends State<SmartResultCard> {
  late bool _includeLocation;
  late bool _includeWeather;

  @override
  void initState() {
    super.initState();
    _includeLocation = widget.initialIncludeLocation;
    _includeWeather = widget.initialIncludeWeather;
  }

  @override
  void didUpdateWidget(SmartResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIncludeLocation != widget.initialIncludeLocation) {
      _includeLocation = widget.initialIncludeLocation;
    }
    if (oldWidget.initialIncludeWeather != widget.initialIncludeWeather) {
      _includeWeather = widget.initialIncludeWeather;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final isNewNote = widget.editorSource == 'new_note' || widget.editorSource == 'addnote_dialog' || widget.editorSource == 'fullscreen';
    final showSaveDirectly = widget.onSaveDirectly != null;

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
                  widget.title,
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
              data: widget.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          if (isNewNote)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(l10n.toggleAddLocation),
                    selected: _includeLocation,
                    onSelected: (value) {
                      setState(() {
                        _includeLocation = value;
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.toggleAddWeather),
                    selected: _includeWeather,
                    onSelected: (value) {
                      setState(() {
                        _includeWeather = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          if (isNewNote) const SizedBox(height: 8),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (widget.onOpenInEditor != null)
                  TextButton.icon(
                    onPressed: () =>
                        widget.onOpenInEditor?.call(_includeLocation, _includeWeather),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(l10n.openInEditor),
                  ),
                if (showSaveDirectly)
                  FilledButton.icon(
                    onPressed: () =>
                        widget.onSaveDirectly?.call(_includeLocation, _includeWeather),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(l10n.saveDirectly),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}