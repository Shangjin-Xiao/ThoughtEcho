/// 本地 AI 服务
///
/// 整合所有设备端 AI 功能的入口服务

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/local_ai_settings.dart';
import '../../models/local_ai_model.dart';
import '../../models/speech_recognition_result.dart';
import '../../models/ocr_result.dart';
import '../../models/embedding_result.dart';
import '../../models/text_processing_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';
import 'speech_recognition_service.dart';
import 'mlkit_ocr_service.dart';
import 'hybrid_ocr_service.dart';
import 'embedding_service.dart';
import 'vector_store.dart';
import 'text_processing_service.dart';

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
  final HybridOCRService _hybridOCRService = HybridOCRService.instance;
  final EmbeddingService _embeddingService = EmbeddingService.instance;
  final VectorStore _vectorStore = VectorStore.instance;
  final TextProcessingService _textService = TextProcessingService.instance;

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

  /// 获取混合 OCR 服务（智能选择 Tesseract/VLM）
  HybridOCRService get hybridOCRService => _hybridOCRService;

  /// 获取嵌入服务
  EmbeddingService get embeddingService => _embeddingService;

  /// 获取向量存储
  VectorStore get vectorStore => _vectorStore;

  /// 获取文本处理服务
  TextProcessingService get textService => _textService;

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
        if (settings.aiSearchEnabled || settings.relatedNotesEnabled) {
          await _embeddingService.initialize();
          await _vectorStore.initialize();
        }
        if (settings.aiCorrectionEnabled ||
            settings.sourceRecognitionEnabled ||
            settings.smartTagsEnabled ||
            settings.noteClassificationEnabled ||
            settings.emotionDetectionEnabled) {
          await _textService.initialize();
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
    if ((settings.aiSearchEnabled || settings.relatedNotesEnabled) &&
        !_embeddingService.isInitialized) {
      await _embeddingService.initialize();
      await _vectorStore.initialize();
    }
    if ((settings.aiCorrectionEnabled ||
            settings.sourceRecognitionEnabled ||
            settings.smartTagsEnabled ||
            settings.noteClassificationEnabled ||
            settings.emotionDetectionEnabled) &&
        !_textService.isInitialized) {
      await _textService.initialize();
    }

    notifyListeners();
    logDebug('本地 AI 设置已更新', source: 'LocalAIService');
  }

  /// 检查功能是否可用
  bool isFeatureAvailable(String feature) {
    if (!_settings.enabled) return false;

    switch (feature) {
      case LocalAIFeature.speechToText:
        return _settings.speechToTextEnabled && _speechService.isModelAvailable;

      case LocalAIFeature.ocr:
        return _settings.ocrEnabled &&
            (_hybridOCRService.isMLKitAvailable ||
                // _hybridOCRService.isTesseractAvailable || // Tesseract 已移除
                _hybridOCRService.isVLMAvailable);

      case LocalAIFeature.aiCorrection:
        // Gemma 模型由 flutter_gemma 管理，ModelManager 不一定能反映其可用性。
        // 因此这里仅按“启用”判断；实际调用会自动降级或提示用户手动加载。
        return _settings.aiCorrectionEnabled;

      case LocalAIFeature.sourceRecognition:
        return _settings.sourceRecognitionEnabled;

      case LocalAIFeature.aiSearch:
        return _settings.aiSearchEnabled && _embeddingService.isModelAvailable;

      case LocalAIFeature.relatedNotes:
        return _settings.relatedNotesEnabled &&
            _embeddingService.isModelAvailable;

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

      case LocalAIFeature.ocr:
        return _settings.ocrEnabled;

      case LocalAIFeature.aiCorrection:
        return _settings.aiCorrectionEnabled;

      case LocalAIFeature.sourceRecognition:
        return _settings.sourceRecognitionEnabled;

      case LocalAIFeature.aiSearch:
        return _settings.aiSearchEnabled;

      case LocalAIFeature.relatedNotes:
        return _settings.relatedNotesEnabled;

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
      throw Exception('语音转文字功能未启用');
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
      throw Exception('语音转文字功能未启用');
    }
    return await _speechService.transcribeFile(audioPath);
  }

  // ==================== OCR API ====================

  /// 从图片识别文字（智能选择引擎）
  ///
  /// 默认使用混合 OCR 服务，自动选择 Tesseract（印刷体）或 VLM（手写）
  /// 如果需要强制使用特定引擎，请使用 [recognizeTextWithEngine]
  Future<OCRResult> recognizeText(String imagePath) async {
    if (!isFeatureEnabled(LocalAIFeature.ocr)) {
      throw Exception('OCR 功能未启用');
    }
    // 使用混合 OCR 服务，自动选择最佳引擎
    return await _hybridOCRService.recognizeFromFile(imagePath);
  }

  /// 使用指定引擎识别文字
  ///
  /// [engineType] OCR 引擎类型：mlkit, vlm, auto（自动选择）
  Future<OCRResult> recognizeTextWithEngine(
    String imagePath, {
    OCREngineType engineType = OCREngineType.auto,
  }) async {
    if (!isFeatureEnabled(LocalAIFeature.ocr)) {
      throw Exception('OCR 功能未启用');
    }
    return await _hybridOCRService.recognizeFromFile(
      imagePath,
      engineType: engineType,
    );
  }

  /// 从图片识别文字（带区域信息）- 仅 Tesseract 支持
  // Future<OCRResult> recognizeTextWithRegions(String imagePath) async {
  //   if (!isFeatureEnabled(LocalAIFeature.ocr)) {
  //     throw Exception('OCR 功能未启用');
  //   }
  //   return await _ocrService.recognizeWithRegions(imagePath);
  // }

  // 临时保留方法签名但抛出不支持，或者完全移除。这里注释掉。

  /// 设置 OCR 引擎偏好
  void setOCREngine(OCREngineType engine) {
    _hybridOCRService.setPreferredEngine(engine);
  }

  /// 获取当前 OCR 引擎
  String get currentOCREngine => _hybridOCRService.getCurrentEngine();

  // ==================== 文本处理 API ====================

  /// AI 文本纠错
  Future<TextCorrectionResult> correctText(String text) async {
    if (!isFeatureEnabled(LocalAIFeature.aiCorrection)) {
      throw Exception('AI 纠错功能未启用');
    }
    return await _textService.correctText(text);
  }

  /// 识别来源
  Future<SourceRecognitionResult> recognizeSource(String text) async {
    if (!isFeatureEnabled(LocalAIFeature.sourceRecognition)) {
      throw Exception('来源识别功能未启用');
    }
    return await _textService.recognizeSource(text);
  }

  /// 智能标签推荐
  Future<TagSuggestionResult> suggestTags(String content) async {
    if (!isFeatureEnabled(LocalAIFeature.smartTags)) {
      throw Exception('智能标签功能未启用');
    }
    return await _textService.suggestTags(content);
  }

  /// 笔记分类
  Future<ClassificationResult> classifyNote(String content) async {
    if (!isFeatureEnabled(LocalAIFeature.noteClassification)) {
      throw Exception('笔记分类功能未启用');
    }
    return await _textService.classifyNote(content);
  }

  /// 情绪检测
  Future<EmotionResult> detectEmotion(String content) async {
    if (!isFeatureEnabled(LocalAIFeature.emotionDetection)) {
      throw Exception('情绪检测功能未启用');
    }
    return await _textService.detectEmotion(content);
  }

  // ==================== 搜索和推荐 API ====================

  /// 语义搜索
  Future<List<SearchResult>> search(String query, {int topK = 10}) async {
    if (!isFeatureEnabled(LocalAIFeature.aiSearch)) {
      throw Exception('AI 搜索功能未启用');
    }
    return await _vectorStore.search(query, topK: topK);
  }

  /// 获取相关笔记
  Future<List<RelatedNote>> getRelatedNotes(String noteId,
      {int topK = 5}) async {
    if (!isFeatureEnabled(LocalAIFeature.relatedNotes)) {
      throw Exception('相关笔记功能未启用');
    }
    return await _vectorStore.getRelatedNotes(noteId, topK: topK);
  }

  /// 索引笔记
  Future<void> indexNote(String noteId, String content) async {
    if (_settings.aiSearchEnabled || _settings.relatedNotesEnabled) {
      await _vectorStore.upsertNote(noteId, content);
    }
  }

  /// 从索引中删除笔记
  Future<void> removeNoteFromIndex(String noteId) async {
    await _vectorStore.deleteNote(noteId);
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
    _embeddingService.dispose();
    _vectorStore.dispose();
    _textService.dispose();
    _modelManager.dispose();
    super.dispose();
  }
}
