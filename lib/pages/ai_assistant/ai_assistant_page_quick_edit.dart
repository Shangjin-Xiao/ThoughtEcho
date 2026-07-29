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

/// 快编面板里的标签选择。
///
/// 两个约束决定了这里的写法：
/// 1. 标签库可能有几百个，全量铺开既刷屏又要一次性建几百个 [FilterChip]
///    （每个都带 InkWell + 动画），面板打开和每次勾选都会卡。所以只渲染
///    「已选 + 最多 [_maxUnselectedChips] 个候选」，其余靠搜索找。
/// 2. 选中态只在本组件内 setState，不回弹到整个面板重建，
///    否则勾一个标签会连带重建正文/作者/出处那些 TextField。
class _QuickEditTagPicker extends StatefulWidget {
  const _QuickEditTagPicker({
    required this.tags,
    required this.initialSelectedTagIds,
    required this.onSelectionChanged,
  });

  final List<NoteCategory> tags;
  final List<String> initialSelectedTagIds;
  final ValueChanged<List<String>> onSelectionChanged;

  @override
  State<_QuickEditTagPicker> createState() => _QuickEditTagPickerState();
}

class _QuickEditTagPickerState extends State<_QuickEditTagPicker> {
  /// 超过这个数量才给搜索框，标签少时不必占地方。
  static const int _searchThreshold = 8;

  /// 一次最多渲染多少个未选中的候选胶囊。
  static const int _maxUnselectedChips = 12;

  final TextEditingController _searchController = TextEditingController();
  late final List<String> _selected = [...widget.initialSelectedTagIds];
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String tagId) {
    setState(() {
      if (!_selected.remove(tagId)) _selected.add(tagId);
    });
    widget.onSelectionChanged(List<String>.unmodifiable(_selected));
  }

  Widget _buildChip(NoteCategory tag, AppLocalizations l10n) {
    return FilterChip(
      key: ValueKey(tag.id),
      showCheckmark: false,
      selected: _selected.contains(tag.id),
      avatar: IconUtils.isEmoji(tag.iconName)
          ? Text(
              IconUtils.getDisplayIcon(tag.iconName),
              style: const TextStyle(fontSize: 14),
            )
          : Icon(IconUtils.getIconData(tag.iconName), size: 18),
      label: Text(tag.localizedName(l10n)),
      onSelected: (_) => _toggle(tag.id),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (widget.tags.isEmpty) {
      return Text(
        l10n.noTagsAvailableHint,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final query = _query.trim().toLowerCase();
    final matched = query.isEmpty
        ? widget.tags
        : [
            for (final tag in widget.tags)
              if (tag.localizedName(l10n).toLowerCase().contains(query)) tag,
          ];

    // 已选的永远渲染（不然勾过的标签会被截断规则藏起来，看不到也取消不掉），
    // 未选的按顺序取前 N 个当候选。
    final selectedTags = <NoteCategory>[];
    final candidateTags = <NoteCategory>[];
    var hiddenCount = 0;
    for (final tag in matched) {
      if (_selected.contains(tag.id)) {
        selectedTags.add(tag);
      } else if (candidateTags.length < _maxUnselectedChips) {
        candidateTags.add(tag);
      } else {
        hiddenCount++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.selectTagsWithCount(_selected.length),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (widget.tags.length > _searchThreshold) ...[
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: l10n.searchTags,
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (matched.isEmpty)
          Text(
            l10n.noMatchingTags,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in selectedTags) _buildChip(tag, l10n),
              for (final tag in candidateTags) _buildChip(tag, l10n),
            ],
          ),
        if (hiddenCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            l10n.quickEditMoreTagsHint(hiddenCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

extension _AIAssistantPageQuickEdit on _AIAssistantPageState {
  /// 结果卡与提案卡共用的快编面板：作者/出处/标签。
  /// 「快编」只管这些元信息，改正文请走完整编辑器，别在小面板里塞长文本框。
  /// 用底部面板而不是 AlertDialog：标签区在弹窗里会被固定高度的嵌套列表
  /// 顶出可视范围（下面的标签点不到），底部面板可以整页滚动 + 固定操作栏，
  /// 键盘弹出时也不会盖住输入框。
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
                                    prefixIcon: const Icon(Icons.person_outline),
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
                          _QuickEditTagPicker(
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
  Future<NoteProposalQuickEdit?> _handleNoteProposalQuickEdit(
    String messageId,
    Map<String, dynamic> meta,
    NoteProposalArtifact artifact,
    NoteProposalQuickEdit current,
  ) async {
    final values = await _showQuickEditDialog(
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
