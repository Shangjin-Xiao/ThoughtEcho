import 'package:flutter/foundation.dart';

/// ASR 模型类型
enum ASRModelType {
  /// Whisper 模型 (OpenAI)
  whisper,

  /// Paraformer 模型 (阿里达摩院)
  paraformer,

  /// Zipformer 模型
  zipformer,
}

/// ASR 模型配置
///
/// 说明：
/// - 当前项目优先使用 sherpa-onnx 的离线 Whisper 模型。
/// - 模型文件需要存在于本地磁盘；在移动端/桌面端会自动“首次使用下载并解压”。
@immutable
class ASRModelConfig {
  /// 模型 ID
  final String modelId;

  /// 模型类型
  final ASRModelType type;

  /// 采样率（Whisper 常用 16000）
  final int sampleRate;

  /// 语言："auto" 表示自动（传给 sherpa-onnx 时会转为空字符串）。
  final String language;

  /// 预训练模型压缩包（tar.bz2）的下载地址（仅 io 平台使用）
  final String? archiveUrl;

  /// tar 解压后的根目录名（例如 sherpa-onnx-whisper-tiny）
  final String? extractedDirName;

  /// Whisper encoder 文件名
  final String? whisperEncoderFile;

  /// Whisper decoder 文件名
  final String? whisperDecoderFile;

  /// tokens 文件名
  final String? tokensFile;

  /// Whisper tail paddings。
  ///
  /// sherpa-onnx 推荐：
  /// - 英文模型：50
  /// - 多语言模型：300
  final int tailPaddings;

  const ASRModelConfig({
    required this.modelId,
    required this.type,
    required this.sampleRate,
    required this.language,
    this.archiveUrl,
    this.extractedDirName,
    this.whisperEncoderFile,
    this.whisperDecoderFile,
    this.tokensFile,
    this.tailPaddings = -1,
  });

  /// 当前配置是否具备可自动下载/解压的 Whisper 文件信息
  bool get hasWhisperBundleInfo {
    return type == ASRModelType.whisper &&
        archiveUrl != null &&
        extractedDirName != null &&
        whisperEncoderFile != null &&
        whisperDecoderFile != null &&
        tokensFile != null;
  }

  @override
  String toString() => 'ASRModelConfig(modelId: $modelId, type: $type)';
}

/// 预设 ASR 模型
class ASRModels {
  /// Whisper tiny（多语言）
  ///
  /// 来源：
  /// https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2
  static const whisperTiny = ASRModelConfig(
    modelId: 'whisper-tiny',
    type: ASRModelType.whisper,
    sampleRate: 16000,
    language: 'auto',
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
    extractedDirName: 'sherpa-onnx-whisper-tiny',
    whisperEncoderFile: 'tiny-encoder.int8.onnx',
    whisperDecoderFile: 'tiny-decoder.int8.onnx',
    tokensFile: 'tiny-tokens.txt',
    tailPaddings: 300,
  );

  /// Paraformer 中文模型（预留；当前未接入）
  static const paraformerChinese = ASRModelConfig(
    modelId: 'paraformer-zh',
    type: ASRModelType.paraformer,
    sampleRate: 16000,
    language: 'zh',
  );
}

/// ASR 识别结果
@immutable
class ASRResult {
  /// 识别的文本
  final String text;

  /// 置信度 (0-1)
  final double confidence;

  /// 处理时间 (毫秒)
  final int processingTimeMs;

  /// 音频时长 (毫秒)
  final int audioDurationMs;

  /// 是否为最终结果
  final bool isFinal;

  const ASRResult({
    required this.text,
    this.confidence = 1.0,
    this.processingTimeMs = 0,
    this.audioDurationMs = 0,
    this.isFinal = true,
  });

  bool get isEmpty => text.trim().isEmpty;

  @override
  String toString() => 'ASRResult(text: "$text", confidence: $confidence)';
}
