/// OCR 识别结果模型
///
/// 用于存储和处理图像文字识别的结果
library;

import 'dart:ui';

/// 文本块信息
class TextBlock {
  /// 识别的文本内容
  final String text;

  /// 文本块在图像中的边界框
  final Rect boundingBox;

  /// 置信度 (0.0 - 1.0)
  final double confidence;

  /// 识别语言
  final String? language;

  /// 是否被用户选中
  final bool isSelected;

  const TextBlock({
    required this.text,
    required this.boundingBox,
    this.confidence = 1.0,
    this.language,
    this.isSelected = false,
  });

  /// 复制并修改
  TextBlock copyWith({
    String? text,
    Rect? boundingBox,
    double? confidence,
    String? language,
    bool? isSelected,
  }) {
    return TextBlock(
      text: text ?? this.text,
      boundingBox: boundingBox ?? this.boundingBox,
      confidence: confidence ?? this.confidence,
      language: language ?? this.language,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  /// 从 JSON 创建
  factory TextBlock.fromJson(Map<String, dynamic> json) {
    final box = json['boundingBox'] as Map<String, dynamic>?;
    return TextBlock(
      text: json['text'] as String? ?? '',
      boundingBox:
          box != null
              ? Rect.fromLTWH(
                (box['left'] as num).toDouble(),
                (box['top'] as num).toDouble(),
                (box['width'] as num).toDouble(),
                (box['height'] as num).toDouble(),
              )
              : Rect.zero,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      language: json['language'] as String?,
      isSelected: json['isSelected'] as bool? ?? false,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'boundingBox': {
        'left': boundingBox.left,
        'top': boundingBox.top,
        'width': boundingBox.width,
        'height': boundingBox.height,
      },
      'confidence': confidence,
      'language': language,
      'isSelected': isSelected,
    };
  }
}

/// OCR 识别结果
class OCRResult {
  /// 完整识别文本
  final String fullText;

  /// 文本块列表（带位置信息）
  final List<TextBlock> blocks;

  /// 图像路径
  final String? imagePath;

  /// 识别耗时（毫秒）
  final int? processingTimeMs;

  /// 时间戳（可为空，在使用时提供默认值）
  final DateTime? _timestamp;

  /// 识别语言
  final List<String> languages;

  /// 获取时间戳（如果为空则返回当前时间）
  DateTime get timestamp => _timestamp ?? DateTime.now();

  const OCRResult({
    required this.fullText,
    this.blocks = const [],
    this.imagePath,
    this.processingTimeMs,
    DateTime? timestamp,
    this.languages = const ['chi_sim', 'eng'],
  }) : _timestamp = timestamp;

  /// 空结果
  static const empty = OCRResult(fullText: '');

  /// 是否为空
  bool get isEmpty => fullText.trim().isEmpty;

  /// 是否非空
  bool get isNotEmpty => !isEmpty;

  /// 获取选中的文本块
  List<TextBlock> get selectedBlocks => blocks.where((b) => b.isSelected).toList();

  /// 获取选中的文本
  String get selectedText =>
      selectedBlocks.map((b) => b.text).join('\n').trim();

  /// 从 JSON 创建
  factory OCRResult.fromJson(Map<String, dynamic> json) {
    return OCRResult(
      fullText: json['fullText'] as String? ?? '',
      blocks:
          (json['blocks'] as List<dynamic>?)
              ?.map((b) => TextBlock.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      imagePath: json['imagePath'] as String?,
      processingTimeMs: json['processingTimeMs'] as int?,
      timestamp:
          json['timestamp'] != null
              ? DateTime.parse(json['timestamp'] as String)
              : null,
      languages:
          (json['languages'] as List<dynamic>?)?.cast<String>() ??
          const ['chi_sim', 'eng'],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'fullText': fullText,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'imagePath': imagePath,
      'processingTimeMs': processingTimeMs,
      'timestamp': timestamp.toIso8601String(),
      'languages': languages,
    };
  }

  /// 复制并修改
  OCRResult copyWith({
    String? fullText,
    List<TextBlock>? blocks,
    String? imagePath,
    int? processingTimeMs,
    DateTime? timestamp,
    List<String>? languages,
  }) {
    return OCRResult(
      fullText: fullText ?? this.fullText,
      blocks: blocks ?? this.blocks,
      imagePath: imagePath ?? this.imagePath,
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      timestamp: timestamp ?? _timestamp,
      languages: languages ?? this.languages,
    );
  }

  @override
  String toString() {
    return 'OCRResult(fullText: ${fullText.length} chars, blocks: ${blocks.length}, languages: $languages)';
  }
}

/// OCR 处理状态
enum OCRState {
  /// 空闲
  idle,

  /// 正在捕获
  capturing,

  /// 正在处理
  processing,

  /// 已完成
  completed,

  /// 错误
  error,
}

/// OCR 状态信息
class OCRStatus {
  /// 当前状态
  final OCRState state;

  /// 进度 (0.0 - 1.0)
  final double progress;

  /// 错误信息
  final String? errorMessage;

  const OCRStatus({
    this.state = OCRState.idle,
    this.progress = 0.0,
    this.errorMessage,
  });

  /// 空闲状态
  static const idle = OCRStatus();

  /// 是否正在处理
  bool get isProcessing => state == OCRState.processing;

  /// 是否有错误
  bool get hasError => state == OCRState.error;

  /// 复制并修改
  OCRStatus copyWith({
    OCRState? state,
    double? progress,
    String? errorMessage,
  }) {
    return OCRStatus(
      state: state ?? this.state,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
