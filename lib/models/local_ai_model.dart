/// 本地 AI 模型定义
///
/// 定义设备端 AI 模型的元数据和状态
library;

/// 用于 copyWith 中区分"未传值"与"传了 null"的哨兵对象
const _copyWithSentinel = Object();

/// 模型类型枚举
enum LocalAIModelType {
  /// LLM 模型 (Gemma 2B)
  llm,

  /// 嵌入模型 (Gecko)
  embedding,

  /// 语音识别模型 (Whisper/Paraformer/SenseVoice 等)
  asr,

  /// OCR 模型
  ocr,
}

/// ASR 模型架构枚举
///
/// 用于区分不同的语音识别模型类型，决定使用哪种 sherpa_onnx 配置类
enum AsrModelArchitecture {
  /// Whisper 离线模型 (OfflineWhisperModelConfig)
  whisper,

  /// Paraformer 离线模型 (OfflineParaformerModelConfig)
  paraformer,

  /// SenseVoice 离线模型 (OfflineSenseVoiceModelConfig)
  senseVoice,

  /// Zipformer2 CTC 流式模型 (OnlineZipformer2CtcModelConfig)
  zipformer2Ctc,

  /// Paraformer 流式模型 (OnlineParaformerModelConfig)
  streamingParaformer,

  /// Zipformer Transducer 流式模型 (OnlineTransducerModelConfig)
  streamingZipformer,

  /// Qwen3-ASR 离线模型 (OfflineQwen3AsrModelConfig)
  qwen3Asr,

  /// FunASR-Nano 离线模型 (OfflineFunAsrNanoModelConfig)
  funAsrNano,
}

/// ASR 模型能力标志
class AsrModelCapabilities {
  /// 是否支持流式识别（实时边录边识别）
  final bool isStreaming;

  /// 是否支持离线识别（录完再识别）
  final bool isOffline;

  /// 支持的语言列表
  final List<String> languages;

  const AsrModelCapabilities({
    required this.isStreaming,
    required this.isOffline,
    required this.languages,
  });
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

  /// 是否支持手动导入
  bool get supportsManualImport =>
      type == LocalAIModelType.asr ||
      type == LocalAIModelType.llm ||
      type == LocalAIModelType.embedding;

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
    Object? errorMessage = _copyWithSentinel,
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
      errorMessage: identical(errorMessage, _copyWithSentinel)
          ? this.errorMessage
          : errorMessage as String?,
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

