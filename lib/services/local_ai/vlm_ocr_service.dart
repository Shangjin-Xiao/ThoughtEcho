/// VLM (Vision Language Model) OCR 服务
///
/// 使用视觉语言模型进行图像文字识别，特别适合手写文字
/// 相比传统 OCR 引擎，VLM 能更好地理解上下文和手写内容

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../models/ocr_result.dart';
import '../../utils/app_logger.dart';
import 'image_preprocessor.dart';
import 'model_manager.dart';

/// VLM OCR 状态
enum VLMOCRState {
  idle,
  loading,
  processing,
  completed,
  error,
}

/// VLM OCR 状态信息
class VLMOCRStatus {
  final VLMOCRState state;
  final double progress;
  final String? errorMessage;

  const VLMOCRStatus({
    required this.state,
    this.progress = 0.0,
    this.errorMessage,
  });

  static const idle = VLMOCRStatus(state: VLMOCRState.idle);

  VLMOCRStatus copyWith({
    VLMOCRState? state,
    double? progress,
    String? errorMessage,
  }) {
    return VLMOCRStatus(
      state: state ?? this.state,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// VLM OCR 识别模式
enum VLMOCRMode {
  /// 精确模式：逐字识别，保留原文格式
  precise,
  
  /// 理解模式：理解内容含义，可能会修正错别字和格式
  understanding,
  
  /// 手写模式：专门针对手写优化
  handwritten,
}

/// VLM OCR 服务
///
/// 使用视觉语言模型进行文字识别，特别适合：
/// - 手写文字
/// - 复杂排版
/// - 需要上下文理解的场景
class VLMOCRService extends ChangeNotifier {
  static VLMOCRService? _instance;

  static VLMOCRService get instance {
    _instance ??= VLMOCRService._();
    return _instance!;
  }

  VLMOCRService._();

  final ModelManager _modelManager = ModelManager.instance;
  VLMOCRStatus _status = VLMOCRStatus.idle;
  bool _initialized = false;
  
  // Gemma 实例（如果支持视觉）
  FlutterGemmaPlugin? _gemma;
  
  VLMOCRStatus get status => _status;
  bool get isInitialized => _initialized;

  /// 检查 VLM 模型是否可用
  bool get isModelAvailable {
    // 检查是否有 Gemma 视觉模型或其他 VLM 模型
    // 这里需要根据实际可用的模型进行判断
    return _modelManager.isModelDownloaded('gemma-2b-vision') ||
           _modelManager.isModelDownloaded('paligemma-3b') ||
           _modelManager.isModelDownloaded('qwen-vl-chat');
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      logInfo('初始化 VLM OCR 服务...', source: 'VLMOCRService');

      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 初始化 Gemma（如果支持视觉）
      try {
        _gemma = FlutterGemmaPlugin.instance;
        logInfo('Gemma 插件初始化成功', source: 'VLMOCRService');
      } catch (e) {
        logError('Gemma 插件初始化失败: $e', source: 'VLMOCRService');
      }

      _initialized = true;
      logInfo('VLM OCR 服务初始化完成', source: 'VLMOCRService');
    } catch (e) {
      logError('VLM OCR 服务初始化失败: $e', source: 'VLMOCRService');
      _initialized = true; // 允许服务继续运行
    }
  }

  /// 使用 VLM 识别图像中的文字
  Future<OCRResult> recognizeFromFile(
    String imagePath, {
    VLMOCRMode mode = VLMOCRMode.precise,
    bool enablePreprocess = false,
  }) async {
    if (!_initialized) {
      throw Exception('service_not_initialized');
    }

    if (!isModelAvailable) {
      throw Exception('vlm_model_required');
    }

    final startTime = DateTime.now();

    try {
      _status = const VLMOCRStatus(state: VLMOCRState.processing, progress: 0.0);
      notifyListeners();

      // 可选的图像预处理
      String processedImagePath = imagePath;
      if (enablePreprocess) {
        _status = _status.copyWith(progress: 0.1);
        notifyListeners();

        // 对于 VLM，预处理不需要那么激进
        final config = PreprocessConfig(
          binarize: false, // VLM 能处理彩色图
          denoise: true,
          enhanceContrast: false,
          sharpen: false,
          targetDpi: 224, // VLM 通常使用 224x224 输入
        );

        processedImagePath = await ImagePreprocessor.preprocessImage(
          imagePath,
          config: config,
        );
      }

      _status = _status.copyWith(progress: 0.2);
      notifyListeners();

      // 构建提示词
      final prompt = _buildPrompt(mode);

      logInfo('开始 VLM OCR 识别: $processedImagePath, 模式: $mode', source: 'VLMOCRService');

      _status = _status.copyWith(progress: 0.3);
      notifyListeners();

      // 调用 VLM 进行识别
      final recognizedText = await _runVLMInference(processedImagePath, prompt);

      _status = _status.copyWith(progress: 0.9);
      notifyListeners();

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      final result = OCRResult(
        fullText: recognizedText,
        imagePath: imagePath,
        processingTimeMs: processingTime,
        languages: const ['auto'], // VLM 自动检测语言
      );

      _status = const VLMOCRStatus(state: VLMOCRState.completed, progress: 1.0);
      notifyListeners();

      logInfo('VLM OCR 识别完成: ${recognizedText.length} 字符', source: 'VLMOCRService');
      return result;
    } catch (e) {
      _status = VLMOCRStatus(
        state: VLMOCRState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('VLM OCR 识别失败: $e', source: 'VLMOCRService');
      rethrow;
    }
  }

  /// 构建 VLM 提示词
  String _buildPrompt(VLMOCRMode mode) {
    switch (mode) {
      case VLMOCRMode.precise:
        return '''请识别这张图片中的所有文字内容。要求：
1. 逐字逐句准确识别，不要遗漏任何文字
2. 保持原文的换行和段落格式
3. 不要添加任何解释或说明
4. 如果有标点符号，请保留
5. 如果文字模糊或难以辨认，用 [?] 标记

请直接输出识别的文字：''';

      case VLMOCRMode.understanding:
        return '''请阅读这张图片中的文字内容，并理解其含义。要求：
1. 识别所有文字内容
2. 如果有明显的错别字，可以修正
3. 保持句子的完整性和可读性
4. 保留段落结构
5. 不要添加额外的解释

请输出整理后的文字内容：''';

      case VLMOCRMode.handwritten:
        return '''这是一张包含手写文字的图片。请仔细识别手写内容。要求：
1. 手写文字可能不规范，请根据上下文推测
2. 注意笔画连接和省略
3. 如果某个字难以辨认，请根据上下文推测最可能的字
4. 保持原文的换行和段落
5. 特别注意中文手写字的草书和连笔

请输出识别的文字：''';
    }
  }

  /// 执行 VLM 推理
  Future<String> _runVLMInference(String imagePath, String prompt) async {
    // 方案1: 如果 flutter_gemma 支持视觉输入
    if (_gemma != null) {
      try {
        return await _runWithGemma(imagePath, prompt);
      } catch (e) {
        logError('Gemma 视觉推理失败: $e', source: 'VLMOCRService');
      }
    }

    // 方案2: 使用其他 VLM 实现
    // TODO: 集成 Qwen-VL、PaliGemma 等模型
    
    // 方案3: 降级到模拟实现（仅用于开发测试）
    return await _fallbackSimulation(imagePath, prompt);
  }

  /// 使用 Gemma 进行推理
  Future<String> _runWithGemma(String imagePath, String prompt) async {
    try {
      // flutter_gemma 0.11.x 支持视觉模型（Gemma3N, DeepSeek 等）
      logInfo('开始 Gemma 视觉推理', source: 'VLMOCRService');
      
      // 读取图片文件
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      
      // 创建视觉模型，需要启用图像支持
      final model = await _gemma!.createModel(
        modelType: ModelType.general, // general 支持多模态（文本+图像）
        maxTokens: 2048, // VLM 需要更大的上下文
        supportImage: true, // 启用图像支持
        maxNumImages: 1, // 支持 1 张图像
      );
      
      // 创建会话，启用视觉模态
      final session = await model.createSession(
        enableVisionModality: true, // 启用视觉模态
      );
      
      // 使用 addQueryChunk 添加带图像的消息
      // Message.withImage 可以同时发送文本和图像
      await session.addQueryChunk(
        Message.withImage(
          text: prompt,
          imageBytes: imageBytes,
          isUser: true,
        ),
      );
      
      // 获取响应
      final response = await session.getResponse();
      
      // 关闭会话
      await session.close();
      await model.close();
      
      return response;
    } catch (e) {
      logError('Gemma 视觉推理失败: $e', source: 'VLMOCRService');
      // 如果视觉推理失败，抛出异常让调用者处理
      throw Exception('gemma_vision_failed: $e');
    }
  }

  /// 降级方案：模拟实现（开发用）
  Future<String> _fallbackSimulation(String imagePath, String prompt) async {
    logWarning('使用 VLM 模拟实现，实际部署时需要真实的 VLM 模型', source: 'VLMOCRService');
    
    // 这是一个占位实现，提示用户配置真实的 VLM
    await Future.delayed(const Duration(seconds: 2)); // 模拟处理时间
    
    return '''[VLM OCR 占位结果]

当前使用的是模拟实现。要启用真实的 VLM OCR 功能，请：

1. 下载支持的 VLM 模型：
   - PaliGemma (推荐，Google 官方)
   - Qwen-VL-Chat (阿里，1.8GB)
   - LLaVA Mobile (轻量级)

2. 在模型管理中配置 VLM 模型路径

3. 重启应用

VLM OCR 特别适合识别手写文字和复杂场景。''';
  }

  /// 批量识别
  Future<List<OCRResult>> recognizeBatch(
    List<String> imagePaths, {
    VLMOCRMode mode = VLMOCRMode.precise,
  }) async {
    final results = <OCRResult>[];

    for (int i = 0; i < imagePaths.length; i++) {
      try {
        final result = await recognizeFromFile(imagePaths[i], mode: mode);
        results.add(result);

        // 更新进度
        _status = _status.copyWith(
          progress: (i + 1) / imagePaths.length,
        );
        notifyListeners();
      } catch (e) {
        logError('批量识别失败 (${imagePaths[i]}): $e', source: 'VLMOCRService');
        // 继续处理下一张
      }
    }

    return results;
  }

  /// 取消当前识别
  void cancelRecognition() {
    if (_status.state == VLMOCRState.processing) {
      _status = VLMOCRStatus.idle;
      notifyListeners();
      logInfo('取消 VLM OCR 识别', source: 'VLMOCRService');
    }
  }

  @override
  void dispose() {
    cancelRecognition();
    _gemma = null;
    super.dispose();
  }
}
