class Quote {
  final String? id;
  final String date;
  final String content;
  final String? source;
  final String? aiAnalysis;
  final String? sentiment;
  final List<String>? keywords;
  final String? summary;
  List<String> tagIds;
  final String? categoryId;

  Quote({
    this.id,
    required this.date,
    required this.content,
    this.source,
    this.aiAnalysis,
    this.sentiment,
    this.keywords,
    this.summary,
    this.tagIds = const [],
    this.categoryId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'content': content,
      'source': source,
      'ai_analysis': aiAnalysis,
      'sentiment': sentiment,
      'keywords': keywords?.join(','),
      'summary': summary,
      'tag_ids': tagIds.join(','),
      'category_id': categoryId,
    };
  }

  factory Quote.fromMap(Map<String, dynamic> map) {
    return Quote(
      id: map['id'],
      date: map['date'],
      content: map['content'],
      source: map['source'],
      aiAnalysis: map['ai_analysis'],
      sentiment: map['sentiment'],
      keywords: map['keywords']?.toString().split(','),
      summary: map['summary'],
      tagIds: (map['tag_ids']?.toString().split(',') ?? []).cast<String>(),
      categoryId: map['category_id'],
    );
  }
}

class QuoteModel {
  final String? author;

  // 添加 const 构造函数，默认值为空字符串
  const QuoteModel({this.author = ''});
  
  String getDisplayAuthor() {
    return author?.toUpperCase() ?? 'UNKNOWN';
  }
}
