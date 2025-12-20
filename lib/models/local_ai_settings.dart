/// 本地 AI 功能设置模型
/// 
/// 控制设备端 AI 功能的各项开关设置
class LocalAISettings {
  /// 总开关 (Preview 标记)
  final bool enabled;
  
  /// 语音转文字开关
  final bool speechToTextEnabled;
  
  /// OCR 文字识别开关
  final bool ocrEnabled;
  
  /// AI 语义搜索开关
  final bool aiSearchEnabled;
  
  /// AI 识别纠错开关
  final bool aiCorrectionEnabled;
  
  /// 智能识别来源开关
  final bool sourceRecognitionEnabled;
  
  /// 智能标签推荐开关
  final bool smartTagsEnabled;
  
  /// 笔记类型分类开关
  final bool noteClassificationEnabled;
  
  /// 情绪检测开关
  final bool emotionDetectionEnabled;
  
  /// 相关笔记推荐开关
  final bool relatedNotesEnabled;

  const LocalAISettings({
    this.enabled = false,
    this.speechToTextEnabled = true,
    this.ocrEnabled = true,
    this.aiSearchEnabled = true,
    this.aiCorrectionEnabled = true,
    this.sourceRecognitionEnabled = true,
    this.smartTagsEnabled = true,
    this.noteClassificationEnabled = true,
    this.emotionDetectionEnabled = true,
    this.relatedNotesEnabled = true,
  });

  /// 默认设置
  factory LocalAISettings.defaultSettings() => const LocalAISettings();

  /// 从 JSON 创建实例
  factory LocalAISettings.fromJson(Map<String, dynamic> json) {
    return LocalAISettings(
      enabled: json['enabled'] as bool? ?? false,
      speechToTextEnabled: json['speechToTextEnabled'] as bool? ?? true,
      ocrEnabled: json['ocrEnabled'] as bool? ?? true,
      aiSearchEnabled: json['aiSearchEnabled'] as bool? ?? true,
      aiCorrectionEnabled: json['aiCorrectionEnabled'] as bool? ?? true,
      sourceRecognitionEnabled: json['sourceRecognitionEnabled'] as bool? ?? true,
      smartTagsEnabled: json['smartTagsEnabled'] as bool? ?? true,
      noteClassificationEnabled: json['noteClassificationEnabled'] as bool? ?? true,
      emotionDetectionEnabled: json['emotionDetectionEnabled'] as bool? ?? true,
      relatedNotesEnabled: json['relatedNotesEnabled'] as bool? ?? true,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'speechToTextEnabled': speechToTextEnabled,
      'ocrEnabled': ocrEnabled,
      'aiSearchEnabled': aiSearchEnabled,
      'aiCorrectionEnabled': aiCorrectionEnabled,
      'sourceRecognitionEnabled': sourceRecognitionEnabled,
      'smartTagsEnabled': smartTagsEnabled,
      'noteClassificationEnabled': noteClassificationEnabled,
      'emotionDetectionEnabled': emotionDetectionEnabled,
      'relatedNotesEnabled': relatedNotesEnabled,
    };
  }

  /// 复制并修改
  LocalAISettings copyWith({
    bool? enabled,
    bool? speechToTextEnabled,
    bool? ocrEnabled,
    bool? aiSearchEnabled,
    bool? aiCorrectionEnabled,
    bool? sourceRecognitionEnabled,
    bool? smartTagsEnabled,
    bool? noteClassificationEnabled,
    bool? emotionDetectionEnabled,
    bool? relatedNotesEnabled,
  }) {
    return LocalAISettings(
      enabled: enabled ?? this.enabled,
      speechToTextEnabled: speechToTextEnabled ?? this.speechToTextEnabled,
      ocrEnabled: ocrEnabled ?? this.ocrEnabled,
      aiSearchEnabled: aiSearchEnabled ?? this.aiSearchEnabled,
      aiCorrectionEnabled: aiCorrectionEnabled ?? this.aiCorrectionEnabled,
      sourceRecognitionEnabled: sourceRecognitionEnabled ?? this.sourceRecognitionEnabled,
      smartTagsEnabled: smartTagsEnabled ?? this.smartTagsEnabled,
      noteClassificationEnabled: noteClassificationEnabled ?? this.noteClassificationEnabled,
      emotionDetectionEnabled: emotionDetectionEnabled ?? this.emotionDetectionEnabled,
      relatedNotesEnabled: relatedNotesEnabled ?? this.relatedNotesEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalAISettings &&
        other.enabled == enabled &&
        other.speechToTextEnabled == speechToTextEnabled &&
        other.ocrEnabled == ocrEnabled &&
        other.aiSearchEnabled == aiSearchEnabled &&
        other.aiCorrectionEnabled == aiCorrectionEnabled &&
        other.sourceRecognitionEnabled == sourceRecognitionEnabled &&
        other.smartTagsEnabled == smartTagsEnabled &&
        other.noteClassificationEnabled == noteClassificationEnabled &&
        other.emotionDetectionEnabled == emotionDetectionEnabled &&
        other.relatedNotesEnabled == relatedNotesEnabled;
  }

  @override
  int get hashCode {
    return Object.hash(
      enabled,
      speechToTextEnabled,
      ocrEnabled,
      aiSearchEnabled,
      aiCorrectionEnabled,
      sourceRecognitionEnabled,
      smartTagsEnabled,
      noteClassificationEnabled,
      emotionDetectionEnabled,
      relatedNotesEnabled,
    );
  }

  @override
  String toString() {
    return 'LocalAISettings('
        'enabled: $enabled, '
        'speechToTextEnabled: $speechToTextEnabled, '
        'ocrEnabled: $ocrEnabled, '
        'aiSearchEnabled: $aiSearchEnabled, '
        'aiCorrectionEnabled: $aiCorrectionEnabled, '
        'sourceRecognitionEnabled: $sourceRecognitionEnabled, '
        'smartTagsEnabled: $smartTagsEnabled, '
        'noteClassificationEnabled: $noteClassificationEnabled, '
        'emotionDetectionEnabled: $emotionDetectionEnabled, '
        'relatedNotesEnabled: $relatedNotesEnabled)';
  }
}
