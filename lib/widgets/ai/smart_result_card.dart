import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../extensions/note_category_localization_extension.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../models/note_category.dart';
import '../../utils/icon_utils.dart';

class SmartResultDraft {
  const SmartResultDraft({
    required this.content,
    required this.author,
    required this.source,
    required this.tagNames,
    required this.includeLocation,
    required this.includeWeather,
  });

  final String content;
  final String? author;
  final String? source;
  final List<String> tagNames;
  final bool includeLocation;
  final bool includeWeather;
}

class SmartResultCard extends StatefulWidget {
  final String title;
  final String content;
  final String? author;
  final String? source;
  final List<String> tagNames;
  final List<NoteCategory> tags;
  final String? locationPreview;
  final String? weatherPreview;
  final void Function(bool includeLocation, bool includeWeather)?
      onOpenInEditor;
  final void Function(bool includeLocation, bool includeWeather)?
      onSaveDirectly;
  final Future<void> Function(SmartResultDraft draft)? onOpenDraftInEditor;
  final Future<String?> Function(SmartResultDraft draft)? onSaveDraftDirectly;
  final void Function(String noteId)? onSavedNoteId;
  final String editorSource;
  final bool initialIncludeLocation;
  final bool initialIncludeWeather;
  final String? initialSavedNoteId;

  const SmartResultCard({
    super.key,
    required this.title,
    required this.content,
    this.author,
    this.source,
    this.tagNames = const [],
    this.tags = const [],
    this.locationPreview,
    this.weatherPreview,
    this.onOpenInEditor,
    this.onSaveDirectly,
    this.onOpenDraftInEditor,
    this.onSaveDraftDirectly,
    this.onSavedNoteId,
    this.editorSource = 'fullscreen',
    this.initialIncludeLocation = false,
    this.initialIncludeWeather = false,
    this.initialSavedNoteId,
  });

  @override
  State<SmartResultCard> createState() => _SmartResultCardState();
}

