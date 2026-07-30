part of '../ai_assistant_page.dart';

/// 快编对话框返回的编辑结果。快编只改元信息，正文一律走完整编辑器。
class _QuickEditValues {
  const _QuickEditValues({
    required this.author,
    required this.source,
    required this.tagIds,
    required this.tagNames,
    required this.tagIconNames,
  });

  final String? author;
  final String? source;
  final List<String> tagIds;
  final List<String> tagNames;
  final List<String?> tagIconNames;
}

/// 快编面板里的标签选择：直接复用新建笔记弹窗的折叠标签区
/// （[TagSelectionSection]，默认折叠、展开后是懒加载列表 + 搜索），
/// 保证两处交互一致，也不用在快编里维护第二套标签 UI。
///
/// 这里再包一层 StatefulWidget 只为一件事：选中态留在本组件内，
/// 勾标签不会把整个面板（含作者/出处输入框）一起重建。
class _QuickEditTagSection extends StatefulWidget {
  const _QuickEditTagSection({
    required this.tags,
    required this.initialSelectedTagIds,
    required this.onSelectionChanged,
  });

  final List<NoteCategory> tags;
  final List<String> initialSelectedTagIds;
  final ValueChanged<List<String>> onSelectionChanged;

  @override
  State<_QuickEditTagSection> createState() => _QuickEditTagSectionState();
}

class _QuickEditTagSectionState extends State<_QuickEditTagSection> {
  late List<String> _selected = [...widget.initialSelectedTagIds];

  @override
  Widget build(BuildContext context) {
    return TagSelectionSection(
      tags: widget.tags,
      selectedTagIds: _selected,
      onSelectionChanged: (newSelection) {
        setState(() => _selected = newSelection);
        widget.onSelectionChanged(newSelection);
      },
    );
  }
}

