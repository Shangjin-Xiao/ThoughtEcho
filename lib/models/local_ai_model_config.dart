/// Configuration for local AI models
/// 
/// Manages user-imported model paths and configurations for:
/// - TFLite embedding models
/// - ASR (Speech Recognition) models  
/// - OCR models

/// Types of local AI models
enum LocalAIModelType {
  /// TFLite embedding model for semantic search
  embedding,
  /// ASR model for speech-to-text
  asr,
  /// OCR model for text recognition
  ocr,
}

/// Status of a local AI model
enum LocalAIModelStatus {
  /// Model not configured
  notConfigured,
  /// Model file exists and ready
  ready,
  /// Model is being downloaded
  downloading,
  /// Model file missing or invalid
  invalid,
}

/// Configuration for a single local AI model
class LocalAIModelInfo {
  /// Unique identifier for this model
  final String id;
  
  /// Human-readable name
  final String name;
  
  /// Model type
  final LocalAIModelType type;
  
  /// Path to the model file
  final String? modelPath;
  
  /// Path to vocabulary file (for embedding models)
  final String? vocabPath;
  
  /// Model file size in bytes
  final int? fileSize;
  
  /// Model version or description
  final String? version;
  
  /// Current status
  final LocalAIModelStatus status;
  
  /// Last update timestamp
  final DateTime? lastUpdated;
  
  const LocalAIModelInfo({
    required this.id,
    required this.name,
    required this.type,
    this.modelPath,
    this.vocabPath,
    this.fileSize,
    this.version,
    this.status = LocalAIModelStatus.notConfigured,
    this.lastUpdated,
  });
  
  /// Check if model is ready for use
  bool get isReady => status == LocalAIModelStatus.ready && modelPath != null;
  
  /// Create from JSON
  factory LocalAIModelInfo.fromJson(Map<String, dynamic> json) {
    return LocalAIModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: LocalAIModelType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => LocalAIModelType.embedding,
      ),
      modelPath: json['modelPath'] as String?,
      vocabPath: json['vocabPath'] as String?,
      fileSize: json['fileSize'] as int?,
      version: json['version'] as String?,
      status: LocalAIModelStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => LocalAIModelStatus.notConfigured,
      ),
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.tryParse(json['lastUpdated'] as String)
          : null,
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'modelPath': modelPath,
      'vocabPath': vocabPath,
      'fileSize': fileSize,
      'version': version,
      'status': status.name,
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }
  
  /// Copy with modifications
  LocalAIModelInfo copyWith({
    String? id,
    String? name,
    LocalAIModelType? type,
    String? modelPath,
    String? vocabPath,
    int? fileSize,
    String? version,
    LocalAIModelStatus? status,
    DateTime? lastUpdated,
  }) {
    return LocalAIModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      modelPath: modelPath ?? this.modelPath,
      vocabPath: vocabPath ?? this.vocabPath,
      fileSize: fileSize ?? this.fileSize,
      version: version ?? this.version,
      status: status ?? this.status,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalAIModelInfo &&
        other.id == id &&
        other.name == name &&
        other.type == type &&
        other.modelPath == modelPath &&
        other.vocabPath == vocabPath &&
        other.fileSize == fileSize &&
        other.version == version &&
        other.status == status;
  }
  
  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      type,
      modelPath,
      vocabPath,
      fileSize,
      version,
      status,
    );
  }
}

/// Configuration for all local AI models
class LocalAIModelConfig {
  /// Embedding model configuration
  final LocalAIModelInfo? embeddingModel;
  
  /// ASR (Speech Recognition) model configuration
  final LocalAIModelInfo? asrModel;
  
  /// OCR model configuration
  final LocalAIModelInfo? ocrModel;
  
  /// OCR language data paths (for Tesseract)
  final List<String> ocrLanguagePaths;
  
  const LocalAIModelConfig({
    this.embeddingModel,
    this.asrModel,
    this.ocrModel,
    this.ocrLanguagePaths = const [],
  });
  
