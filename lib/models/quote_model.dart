class Quote {
  final String? id;
  final String content;
  final String date;
  final String? aiAnalysis;
  final String? source;
  final String? sourceAuthor;
  final String? sourceWork;
  final List<String> tagIds;
  final String? sentiment;
  final List<String>? keywords;
  final String? summary;
  final String? categoryId;
  final String? colorHex;
  final String? location;
  final String? weather;
  final String? temperature;
  final String? editSource; // "fullscreen" 或 null
  final String? deltaContent; // 新增：用于存储富文本格式(Delta JSON)
  final String? dayPeriod; // 新增：时间段标识(晨曦、午后、黄昏、夜晚等)
  final String? lastModified;
  final int favoriteCount; // 新增：心形点击次数

  const Quote({
    this.id,
    required this.content,
    required this.date,
    this.source, // TODO: 优化：考虑source字段是否冗余。如果sourceAuthor和sourceWork总是用于重建source，则可以移除source字段以减少数据冗余。
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
    this.weather,
    this.temperature,
    this.editSource,
    this.deltaContent, // 新增：Delta JSON
    this.dayPeriod, // 新增：时间段
    this.lastModified,
    this.favoriteCount = 0, // 新增：心形点击次数，默认为0
  });

  /// 修复：添加数据验证方法
  static bool isValidDate(String date) {
    try {
      DateTime.parse(date);
      return true;
    } catch (e) {
      return false;
    }
  }

  static bool isValidColorHex(String? colorHex) {
    if (colorHex == null) return true;
    final regex = RegExp(r'^#[0-9A-Fa-f]{6}$');
    return regex.hasMatch(colorHex);
  }

  static bool isValidContent(String content) {
    return content.isNotEmpty && content.length <= 10000;
  }

  /// 修复：创建验证过的Quote实例
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
    String? weather,
    String? temperature,
    String? editSource,
    String? deltaContent,
    String? dayPeriod,
    int favoriteCount = 0, // 新增：心形点击次数，默认为0
  }) {
    // 验证必填字段
    if (!isValidContent(content)) {
      throw ArgumentError('笔记内容无效：内容不能为空且不能超过10000字符');
    }

    if (!isValidDate(date)) {
      throw ArgumentError('日期格式无效：$date');
    }

    if (!isValidColorHex(colorHex)) {
      throw ArgumentError('颜色格式无效：$colorHex，应为#RRGGBB格式');
    }

    // 验证情感分析值
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
      weather: weather?.trim(),
      temperature: temperature?.trim(),
      editSource: editSource,
      deltaContent: deltaContent,
      dayPeriod: dayPeriod,
      favoriteCount: favoriteCount, // 新增：心形点击次数
    );
  }

  /// 修复：从JSON构建Quote对象，增加数据验证和错误处理
  factory Quote.fromJson(Map<String, dynamic> json) {
    try {
      // 解析tagIds（确保它们是字符串列表）
      List<String> parseTagIds() {
        if (json['tag_ids'] == null) return [];
        if (json['tag_ids'] is String) {
          final tagString = json['tag_ids'] as String;
          if (tagString.isEmpty) return [];
          return tagString
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        if (json['tag_ids'] is List) {
          return (json['tag_ids'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        return [];
      }

      // 解析keywords（确保它们是字符串列表）
      List<String>? parseKeywords() {
        if (json['keywords'] == null) return null;
        if (json['keywords'] is String) {
          final keywordString = json['keywords'] as String;
          if (keywordString.isEmpty) return null;
          return keywordString
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        if (json['keywords'] is List) {
          final keywords = (json['keywords'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          return keywords.isEmpty ? null : keywords;
        }
        return null;
      }

      // 验证必填字段
      final content = json['content']?.toString() ?? '';
      final date = json['date']?.toString() ?? '';

      if (content.isEmpty) {
        throw ArgumentError('笔记内容不能为空');
      }

      if (date.isEmpty) {
        throw ArgumentError('日期不能为空');
      }

      // 验证日期格式
      if (!isValidDate(date)) {
        throw ArgumentError('日期格式无效: $date');
      }

      // 验证颜色格式
      final colorHex = json['color_hex']?.toString();
      if (colorHex != null && !isValidColorHex(colorHex)) {
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
        weather: json['weather']?.toString(),
        temperature: json['temperature']?.toString(),
        editSource: json['edit_source']?.toString(),
        deltaContent: json['delta_content']?.toString(),
        dayPeriod: json['day_period']?.toString(),
        lastModified: json['last_modified']?.toString(),
        favoriteCount: (json['favorite_count'] as num?)?.toInt() ?? 0, // 新增：心形点击次数
      );
    } catch (e) {
      throw FormatException('解析Quote JSON失败: $e, JSON: $json');
    }
  }

  // 将Quote对象转换为JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'id': id,
      'content': content,
      'date': date,
      'ai_analysis': aiAnalysis,
      'source': source,
      'source_author': sourceAuthor,
      'source_work': sourceWork,
      // 'tag_ids' 不再直接保存到此表中，它将通过关联表进行管理
      'sentiment': sentiment,
      'keywords': keywords?.join(','),
      'summary': summary,
      'category_id': categoryId,
      'color_hex': colorHex,
      'location': location,
      'weather': weather,
      'temperature': temperature,
      'edit_source': editSource,
      'delta_content': deltaContent, // 新增：Delta JSON
      'day_period': dayPeriod, // 新增：时间段
      'last_modified': lastModified,
      'favorite_count': favoriteCount, // 新增：心形点击次数
    };
    // 移除tag_ids字段，因为它不再直接存储在quotes表中
    json.remove('tag_ids');
    return json;
  }

  // 复制并修改当前Quote对象
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
    String? weather,
    String? temperature,
    String? editSource,
    String? deltaContent, // 新增：Delta JSON
    String? dayPeriod, // 新增：时间段
    String? lastModified,
    int? favoriteCount, // 新增：心形点击次数
  }) {
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
      weather: weather ?? this.weather,
      temperature: temperature ?? this.temperature,
      editSource: editSource ?? this.editSource,
      deltaContent: deltaContent ?? this.deltaContent, // 新增：Delta JSON
      dayPeriod: dayPeriod ?? this.dayPeriod, // 新增：时间段
      lastModified: lastModified ?? this.lastModified,
      favoriteCount: favoriteCount ?? this.favoriteCount, // 新增：心形点击次数
    );
  }

  // 静态key-label映射
  static const Map<String, String> sentimentKeyToLabel = {
    'positive': '积极',
    'negative': '消极',
    'neutral': '中性',
    'mixed': '复杂',
  };
  static const Map<String, String> sourceTypeKeyToLabel = {
    'manual': '手动',
    'ai': 'AI生成',
    'import': '导入',
  };

  /// 修复：添加工具方法
  bool get hasLocation => location != null && location!.isNotEmpty;
  bool get hasWeather => weather != null && weather!.isNotEmpty;
  bool get hasAiAnalysis => aiAnalysis != null && aiAnalysis!.isNotEmpty;
  bool get hasTags => tagIds.isNotEmpty;
  bool get hasKeywords => keywords != null && keywords!.isNotEmpty;

  /// 获取情感分析的中文标签
  String? get sentimentLabel =>
      sentiment != null ? sentimentKeyToLabel[sentiment] : null;

  /// 获取完整的来源信息
  String get fullSource {
    if (sourceAuthor != null && sourceWork != null) {
      return '$sourceAuthor - $sourceWork';
    } else if (sourceAuthor != null) {
      return sourceAuthor!;
    } else if (sourceWork != null) {
      return sourceWork!;
    } else if (source != null) {
      return source!;
    }
    return '未知来源';
  }

  /// 验证Quote对象的完整性
  bool get isValid {
    try {
      return isValidContent(content) &&
          isValidDate(date) &&
          isValidColorHex(colorHex) &&
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

// 移除了冗余的QuoteModel类，该类在项目中未被使用
// 如果将来需要类似功能，可以直接在Quote类中添加相应方法
