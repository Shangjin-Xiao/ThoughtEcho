/// 语音识别结果模型
///
/// 用于存储和处理语音转文字的结果
library;

/// 语音识别结果
class SpeechRecognitionResult {
  /// 识别出的文本
  final String text;

  /// 置信度 (0.0 - 1.0)
  final double confidence;

  /// 识别语言代码
  final String? languageCode;

  /// 是否为最终结果（非流式中间结果）
  final bool isFinal;

  /// 识别时长（毫秒）
  final int? durationMs;

  /// 时间戳
  final DateTime _timestamp;

  /// 获取时间戳
  DateTime get timestamp => _timestamp;

  SpeechRecognitionResult({
    required this.text,
    this.confidence = 1.0,
    this.languageCode,
    this.isFinal = true,
    this.durationMs,
    DateTime? timestamp,
  }) : _timestamp = timestamp ?? DateTime.now();

  /// 空结果
  /// 空结果
  static final empty = SpeechRecognitionResult(text: '');

  /// 是否为空
  bool get isEmpty => text.trim().isEmpty;

  /// 是否非空
  bool get isNotEmpty => !isEmpty;

  /// 从 JSON 创建
  factory SpeechRecognitionResult.fromJson(Map<String, dynamic> json) {
    return SpeechRecognitionResult(
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      languageCode: json['languageCode'] as String?,
      isFinal: json['isFinal'] as bool? ?? true,
      durationMs: json['durationMs'] as int?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'confidence': confidence,
      'languageCode': languageCode,
      'isFinal': isFinal,
      'durationMs': durationMs,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// 复制并修改
  SpeechRecognitionResult copyWith({
    String? text,
    double? confidence,
    String? languageCode,
    bool? isFinal,
    int? durationMs,
    DateTime? timestamp,
  }) {
    return SpeechRecognitionResult(
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      languageCode: languageCode ?? this.languageCode,
      isFinal: isFinal ?? this.isFinal,
      durationMs: durationMs ?? this.durationMs,
      timestamp: timestamp ?? _timestamp,
    );
  }

  @override
  String toString() {
    return 'SpeechRecognitionResult(text: $text, confidence: $confidence, isFinal: $isFinal)';
  }
}

/// 语音录制状态
enum RecordingState {
  /// 空闲
  idle,

  /// 正在录制
  recording,

  /// 正在处理
  processing,

  /// 已完成
  completed,

  /// 错误
  error,
}

/// 录制状态信息
class RecordingStatus {
  /// 当前状态
  final RecordingState state;

  /// 录制时长（秒）
  final double durationSeconds;

  /// 当前音量级别 (0.0 - 1.0)
  final double volumeLevel;

  /// 错误信息
  final String? errorMessage;

  const RecordingStatus({
    this.state = RecordingState.idle,
    this.durationSeconds = 0.0,
    this.volumeLevel = 0.0,
    this.errorMessage,
  });

  /// 空闲状态
  static const idle = RecordingStatus();

  /// 是否正在录制
  bool get isRecording => state == RecordingState.recording;

  /// 是否正在处理
  bool get isProcessing => state == RecordingState.processing;

  /// 是否有错误
  bool get hasError => state == RecordingState.error;

  /// 复制并修改
  RecordingStatus copyWith({
    RecordingState? state,
    double? durationSeconds,
    double? volumeLevel,
    String? errorMessage,
  }) {
    return RecordingStatus(
      state: state ?? this.state,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      volumeLevel: volumeLevel ?? this.volumeLevel,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
