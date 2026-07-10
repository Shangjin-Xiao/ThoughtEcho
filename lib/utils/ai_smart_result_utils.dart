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
