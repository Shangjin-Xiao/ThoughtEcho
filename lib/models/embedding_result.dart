/// 嵌入向量和搜索结果模型
///
/// 用于语义搜索和相关笔记推荐

/// 嵌入向量
class Embedding {
  /// 向量数据
  final List<double> vector;

  /// 原始文本
  final String sourceText;

  /// 关联的笔记 ID
  final String? noteId;

  /// 创建时间
  final DateTime createdAt;

  const Embedding({
    required this.vector,
    required this.sourceText,
    this.noteId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? const _DefaultDateTime();

  /// 向量维度
  int get dimension => vector.length;

  /// 是否为空
  bool get isEmpty => vector.isEmpty;

  /// 计算与另一个嵌入的余弦相似度
  double cosineSimilarity(Embedding other) {
    if (vector.length != other.vector.length) {
      throw ArgumentError('向量维度不匹配: ${vector.length} vs ${other.vector.length}');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vector.length; i++) {
      dotProduct += vector[i] * other.vector[i];
      normA += vector[i] * vector[i];
      normB += other.vector[i] * other.vector[i];
    }

    if (normA == 0 || normB == 0) return 0.0;

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// 从 JSON 创建
  factory Embedding.fromJson(Map<String, dynamic> json) {
    return Embedding(
      vector:
          (json['vector'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      sourceText: json['sourceText'] as String? ?? '',
      noteId: json['noteId'] as String?,
      createdAt:
          json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : DateTime.now(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'vector': vector,
      'sourceText': sourceText,
      'noteId': noteId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 复制并修改
  Embedding copyWith({
    List<double>? vector,
    String? sourceText,
    String? noteId,
    DateTime? createdAt,
  }) {
    return Embedding(
      vector: vector ?? this.vector,
      sourceText: sourceText ?? this.sourceText,
      noteId: noteId ?? this.noteId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 搜索结果
class SearchResult {
  /// 笔记 ID
  final String noteId;

  /// 相似度分数 (0.0 - 1.0)
  final double score;

  /// 匹配的文本片段
  final String? matchedText;

  /// 高亮位置
  final List<HighlightRange>? highlights;

  const SearchResult({
    required this.noteId,
    required this.score,
    this.matchedText,
    this.highlights,
  });

  /// 从 JSON 创建
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      noteId: json['noteId'] as String,
      score: (json['score'] as num).toDouble(),
      matchedText: json['matchedText'] as String?,
      highlights:
          (json['highlights'] as List<dynamic>?)
              ?.map((h) => HighlightRange.fromJson(h as Map<String, dynamic>))
              .toList(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'score': score,
      'matchedText': matchedText,
      'highlights': highlights?.map((h) => h.toJson()).toList(),
    };
  }
}

/// 高亮范围
class HighlightRange {
  /// 开始位置
  final int start;

  /// 结束位置
  final int end;

  const HighlightRange({required this.start, required this.end});

  /// 从 JSON 创建
  factory HighlightRange.fromJson(Map<String, dynamic> json) {
    return HighlightRange(
      start: json['start'] as int,
      end: json['end'] as int,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {'start': start, 'end': end};
  }
}

/// 相关笔记
class RelatedNote {
  /// 笔记 ID
  final String noteId;

  /// 相似度分数
  final double similarity;

  /// 推荐原因
  final String? reason;

  const RelatedNote({
    required this.noteId,
    required this.similarity,
    this.reason,
  });

  /// 从 JSON 创建
  factory RelatedNote.fromJson(Map<String, dynamic> json) {
    return RelatedNote(
      noteId: json['noteId'] as String,
      similarity: (json['similarity'] as num).toDouble(),
      reason: json['reason'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'similarity': similarity,
      'reason': reason,
    };
  }
}

/// 简单的平方根实现
double sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;

  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}

/// 默认时间类（用于 const 构造函数）
class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();

  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime.now();
}
