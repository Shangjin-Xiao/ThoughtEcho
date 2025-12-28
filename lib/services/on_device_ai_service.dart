import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/local_ai_settings.dart';
import '../utils/app_logger.dart';

/// 本地AI服务状态
enum OnDeviceAIStatus {
  uninitialized, // 未初始化
  initializing, // 初始化中
  ready, // 就绪
  processing, // 处理中
  error, // 错误
}

/// 本地AI服务
/// 
/// 实现方案B: cactus + ML Kit
/// - LLM/嵌入/ASR: cactus (许可证未知⚠️)
/// - OCR: google_mlkit_text_recognition (MIT)
/// 
/// ⚠️ 重要提示：
/// cactus 许可证不明确，商业使用前请确认许可证状态。
/// 源码包含 telemetry/ProKey 代码，不建议在商业发布前使用。
/// 此功能目前处于 Preview 阶段。
class OnDeviceAIService extends ChangeNotifier {
  /// 服务状态
  OnDeviceAIStatus _status = OnDeviceAIStatus.uninitialized;
  OnDeviceAIStatus get status => _status;

  /// 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// ML Kit OCR 识别器（中文）
  TextRecognizer? _chineseRecognizer;
  
  /// ML Kit OCR 识别器（拉丁文，用于英文等）
  TextRecognizer? _latinRecognizer;

  /// 本地AI设置引用
  LocalAISettings? _settings;

  /// 模型文件路径
  String? _modelPath;

  /// Cactus 会话（当 cactus 包可用时启用）
  /// 注意：cactus 包许可证待确认，暂时禁用 LLM 功能
  // CactusSession? _cactusSession;
  bool _cactusAvailable = false;

  /// 获取当前设置
  LocalAISettings? get settings => _settings;

  /// 检查服务是否已就绪
  bool get isReady => _status == OnDeviceAIStatus.ready;

  /// 检查 OCR 功能是否可用
  bool get isOCRAvailable => 
      _settings?.ocrEnabled == true && 
      (_chineseRecognizer != null || _latinRecognizer != null);

  /// 检查 LLM 功能是否可用
  /// 注意：cactus 许可证待确认，此功能暂时禁用
  bool get isLLMAvailable => 
      _settings?.enabled == true && _cactusAvailable;

  /// 检查 ASR (语音转文字) 功能是否可用
  /// 注意：cactus 许可证待确认，此功能暂时禁用
  bool get isASRAvailable => 
      _settings?.speechToTextEnabled == true && _cactusAvailable;

  /// 检查嵌入功能是否可用
  /// 注意：cactus 许可证待确认，此功能暂时禁用
  bool get isEmbeddingAvailable => 
      _settings?.aiSearchEnabled == true && _cactusAvailable;

  /// 初始化服务
  Future<void> initialize({
    required LocalAISettings settings,
    String? modelPath,
  }) async {
    if (_status == OnDeviceAIStatus.initializing) {
      logDebug('OnDeviceAIService: 初始化进行中，跳过重复调用');
      return;
    }

    _status = OnDeviceAIStatus.initializing;
    _settings = settings;
    _modelPath = modelPath;
    _errorMessage = null;
    notifyListeners();

    try {
      // 仅在功能启用时初始化
      if (!settings.enabled) {
        logDebug('OnDeviceAIService: 本地AI功能已禁用，跳过初始化');
        _status = OnDeviceAIStatus.ready;
        notifyListeners();
        return;
      }

      // 初始化 OCR 识别器
      if (settings.ocrEnabled) {
        await _initializeOCR();
      }

      // 初始化 Cactus (LLM/ASR/Embedding)
      // ⚠️ 注意：cactus 许可证待确认，暂时禁用
      // 商业使用前请确认许可证状态
      if (settings.speechToTextEnabled || 
          settings.aiSearchEnabled || 
          settings.aiCorrectionEnabled) {
        await _initializeCactus();
      }

      _status = OnDeviceAIStatus.ready;
      logDebug('OnDeviceAIService: 初始化完成');
    } catch (e, stackTrace) {
      _status = OnDeviceAIStatus.error;
      _errorMessage = e.toString();
      logDebug('OnDeviceAIService: 初始化失败: $e\n$stackTrace');
    }

    notifyListeners();
  }

