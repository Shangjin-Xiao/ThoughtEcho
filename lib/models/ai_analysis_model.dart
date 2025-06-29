/// AI分析结果模型
class AIAnalysis {
  final String? id;
  final String title;
  final String content;
  final String
  analysisType; // 'comprehensive', 'emotional', 'mindmap', 'growth' 或 'custom'
  final String
  analysisStyle; // 'professional', 'friendly', 'humorous', 'literary'
  final String? customPrompt; // 自定义提示词（如果使用）
  final String createdAt;
  final List<String>? relatedQuoteIds; // 相关的笔记ID列表
  final int? quoteCount; // 分析时包含的笔记数量

  const AIAnalysis({
    this.id,
    required this.title,
    required this.content,
    required this.analysisType,
    required this.analysisStyle,
    this.customPrompt,
    required this.createdAt,
    this.relatedQuoteIds,
    this.quoteCount,
  });

  // 从JSON构建AIAnalysis对象
  factory AIAnalysis.fromJson(Map<String, dynamic> json) {
    // 解析相关笔记ID（确保它们是字符串列表）
    List<String>? parseRelatedQuoteIds() {
      if (json['related_quote_ids'] == null) return null;
      if (json['related_quote_ids'] is String) {
        final String idsStr = json['related_quote_ids'] as String;
        if (idsStr.isEmpty) return null;
        return idsStr.split(',');
      }
      if (json['related_quote_ids'] is List) {
        return (json['related_quote_ids'] as List)
            .map((e) => e.toString())
            .toList();
      }
      return null;
    }

    return AIAnalysis(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      analysisType: json['analysis_type'],
      analysisStyle: json['analysis_style'],
      customPrompt: json['custom_prompt'],
      createdAt: json['created_at'],
      relatedQuoteIds: parseRelatedQuoteIds(),
      quoteCount: json['quote_count'],
    );
  }

  // 将AIAnalysis对象转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'analysis_type': analysisType,
      'analysis_style': analysisStyle,
      'custom_prompt': customPrompt,
      'created_at': createdAt,
      'related_quote_ids': relatedQuoteIds?.join(','),
      'quote_count': quoteCount,
    };
  }

  // 深拷贝方法
  AIAnalysis copyWith({
    String? id,
    String? title,
    String? content,
    String? analysisType,
    String? analysisStyle,
    String? customPrompt,
    String? createdAt,
    List<String>? relatedQuoteIds,
    int? quoteCount,
  }) {
    return AIAnalysis(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      analysisType: analysisType ?? this.analysisType,
      analysisStyle: analysisStyle ?? this.analysisStyle,
      customPrompt: customPrompt ?? this.customPrompt,
      createdAt: createdAt ?? this.createdAt,
      relatedQuoteIds: relatedQuoteIds ?? this.relatedQuoteIds,
      quoteCount: quoteCount ?? this.quoteCount,
    );
  }

  @override
  String toString() {
    return 'AIAnalysis{id: $id, title: $title, analysisType: $analysisType, '
        'createdAt: $createdAt, quoteCount: $quoteCount}';
  }
}