class _SmartResultCardState extends State<SmartResultCard> {
  late bool _includeLocation;
  late bool _includeWeather;
  bool _isSaving = false;
  String? _savedNoteId;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _includeLocation = widget.initialIncludeLocation;
    _includeWeather = widget.initialIncludeWeather;
    _savedNoteId = widget.initialSavedNoteId;
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
    if (oldWidget.initialSavedNoteId != widget.initialSavedNoteId) {
      _savedNoteId = widget.initialSavedNoteId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final showSaveDirectly =
        widget.onSaveDirectly != null || widget.onSaveDraftDirectly != null;
    final isSaved = _savedNoteId != null && _savedNoteId!.isNotEmpty;
    final canChangeMetadata = !isSaved &&
        !_isSaving &&
        (showSaveDirectly ||
            widget.onOpenInEditor != null ||
            widget.onOpenDraftInEditor != null);
    final displayTags = widget.tags.isNotEmpty
        ? widget.tags
        : widget.tagNames
            .map((name) => NoteCategory(id: name, name: name))
            .toList();

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarkdownBody(
                  data: widget.content,
                  selectable: true,
                ),
                const SizedBox(height: 12),
                if (_hasSourceInfo) _buildSourceInfo(),
                if (_hasSourceInfo && displayTags.isNotEmpty)
                  const SizedBox(height: 8),
                if (displayTags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Icon(
                          Icons.label_outline,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in displayTags) _TagChip(tag: tag),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.saveFailed(_saveError!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MetaToggleChip(
                  icon: Icons.location_on_outlined,
                  label: widget.locationPreview ?? l10n.location,
                  selected: _includeLocation,
                  enabled: canChangeMetadata,
                  onTap: canChangeMetadata
                      ? () => _handleLocationWeatherSelection(
                            !_includeLocation,
                            true,
                          )
                      : null,
                ),
                _MetaToggleChip(
                  icon: Icons.wb_sunny_outlined,
                  label: widget.weatherPreview ?? l10n.weather,
                  selected: _includeWeather,
                  enabled: canChangeMetadata,
                  onTap: canChangeMetadata
                      ? () => _handleLocationWeatherSelection(
                            !_includeWeather,
                            false,
                          )
                      : null,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (widget.onOpenInEditor != null ||
                    widget.onOpenDraftInEditor != null)
                  TextButton.icon(
                    onPressed: _isSaving ? null : _handleOpenInEditor,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(l10n.openInEditor),
                  ),
                if (showSaveDirectly)
                  FilledButton.icon(
                    onPressed:
                        (_isSaving || isSaved) ? null : _handleSaveDirectly,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isSaved
                                ? Icons.check_circle_outline
                                : Icons.save_outlined,
                            size: 18,
                          ),
                    label: Text(isSaved ? l10n.noteSaved : l10n.saveDirectly),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasSourceInfo {
    return (widget.author?.trim().isNotEmpty ?? false) ||
        (widget.source?.trim().isNotEmpty ?? false);
  }

  Widget _buildSourceInfo() {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (widget.author?.trim().isNotEmpty ?? false)
          _InlineMetadata(
            icon: Icons.person_outline,
            label: widget.author!.trim(),
          ),
        if (widget.source?.trim().isNotEmpty ?? false)
          _InlineMetadata(
            icon: Icons.menu_book_outlined,
            label: widget.source!.trim(),
          ),
      ],
    );
  }

  void _handleLocationWeatherSelection(bool value, bool isLocation) {
    setState(() {
      if (isLocation) {
        _includeLocation = value;
      } else {
        _includeWeather = value;
      }
    });
  }

  SmartResultDraft _buildDraft() {
    return SmartResultDraft(
      content: widget.content.trim(),
      author: _trimToNull(widget.author ?? ''),
      source: _trimToNull(widget.source ?? ''),
      tagNames: widget.tags.isNotEmpty
          ? widget.tags.map((tag) => tag.name).toList()
          : widget.tagNames,
      includeLocation: _includeLocation,
      includeWeather: _includeWeather,
    );
  }

  String? _trimToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _handleOpenInEditor() async {
    final draft = _buildDraft();
    if (widget.onOpenDraftInEditor != null) {
      await widget.onOpenDraftInEditor!(draft);
      return;
    }
    widget.onOpenInEditor?.call(draft.includeLocation, draft.includeWeather);
  }

  Future<void> _handleSaveDirectly() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final draft = _buildDraft();
      final noteId = widget.onSaveDraftDirectly != null
          ? await widget.onSaveDraftDirectly!(draft)
          : null;
      if (widget.onSaveDirectly != null && widget.onSaveDraftDirectly == null) {
        widget.onSaveDirectly!(draft.includeLocation, draft.includeWeather);
      }
      if (!mounted) return;
      if (noteId != null && noteId.isNotEmpty) {
        widget.onSavedNoteId?.call(noteId);
        setState(() {
          _savedNoteId = noteId;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _InlineMetadata extends StatelessWidget {
  const _InlineMetadata({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final NoteCategory tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final iconName = tag.iconName;

    final bool hasEmoji =
        iconName != null && iconName.isNotEmpty && IconUtils.isEmoji(iconName);
    final bool hasIcon =
        iconName != null && iconName.isNotEmpty && !IconUtils.isEmoji(iconName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasEmoji) ...[
            Text(
              IconUtils.getDisplayIcon(iconName),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 4),
          ] else if (hasIcon) ...[
            Icon(
              IconUtils.getIconData(iconName),
              size: 13,
              color:
                  theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            tag.localizedName(l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 紧凑的元数据开关胶囊（位置/天气）
class _MetaToggleChip extends StatelessWidget {
  const _MetaToggleChip({
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
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final bgColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final borderColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.5)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: enabled
                    ? color
                    : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