extension _AIAssistantPageQuickEdit on _AIAssistantPageState {
  /// 结果卡与提案卡共用的快编面板：作者/出处/标签。
  /// 「快编」只管这些元信息，改正文请走完整编辑器，别在小面板里塞长文本框。
  /// 用底部面板而不是 AlertDialog：折叠的标签区展开后要占一屏高度，
  /// AlertDialog 会把它顶出可视范围（下面的标签点不到），
  /// 底部面板可以整页滚动 + 固定操作栏，键盘弹出时也不会盖住输入框。
  Future<_QuickEditValues?> _showQuickEditDialog({
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

    final authorController = TextEditingController(text: author ?? '');
    final sourceController = TextEditingController(text: source ?? '');
    final selected = <String>[...selectedTagIds];

    try {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      l10n.aiCardQuickEditTooltip,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: authorController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: l10n.author,
                                    isDense: true,
                                    prefixIcon:
                                        const Icon(Icons.person_outline),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: sourceController,
                                  decoration: InputDecoration(
                                    labelText: l10n.source,
                                    isDense: true,
                                    prefixIcon:
                                        const Icon(Icons.menu_book_outlined),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _QuickEditTagSection(
                            tags: allTags,
                            initialSelectedTagIds: selected,
                            onSelectionChanged: (newSelection) {
                              selected
                                ..clear()
                                ..addAll(newSelection);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          child: Text(l10n.cancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          child: Text(l10n.done),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
        author: trimToNull(authorController.text),
        source: trimToNull(sourceController.text),
        tagIds: [for (final tag in selectedTags) tag.id],
        tagNames: [for (final tag in selectedTags) tag.name],
        tagIconNames: [for (final tag in selectedTags) tag.iconName],
      );
    } finally {
      authorController.dispose();
      sourceController.dispose();
    }
  }

  /// 提案卡快编：弹窗 → 写回 artifact。只改 author/source/tag_ids，
  /// 正文交给完整编辑器，避免与 ops 应用结果不一致。
  ///
  /// 新建提案的 metadata 是平铺值；修改提案的 metadata 是「补丁」
  /// （`{'author': {'action': 'set', 'value': ...}}`，没有这个键就表示保持原样）。
  /// 所以这里要先把补丁盖到原笔记上算出「当前生效值」再回填弹窗，
  /// 否则改笔记时快编里一片空白；写回也必须按补丁格式来，
  /// 不然 [_quoteFromArtifact] 认不出来，保存时会把用户的改动丢掉。
  Future<NoteProposalQuickEdit?> _handleNoteProposalQuickEdit(
    String messageId,
    Map<String, dynamic> meta,
    NoteProposalArtifact artifact,
    NoteProposalQuickEdit current,
  ) async {
    final isEdit = artifact.action == NoteProposalAction.edit;
    Quote? original;
    if (isEdit && artifact.noteId != null) {
      original = await context.read<DatabaseService>().getQuoteById(
            artifact.noteId!,
          );
      if (!mounted) return null;
    }
    final effective = isEdit
        ? _effectiveProposalMeta(artifact, original)
        : (
            author: current.author,
            source: current.source,
            tagIds: current.tagIds,
          );

    final values = await _showQuickEditDialog(
      author: effective.author,
      source: effective.source,
      selectedTagIds: effective.tagIds,
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
      final metadata = Map<String, Object?>.from(
        (artifactJson['metadata'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const <String, Object?>{},
      );
      if (isEdit) {
        // 只给「用户真的改过」的字段写补丁：没动的字段保持原样，
        // 免得把 AI 原本的补丁或笔记的旧 source 字段无谓地覆盖掉。
        void writePatch(String key, String? value, String? before) {
          if (value == before) return;
          metadata[key] = value == null
              ? <String, Object?>{'action': 'clear'}
              : <String, Object?>{'action': 'set', 'value': value};
        }

        writePatch('author', values.author, effective.author);
        writePatch('source', values.source, effective.source);
        if (!_sameTagIds(values.tagIds, effective.tagIds)) {
          metadata['tag_ids'] = values.tagIds.isEmpty
              ? <String, Object?>{'action': 'clear'}
              : <String, Object?>{'action': 'set', 'value': values.tagIds};
        }
      } else {
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
      }
      // 卡片上的标签胶囊只认平铺的 tag_names，两种提案都写一份
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
      content: current.content,
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

  /// 提案卡勾选「位置」时才现场定位（与编辑器一致：不勾不定位）。
  /// 返回胶囊上显示的地点文本；权限被拒或取不到时返回 null，由卡片回退开关。
  Future<String?> _resolveProposalLocation() async {
    final locationService = context.read<LocationService>();
    if (!locationService.hasLocationPermission) {
      final granted = await locationService.requestLocationPermission();
      if (!granted) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.cannotGetLocationPermissionShort)),
          );
        }
        return null;
      }
    }
    await locationService.getCurrentLocation();
    final display = locationService.getDisplayLocation();
    return display.trim().isEmpty ? null : display;
  }

  /// 提案卡勾选「天气」时才现场获取。天气依赖坐标，必要时先定位。
  Future<String?> _resolveProposalWeather() async {
    final locationService = context.read<LocationService>();
    final weatherService = context.read<WeatherService>();
    var position = locationService.currentPosition;
    if (position == null) {
      // 天气必须有坐标，先走一次定位（含权限请求）；地址串取不到不影响天气
      await _resolveProposalLocation();
      if (!mounted) return null;
      position = locationService.currentPosition;
    }
    if (position == null) {
      // 权限被拒时定位那步已经提示过，这里不再叠一条
      if (mounted && locationService.hasLocationPermission) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.locationAndWeatherUnavailable)),
        );
      }
      return null;
    }
    try {
      await weatherService.getWeatherData(
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      logDebug('提案卡获取天气失败: $e');
      return null;
    }
    if (!mounted || weatherService.currentWeather == null) return null;
    final l10n = AppLocalizations.of(context);
    final description = weatherService.getFormattedWeather(l10n);
    return description.trim().isEmpty ? null : description;
  }

  /// 修改提案里 metadata 是补丁格式，取「补丁盖到原笔记之后」的生效值，
  /// 供快编回填用。拿不到原笔记（已被删/查询失败）时就只认补丁里写了的部分。
  ({String? author, String? source, List<String> tagIds})
      _effectiveProposalMeta(
    NoteProposalArtifact artifact,
    Quote? original,
  ) {
    String? readPatch(Object? patch, String? fallback) {
      if (patch is! Map) return fallback;
      if (patch['action'] == 'clear') return null;
      return patch['value']?.toString();
    }

    final metadata = artifact.metadata;
    final tagPatch = metadata['tag_ids'];
    return (
      author: readPatch(metadata['author'], original?.sourceAuthor),
      source: readPatch(metadata['source'], original?.sourceWork),
      tagIds: tagPatch is Map
          ? (tagPatch['action'] == 'clear'
              ? const <String>[]
              : _extractStringList(tagPatch['value']))
          : (original?.tagIds ?? const <String>[]),
    );
  }

  bool _sameTagIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.toSet().containsAll(b);
  }

  /// 提案卡的展示标签：优先 metadata 里的 tag_names，缺失时退化为 id。
  /// 修改提案的 tag_ids 是补丁，取补丁里的 value（没有补丁就是没动过标签）。
  List<NoteCategory> _resolveProposalDisplayTags(
    NoteProposalArtifact artifact,
  ) {
    final metadata = artifact.metadata;
    final rawTagIds = metadata['tag_ids'];
    final ids = rawTagIds is Map
        ? (rawTagIds['action'] == 'clear'
            ? const <String>[]
            : _extractStringList(rawTagIds['value']))
        : _extractStringList(rawTagIds);
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
