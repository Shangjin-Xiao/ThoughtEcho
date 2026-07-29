part of '../ai_assistant_page.dart';

/// 快编对话框返回的编辑结果。
class _QuickEditValues {
  const _QuickEditValues({
    required this.content,
    required this.author,
    required this.source,
    required this.tagIds,
    required this.tagNames,
    required this.tagIconNames,
  });

  final String content;
  final String? author;
  final String? source;
  final List<String> tagIds;
  final List<String> tagNames;
  final List<String?> tagIconNames;
}

extension _AIAssistantPageQuickEdit on _AIAssistantPageState {
  /// 结果卡与提案卡共用的快编弹窗：内容（可选）/作者/出处/标签。
  /// 样式对齐 AddNoteDialog：输入框 + TagSelectionSection。
  Future<_QuickEditValues?> _showQuickEditDialog({
    required bool contentEditable,
    required String content,
    required String? author,
    required String? source,
    required List<String> selectedTagIds,
  }) async {
    final db = context.read<DatabaseService>();
    final categories = await db.getCategories();
    if (!mounted) return null;
    final l10n = AppLocalizations.of(context);
    final allTags = [
      for (final category in categories)
        if (category.id != DatabaseService.hiddenTagId) category,
    ];

    final contentController = TextEditingController(text: content);
    final authorController = TextEditingController(text: author ?? '');
    final sourceController = TextEditingController(text: source ?? '');
    final selected = <String>[...selectedTagIds];

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(l10n.aiCardQuickEditTooltip),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (contentEditable) ...[
                        TextField(
                          controller: contentController,
                          minLines: 3,
                          maxLines: 6,
                          decoration: InputDecoration(
                            labelText: l10n.aiCardEditContentHint,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: authorController,
                        decoration: InputDecoration(
                          labelText: l10n.author,
                          prefixIcon: const Icon(Icons.person_outline),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sourceController,
                        decoration: InputDecoration(
                          labelText: l10n.source,
                          prefixIcon: const Icon(Icons.menu_book_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TagSelectionSection(
                        tags: allTags,
                        selectedTagIds: selected,
                        onSelectionChanged: (newSelection) {
                          setDialogState(() {
                            selected
                              ..clear()
                              ..addAll(newSelection);
                          });
                        },
                        isLoading: false,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(l10n.done),
                ),
              ],
            ),
          );
        },
      );
      if (confirmed != true) return null;

      final selectedTags = [
        for (final tag in allTags)
          if (selected.contains(tag.id)) tag,
      ];
      String? trimToNull(String value) =>
          value.trim().isEmpty ? null : value.trim();
      return _QuickEditValues(
        content: contentEditable ? contentController.text.trim() : content,
        author: trimToNull(authorController.text),
        source: trimToNull(sourceController.text),
        tagIds: [for (final tag in selectedTags) tag.id],
        tagNames: [for (final tag in selectedTags) tag.name],
        tagIconNames: [for (final tag in selectedTags) tag.iconName],
      );
    } finally {
      contentController.dispose();
      authorController.dispose();
      sourceController.dispose();
    }
  }

  /// 结果卡快编：弹窗 → 写回消息 content 与 metaJson（author/source/标签）。
  Future<SmartResultDraft?> _handleSmartResultQuickEdit(
    String messageId,
    Map<String, dynamic> meta,
    SmartResultDraft current,
  ) async {
    final isRich = _opsFromRichDocument(meta['rich_document']) != null;
    final values = await _showQuickEditDialog(
      contentEditable: !isRich,
      content: current.content,
      author: current.author,
      source: current.source,
      selectedTagIds: _extractStringList(meta['tag_ids']),
    );
    if (values == null || !mounted) return null;
    _persistSmartResultQuickEdit(messageId, meta, values,
        updateContent: !isRich);
    return SmartResultDraft(
      content: values.content,
      author: values.author,
      source: values.source,
      tagNames: values.tagNames,
      includeLocation: current.includeLocation,
      includeWeather: current.includeWeather,
    );
  }

