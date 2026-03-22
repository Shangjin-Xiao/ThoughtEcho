import 'package:thoughtecho/models/quote_model.dart';

/// 构建恢复草稿时传给编辑器的笔记对象。
Quote buildRestoredDraftQuote({
  required Map<String, dynamic> draftData,
  Quote? original,
  DateTime? now,
}) {
  final draftId = draftData['id'] as String;
  final isNew = draftId.startsWith('new_');
  final timestamp = (now ?? DateTime.now()).toIso8601String();

  if (!isNew && original != null) {
    return original.copyWith(
      content: draftData['plainText'] as String? ?? '',
      deltaContent: draftData['deltaContent'] as String?,
      aiAnalysis: draftData['aiAnalysis'] as String?,
      sourceAuthor: draftData['author'] as String?,
      sourceWork: draftData['work'] as String?,
      tagIds: (draftData['tagIds'] as List?)?.map((e) => e.toString()).toList(),
      colorHex: draftData['colorHex'] as String?,
      location: draftData['location'] as String?,
      latitude: (draftData['latitude'] as num?)?.toDouble(),
      longitude: (draftData['longitude'] as num?)?.toDouble(),
      weather: draftData['weather'] as String?,
      temperature: draftData['temperature'] as String?,
    );
  }

  return Quote(
    id: isNew ? null : draftId,
    content: draftData['plainText'] as String? ?? '',
    deltaContent: draftData['deltaContent'] as String?,
    date: timestamp,
    aiAnalysis: draftData['aiAnalysis'] as String?,
    sourceAuthor: draftData['author'] as String?,
    sourceWork: draftData['work'] as String?,
    tagIds:
        (draftData['tagIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
    colorHex: draftData['colorHex'] as String?,
    location: draftData['location'] as String?,
    latitude: (draftData['latitude'] as num?)?.toDouble(),
    longitude: (draftData['longitude'] as num?)?.toDouble(),
    weather: draftData['weather'] as String?,
    temperature: draftData['temperature'] as String?,
    editSource: 'fullscreen',
  );
}
