part of '../quote_model.dart';

Quote _quoteFromJson(Map<String, dynamic> json) {
    List<String> parseTagIds() {
      final tagIdsValue = json['tag_ids'];
      if (tagIdsValue == null) return [];
      if (tagIdsValue is String) {
        if (tagIdsValue.isEmpty) return [];
        return tagIdsValue
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (tagIdsValue is List) {
        return tagIdsValue
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return [];
    }

    List<String>? parseKeywords() {
      final keywordsValue = json['keywords'];
      if (keywordsValue == null) return null;
      if (keywordsValue is String) {
        if (keywordsValue.isEmpty) return null;
        final keywords = keywordsValue
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return keywords.isEmpty ? null : keywords;
      }
      if (keywordsValue is List) {
        final keywords = (keywordsValue as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return keywords.isEmpty ? null : keywords;
      }
      return null;
    }

    final content = json['content']?.toString() ?? '';
    final date = json['date']?.toString() ?? '';

    if (content.isEmpty) {
      throw ArgumentError('笔记内容不能为空');
    }

    if (date.isEmpty) {
      throw ArgumentError('日期不能为空');
    }

    if (!_isValidDate(date)) {
      throw ArgumentError('日期格式无效: $date');
    }

    final colorHex = json['color_hex']?.toString();
    if (colorHex != null && !_isValidColorHex(colorHex)) {
      throw ArgumentError('颜色格式无效: $colorHex');
    }

    return Quote(
      id: json['id']?.toString(),
      content: content,
      date: date,
      aiAnalysis: json['ai_analysis']?.toString(),
      source: json['source']?.toString(),
      sourceAuthor: json['source_author']?.toString(),
      sourceWork: json['source_work']?.toString(),
      tagIds: parseTagIds(),
      sentiment: json['sentiment']?.toString(),
      keywords: parseKeywords(),
      summary: json['summary']?.toString(),
      categoryId: json['category_id']?.toString(),
      colorHex: colorHex,
      location: json['location']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      weather: json['weather']?.toString(),
      temperature: json['temperature']?.toString(),
      editSource: json['edit_source']?.toString(),
      deltaContent: json['delta_content']?.toString(),
      dayPeriod: json['day_period']?.toString(),
      lastModified: json['last_modified']?.toString(),
      favoriteCount: (json['favorite_count'] as num?)?.toInt() ?? 0,
      isDeleted: _parseDeletedFlag(json['is_deleted']),
      deletedAt: _normalizeDeletedAtForState(
        isDeleted: _parseDeletedFlag(json['is_deleted']),
        deletedAt: json['deleted_at']?.toString(),
      ),
    );
}

Map<String, dynamic> _quoteToJson(Quote quote) {
  return {
    if (quote.id != null) 'id': quote.id,
    'content': quote.content,
    'date': quote.date,
    if (quote.aiAnalysis != null) 'ai_analysis': quote.aiAnalysis,
    if (quote._source != null && quote._source!.isNotEmpty)
      'source': quote._source,
    if (quote.sourceAuthor != null) 'source_author': quote.sourceAuthor,
    if (quote.sourceWork != null) 'source_work': quote.sourceWork,
    if (quote.tagIds.isNotEmpty) 'tag_ids': quote.tagIds.join(','),
    if (quote.sentiment != null) 'sentiment': quote.sentiment,
    if (quote.keywords != null) 'keywords': quote.keywords!.join(','),
    if (quote.summary != null) 'summary': quote.summary,
    if (quote.categoryId != null) 'category_id': quote.categoryId,
    if (quote.colorHex != null) 'color_hex': quote.colorHex,
    if (quote.location != null) 'location': quote.location,
    if (quote.latitude != null) 'latitude': quote.latitude,
    if (quote.longitude != null) 'longitude': quote.longitude,
    if (quote.weather != null) 'weather': quote.weather,
    if (quote.temperature != null) 'temperature': quote.temperature,
    if (quote.editSource != null) 'edit_source': quote.editSource,
    if (quote.deltaContent != null) 'delta_content': quote.deltaContent,
    if (quote.dayPeriod != null) 'day_period': quote.dayPeriod,
    if (quote.lastModified != null) 'last_modified': quote.lastModified,
    'favorite_count': quote.favoriteCount,
    'is_deleted': quote.isDeleted ? 1 : 0,
    if (quote.deletedAt != null) 'deleted_at': quote.deletedAt,
  };
}
