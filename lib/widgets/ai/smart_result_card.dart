import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../gen_l10n/app_localizations.dart';

class SmartResultCard extends StatefulWidget {
  final String title;
  final String content;
  final String? author;
  final String? source;
  final List<String> tagNames;
  final String? locationPreview;
  final String? weatherPreview;
  final void Function(bool includeLocation, bool includeWeather)?
      onOpenInEditor;
  final void Function(bool includeLocation, bool includeWeather)?
      onSaveDirectly;
  final String editorSource;
  final bool initialIncludeLocation;
  final bool initialIncludeWeather;

  const SmartResultCard({
    super.key,
    required this.title,
    required this.content,
    this.author,
    this.source,
    this.tagNames = const [],
    this.locationPreview,
    this.weatherPreview,
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

    final isNewNote = widget.editorSource == 'new_note' ||
        widget.editorSource == 'addnote_dialog' ||
        widget.editorSource == 'fullscreen';
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
          // 元数据预览：作者、出处、标签、位置、天气
          if (_hasMetadataPreview)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.author != null && widget.author!.isNotEmpty)
                    _MetaChip(
                      icon: Icons.person_outline,
                      label: widget.author!,
                    ),
                  if (widget.source != null && widget.source!.isNotEmpty)
                    _MetaChip(
                      icon: Icons.menu_book_outlined,
                      label: widget.source!,
                    ),
                  ...widget.tagNames.map(
                    (name) => _MetaChip(
                      icon: Icons.local_offer_outlined,
                      label: name,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  if (_includeLocation && widget.locationPreview != null)
                    _MetaChip(
                      icon: Icons.location_on_outlined,
                      label: widget.locationPreview!,
                    ),
                  if (_includeWeather && widget.weatherPreview != null)
                    _MetaChip(
                      icon: Icons.wb_sunny_outlined,
                      label: widget.weatherPreview!,
                    ),
                ],
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
                    onPressed: () => widget.onOpenInEditor
                        ?.call(_includeLocation, _includeWeather),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(l10n.openInEditor),
                  ),
                if (showSaveDirectly)
                  FilledButton.icon(
                    onPressed: () => widget.onSaveDirectly
                        ?.call(_includeLocation, _includeWeather),
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

  bool get _hasMetadataPreview {
    return (widget.author != null && widget.author!.isNotEmpty) ||
        (widget.source != null && widget.source!.isNotEmpty) ||
        widget.tagNames.isNotEmpty ||
        (_includeLocation && widget.locationPreview != null) ||
        (_includeWeather && widget.weatherPreview != null);
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(
        icon,
        size: 14,
        color: foregroundColor ?? theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foregroundColor ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: backgroundColor ??
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
