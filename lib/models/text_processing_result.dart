/// 文本处理结果模型
///
/// 用于 LLM 文本处理功能的结果
library;

/// 来源类型
enum SourceType {
  /// 名言警句
  quote,

  /// 书籍摘录
  book,

  /// 诗词
  poetry,

  /// 歌词
  lyrics,

  /// 电影台词
  movie,

  /// 原创内容
  original,

  /// 网络内容
  internet,

  /// 未知来源
  unknown,
}

/// 来源识别结果
class SourceRecognitionResult {
  /// 来源类型
  final SourceType type;

  /// 作者名称
  final String? author;

  /// 作品名称
  final String? work;

  /// 置信度 (0.0 - 1.0)
  final double confidence;

  /// 额外信息
  final String? additionalInfo;

  const SourceRecognitionResult({
    this.type = SourceType.unknown,
    this.author,
    this.work,
    this.confidence = 0.0,
    this.additionalInfo,
  });

  /// 空结果
  static const empty = SourceRecognitionResult();

  /// 是否识别到来源
  bool get hasSource => author != null || work != null;

  /// 格式化显示
  String get formattedSource {
    if (!hasSource) return '';
    final parts = <String>[];
    if (author != null) parts.add(author!);
    if (work != null) parts.add('《$work》');
    return parts.join(' - ');
  }

  /// 从 JSON 创建
  factory SourceRecognitionResult.fromJson(Map<String, dynamic> json) {
    return SourceRecognitionResult(
      type: SourceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SourceType.unknown,
      ),
      author: json['author'] as String?,
      work: json['work'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      additionalInfo: json['additionalInfo'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'author': author,
      'work': work,
      'confidence': confidence,
      'additionalInfo': additionalInfo,
    };
  }

  /// 复制并修改
  SourceRecognitionResult copyWith({
    SourceType? type,
    String? author,
    String? work,
    double? confidence,
    String? additionalInfo,
  }) {
    return SourceRecognitionResult(
      type: type ?? this.type,
      author: author ?? this.author,
      work: work ?? this.work,
      confidence: confidence ?? this.confidence,
      additionalInfo: additionalInfo ?? this.additionalInfo,
    );
  }
}

/// 文本纠错结果
class TextCorrectionResult {
  /// 原始文本
  final String originalText;

  /// 纠错后的文本
  final String correctedText;

  /// 修正列表
  final List<TextCorrection> corrections;

  /// 是否有修改
  final bool hasChanges;

  const TextCorrectionResult({
    required this.originalText,
    required this.correctedText,
    this.corrections = const [],
    bool? hasChanges,
  }) : hasChanges = hasChanges ?? (originalText != correctedText);

  /// 空结果
  factory TextCorrectionResult.noChange(String text) {
    return TextCorrectionResult(
      originalText: text,
      correctedText: text,
      hasChanges: false,
    );
  }

  /// 从 JSON 创建
  factory TextCorrectionResult.fromJson(Map<String, dynamic> json) {
    return TextCorrectionResult(
      originalText: json['originalText'] as String? ?? '',
      correctedText: json['correctedText'] as String? ?? '',
      corrections:
          (json['corrections'] as List<dynamic>?)
              ?.map((c) => TextCorrection.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      hasChanges: json['hasChanges'] as bool?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'originalText': originalText,
      'correctedText': correctedText,
      'corrections': corrections.map((c) => c.toJson()).toList(),
      'hasChanges': hasChanges,
    };
  }
}

/// 单个纠错项
class TextCorrection {
  /// 原始内容
  final String original;

  /// 修正后内容
  final String corrected;

  /// 位置
  final int position;

  /// 纠错原因
  final String? reason;

  const TextCorrection({
    required this.original,
    required this.corrected,
    required this.position,
    this.reason,
  });

  /// 从 JSON 创建
  factory TextCorrection.fromJson(Map<String, dynamic> json) {
    return TextCorrection(
      original: json['original'] as String? ?? '',
      corrected: json['corrected'] as String? ?? '',
      position: json['position'] as int? ?? 0,
      reason: json['reason'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'original': original,
      'corrected': corrected,
      'position': position,
      'reason': reason,
    };
  }
}

/// 标签建议结果
class TagSuggestionResult {
  /// 建议的标签列表
  final List<SuggestedTag> tags;

  /// 分析的文本内容
  final String analyzedText;

  const TagSuggestionResult({
    this.tags = const [],
    this.analyzedText = '',
  });

  /// 空结果
  static const empty = TagSuggestionResult();

  /// 是否有建议
  bool get hasSuggestions => tags.isNotEmpty;

  /// 获取标签名称列表
  List<String> get tagNames => tags.map((t) => t.name).toList();

