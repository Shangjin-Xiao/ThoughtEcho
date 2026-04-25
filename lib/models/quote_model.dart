part 'quote/quote_validation.dart';
part 'quote/quote_serialization.dart';

class Quote {
  static const Object _noValue = Object();

  final String? id;
  final String content;
  final String date;
  final String? aiAnalysis;
  final String? _source;
  final String? sourceAuthor;
  final String? sourceWork;
  final List<String> tagIds;
  final String? sentiment;
  final List<String>? keywords;
  final String? summary;
  final String? categoryId;
  final String? colorHex;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? weather;
  final String? temperature;
  final String? editSource;
  final String? deltaContent;
  final String? dayPeriod;
  final String? lastModified;
  final int favoriteCount;
  final bool isDeleted;
  final String? deletedAt;

  Quote({
    this.id,
    required this.content,
    required this.date,
    String? source,
    this.sourceAuthor,
    this.sourceWork,
    this.tagIds = const [],
    this.aiAnalysis,
    this.sentiment,
    this.keywords,
    this.summary,
    this.categoryId,
    this.colorHex,
    this.location,
    this.latitude,
    this.longitude,
    this.weather,
    this.temperature,
    this.editSource,
    this.deltaContent,
    this.dayPeriod,
    this.lastModified,
    this.favoriteCount = 0,
    this.isDeleted = false,
    String? deletedAt,
  })  : _source = source,
        deletedAt = isDeleted ? _normalizeToUtc(deletedAt) : null;

  String? get source {
    if (sourceAuthor != null &&
        sourceWork != null &&
        sourceAuthor!.isNotEmpty &&
        sourceWork!.isNotEmpty) {
      return '$sourceAuthor - $sourceWork';
    } else if (sourceAuthor != null && sourceAuthor!.isNotEmpty) {
      return sourceAuthor;
    } else if (sourceWork != null && sourceWork!.isNotEmpty) {
      return sourceWork;
    }
    return _source;
  }

  static bool isValidDate(String date) => _isValidDate(date);
  static bool isValidColorHex(String? colorHex) => _isValidColorHex(colorHex);
  static bool isValidContent(String content) => _isValidContent(content);

  factory Quote.validated({
    String? id,
    required String content,
    required String date,
    String? source,
    String? sourceAuthor,
    String? sourceWork,
    List<String> tagIds = const [],
    String? aiAnalysis,
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
    int favoriteCount = 0,
    bool isDeleted = false,
    String? deletedAt,
  }) {
    if (!_isValidContent(content)) {
      throw ArgumentError('笔记内容无效：内容不能为空且不能超过10000字符');
    }

    if (!_isValidDate(date)) {
      throw ArgumentError('日期格式无效：$date');
    }

    if (!_isValidColorHex(colorHex)) {
      throw ArgumentError('颜色格式无效：$colorHex，应为#RRGGBB格式');
    }

    if (sentiment != null && !sentimentKeyToLabel.containsKey(sentiment)) {
      throw ArgumentError('情感分析值无效：$sentiment');
    }

    return Quote(
      id: id,
      content: content.trim(),
      date: date,
      source: source?.trim(),
      sourceAuthor: sourceAuthor?.trim(),
      sourceWork: sourceWork?.trim(),
      tagIds: tagIds,
      aiAnalysis: aiAnalysis?.trim(),
      sentiment: sentiment,
      keywords: keywords,
      summary: summary?.trim(),
      categoryId: categoryId,
      colorHex: colorHex,
      location: location?.trim(),
      latitude: latitude,
      longitude: longitude,
      weather: weather?.trim(),
      temperature: temperature?.trim(),
      editSource: editSource,
      deltaContent: deltaContent,
      dayPeriod: dayPeriod,
      favoriteCount: favoriteCount,
      isDeleted: isDeleted,
      deletedAt: deletedAt,
    );
  }

  factory Quote.fromJson(Map<String, dynamic> json) {
    try {
      return _quoteFromJson(json);
    } on ArgumentError {
      rethrow;
    } catch (e) {
      throw FormatException('解析Quote JSON失败: $e, JSON: $json');
    }
  }

  Map<String, dynamic> toJson() => _quoteToJson(this);

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
    final nextDeletedAt = identical(deletedAt, _noValue)
        ? this.deletedAt
        : (deletedAt is String? ? deletedAt : this.deletedAt);

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

  static const Map<String, String> sentimentKeyToLabel = _sentimentKeyToLabel;
  static const Map<String, String> sourceTypeKeyToLabel = _sourceTypeKeyToLabel;

  bool get hasLocation =>
      (location != null && location!.isNotEmpty) || hasCoordinates;
  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasWeather => weather != null && weather!.isNotEmpty;
  bool get hasAiAnalysis => aiAnalysis != null && aiAnalysis!.isNotEmpty;
  bool get hasTags => tagIds.isNotEmpty;
  bool get hasKeywords => keywords != null && keywords!.isNotEmpty;

  String? get sentimentLabel =>
      sentiment != null ? sentimentKeyToLabel[sentiment] : null;

  String get fullSource {
    final s = source;
    if (s != null && s.isNotEmpty) return s;
    return '未知来源';
  }

  bool get isValid {
    try {
      return _isValidContent(content) &&
          _isValidDate(date) &&
          _isValidColorHex(colorHex) &&
          (sentiment == null || sentimentKeyToLabel.containsKey(sentiment!));
    } catch (e) {
      return false;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Quote && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Quote(id: $id, content: ${content.length > 50 ? '${content.substring(0, 50)}...' : content}, date: $date)';
  }
}