  /// Default configuration
  factory LocalAIModelConfig.defaultConfig() => const LocalAIModelConfig();
  
  /// Create from JSON
  factory LocalAIModelConfig.fromJson(Map<String, dynamic> json) {
    return LocalAIModelConfig(
      embeddingModel: json['embeddingModel'] != null
          ? LocalAIModelInfo.fromJson(
              json['embeddingModel'] as Map<String, dynamic>)
          : null,
      asrModel: json['asrModel'] != null
          ? LocalAIModelInfo.fromJson(json['asrModel'] as Map<String, dynamic>)
          : null,
      ocrModel: json['ocrModel'] != null
          ? LocalAIModelInfo.fromJson(json['ocrModel'] as Map<String, dynamic>)
          : null,
      ocrLanguagePaths: (json['ocrLanguagePaths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'embeddingModel': embeddingModel?.toJson(),
      'asrModel': asrModel?.toJson(),
      'ocrModel': ocrModel?.toJson(),
      'ocrLanguagePaths': ocrLanguagePaths,
    };
  }
  
  /// Copy with modifications
  LocalAIModelConfig copyWith({
    LocalAIModelInfo? embeddingModel,
    LocalAIModelInfo? asrModel,
    LocalAIModelInfo? ocrModel,
    List<String>? ocrLanguagePaths,
    bool clearEmbeddingModel = false,
    bool clearAsrModel = false,
    bool clearOcrModel = false,
  }) {
    return LocalAIModelConfig(
      embeddingModel: clearEmbeddingModel
          ? null
          : (embeddingModel ?? this.embeddingModel),
      asrModel: clearAsrModel ? null : (asrModel ?? this.asrModel),
      ocrModel: clearOcrModel ? null : (ocrModel ?? this.ocrModel),
      ocrLanguagePaths: ocrLanguagePaths ?? this.ocrLanguagePaths,
    );
  }
  
  /// Check if any model is configured
  bool get hasAnyModel =>
      embeddingModel != null || asrModel != null || ocrModel != null;
  
  /// Check if embedding is ready
  bool get isEmbeddingReady => embeddingModel?.isReady ?? false;
  
  /// Check if ASR is ready
  bool get isAsrReady => asrModel?.isReady ?? false;
  
  /// Check if OCR is ready
  bool get isOcrReady => ocrModel?.isReady ?? false;
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalAIModelConfig &&
        other.embeddingModel == embeddingModel &&
        other.asrModel == asrModel &&
        other.ocrModel == ocrModel;
  }
  
  @override
  int get hashCode => Object.hash(embeddingModel, asrModel, ocrModel);
}

/// Recommended model download links
class LocalAIModelRecommendations {
  /// Recommended embedding models
  static const List<Map<String, String>> embeddingModels = [
    {
      'name': 'paraphrase-multilingual-MiniLM-L12-v2 (TFLite)',
      'description': '25MB, 384 dimensions, 50+ languages',
      'url':
          'https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2',
      'size': '~25MB',
    },
  ];
  
  /// Recommended ASR models (Whisper ONNX)
  static const List<Map<String, String>> asrModels = [
    {
      'name': 'Whisper Tiny (ONNX)',
      'description': '39MB, fast, suitable for short audio',
      'url': 'https://github.com/openai/whisper',
      'size': '~39MB',
    },
    {
      'name': 'Whisper Base (ONNX)',
      'description': '74MB, better accuracy',
      'url': 'https://github.com/openai/whisper',
      'size': '~74MB',
    },
  ];
  
  /// Recommended OCR models
  static const List<Map<String, String>> ocrModels = [
    {
      'name': 'Tesseract chi_sim+eng',
      'description': 'Chinese Simplified + English',
      'url': 'https://github.com/tesseract-ocr/tessdata',
      'size': '~30MB',
    },
    {
      'name': 'PaddleOCR Lite',
      'description': '~8MB, optimized for Chinese',
      'url': 'https://github.com/PaddlePaddle/PaddleOCR',
      'size': '~8MB',
    },
  ];
}
