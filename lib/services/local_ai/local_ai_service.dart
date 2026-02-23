/// 本地 AI 服务
///
/// 整合所有设备端 AI 功能的入口服务
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/local_ai_settings.dart';
import '../../models/local_ai_model.dart';
import '../../models/speech_recognition_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';
import 'speech_recognition_service.dart';

/// 本地 AI 功能标识
class LocalAIFeature {
  static const String speechToText = 'speechToText';
  static const String ocr = 'ocr';
  static const String aiCorrection = 'aiCorrection';
  static const String sourceRecognition = 'sourceRecognition';
  static const String aiSearch = 'aiSearch';
  static const String relatedNotes = 'relatedNotes';
  static const String smartTags = 'smartTags';
  static const String noteClassification = 'noteClassification';
  static const String emotionDetection = 'emotionDetection';
}

/// 本地 AI 服务
class LocalAIService extends ChangeNotifier {
  static LocalAIService? _instance;

  /// 单例实例
  static LocalAIService get instance {
    _instance ??= LocalAIService._();
    return _instance!;
  }

  LocalAIService._();

  // 子服务
  final ModelManager _modelManager = ModelManager.instance;
  final SpeechRecognitionService _speechService =
      SpeechRecognitionService.instance;
  // final OCRService _ocrService = OCRService.instance; // Tesseract 已移除

  /// 当前设置
  LocalAISettings _settings = LocalAISettings.defaultSettings();

  /// 是否已初始化
  bool _initialized = false;

  /// 获取是否已初始化
  bool get isInitialized => _initialized;

  /// 获取当前设置
  LocalAISettings get settings => _settings;

  /// 获取模型管理器
  ModelManager get modelManager => _modelManager;

  /// 获取语音识别服务
  SpeechRecognitionService get speechService => _speechService;

  // OCRService get ocrService => _ocrService; // Tesseract 已移除

  /// 初始化本地 AI 服务
  Future<void> initialize(
    LocalAISettings settings, {
    bool eagerLoadModels = true,
  }) async {
    if (_initialized) {
      // 更新设置
      _settings = settings;
      notifyListeners();
      return;
    }

    try {
      _settings = settings;

      // 初始化模型管理器
      await _modelManager.initialize();

      // 根据设置初始化各个子服务
      if (settings.enabled) {
        if (settings.speechToTextEnabled) {
          await _speechService.initialize(eagerLoadModel: eagerLoadModels);
        }
        if (settings.ocrEnabled) {
          // await _ocrService.initialize(); // Tesseract 已移除
        }
      }

      _initialized = true;
      notifyListeners();

      logInfo('本地 AI 服务初始化完成', source: 'LocalAIService');
    } catch (e) {
      logError('本地 AI 服务初始化失败: $e', source: 'LocalAIService');
      rethrow;
    }
  }

  /// 更新设置
  Future<void> updateSettings(LocalAISettings settings) async {
    _settings = settings;

    // 如果总开关关闭，不需要初始化子服务
    if (!settings.enabled) {
      notifyListeners();
      return;
    }

    // 懒初始化各个子服务
    if (settings.speechToTextEnabled && !_speechService.isInitialized) {
      await _speechService.initialize();
    }
    // if (settings.ocrEnabled && !_ocrService.isInitialized) { // Tesseract 已移除
    //   await _ocrService.initialize();
    // }

    notifyListeners();
    logDebug('本地 AI 设置已更新', source: 'LocalAIService');
  }

  /// 检查功能是否可用
  bool isFeatureAvailable(String feature) {
    if (!_settings.enabled) return false;

    switch (feature) {
      case LocalAIFeature.speechToText:
        return _settings.speechToTextEnabled && _speechService.isModelAvailable;

      case LocalAIFeature.aiCorrection:
        // Gemma 模型由 flutter_gemma 管理，ModelManager 不一定能反映其可用性。
        // 因此这里仅按“启用”判断；实际调用会自动降级或提示用户手动加载。
        return _settings.aiCorrectionEnabled;

      case LocalAIFeature.sourceRecognition:
        return _settings.sourceRecognitionEnabled;

      case LocalAIFeature.smartTags:
        return _settings.smartTagsEnabled;

      case LocalAIFeature.noteClassification:
        return _settings.noteClassificationEnabled;

      case LocalAIFeature.emotionDetection:
        return _settings.emotionDetectionEnabled;

      default:
        return false;
    }
  }

  /// 检查功能是否启用（设置层面）
  bool isFeatureEnabled(String feature) {
    if (!_settings.enabled) return false;

    switch (feature) {
      case LocalAIFeature.speechToText:
        return _settings.speechToTextEnabled;

      case LocalAIFeature.aiCorrection:
        return _settings.aiCorrectionEnabled;

      case LocalAIFeature.sourceRecognition:
        return _settings.sourceRecognitionEnabled;

      case LocalAIFeature.smartTags:
        return _settings.smartTagsEnabled;

      case LocalAIFeature.noteClassification:
        return _settings.noteClassificationEnabled;

      case LocalAIFeature.emotionDetection:
        return _settings.emotionDetectionEnabled;

      default:
        return false;
    }
  }

  // ==================== 语音识别 API ====================

  /// 开始录音
  Future<void> startRecording() async {
    if (!isFeatureEnabled(LocalAIFeature.speechToText)) {
      throw Exception('feature_not_enabled:speechToText');
    }
    await _speechService.startRecording();
  }

  /// 停止录音并转写
  Future<SpeechRecognitionResult> stopAndTranscribe() async {
    return await _speechService.stopAndTranscribe();
  }

  /// 从音频文件转写
  Future<SpeechRecognitionResult> transcribeFile(String audioPath) async {
    if (!isFeatureEnabled(LocalAIFeature.speechToText)) {
      throw Exception('feature_not_enabled:speechToText');
    }
    return await _speechService.transcribeFile(audioPath);
  }


  // ==================== 模型管理 API ====================

  /// 获取所有模型
  List<LocalAIModelInfo> get models => _modelManager.models;

  /// 下载模型
  Future<void> downloadModel(
    String modelId, {
    void Function(double progress)? onProgress,
    void Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    await _modelManager.downloadModel(
      modelId,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  /// 取消下载
  Future<void> cancelDownload(String modelId) async {
    await _modelManager.cancelDownload(modelId);
  }

  /// 删除模型
  Future<void> deleteModel(String modelId) async {
    await _modelManager.deleteModel(modelId);
  }

  /// 导入模型
  Future<void> importModel(String modelId, String filePath) async {
    await _modelManager.importModel(modelId, filePath);
  }

  /// 获取存储占用
  Future<int> getStorageUsage() async {
    return await _modelManager.getTotalStorageUsage();
  }

  @override
  void dispose() {
    _speechService.dispose();
    // _ocrService.dispose(); // Tesseract 已移除
    _modelManager.dispose();
    super.dispose();
  }
}
