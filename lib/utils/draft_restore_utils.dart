import 'package:thoughtecho/models/quote_model.dart';

String? _nonEmptyString(dynamic value) {
  if (value == null) return null;
  final str = value.toString();
  return str.trim().isEmpty ? null : str;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return null;
  return double.tryParse(value.toString());
}

List<String>? _toStringList(dynamic value) {
  if (value is! List) return null;
  return value.map((e) => _nonEmptyString(e)).whereType<String>().toList();
}

/// 构建恢复草稿时传给编辑器的笔记对象。
Quote buildRestoredDraftQuote({
  required Map<String, dynamic> draftData,
  Quote? original,
  DateTime? now,
}) {
  final draftId = draftData['id']?.toString() ?? '';
  final isNew = draftId.startsWith('new_');
  final timestamp = (now ?? DateTime.now()).toIso8601String();

  if (!isNew && original != null) {
    return original.copyWith(
      content: _nonEmptyString(draftData['plainText']) ?? '',
      deltaContent: _nonEmptyString(draftData['deltaContent']),
      aiAnalysis: _nonEmptyString(draftData['aiAnalysis']),
      sourceAuthor: _nonEmptyString(draftData['author']),
      sourceWork: _nonEmptyString(draftData['work']),
      tagIds: _toStringList(draftData['tagIds']),
      colorHex: _nonEmptyString(draftData['colorHex']),
      location: _nonEmptyString(draftData['location']),
      poiName: _nonEmptyString(draftData['poiName']),
      latitude: _toDouble(draftData['latitude']),
      longitude: _toDouble(draftData['longitude']),
      weather: _nonEmptyString(draftData['weather']),
      temperature: _nonEmptyString(draftData['temperature']),
    );
  }

  return Quote(
    id: isNew ? null : draftId,
    content: _nonEmptyString(draftData['plainText']) ?? '',
    deltaContent: _nonEmptyString(draftData['deltaContent']),
    date: _nonEmptyString(draftData['date']) ??
        _nonEmptyString(draftData['timestamp']) ??
        timestamp,
    aiAnalysis: _nonEmptyString(draftData['aiAnalysis']),
    sourceAuthor: _nonEmptyString(draftData['author']),
    sourceWork: _nonEmptyString(draftData['work']),
    tagIds: _toStringList(draftData['tagIds']) ?? [],
    colorHex: _nonEmptyString(draftData['colorHex']),
    location: _nonEmptyString(draftData['location']),
    poiName: _nonEmptyString(draftData['poiName']),
    latitude: _toDouble(draftData['latitude']),
    longitude: _toDouble(draftData['longitude']),
    weather: _nonEmptyString(draftData['weather']),
    temperature: _nonEmptyString(draftData['temperature']),
    editSource: 'fullscreen',
  );
}
