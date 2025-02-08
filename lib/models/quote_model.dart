class Quote {
  final String? id;
  final String date;
  final String content;
  final String? aiAnalysis;
  final String? sentiment;
  final List<String>? keywords;
  final String? summary;
  String categoryId;

  Quote({
    this.id,
    required this.date,
    required this.content,
    this.aiAnalysis,
    this.sentiment,
    this.keywords,
    this.summary,
    this.categoryId = 'general',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'content': content,
      'aiAnalysis': aiAnalysis,
      'sentiment': sentiment,
      'keywords': keywords,
      'summary': summary,
      'categoryId': categoryId,
    };
  }

  factory Quote.fromMap(Map<String, dynamic> map) {
    return Quote(
      id: map['id'],
      date: map['date'],
      content: map['content'],
      aiAnalysis: map['aiAnalysis'],
      sentiment: map['sentiment'],
      keywords: map['keywords'] != null ? List<String>.from(map['keywords']) : null,
      summary: map['summary'],
      categoryId: map['categoryId'] ?? 'general',
    );
  }
}