  /// 初始化 ML Kit OCR
  Future<void> _initializeOCR() async {
    try {
      // Web 平台不支持 ML Kit
      if (kIsWeb) {
        logDebug('OnDeviceAIService: Web 平台不支持 ML Kit OCR');
        return;
      }

      // 初始化中文识别器
      _chineseRecognizer = TextRecognizer(
        script: TextRecognitionScript.chinese,
      );
      logDebug('OnDeviceAIService: 中文 OCR 识别器已初始化');

      // 初始化拉丁文识别器（用于英文）
      _latinRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      logDebug('OnDeviceAIService: 拉丁文 OCR 识别器已初始化');
    } catch (e) {
      logDebug('OnDeviceAIService: OCR 初始化失败: $e');
      // OCR 初始化失败不阻塞其他功能
    }
  }

  /// 初始化 Cactus (LLM/ASR/Embedding)
  /// 
  /// ⚠️ 重要提示：
  /// cactus 许可证不明确，商业使用前请确认许可证状态。
  /// 源码包含 telemetry/ProKey 代码，不建议在商业发布前使用。
  Future<void> _initializeCactus() async {
    try {
      // Web 平台不支持本地模型
      if (kIsWeb) {
        logDebug('OnDeviceAIService: Web 平台不支持 Cactus');
        _cactusAvailable = false;
        return;
      }

      // ⚠️ Cactus 许可证待确认，暂时禁用
      // 以下代码在确认许可证后启用：
      // 
      // if (_modelPath == null || _modelPath!.isEmpty) {
      //   logDebug('OnDeviceAIService: 未指定模型路径，跳过 Cactus 初始化');
      //   _cactusAvailable = false;
      //   return;
      // }
      // 
      // final modelFile = File(_modelPath!);
      // if (!await modelFile.exists()) {
      //   logDebug('OnDeviceAIService: 模型文件不存在: $_modelPath');
      //   _cactusAvailable = false;
      //   return;
      // }
      // 
      // _cactusSession = CactusSession();
      // await _cactusSession!.initialize(modelPath: _modelPath!);
      // _cactusAvailable = true;
      // logDebug('OnDeviceAIService: Cactus 已初始化，模型: $_modelPath');

      logDebug('OnDeviceAIService: Cactus 功能暂时禁用（许可证待确认）');
      _cactusAvailable = false;
    } catch (e) {
      logDebug('OnDeviceAIService: Cactus 初始化失败: $e');
      _cactusAvailable = false;
    }
  }

  /// 更新设置
  Future<void> updateSettings(LocalAISettings newSettings) async {
    final oldSettings = _settings;
    _settings = newSettings;

    // 检查是否需要重新初始化
    bool needsReinit = oldSettings == null ||
        oldSettings.enabled != newSettings.enabled ||
        oldSettings.ocrEnabled != newSettings.ocrEnabled ||
        oldSettings.speechToTextEnabled != newSettings.speechToTextEnabled ||
        oldSettings.aiSearchEnabled != newSettings.aiSearchEnabled;

    if (needsReinit) {
      await initialize(settings: newSettings, modelPath: _modelPath);
    } else {
      notifyListeners();
    }
  }

  // ========== OCR 功能 ==========

  /// 从图片识别文本（OCR）
  /// 
  /// [imagePath] 图片文件路径
  /// [preferredScript] 优先使用的文字脚本类型
  /// 
  /// 返回识别到的文本内容
  Future<String> recognizeText({
    required String imagePath,
    TextRecognitionScript preferredScript = TextRecognitionScript.chinese,
  }) async {
    if (!isOCRAvailable) {
      throw Exception('OCR 功能未启用或不可用');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      
      // 根据偏好选择识别器
      final recognizer = preferredScript == TextRecognitionScript.chinese
          ? _chineseRecognizer
          : _latinRecognizer;

      if (recognizer == null) {
        throw Exception('OCR 识别器未初始化');
      }

      final result = await recognizer.processImage(inputImage);
      
      _status = OnDeviceAIStatus.ready;
      notifyListeners();

      logDebug('OnDeviceAIService: OCR 识别完成，识别到 ${result.text.length} 个字符');
      return result.text;
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      logDebug('OnDeviceAIService: OCR 识别失败: $e');
      rethrow;
    }
  }

