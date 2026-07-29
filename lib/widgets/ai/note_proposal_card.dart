import 'dart:convert';

import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/note_category.dart';
import '../../models/note_proposal_artifact.dart';
import '../../models/quote_model.dart';
import '../quote_content_widget.dart';
import 'ai_card_parts.dart';

/// 快编结果：页面弹窗编辑后写回 artifact（纯文本内容 + author/source/tag_ids）。
class NoteProposalQuickEdit {
  const NoteProposalQuickEdit({
    required this.content,
    required this.author,
    required this.source,
    required this.tagIds,
  });

  final String content;
  final String? author;
  final String? source;
  final List<String> tagIds;
}

/// Agent 笔记提案卡片（新建/修改）。
/// 骨架与 SmartResultCard 统一：卡头徽章 → 限高内容 → 来源/标签 →
/// 快编 → 底部操作，应用后变为「✓已保存 · 查看笔记」。
class NoteProposalCard extends StatefulWidget {
  const NoteProposalCard({
    super.key,
    required this.artifact,
    required this.onOpenInEditor,
    required this.onApply,
    this.initialCompleted = false,
    this.initialSavedNoteId,
    this.plainCreateOpensRich = false,
    this.tags = const [],
    this.locationPreview,
    this.weatherPreview,
    this.onResolveLocation,
    this.onResolveWeather,
    this.onMetadataChanged,
    this.onQuickEdit,
    this.onViewNote,
  });

  final NoteProposalArtifact artifact;
  final Future<void> Function() onOpenInEditor;

  /// 应用提案。成功返回笔记 ID（用于「查看笔记」出口）；取消或失败返回 null。
  final Future<String?> Function() onApply;

  final bool initialCompleted;

  /// 历史会话恢复出的已保存笔记 ID。
  final String? initialSavedNoteId;
  final bool plainCreateOpensRich;

  /// 展示用标签（页面按 metadata 中的 tag_ids/tag_names 解析）。
  final List<NoteCategory> tags;

  /// 位置/天气胶囊上的实际内容预览，为空时退化为「位置」「天气」通用文案。
  /// 只用已缓存的值，卡片渲染不会为此等待定位/天气请求。
  final String? locationPreview;
  final String? weatherPreview;

  /// 勾选位置/天气时才现场获取（与编辑器一致：不勾就不定位）。
  /// 返回胶囊上要显示的文本；返回 null 表示获取失败，开关回退为未勾选。
  final Future<String?> Function()? onResolveLocation;
  final Future<String?> Function()? onResolveWeather;

  /// 位置/天气勾选变化：由页面写回 artifact metadata 并持久化，
  /// 保证「保存」与「打开编辑器」两条路径读到的是同一份开关状态。
  final void Function(bool includeLocation, bool includeWeather)?
      onMetadataChanged;

  /// 快编入口：页面弹出快速编辑对话框并写回 metaJson，取消返回 null。
  final Future<NoteProposalQuickEdit?> Function(NoteProposalQuickEdit current)?
      onQuickEdit;

  /// 应用完成后「查看笔记」出口。
  final void Function(String noteId)? onViewNote;

  @override
  State<NoteProposalCard> createState() => _NoteProposalCardState();
}

class _NoteProposalCardState extends State<NoteProposalCard> {
  bool _saving = false;
  late bool _completed;
  bool _failed = false;
  String? _savedNoteId;
  late bool _includeLocation;
  late bool _includeWeather;
  // 勾选后现场获取到的位置/天气文本（优先于缓存预览显示）
  String? _resolvedLocation;
  String? _resolvedWeather;
  bool _loadingLocation = false;
  bool _loadingWeather = false;

  NoteProposalArtifact get artifact => widget.artifact;

  @override
  void initState() {
    super.initState();
    _completed = widget.initialCompleted;
    _savedNoteId = widget.initialSavedNoteId;
    _includeLocation = artifact.metadata['include_location'] == true;
    _includeWeather = artifact.metadata['include_weather'] == true;
  }