  void _persistSmartResultQuickEdit(
    String messageId,
    Map<String, dynamic> meta,
    _QuickEditValues values, {
    required bool updateContent,
  }) {
    _setState(() {
      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index == -1) return;
      final oldMessage = _messages[index];
      final updatedMeta = Map<String, dynamic>.from(meta);
      updatedMeta['author'] = values.author;
      updatedMeta['source'] = values.source;
      updatedMeta['tag_names'] = values.tagNames;
      updatedMeta['tag_ids'] = values.tagIds;
      updatedMeta['tag_icon_names'] = values.tagIconNames;
      final updatedMessage = oldMessage.copyWith(
        content: updateContent ? values.content : oldMessage.content,
        metaJson: jsonEncode(updatedMeta),
      );
      _messages[index] = updatedMessage;
      if (_currentSessionId != null) {
        unawaited(
          _chatSessionService.addMessage(_currentSessionId!, updatedMessage),
        );
      }
    });
  }

  /// 提案卡快编：弹窗 → 写回 artifact（纯文本新建可改正文，
  /// 其余只改 author/source/tag_ids，避免与 ops 应用结果不一致）。
  Future<NoteProposalQuickEdit?> _handleNoteProposalQuickEdit(
    String messageId,
    Map<String, dynamic> meta,
    NoteProposalArtifact artifact,
    NoteProposalQuickEdit current,
  ) async {
    final contentEditable = artifact.action == NoteProposalAction.create &&
        artifact.resultKind == NoteDocumentKind.plain;
    final values = await _showQuickEditDialog(
      contentEditable: contentEditable,
      content: current.content,
      author: current.author,
      source: current.source,
      selectedTagIds: current.tagIds,
    );
    if (values == null || !mounted) return null;

    _setState(() {
      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index == -1) return;
      final oldMessage = _messages[index];
      final updatedMeta = Map<String, dynamic>.from(meta);
      final artifactJson = Map<String, dynamic>.from(
        (updatedMeta['artifact'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      if (contentEditable) {
        artifactJson['content'] = values.content;
      }
      final metadata = Map<String, Object?>.from(
        (artifactJson['metadata'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const <String, Object?>{},
      );
      if (values.author == null) {
        metadata.remove('author');
      } else {
        metadata['author'] = values.author;
      }
      if (values.source == null) {
        metadata.remove('source');
      } else {
        metadata['source'] = values.source;
      }
      metadata['tag_ids'] = values.tagIds;
      metadata['tag_names'] = values.tagNames;
      artifactJson['metadata'] = metadata;
      updatedMeta['artifact'] = artifactJson;
      final updatedMessage = oldMessage.copyWith(
        metaJson: jsonEncode(updatedMeta),
      );
      _messages[index] = updatedMessage;
      if (_currentSessionId != null) {
        unawaited(
          _chatSessionService.addMessage(_currentSessionId!, updatedMessage),
        );
      }
    });

    return NoteProposalQuickEdit(
      content: values.content,
      author: values.author,
      source: values.source,
      tagIds: values.tagIds,
    );
  }

  /// 提案卡位置/天气开关变更：写回 artifact.metadata 并持久化，
  /// 让「保存」与「打开编辑器」两条路径都读到最新开关。
  void _persistNoteProposalMetadataFlags(
    String messageId,
    Map<String, dynamic> meta, {
    required bool includeLocation,
    required bool includeWeather,
  }) {
    _setState(() {
      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index == -1) return;
      final oldMessage = _messages[index];
      final updatedMeta = Map<String, dynamic>.from(meta);
      final artifactJson = Map<String, dynamic>.from(
        (updatedMeta['artifact'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      final metadata = Map<String, Object?>.from(
        (artifactJson['metadata'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const <String, Object?>{},
      );
      metadata['include_location'] = includeLocation;
      metadata['include_weather'] = includeWeather;
      artifactJson['metadata'] = metadata;
      updatedMeta['artifact'] = artifactJson;
      final updatedMessage = oldMessage.copyWith(
        metaJson: jsonEncode(updatedMeta),
      );
      _messages[index] = updatedMessage;
      if (_currentSessionId != null) {
        unawaited(
          _chatSessionService.addMessage(_currentSessionId!, updatedMessage),
        );
      }
    });
  }

  /// 提案卡的展示标签：优先 metadata 里的 tag_names，缺失时退化为 id。
  List<NoteCategory> _resolveProposalDisplayTags(
    NoteProposalArtifact artifact,
  ) {
    final metadata = artifact.metadata;
    final ids = _extractStringList(metadata['tag_ids']);
    final rawNames = metadata['tag_names'];
    final names = rawNames is List
        ? rawNames.map((item) => item.toString()).toList()
        : const <String>[];
    return [
      for (var i = 0; i < ids.length; i++)
        NoteCategory(
          id: ids[i],
          name: i < names.length && names[i].trim().isNotEmpty
              ? names[i]
              : ids[i],
        ),
    ];
  }

  /// 追加/替换的目标笔记展示标题：取绑定笔记首行前 20 字。
  String? _boundNoteTitle() {
    final content = widget.quote?.content.trim();
    if (content == null || content.isEmpty) return null;
    final firstLine = content.split('\n').first.trim();
    if (firstLine.isEmpty) return null;
    return firstLine.length <= 20
        ? firstLine
        : '${firstLine.substring(0, 20)}…';
  }

  /// 「已保存 · 查看笔记」出口：从数据库取出笔记并打开。
  Future<void> _viewSavedNote(String noteId) async {
    final db = context.read<DatabaseService>();
    final quote = await db.getQuoteById(noteId);
    if (!mounted || quote == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteFullEditorPage(
          initialContent: quote.content,
          initialQuote: quote,
        ),
      ),
    );
  }
}