  /// 从 Map 创建（兼容数据库序列化接口）
  factory LocalAIModelInfo.fromMap(Map<String, dynamic> map) {
    return LocalAIModelInfo.fromJson(map);
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

  /// 转换为 Map（兼容数据库序列化接口）
  Map<String, dynamic> toMap() {
    return toJson();
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

  // ==================== ASR 轻量模型 ====================

  /// Zipformer Small CTC 中文流式模型 - 最小流式模型
  static const zipformerSmallCtcZh = LocalAIModelInfo(
    id: 'zipformer-small-ctc-zh',
    name: 'Zipformer Small CTC 中文 (流式)',
    type: LocalAIModelType.asr,
    description: '极轻量中文流式语音识别模型，仅25MB，RTF 0.038，适合实时语音输入场景。仅支持中文。',
    sizeBytes: 21 * 1024 * 1024, // ~21MB (tar.bz2)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01.tar.bz2',
    fileName:
        'sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  /// Paraformer Small 中文离线模型 - 轻量离线模型
  static const paraformerZhSmall = LocalAIModelInfo(
    id: 'paraformer-zh-small',
    name: 'Paraformer Small 中文 (离线)',
    type: LocalAIModelType.asr,
    description: '轻量中文离线语音识别模型，仅79MB，支持中英双语及多种方言，CER约3-5%。',
    sizeBytes: 76 * 1024 * 1024, // ~76MB (tar.bz2)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-small-2024-03-09.tar.bz2',
    fileName: 'sherpa-onnx-paraformer-zh-small-2024-03-09.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  // ==================== ASR 流式模型 ====================

  /// Streaming Paraformer 中英双语流式模型
  static const streamingParaformerZhEn = LocalAIModelInfo(
    id: 'streaming-paraformer-zh-en',
    name: 'Paraformer 流式中英 (流式)',
    type: LocalAIModelType.asr,
    description: '中英双语流式语音识别模型，支持实时边录边识别，RTF 0.15，含中英及多种方言。',
    sizeBytes: 1023 * 1024 * 1024, // ~1GB (tar.bz2, 含fp32+int8)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2',
    fileName: 'sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  /// Streaming Zipformer 中文流式模型 (Transducer)
  static const streamingZipformerZh = LocalAIModelInfo(
    id: 'streaming-zipformer-zh',
    name: 'Zipformer 中文 (流式)',
    type: LocalAIModelType.asr,
    description: '中文流式语音识别模型（Transducer架构），RTF 0.15，仅支持中文。',
    sizeBytes: 130 * 1024 * 1024, // ~130MB (tar.bz2)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30.tar.bz2',
    fileName: 'sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  // ==================== ASR 高精度离线模型 ====================

  /// SenseVoice 多语言离线模型
  static const senseVoiceZhEnJaKoYue = LocalAIModelInfo(
    id: 'sense-voice-zh-en-ja-ko-yue',
    name: 'SenseVoice 多语言 (离线)',
    type: LocalAIModelType.asr,
    description: '多语言离线语音识别模型，支持中/英/日/韩/粤语，RTF 0.049，内置情感识别和音频事件检测。',
    sizeBytes: 228 * 1024 * 1024, // ~228MB (int8 only tar.bz2)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2',
    fileName: 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  /// Paraformer 中文离线模型 (高精度)
  static const paraformerZh = LocalAIModelInfo(
    id: 'paraformer-zh',
    name: 'Paraformer 中文高精度 (离线)',
    type: LocalAIModelType.asr,
    description: '中文离线语音识别高精度模型，CER 1.95%（AISHELL-1），支持中英双语及多种方言。',
    sizeBytes: 973 * 1024 * 1024, // ~973MB (tar.bz2, 含fp32+int8)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2',
    fileName: 'sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  // ==================== ASR 大模型 ====================

  /// Qwen3-ASR 0.6B 离线模型
  static const qwen3Asr = LocalAIModelInfo(
    id: 'qwen3-asr-0.6b',
    name: 'Qwen3-ASR 0.6B (离线)',
    type: LocalAIModelType.asr,
    description: '通义千问语音识别模型，支持30+语言（含20+中文方言），LLM架构，精度极高但体积大。',
    sizeBytes: 939 * 1024 * 1024, // ~939MB (tar.bz2)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2',
    fileName: 'sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2',
    version: '1.0',
    isRequired: false,
  );

  /// FunASR-Nano 离线模型
  static const funAsrNano = LocalAIModelInfo(
    id: 'funasr-nano',
    name: 'FunASR-Nano (离线)',
    type: LocalAIModelType.asr,
    description: 'FunASR Nano语音识别模型，支持7种中文方言+26种口音+日英，含歌词/说唱识别能力。体积大，推理较慢。',
    sizeBytes: 948 * 1024 * 1024, // ~948MB (tar.bz2)
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2',
    fileName: 'sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2',
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
        // ASR 轻量模型
        zipformerSmallCtcZh,
        paraformerZhSmall,
        whisperTiny,
        whisperBase,
        // ASR 流式模型
        streamingParaformerZhEn,
        streamingZipformerZh,
        // ASR 高精度离线模型
        senseVoiceZhEnJaKoYue,
        paraformerZh,
        // ASR 大模型
        qwen3Asr,
        funAsrNano,
        // OCR 模型
        paliGemma3B,
      ];

  /// 按类型获取模型
  static List<LocalAIModelInfo> byType(LocalAIModelType type) {
    return all.where((m) => m.type == type).toList();
  }

  /// ASR 模型 ID 到架构的映射
  static const Map<String, AsrModelArchitecture> asrArchitectures = {
    'whisper-tiny': AsrModelArchitecture.whisper,
    'whisper-base': AsrModelArchitecture.whisper,
    'zipformer-small-ctc-zh': AsrModelArchitecture.zipformer2Ctc,
    'paraformer-zh-small': AsrModelArchitecture.paraformer,
    'streaming-paraformer-zh-en': AsrModelArchitecture.streamingParaformer,
    'streaming-zipformer-zh': AsrModelArchitecture.streamingZipformer,
    'sense-voice-zh-en-ja-ko-yue': AsrModelArchitecture.senseVoice,
    'paraformer-zh': AsrModelArchitecture.paraformer,
    'qwen3-asr-0.6b': AsrModelArchitecture.qwen3Asr,
    'funasr-nano': AsrModelArchitecture.funAsrNano,
  };

  /// 获取 ASR 模型的架构类型
  static AsrModelArchitecture? getAsrArchitecture(String modelId) {
    return asrArchitectures[modelId];
  }

  /// 判断 ASR 模型是否为流式模型
  static bool isStreamingAsr(String modelId) {
    final arch = getAsrArchitecture(modelId);
    if (arch == null) return false;
    return arch == AsrModelArchitecture.zipformer2Ctc ||
        arch == AsrModelArchitecture.streamingParaformer ||
        arch == AsrModelArchitecture.streamingZipformer;
  }

  /// ASR 模型能力映射
  static const Map<String, AsrModelCapabilities> asrCapabilities = {
    'whisper-tiny': AsrModelCapabilities(
      isStreaming: false,
      isOffline: true,
      languages: ['zh', 'en', 'ja', 'ko', '多语言'],
    ),
    'whisper-base': AsrModelCapabilities(
      isStreaming: false,
      isOffline: true,
      languages: ['zh', 'en', 'ja', 'ko', '多语言'],
    ),
    'zipformer-small-ctc-zh': AsrModelCapabilities(
      isStreaming: true,
      isOffline: false,
      languages: ['zh'],
    ),
    'paraformer-zh-small': AsrModelCapabilities(
      isStreaming: false,
      isOffline: true,
      languages: ['zh', 'en'],
    ),
    'streaming-paraformer-zh-en': AsrModelCapabilities(
      isStreaming: true,
      isOffline: false,
      languages: ['zh', 'en'],
    ),
    'streaming-zipformer-zh': AsrModelCapabilities(
      isStreaming: true,
      isOffline: false,
      languages: ['zh'],
    ),
    'sense-voice-zh-en-ja-ko-yue': AsrModelCapabilities(
      isStreaming: false,
      isOffline: true,
      languages: ['zh', 'en', 'ja', 'ko', 'yue'],
    ),
    'paraformer-zh': AsrModelCapabilities(
      isStreaming: false,
      isOffline: true,
      languages: ['zh', 'en'],
    ),
    'qwen3-asr-0.6b': AsrModelCapabilities(
      isStreaming: false,
      isOffline: true,
      languages: ['zh', 'en', 'ja', 'ko', 'de', 'fr', 'es', '等30+语言'],
    ),
    'funasr-nano': AsrModelCapabilities(
      isStreaming: false,
      isOffline: true,
      languages: ['zh', 'en', 'ja', '7种方言', '26种口音'],
    ),
  };

  /// 获取 ASR 模型能力
  static AsrModelCapabilities? getAsrCapabilities(String modelId) {
    return asrCapabilities[modelId];
  }
}