  @override
  void didUpdateWidget(NoteProposalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCompleted != widget.initialCompleted) {
      _completed = widget.initialCompleted;
    }
    if (oldWidget.initialSavedNoteId != widget.initialSavedNoteId) {
      _savedNoteId = widget.initialSavedNoteId;
    }
    if (!identical(oldWidget.artifact, widget.artifact)) {
      _includeLocation = artifact.metadata['include_location'] == true;
      _includeWeather = artifact.metadata['include_weather'] == true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isCreate = artifact.action == NoteProposalAction.create;
    final author = artifact.metadata['author']?.toString();
    final source = artifact.metadata['source']?.toString();
    final hasSource = (author?.trim().isNotEmpty ?? false) ||
        (source?.trim().isNotEmpty ?? false);
    final canEdit = !_completed && !_saving && !artifact.readOnly;
    final showQuickEdit =
        widget.onQuickEdit != null && !artifact.readOnly && !_completed;
    // 位置/天气只在新建提案上有意义（修改提案按 ops 应用，不改元数据）
    final showMetaRow = showQuickEdit || (isCreate && !artifact.readOnly);

    return AiCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AiCardHeader(
            isCreate: isCreate,
            title: artifact.proposalTitle,
          ),
          const SizedBox(height: 8),
          AiCardExpandableContent(
            child: _DocumentPreview(artifact: artifact),
          ),
          if (hasSource || widget.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasSource) ...[
                    AiCardSourceLine(author: author, source: source),
                    if (widget.tags.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (widget.tags.isNotEmpty) AiCardTagList(tags: widget.tags),
                ],
              ),
            ),
          if (artifact.modeTransition == NoteModeTransition.plainToRich)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.noteProposalPlainToRichWarning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          if (widget.plainCreateOpensRich)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.noteProposalPlainEditorPreferenceWarning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.agentErrorGeneric,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (artifact.readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.noteProposalLegacyReadOnly,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (showMetaRow)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isCreate) ...[
                    AiMetaChip(
                      icon: Icons.location_on_outlined,
                      // 预览取的是已缓存值（同步 getter，不会拖慢卡片渲染），
                      // 有就直接显示；勾选后现场获取到的值优先。
                      label: _resolvedLocation ??
                          widget.locationPreview ??
                          l10n.location,
                      selected: _includeLocation,
                      enabled: canEdit,
                      loading: _loadingLocation,
                      onTap: canEdit
                          ? () => _toggleLocation(!_includeLocation)
                          : null,
                    ),
                    AiMetaChip(
                      icon: Icons.wb_sunny_outlined,
                      label: _resolvedWeather ??
                          widget.weatherPreview ??
                          l10n.weather,
                      selected: _includeWeather,
                      enabled: canEdit,
                      loading: _loadingWeather,
                      onTap: canEdit
                          ? () => _toggleWeather(!_includeWeather)
                          : null,
                    ),
                  ],
                  if (showQuickEdit)
                    AiQuickEditChip(
                      enabled: canEdit,
                      onTap: canEdit ? _handleQuickEdit : null,
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
                if (_completed)
                  _savedNoteId != null && widget.onViewNote != null
                      ? AiCardSavedViewButton(
                          onPressed: () => widget.onViewNote!(_savedNoteId!),
                        )
                      : TextButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(l10n.noteProposalCompleted),
                        )
                else ...[
                  TextButton.icon(
                    onPressed:
                        _saving || artifact.readOnly ? null : _openInEditor,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(l10n.openInEditor),
                  ),
                  FilledButton.icon(
                    onPressed: _saving || artifact.readOnly ? null : _apply,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      isCreate ? l10n.noteProposalSave : l10n.noteProposalApply,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMetadata({bool? location, bool? weather}) {
    setState(() {
      _includeLocation = location ?? _includeLocation;
      _includeWeather = weather ?? _includeWeather;
    });
    widget.onMetadataChanged?.call(_includeLocation, _includeWeather);
  }

  /// 勾选位置：先落开关状态，再现场获取（失败则回退为未勾选）。
  Future<void> _toggleLocation(bool value) async {
    _toggleMetadata(location: value);
    if (!value) {
      setState(() => _resolvedLocation = null);
      return;
    }
    final resolver = widget.onResolveLocation;
    if (resolver == null) return;
    setState(() => _loadingLocation = true);
    String? label;
    try {
      label = await resolver();
    } catch (_) {
      label = null;
    }
    if (!mounted) return;
    setState(() {
      _loadingLocation = false;
      _resolvedLocation = label;
    });
    if (label == null) _toggleMetadata(location: false);
  }

  /// 勾选天气：同上。天气依赖定位，失败由页面提示，这里只回退开关。
  Future<void> _toggleWeather(bool value) async {
    _toggleMetadata(weather: value);
    if (!value) {
      setState(() => _resolvedWeather = null);
      return;
    }
    final resolver = widget.onResolveWeather;
    if (resolver == null) return;
    setState(() => _loadingWeather = true);
    String? label;
    try {
      label = await resolver();
    } catch (_) {
      label = null;
    }
    if (!mounted) return;
    setState(() {
      _loadingWeather = false;
      _resolvedWeather = label;
    });
    if (label == null) _toggleMetadata(weather: false);
  }

  Future<void> _handleQuickEdit() async {
    final metadata = artifact.metadata;
    final rawTagIds = metadata['tag_ids'];
    await widget.onQuickEdit!(
      NoteProposalQuickEdit(
        content: artifact.content,
        author: metadata['author']?.toString(),
        source: metadata['source']?.toString(),
        tagIds: rawTagIds is List
            ? rawTagIds.map((id) => id.toString()).toList()
            : const [],
      ),
    );
    // 页面负责把改动写回 metaJson 并触发重建，卡片无需本地覆盖
  }

  Future<void> _apply() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final noteId = await widget.onApply();
      if (mounted && noteId != null && noteId.isNotEmpty) {
        setState(() {
          _completed = true;
          _savedNoteId = noteId;
        });
      }
    } catch (_) {
      // 具体错误已在上游记录日志，卡片只提示可重试的通用文案
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openInEditor() async {
    setState(() => _failed = false);
    try {
      await widget.onOpenInEditor();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }
}

/// 提案内容预览：纯文本用 SelectableText，富文本走 QuoteContent 真实渲染。
class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({required this.artifact});

  final NoteProposalArtifact artifact;

  @override
  Widget build(BuildContext context) {
    if (artifact.resultKind == NoteDocumentKind.plain) {
      return SelectableText(artifact.content);
    }
    return QuoteContent(
      quote: Quote(
        id: 'agent-proposal-${artifact.noteId ?? artifact.proposalTitle}',
        content: artifact.content,
        date: DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        editSource: 'fullscreen',
        deltaContent: jsonEncode(artifact.documentOps),
      ),
      showFullContent: true,
    );
  }
}
