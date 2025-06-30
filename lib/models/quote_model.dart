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
  });

  // 从JSON构建Quote对象
  factory Quote.fromJson(Map<String, dynamic> json) {
    // 解析tagIds（确保它们是字符串列表）
    List<String> parseTagIds() {
      if (json['tag_ids'] == null) return [];
      if (json['tag_ids'] is String) {
        if ((json['tag_ids'] as String).isEmpty) return [];
        return (json['tag_ids'] as String).split(',');
      }
      if (json['tag_ids'] is List) {
        return (json['tag_ids'] as List).map((e) => e.toString()).toList();
      }
      return [];
    }

    // 解析keywords（确保它们是字符串列表）
    List<String>? parseKeywords() {
      if (json['keywords'] == null) return null;
      if (json['keywords'] is String) {
        if ((json['keywords'] as String).isEmpty) return null;
        return (json['keywords'] as String).split(',');
      }
      if (json['keywords'] is List) {
        return (json['keywords'] as List).map((e) => e.toString()).toList();
      }
      return null;
    }

    return Quote(
      id: json['id'],
      content: json['content'],
      date: json['date'],
      aiAnalysis: json['ai_analysis'],
      source: json['source'],
      sourceAuthor: json['source_author'],
      sourceWork: json['source_work'],
      tagIds: parseTagIds(),
      sentiment: json['sentiment'],
      keywords: parseKeywords(),
      summary: json['summary'],
      categoryId: json['category_id'],
      colorHex: json['color_hex'],
      location: json['location'],
      weather: json['weather'],
      temperature: json['temperature'],
      editSource: json['edit_source'],
      deltaContent: json['delta_content'], // 新增：Delta JSON
      dayPeriod: json['day_period'], // 新增：时间段
    );
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
}

class QuoteModel {
  final String? author;

  // 添加 const 构造函数，默认值为空字符串
  const QuoteModel({this.author = ''});

  String getDisplayAuthor() {
    return author?.toUpperCase() ?? 'UNKNOWN';
  }
}
