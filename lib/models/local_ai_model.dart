/// 本地 AI 模型定义
///
/// 定义设备端 AI 模型的元数据和状态
library;

/// 模型类型枚举
enum LocalAIModelType {
  /// LLM 模型 (Gemma 2B)
  llm,

  /// 嵌入模型 (Gecko)
  embedding,

  /// 语音识别模型 (Whisper)
  asr,

  /// OCR 模型 (Tesseract)
  ocr,
}

/// 模型状态枚举
enum LocalAIModelStatus {
  /// 未下载
  notDownloaded,

  /// 下载中
  downloading,

  /// 已下载
  downloaded,

  /// 加载中
  loading,

  /// 已加载
  loaded,

  /// 错误
  error,
}

/// 本地 AI 模型信息
class LocalAIModelInfo {
  /// 模型唯一标识
  final String id;

  /// 模型显示名称
  final String name;

  /// 模型类型
  final LocalAIModelType type;

  /// 模型描述
  final String description;

  /// 模型大小（字节）
  final int sizeBytes;

  /// 下载 URL
  final String downloadUrl;

  /// 模型文件名
  final String fileName;

  /// 当前状态
  final LocalAIModelStatus status;

  /// 下载进度 (0.0 - 1.0)
  final double downloadProgress;

  /// 错误信息
  final String? errorMessage;

  /// 模型版本
  final String version;

  /// 是否必需
  final bool isRequired;

  const LocalAIModelInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.sizeBytes,
    required this.downloadUrl,
    required this.fileName,
    this.status = LocalAIModelStatus.notDownloaded,
    this.downloadProgress = 0.0,
    this.errorMessage,
    required this.version,
    this.isRequired = false,
  });

  /// 格式化显示大小
  String get formattedSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    } else if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    } else if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 复制并更新状态
  LocalAIModelInfo copyWith({
    String? id,
    String? name,
    LocalAIModelType? type,
    String? description,
    int? sizeBytes,
    String? downloadUrl,
    String? fileName,
    LocalAIModelStatus? status,
    double? downloadProgress,
    String? errorMessage,
    String? version,
    bool? isRequired,
  }) {
    return LocalAIModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
      version: version ?? this.version,
      isRequired: isRequired ?? this.isRequired,
    );
  }

  /// 从 JSON 创建
  factory LocalAIModelInfo.fromJson(Map<String, dynamic> json) {
    return LocalAIModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      type: LocalAIModelType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => LocalAIModelType.llm,
      ),
      description: json['description'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      status: LocalAIModelStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => LocalAIModelStatus.notDownloaded,
      ),
      downloadProgress: (json['downloadProgress'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['errorMessage'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      isRequired: json['isRequired'] as bool? ?? false,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'description': description,
      'sizeBytes': sizeBytes,
      'downloadUrl': downloadUrl,
      'fileName': fileName,
      'status': status.name,
      'downloadProgress': downloadProgress,
      'errorMessage': errorMessage,
      'version': version,
      'isRequired': isRequired,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalAIModelInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 预定义的模型配置
class LocalAIModels {
  /// Gemma 2B LLM 模型
  /// 注意：这些模型需要通过 flutter_gemma 包进行下载和管理
  /// 此处的 URL 是信息性的，实际下载由 flutter_gemma 处理
  static const gemma2b = LocalAIModelInfo(
    id: 'gemma-2b',
    name: 'Gemma 2B',
    type: LocalAIModelType.llm,
    description: 'Google Gemma 2B 语言模型，用于文本纠错、来源识别、标签推荐等。需要通过flutter_gemma下载。',
    sizeBytes: 1500 * 1024 * 1024, // ~1.5GB
    downloadUrl: 'managed://flutter_gemma/gemma-2b', // 由 flutter_gemma 管理
    fileName: 'gemma-2b.task',
    version: '2.0',
    isRequired: false,
  );

  /// Gecko 嵌入模型
  static const gecko384 = LocalAIModelInfo(
    id: 'gecko-384',
    name: 'Gecko 384D',
    type: LocalAIModelType.embedding,
    description: 'Google Gecko 384维嵌入模型，用于语义搜索和相关笔记推荐。需要通过flutter_gemma下载。',
    sizeBytes: 150 * 1024 * 1024, // ~150MB
    downloadUrl: 'managed://flutter_gemma/gecko-384', // 由 flutter_gemma 管理
    fileName: 'gecko-384.task',
    version: '1.0',
    isRequired: false,
  );

  /// Whisper Tiny ASR 模型 - sherpa-onnx 预编译模型（中文优化）
  /// 使用多语言模型支持中文识别
  static const whisperTiny = LocalAIModelInfo(
    id: 'whisper-tiny',
    name: 'Whisper Tiny (多语言)',
    type: LocalAIModelType.asr,
    description: 'OpenAI Whisper Tiny 多语言语音识别模型，轻量快速，支持中文',
    sizeBytes: 75 * 1024 * 1024, // ~75MB (包含3个文件)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
    fileName: 'sherpa-onnx-whisper-tiny.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  /// Whisper Base ASR 模型 - sherpa-onnx 预编译模型（中文优化）
  static const whisperBase = LocalAIModelInfo(
    id: 'whisper-base',
    name: 'Whisper Base (多语言)',
    type: LocalAIModelType.asr,
    description: 'OpenAI Whisper Base 多语言语音识别模型，准确率更高，支持中文',
    sizeBytes: 145 * 1024 * 1024, // ~145MB
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2',
    fileName: 'sherpa-onnx-whisper-base.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  /// PaliGemma 视觉语言模型（推荐用于手写 OCR）
  /// 通过 flutter_gemma 管理和加载
  static const paliGemma3B = LocalAIModelInfo(
    id: 'paligemma-3b',
    name: 'PaliGemma 3B (手写识别)',
    type: LocalAIModelType.ocr,
    description:
        'Google PaliGemma 视觉语言模型，专为图像理解和手写 OCR 优化，识别准确率远超传统 OCR。需要通过 flutter_gemma 下载。',
    sizeBytes: 3000 * 1024 * 1024, // ~3GB
    downloadUrl:
        'managed://flutter_gemma/paligemma-3b-mix-224', // 由 flutter_gemma 管理
    fileName: 'paligemma-3b.task',
    version: '1.0',
    isRequired: false,
  );

  // 注：其他 VLM 模型（Qwen-VL、MobileVLM）暂不支持 flutter_gemma
  // 未来可以通过其他方式集成

  /// 获取所有预定义模型
  static List<LocalAIModelInfo> get all => [
        gemma2b,
        gecko384,
        whisperTiny,
        whisperBase,
        paliGemma3B, // flutter_gemma 支持
      ];

  /// 按类型获取模型
  static List<LocalAIModelInfo> byType(LocalAIModelType type) {
    return all.where((m) => m.type == type).toList();
  }
}
