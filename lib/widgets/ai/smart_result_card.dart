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
  final Future<void> Function()? onEditExistingLocationWeather;
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
    this.onEditExistingLocationWeather,
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

    final isNewNote = widget.editorSource == 'new_note' ||
        widget.editorSource == 'addnote_dialog';
    final showSaveDirectly =
        widget.onSaveDirectly != null || widget.onSaveDraftDirectly != null;
    final isSaved = _savedNoteId != null && _savedNoteId!.isNotEmpty;
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
                if (displayTags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in displayTags) _TagChip(tag: tag),
                    ],
                  ),
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
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.location_on_outlined, size: 18),
                  label: Text(widget.locationPreview ?? l10n.location),
                  selected: _includeLocation,
                  onSelected: (value) =>
                      _handleLocationWeatherSelection(isNewNote, value, true),
                ),
                FilterChip(
                  avatar: const Icon(Icons.wb_sunny_outlined, size: 18),
                  label: Text(widget.weatherPreview ?? l10n.weather),
                  selected: _includeWeather,
                  onSelected: (value) =>
                      _handleLocationWeatherSelection(isNewNote, value, false),
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

  Future<void> _handleLocationWeatherSelection(
    bool isNewNote,
    bool value,
    bool isLocation,
  ) async {
    if (!isNewNote) {
      await widget.onEditExistingLocationWeather?.call();
      return;
    }
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
    final iconName = tag.iconName;
    final Widget? avatar = switch (iconName) {
      final value? when value.isNotEmpty && IconUtils.isEmoji(value) => Text(
          IconUtils.getDisplayIcon(value),
          style: const TextStyle(fontSize: 12),
        ),
      final value? when value.isNotEmpty => Icon(
          IconUtils.getIconData(value),
          size: 14,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      _ => null,
    };

    return Chip(
      avatar: avatar,
      label: Text(tag.localizedName(AppLocalizations.of(context))),
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
      ),
      backgroundColor: theme.colorScheme.primaryContainer,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