  /// 从图片识别文本并返回详细结果
  /// 
  /// 包含每个文本块的位置信息
  Future<RecognizedText?> recognizeTextWithDetails({
    required String imagePath,
    TextRecognitionScript preferredScript = TextRecognitionScript.chinese,
  }) async {
    if (!isOCRAvailable) {
      throw Exception('OCR 功能未启用或不可用');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      
      final recognizer = preferredScript == TextRecognitionScript.chinese
          ? _chineseRecognizer
          : _latinRecognizer;

      if (recognizer == null) {
        throw Exception('OCR 识别器未初始化');
      }

      final result = await recognizer.processImage(inputImage);
      
      _status = OnDeviceAIStatus.ready;
      notifyListeners();

      return result;
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      logDebug('OnDeviceAIService: OCR 详细识别失败: $e');
      rethrow;
    }
  }

  // ========== LLM 功能（许可证待确认，暂时禁用）==========

  /// 与本地 LLM 对话
  /// 
  /// ⚠️ 此功能依赖 cactus，许可证待确认
  /// 商业使用前请确认许可证状态
  /// 
  /// [message] 用户消息
  /// 返回 AI 回复
  Future<String> chat(String message) async {
    if (!isLLMAvailable) {
      throw Exception('LLM 功能未启用或不可用（许可证待确认）');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      // ⚠️ Cactus 许可证待确认，暂时禁用
      // 以下代码在确认许可证后启用：
      // 
      // final response = await _cactusSession!.chat(message);
      // 
      // _status = OnDeviceAIStatus.ready;
      // notifyListeners();
      // 
      // return response;

      throw Exception('LLM 功能暂时禁用（cactus 许可证待确认）');
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      rethrow;
    }
  }

  // ========== ASR 功能（许可证待确认，暂时禁用）==========

  /// 语音转文字
  /// 
  /// ⚠️ 此功能依赖 cactus，许可证待确认
  /// 商业使用前请确认许可证状态
  /// 
  /// [audioPath] 音频文件路径
  /// 返回转录文本
  Future<String> transcribe(String audioPath) async {
    if (!isASRAvailable) {
      throw Exception('ASR 功能未启用或不可用（许可证待确认）');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      // ⚠️ Cactus 许可证待确认，暂时禁用
      // 以下代码在确认许可证后启用：
      // 
      // final text = await _cactusSession!.transcribe(audioPath: audioPath);
      // 
      // _status = OnDeviceAIStatus.ready;
      // notifyListeners();
      // 
      // return text;

      throw Exception('ASR 功能暂时禁用（cactus 许可证待确认）');
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      rethrow;
    }
  }

  // ========== 嵌入功能（许可证待确认，暂时禁用）==========

  /// 生成文本嵌入向量
  /// 
  /// ⚠️ 此功能依赖 cactus，许可证待确认
  /// 商业使用前请确认许可证状态
  /// 
  /// [text] 要嵌入的文本
  /// 返回嵌入向量
  Future<List<double>> embed(String text) async {
    if (!isEmbeddingAvailable) {
      throw Exception('嵌入功能未启用或不可用（许可证待确认）');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      // ⚠️ Cactus 许可证待确认，暂时禁用
      // 以下代码在确认许可证后启用：
      // 
      // final embedding = await _cactusSession!.embed(text);
      // 
      // _status = OnDeviceAIStatus.ready;
      // notifyListeners();
      // 
      // return embedding;

      throw Exception('嵌入功能暂时禁用（cactus 许可证待确认）');
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      rethrow;
    }
  }

  // ========== 辅助功能 ==========

  /// 获取许可证警告信息
  String get licenseWarning => '''
⚠️ 许可证警告

本地AI功能使用了以下第三方库：
• cactus: 许可证不明确
• google_mlkit_text_recognition: MIT 许可证

cactus 库的许可证状态未明确，源码中包含 telemetry/ProKey 相关代码。
在商业发布前，请务必确认 cactus 的许可证状态。

当前建议：
• 仅用于快速原型测试和个人使用
• 商业发布请选择其他方案或等待许可证确认
''';

  /// 获取功能状态摘要
  Map<String, bool> getFeatureStatus() {
    return {
      'enabled': _settings?.enabled ?? false,
      'ocr': isOCRAvailable,
      'llm': isLLMAvailable,
      'asr': isASRAvailable,
      'embedding': isEmbeddingAvailable,
    };
  }

  /// 释放资源
  @override
  void dispose() {
    _chineseRecognizer?.close();
    _latinRecognizer?.close();
    // _cactusSession?.dispose(); // 许可证确认后启用
    super.dispose();
  }
}
