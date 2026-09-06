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

  // 从JSON构建AIAnalysis对象（增强容错：支持下划线/驼峰属性、隐式Null/类型不匹配保护）
  factory AIAnalysis.fromJson(Map<String, dynamic> json) {
    // 解析相关笔记ID（确保它们是字符串列表）
    List<String>? parseRelatedQuoteIds() {
      final raw = json['related_quote_ids'] ?? json['relatedQuoteIds'];
      if (raw == null) return null;
      if (raw is String) {
        if (raw.isEmpty) return null;
        final list = raw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return list.isEmpty ? null : list;
      }
      if (raw is List) {
        final list = raw
            .whereType<Object>()
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return list.isEmpty ? null : list;
      }
      return null;
    }

    final rawQuoteCount = json['quote_count'] ?? json['quoteCount'];
    final int? quoteCount = rawQuoteCount is int
        ? rawQuoteCount
        : rawQuoteCount is double &&
                rawQuoteCount.isFinite &&
                rawQuoteCount == rawQuoteCount.truncateToDouble()
            ? rawQuoteCount.toInt()
            : int.tryParse(rawQuoteCount?.toString() ?? '');

    return AIAnalysis(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      analysisType:
          (json['analysis_type'] ?? json['analysisType'])?.toString() ??
              'comprehensive',
      analysisStyle:
          (json['analysis_style'] ?? json['analysisStyle'])?.toString() ??
              'professional',
      customPrompt: (json['custom_prompt'] ?? json['customPrompt'])?.toString(),
      createdAt: (json['created_at'] ?? json['createdAt'])?.toString() ??
          DateTime.now().toIso8601String(),
      relatedQuoteIds: parseRelatedQuoteIds(),
      quoteCount: quoteCount,
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
