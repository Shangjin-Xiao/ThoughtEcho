import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../gen_l10n/app_localizations.dart';

part 'smart_result_card_editing.dart';

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
  final String? locationPreview;
  final String? weatherPreview;
  final void Function(bool includeLocation, bool includeWeather)?
      onOpenInEditor;
  final void Function(bool includeLocation, bool includeWeather)?
      onSaveDirectly;
  final Future<void> Function(SmartResultDraft draft)? onOpenDraftInEditor;
  final Future<String?> Function(SmartResultDraft draft)? onSaveDraftDirectly;
  final Future<List<String>> Function()? loadAvailableTagNames;
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
    this.locationPreview,
    this.weatherPreview,
    this.onOpenInEditor,
    this.onSaveDirectly,
    this.onOpenDraftInEditor,
    this.onSaveDraftDirectly,
    this.loadAvailableTagNames,
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
  late final TextEditingController _contentController;
  late final TextEditingController _authorController;
  late final TextEditingController _sourceController;
  late final TextEditingController _tagsController;
  late bool _includeLocation;
  late bool _includeWeather;
  bool _isSaving = false;
  String? _savedNoteId;
  String? _saveError;

  void _updateDraft(VoidCallback update) => setState(update);

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.content);
    _authorController = TextEditingController(text: widget.author ?? '');
    _sourceController = TextEditingController(text: widget.source ?? '');
    _tagsController = TextEditingController(text: widget.tagNames.join(', '));
    _includeLocation = widget.initialIncludeLocation;
    _includeWeather = widget.initialIncludeWeather;
    _savedNoteId = widget.initialSavedNoteId;
  }

  @override
  void didUpdateWidget(SmartResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _contentController.text = widget.content;
    }
    if (oldWidget.author != widget.author) {
      _authorController.text = widget.author ?? '';
    }
    if (oldWidget.source != widget.source) {
      _sourceController.text = widget.source ?? '';
    }
    if (oldWidget.tagNames.join('\u001f') != widget.tagNames.join('\u001f')) {
      _tagsController.text = widget.tagNames.join(', ');
    }
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
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    _sourceController.dispose();
    _tagsController.dispose();
    super.dispose();
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
    final supportsDraftEdits = widget.onOpenDraftInEditor != null ||
        widget.onSaveDraftDirectly != null ||
        (widget.onOpenInEditor == null && widget.onSaveDirectly == null);

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MarkdownBody(
                        data: _contentController.text,
                        selectable: true,
                      ),
                    ),
                    if (supportsDraftEdits)
                      IconButton(
                        onPressed: () => _editTextValue(
                          title: l10n.content,
                          controller: _contentController,
                          maxLines: 10,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: l10n.edit,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_authorController.text.trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.person_outline,
                        label: _authorController.text.trim(),
                      ),
                    if (_sourceController.text.trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.menu_book_outlined,
                        label: _sourceController.text.trim(),
                      ),
                    for (final tag in _draftTagNames)
                      _MetaChip(
                        icon: Icons.local_offer_outlined,
                        label: tag,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                    if (supportsDraftEdits)
                      ActionChip(
                        avatar: const Icon(Icons.tune, size: 16),
                        label: Text(l10n.editMetadataShort),
                        onPressed: _editMetadata,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_hasMetadataPreview)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
                  if (isSaved)
                    _MetaChip(
                      icon: Icons.check_circle_outline,
                      label: l10n.noteSaved,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
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

  bool get _hasMetadataPreview {
    return (_includeLocation && widget.locationPreview != null) ||
        (_includeWeather && widget.weatherPreview != null) ||
        (_savedNoteId != null && _savedNoteId!.isNotEmpty);
  }

  SmartResultDraft _buildDraft() {
    return SmartResultDraft(
      content: _contentController.text.trim(),
      author: _trimToNull(_authorController.text),
      source: _trimToNull(_sourceController.text),
      tagNames: _tagsController.text
          .split(RegExp(r'[,，、]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
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
