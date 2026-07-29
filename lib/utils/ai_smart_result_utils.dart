class AiSmartResultMetadata {
  AiSmartResultMetadata({
    required List<String> tagIds,
    required this.includeLocation,
    required this.includeWeather,
    this.author,
    this.source,
  }) : tagIds = List<String>.unmodifiable(tagIds);

  final String? author;
  final String? source;
  final List<String> tagIds;
  final bool includeLocation;
  final bool includeWeather;
}

class AiSmartResultUtils {
  static const int fullEditorContentThreshold = 100;

  static bool shouldOpenFullEditor(String content) {
    return content.length > fullEditorContentThreshold;
  }

  /// 建议卡片消息的 meta type，用于在历史里识别卡片。
  static const Set<String> proposalCardTypes = {'note_proposal'};

  /// 找出最近一张建议卡片已保存成的笔记 id；最近一张还没被采纳时返回 null。
  ///
  /// 卡片消息带 metaJson，会被 Agent 的历史过滤排除掉，采纳状态（saved_note_id）
  /// 就跟着一起丢了——模型因此看不到自己的建议有没有被接受。调用方拿这个 id
  /// 合成一条状态说明补进历史。
  ///
  /// [metaOf] 从消息取出已解析的 meta，无 meta 返回 null。
  static String? latestAdoptedProposalNoteId<T>(
    List<T> messages,
    Map<String, dynamic>? Function(T message) metaOf,
  ) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final meta = metaOf(messages[i]);
      if (meta == null) continue;
      if (!proposalCardTypes.contains(meta['type'])) continue;
      final savedNoteId = meta['saved_note_id']?.toString().trim();
      if (savedNoteId == null || savedNoteId.isEmpty) return null;
      return savedNoteId;
    }
    return null;
  }

  /// 给模型看的采纳状态说明。
  ///
  /// 措辞刻意避开「上述提案」这类指代——被指代的那条卡片消息并不在历史里，
  /// 模型顺着指代找不到东西。
  static String proposalAdoptionNotice(String savedNoteId) =>
      '[系统提示：用户已采纳你最近一条笔记建议并保存，笔记 id 为 $savedNoteId。'
      '不要重复提出同一条建议；如需继续改这条笔记，用这个 id 调用笔记编辑工具。]';

  static AiSmartResultMetadata resolveNewNoteMetadata({
    required String? aiAuthor,
    required String? aiSource,
    required List<String> aiTagIds,
    required List<String> defaultTagIds,
    required bool? aiIncludeLocation,
    required bool? aiIncludeWeather,
    required bool userAutoAttachLocation,
    required bool userAutoAttachWeather,
  }) {
    return AiSmartResultMetadata(
      author: _trimToNull(aiAuthor),
      source: _trimToNull(aiSource),
      tagIds: _mergeTagIds(defaultTagIds, aiTagIds),
      includeLocation: aiIncludeLocation ?? userAutoAttachLocation,
      includeWeather: aiIncludeWeather ?? userAutoAttachWeather,
    );
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _mergeTagIds(
    List<String> defaultTagIds,
    List<String> aiTagIds,
  ) {
    final merged = <String>[];
    for (final id in [...defaultTagIds, ...aiTagIds]) {
      final trimmed = id.trim();
      if (trimmed.isNotEmpty && !merged.contains(trimmed)) {
        merged.add(trimmed);
      }
    }
    return merged;
  }
}
