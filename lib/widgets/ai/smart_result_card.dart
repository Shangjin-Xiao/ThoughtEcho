import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/note_category.dart';
import '../../models/quote_model.dart';
import '../quote_content_widget.dart';
import 'ai_card_parts.dart';

/// 快编草稿：卡片与页面之间传递的可编辑字段。
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

/// 润色/续写/新建等 AI 工作流结果卡片。
/// 骨架与 NoteProposalCard 统一：卡头徽章 → 限高内容 → 来源/标签 →
/// 元数据开关与快编 → 底部操作，保存后变为「✓已保存 · 查看笔记」。
class SmartResultCard extends StatefulWidget {
  final String title;
  final String content;
  final String? author;
  final String? source;
  final List<String> tagNames;
  final List<NoteCategory> tags;
  final String? locationPreview;
  final String? weatherPreview;

  /// 'create' / 'append' / 'replace'，决定卡头动作徽章；为空时不显示徽章。
  final String? action;

  /// 追加/替换的目标笔记标题，展示在卡头《》中。
  final String? targetNoteTitle;

  /// 富文本 Quill delta ops；提供时内容区用 Quill 真实渲染，否则按 Markdown 展示。
  final List<Map<String, dynamic>>? previewDeltaOps;

  final void Function(bool includeLocation, bool includeWeather)?
      onOpenInEditor;
  final void Function(bool includeLocation, bool includeWeather)?
      onSaveDirectly;

  /// 打开编辑器。返回编辑器内保存成功的笔记 ID（未保存时返回 null），
  /// 用于回写采纳状态，避免重复采纳产生重复笔记。
  final Future<String?> Function(SmartResultDraft draft)? onOpenDraftInEditor;
  final Future<String?> Function(SmartResultDraft draft)? onSaveDraftDirectly;
  final void Function(String noteId)? onSavedNoteId;

  /// 快编入口：页面弹出快速编辑对话框，返回修改后的草稿（取消返回 null），
  /// 并负责把改动写回 metaJson 持久化。
  final Future<SmartResultDraft?> Function(SmartResultDraft current)?
      onQuickEdit;

  /// 保存完成后「查看笔记」出口。
  final void Function(String noteId)? onViewNote;

  final bool initialIncludeLocation;
  final bool initialIncludeWeather;
  final String? initialSavedNoteId;
  final bool readOnly;

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
    this.action,
    this.targetNoteTitle,
    this.previewDeltaOps,
    this.onOpenInEditor,
    this.onSaveDirectly,
    this.onOpenDraftInEditor,
    this.onSaveDraftDirectly,
    this.onSavedNoteId,
    this.onQuickEdit,
    this.onViewNote,
    this.initialIncludeLocation = false,
    this.initialIncludeWeather = false,
    this.initialSavedNoteId,
    this.readOnly = false,
  });

  @override
  State<SmartResultCard> createState() => _SmartResultCardState();
}

class _SmartResultCardState extends State<SmartResultCard> {
  late bool _includeLocation;
  late bool _includeWeather;
  bool _isSaving = false;
  String? _savedNoteId;
  bool _saveFailed = false;

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
    final canChangeMetadata = !widget.readOnly &&
        !isSaved &&
        !_isSaving &&
        (showSaveDirectly ||
            widget.onOpenInEditor != null ||
            widget.onOpenDraftInEditor != null);
    final displayTags = widget.tags.isNotEmpty
        ? widget.tags
        : widget.tagNames
            .map((name) => NoteCategory(id: name, name: name))
            .toList();
    final hasSource = (widget.author?.trim().isNotEmpty ?? false) ||
        (widget.source?.trim().isNotEmpty ?? false);

    return AiCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AiCardHeader(
            isCreate: widget.action == 'create',
            showBadge: widget.action != null,
            title: widget.title,
            targetNoteTitle: widget.targetNoteTitle,
          ),
          const SizedBox(height: 8),
          AiCardExpandableContent(child: _buildContent()),
          if (hasSource || displayTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasSource) ...[
                    AiCardSourceLine(
                      author: widget.author,
                      source: widget.source,
                    ),
                    if (displayTags.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (displayTags.isNotEmpty) AiCardTagList(tags: displayTags),
                ],
              ),
            ),
          if (_saveFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.aiCardSaveFailedGeneric,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (widget.readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.noteProposalLegacyReadOnly,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AiMetaChip(
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
                AiMetaChip(
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
                if (widget.onQuickEdit != null && !widget.readOnly)
                  AiQuickEditChip(
                    enabled: canChangeMetadata,
                    onTap: canChangeMetadata ? _handleQuickEdit : null,
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
                if (isSaved)
                  AiCardSavedViewButton(
                    onPressed: widget.onViewNote != null
                        ? () => widget.onViewNote!(_savedNoteId!)
                        : null,
                  )
                else ...[
                  if (widget.onOpenInEditor != null ||
                      widget.onOpenDraftInEditor != null)
                    TextButton.icon(
                      onPressed: _isSaving || widget.readOnly
                          ? null
                          : _handleOpenInEditor,
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: Text(l10n.openInEditor),
                    ),
                  if (showSaveDirectly)
                    FilledButton.icon(
                      onPressed: (_isSaving || widget.readOnly)
                          ? null
                          : _handleSaveDirectly,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(l10n.saveDirectly),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final ops = widget.previewDeltaOps;
    if (ops != null) {
      return QuoteContent(
        quote: Quote(
          id: 'smart-result-${widget.title}',
          content: widget.content,
          date: DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
          editSource: 'fullscreen',
          deltaContent: jsonEncode(ops),
        ),
        showFullContent: true,
      );
    }
    return MarkdownBody(
      data: widget.content,
      selectable: true,
      onTapLink: (text, href, title) async {
        if (href == null || href.isEmpty) return;
        try {
          final uri = Uri.tryParse(href);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (_) {}
      },
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

  Future<void> _handleQuickEdit() async {
    final updated = await widget.onQuickEdit!(_buildDraft());
    // 页面负责把改动写回 metaJson 并触发重建；这里只同步勾选状态
    if (updated == null || !mounted) return;
    setState(() {
      _includeLocation = updated.includeLocation;
      _includeWeather = updated.includeWeather;
    });
  }

  Future<void> _handleOpenInEditor() async {
    final draft = _buildDraft();
    if (widget.onOpenDraftInEditor != null) {
      final noteId = await widget.onOpenDraftInEditor!(draft);
      if (!mounted || noteId == null || noteId.isEmpty) return;
      // 编辑器内已保存：回写采纳状态，防止重复采纳产生重复笔记
      widget.onSavedNoteId?.call(noteId);
      setState(() {
        _savedNoteId = noteId;
      });
      return;
    }
    widget.onOpenInEditor?.call(draft.includeLocation, draft.includeWeather);
  }

  Future<void> _handleSaveDirectly() async {
    setState(() {
      _isSaving = true;
      _saveFailed = false;
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
    } catch (_) {
      // 具体错误已在上游记录日志，卡片只提示可重试的通用文案
      if (!mounted) return;
      setState(() {
        _saveFailed = true;
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