  /// 从 JSON 创建
  factory TagSuggestionResult.fromJson(Map<String, dynamic> json) {
    return TagSuggestionResult(
      tags:
          (json['tags'] as List<dynamic>?)
              ?.map((t) => SuggestedTag.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      analyzedText: json['analyzedText'] as String? ?? '',
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'tags': tags.map((t) => t.toJson()).toList(),
      'analyzedText': analyzedText,
    };
  }
}

/// 建议的标签
class SuggestedTag {
  /// 标签名称
  final String name;

  /// 置信度 (0.0 - 1.0)
  final double confidence;

  /// 推荐原因
  final String? reason;

  const SuggestedTag({
    required this.name,
    this.confidence = 1.0,
    this.reason,
  });

  /// 从 JSON 创建
  factory SuggestedTag.fromJson(Map<String, dynamic> json) {
    return SuggestedTag(
      name: json['name'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      reason: json['reason'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'confidence': confidence,
      'reason': reason,
    };
  }
}

/// 笔记分类
enum NoteClassification {
  /// 感悟
  insight,

  /// 摘录
  excerpt,

  /// 日记
  diary,

  /// 想法
  thought,

  /// 待办
  todo,

  /// 笔记
  note,

  /// 其他
  other,
}

/// 分类结果
class ClassificationResult {
  /// 分类类型
  final NoteClassification classification;

  /// 置信度 (0.0 - 1.0)
  final double confidence;

  /// 分类原因
  final String? reason;

  const ClassificationResult({
    this.classification = NoteClassification.other,
    this.confidence = 0.0,
    this.reason,
  });

  /// 空结果
  static const empty = ClassificationResult();

  /// 从 JSON 创建
  factory ClassificationResult.fromJson(Map<String, dynamic> json) {
    return ClassificationResult(
      classification: NoteClassification.values.firstWhere(
        (e) => e.name == json['classification'],
        orElse: () => NoteClassification.other,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reason: json['reason'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'classification': classification.name,
      'confidence': confidence,
      'reason': reason,
    };
  }
}

/// 情绪类型
enum EmotionType {
  /// 快乐
  happy,

  /// 悲伤
  sad,

  /// 愤怒
  angry,

  /// 恐惧
  fear,

  /// 惊讶
  surprise,

  /// 厌恶
  disgust,

  /// 平静
  neutral,

  /// 期待
  anticipation,

  /// 信任
  trust,
}

/// 情绪检测结果
class EmotionResult {
  /// 主要情绪
  final EmotionType primaryEmotion;

  /// 情绪强度 (0.0 - 1.0)
  final double intensity;

  /// 情绪分析详情
  final Map<EmotionType, double> emotionScores;

  /// 分析摘要
  final String? summary;

  const EmotionResult({
    this.primaryEmotion = EmotionType.neutral,
    this.intensity = 0.0,
    this.emotionScores = const {},
    this.summary,
  });

  /// 空结果
  static const empty = EmotionResult();

  /// 是否为中性情绪
  bool get isNeutral => primaryEmotion == EmotionType.neutral;

  /// 是否为正面情绪
  bool get isPositive =>
      primaryEmotion == EmotionType.happy ||
      primaryEmotion == EmotionType.surprise ||
      primaryEmotion == EmotionType.anticipation ||
      primaryEmotion == EmotionType.trust;

  /// 是否为负面情绪
  bool get isNegative =>
      primaryEmotion == EmotionType.sad ||
      primaryEmotion == EmotionType.angry ||
      primaryEmotion == EmotionType.fear ||
      primaryEmotion == EmotionType.disgust;

  /// 从 JSON 创建
  factory EmotionResult.fromJson(Map<String, dynamic> json) {
    final scoresJson = json['emotionScores'] as Map<String, dynamic>?;
    final scores = <EmotionType, double>{};

    if (scoresJson != null) {
      for (final entry in scoresJson.entries) {
        final emotion = EmotionType.values.firstWhere(
          (e) => e.name == entry.key,
          orElse: () => EmotionType.neutral,
        );
        scores[emotion] = (entry.value as num).toDouble();
      }
    }

    return EmotionResult(
      primaryEmotion: EmotionType.values.firstWhere(
        (e) => e.name == json['primaryEmotion'],
        orElse: () => EmotionType.neutral,
      ),
      intensity: (json['intensity'] as num?)?.toDouble() ?? 0.0,
      emotionScores: scores,
      summary: json['summary'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'primaryEmotion': primaryEmotion.name,
      'intensity': intensity,
      'emotionScores': emotionScores.map((k, v) => MapEntry(k.name, v)),
      'summary': summary,
    };
  }
}
