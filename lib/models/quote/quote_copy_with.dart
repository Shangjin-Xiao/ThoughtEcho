part of '../quote_model.dart';

/// Sentinel value used to distinguish between "not provided" and "null" in copyWith
const Object _noValue = Object();

/// Extension providing copyWith functionality for Quote
extension QuoteCopyWith on Quote {
  /// Creates a copy of this Quote with the specified fields replaced with new values.
  ///
  /// Uses a sentinel value (_noValue) to distinguish between explicitly setting a field
  /// to null vs not providing the field at all (keeping the current value).
  Quote copyWith({
    String? id,
    String? content,
    String? date,
    String? aiAnalysis,
    String? source,
    String? sourceAuthor,
    String? sourceWork,
    List<String>? tagIds,
    String? sentiment,
    List<String>? keywords,
    String? summary,
    String? categoryId,
    String? colorHex,
    String? location,
    double? latitude,
    double? longitude,
    String? weather,
    String? temperature,
    String? editSource,
    String? deltaContent,
    String? dayPeriod,
    String? lastModified,
    int? favoriteCount,
    Object? isDeleted = _noValue,
    Object? deletedAt = _noValue,
  }) {
    final nextIsDeleted = identical(isDeleted, _noValue)
        ? this.isDeleted
        : (isDeleted is bool ? isDeleted : this.isDeleted);
    final nextDeletedAt =
        identical(deletedAt, _noValue) ? this.deletedAt : deletedAt as String?;

    return Quote(
      id: id ?? this.id,
      content: content ?? this.content,
      date: date ?? this.date,
      aiAnalysis: aiAnalysis ?? this.aiAnalysis,
      source: source ?? this.source,
      sourceAuthor: sourceAuthor ?? this.sourceAuthor,
      sourceWork: sourceWork ?? this.sourceWork,
      tagIds: tagIds ?? this.tagIds,
      sentiment: sentiment ?? this.sentiment,
      keywords: keywords ?? this.keywords,
      summary: summary ?? this.summary,
      categoryId: categoryId ?? this.categoryId,
      colorHex: colorHex ?? this.colorHex,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      weather: weather ?? this.weather,
      temperature: temperature ?? this.temperature,
      editSource: editSource ?? this.editSource,
      deltaContent: deltaContent ?? this.deltaContent,
      dayPeriod: dayPeriod ?? this.dayPeriod,
      lastModified: lastModified ?? this.lastModified,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      isDeleted: nextIsDeleted,
      deletedAt: _normalizeDeletedAtForState(
        isDeleted: nextIsDeleted,
        deletedAt: nextDeletedAt,
      ),
    );
  }
}

/// Helper function to parse deleted flag from various formats
bool _parseDeletedFlag(dynamic raw) {
  if (raw == null) return false;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final text = raw.toString().trim().toLowerCase();
  return text == '1' || text == 'true';
}

/// Normalizes deletedAt timestamp to UTC format
/// If deletedAt is missing or invalid, generates current UTC time
String _normalizeToUtc(String? deletedAt) {
  final trimmed = deletedAt?.trim();
  if (trimmed != null && trimmed.isNotEmpty && Quote.isValidDate(trimmed)) {
    return DateTime.parse(trimmed).toUtc().toIso8601String();
  }
  return DateTime.now().toUtc().toIso8601String();
}

/// Normalizes deletedAt based on isDeleted state
/// Returns null if not deleted, otherwise ensures valid UTC timestamp
String? _normalizeDeletedAtForState({
  required bool isDeleted,
  required String? deletedAt,
}) {
  if (!isDeleted) {
    return null;
  }

  final trimmed = deletedAt?.trim();
  if (trimmed != null && trimmed.isNotEmpty && Quote.isValidDate(trimmed)) {
    // 统一归一化到 UTC
    return DateTime.parse(trimmed).toUtc().toIso8601String();
  }

  // 缺失时生成当前 UTC 时间，而非回退到 quote.date
  return DateTime.now().toUtc().toIso8601String();
}
