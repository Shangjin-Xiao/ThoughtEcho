import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:cactus/cactus.dart';
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
/// 实现方案: cactus + ML Kit
/// - LLM/嵌入: cactus
/// - OCR: google_mlkit_text_recognition (MIT)
/// - ASR: 待集成（可使用 speech_to_text 或其他方案）
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

  /// Cactus LM 实例
  CactusLM? _cactusLM;
  
  /// Cactus 功能可用性标记
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
  bool get isLLMAvailable => 
      _settings?.enabled == true && _cactusAvailable;

  /// 检查 ASR (语音转文字) 功能是否可用
  /// 注意：ASR 功能需要使用第三方服务或其他包实现
  bool get isASRAvailable => 
      _settings?.speechToTextEnabled == true && false; // ASR not yet implemented

  /// 检查嵌入功能是否可用
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

      // 初始化 OCR 识别器 (ML Kit - MIT 许可证, 可用)
      if (settings.ocrEnabled) {
        await _initializeOCR();
      }

      // 初始化 Cactus LLM/Embedding 功能
      if (settings.aiSearchEnabled || settings.aiCorrectionEnabled) {
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

  /// 初始化 Cactus (LLM/Embedding)
  Future<void> _initializeCactus() async {
    try {
      // Web 平台不支持 Cactus
      if (kIsWeb) {
        logDebug('OnDeviceAIService: Web 平台不支持 Cactus');
        _cactusAvailable = false;
        return;
      }

      // 检查模型路径
      if (_modelPath == null || _modelPath!.isEmpty) {
        logDebug('OnDeviceAIService: 未提供 Cactus 模型路径，使用默认模型');
        
        // 使用默认的轻量级模型 URL
        // 这是一个小型的 600M 参数模型，适合移动设备
        const defaultModelUrl = 'https://huggingface.co/Cactus-Compute/Qwen3-600m-Instruct-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf';
        
        _cactusLM = await CactusLM.init(
          modelUrl: defaultModelUrl,
          contextSize: 2048,
          threads: 4,
          generateEmbeddings: _settings?.aiSearchEnabled ?? false,
          onProgress: (progress, message, isError) {
            if (isError) {
              logDebug('OnDeviceAIService: Cactus 初始化错误: $message');
            } else {
              logDebug('OnDeviceAIService: Cactus 初始化进度: ${(progress ?? 0) * 100}% - $message');
            }
          },
        );
      } else {
        // 使用用户指定的本地模型文件
        final modelFile = File(_modelPath!);
        if (!await modelFile.exists()) {
          logDebug('OnDeviceAIService: 模型文件不存在: $_modelPath');
          _cactusAvailable = false;
          return;
        }
        
        _cactusLM = await CactusLM.init(
          modelUrl: _modelPath!,
          contextSize: 2048,
          threads: 4,
          generateEmbeddings: _settings?.aiSearchEnabled ?? false,
          onProgress: (progress, message, isError) {
            if (isError) {
              logDebug('OnDeviceAIService: Cactus 初始化错误: $message');
            } else {
              logDebug('OnDeviceAIService: Cactus 初始化进度: ${(progress ?? 0) * 100}% - $message');
            }
          },
        );
      }
      
      _cactusAvailable = true;
      logDebug('OnDeviceAIService: Cactus LM 已初始化');
    } catch (e, stackTrace) {
      _cactusAvailable = false;
      logDebug('OnDeviceAIService: Cactus 初始化失败: $e\n$stackTrace');
      // Cactus 初始化失败不阻塞其他功能
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
      throw Exception('OCR feature not enabled or unavailable');
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
        throw Exception('OCR recognizer not initialized');
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
      throw Exception('OCR feature not enabled or unavailable');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      
      final recognizer = preferredScript == TextRecognitionScript.chinese
          ? _chineseRecognizer
          : _latinRecognizer;

      if (recognizer == null) {
        throw Exception('OCR recognizer not initialized');
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

  // ========== LLM 功能 ==========

  /// 与本地 LLM 对话
  /// 
  /// [message] 用户消息
  /// [onToken] 可选的流式回调，每生成一个token时调用
  /// 返回 AI 回复
  Future<String> chat(String message, {CactusTokenCallback? onToken}) async {
    if (!isLLMAvailable) {
      throw Exception('LLM feature not enabled or unavailable');
    }

    if (_cactusLM == null) {
      throw Exception('Cactus LM not initialized');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      final result = await _cactusLM!.completion(
        [ChatMessage(role: 'user', content: message)],
        maxTokens: 256,
        temperature: 0.7,
        onToken: onToken,
      );
      
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      
      logDebug('OnDeviceAIService: LLM 生成完成，生成了 ${result.tokensPredicted} 个token');
      return result.text;
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      logDebug('OnDeviceAIService: LLM 生成失败: $e');
      rethrow;
    }
  }

  /// 与本地 LLM 进行多轮对话
  /// 
  /// [messages] 对话历史
  /// [onToken] 可选的流式回调
  /// 返回 AI 回复
  Future<String> chatWithHistory(
    List<ChatMessage> messages, {
    CactusTokenCallback? onToken,
  }) async {
    if (!isLLMAvailable) {
      throw Exception('LLM feature not enabled or unavailable');
    }

    if (_cactusLM == null) {
      throw Exception('Cactus LM not initialized');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      final result = await _cactusLM!.completion(
        messages,
        maxTokens: 256,
        temperature: 0.7,
        onToken: onToken,
      );
      
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      
      return result.text;
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      rethrow;
    }
  }

  // ========== ASR 功能（需要额外的语音识别包）==========

  /// 语音转文字
  /// 
  /// 注意：Cactus v0.1.4 不包含 ASR 功能
  /// 需要使用其他包如 speech_to_text 或云服务
  /// 
  /// [audioPath] 音频文件路径
  /// 返回转录文本
  Future<String> transcribe(String audioPath) async {
    if (!isASRAvailable) {
      throw Exception('ASR feature not yet implemented');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      // TODO: 集成语音识别功能
      // 可以使用 speech_to_text 包或其他方案
      throw Exception('ASR feature not yet implemented - needs speech recognition package');
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      rethrow;
    }
  }

  // ========== 嵌入功能 ==========

  /// 生成文本嵌入向量
  /// 
  /// [text] 要嵌入的文本
  /// 返回嵌入向量
  Future<List<double>> embed(String text) async {
    if (!isEmbeddingAvailable) {
      throw Exception('Embedding feature not enabled or unavailable');
    }

    if (_cactusLM == null) {
      throw Exception('Cactus LM not initialized');
    }

    _status = OnDeviceAIStatus.processing;
    notifyListeners();

    try {
      final embedding = _cactusLM!.embedding(text);
      
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      
      logDebug('OnDeviceAIService: 生成了 ${embedding.length} 维嵌入向量');
      return embedding;
    } catch (e) {
      _status = OnDeviceAIStatus.ready;
      notifyListeners();
      logDebug('OnDeviceAIService: 嵌入生成失败: $e');
      rethrow;
    }
  }

  // ========== 辅助功能 ==========

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
    _cactusLM?.dispose();
    super.dispose();
  }
}
