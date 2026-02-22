/// MLKit OCR 文字识别服务
///
/// 使用 Google MLKit 进行设备端图像文字识别
/// 适合印刷体文字，准确率高、速度快
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../models/ocr_result.dart' as ocr_model;
import '../../utils/app_logger.dart';

/// MLKit OCR 服务
class MLKitOCRService extends ChangeNotifier {
  static MLKitOCRService? _instance;

  /// 单例实例
  static MLKitOCRService get instance {
    _instance ??= MLKitOCRService._();
    return _instance!;
  }

  MLKitOCRService._();

  /// 文字识别器
  TextRecognizer? _textRecognizer;

  /// 当前状态
  ocr_model.OCRStatus _status = ocr_model.OCRStatus.idle;

  /// 是否已初始化
  bool _initialized = false;

  /// 识别脚本（语言）
  TextRecognitionScript _script = TextRecognitionScript.chinese;

  /// 获取当前状态
  ocr_model.OCRStatus get status => _status;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 获取当前脚本
  TextRecognitionScript get currentScript => _script;

  /// MLKit 始终可用（内置模型）
  bool get isModelAvailable => true;

  /// 初始化服务
  Future<void> initialize({TextRecognitionScript? script}) async {
    if (_initialized) return;

    try {
      logInfo('初始化 MLKit OCR 服务...', source: 'MLKitOCRService');

      _script = script ?? TextRecognitionScript.chinese;
      _textRecognizer = TextRecognizer(script: _script);

      _initialized = true;
      logInfo('MLKit OCR 服务初始化完成，脚本: $_script', source: 'MLKitOCRService');
    } catch (e) {
      logError('MLKit OCR 服务初始化失败: $e', source: 'MLKitOCRService');
      // 初始化失败时不设置 _initialized = true，允许重试
      // 但设置 _textRecognizer 为 null 确保安全
      _textRecognizer = null;
    }
  }

  /// 设置识别脚本（语言）
  Future<void> setScript(TextRecognitionScript script) async {
    if (_script == script) return;

    _script = script;
    _textRecognizer?.close();
    _textRecognizer = TextRecognizer(script: script);

    logInfo('切换 MLKit 脚本: $script', source: 'MLKitOCRService');
    notifyListeners();
  }

  /// 从图片文件识别文字
  Future<ocr_model.OCRResult> recognizeFromFile(
    String imagePath, {
    TextRecognitionScript? script,
  }) async {
    if (!_initialized) {
      await initialize(script: script);
    }

    // 临时切换脚本
    if (script != null && script != _script) {
      await setScript(script);
    }

    final startTime = DateTime.now();

    try {
      _status = const ocr_model.OCRStatus(
          state: ocr_model.OCRState.processing, progress: 0.0);
      notifyListeners();

      logInfo('开始 MLKit OCR 识别: $imagePath', source: 'MLKitOCRService');

      // 创建输入图像
      final inputImage = InputImage.fromFilePath(imagePath);

      _status = _status.copyWith(progress: 0.3);
      notifyListeners();

      // 执行识别
      if (_textRecognizer == null) {
        throw StateError('mlkit_not_initialized');
      }
      final recognizedText = await _textRecognizer!.processImage(inputImage);

      _status = _status.copyWith(progress: 0.8);
      notifyListeners();

      // 转换结果
      final blocks = <ocr_model.TextBlock>[];
      for (final block in recognizedText.blocks) {
        blocks.add(ocr_model.TextBlock(
          text: block.text,
          boundingBox: block.boundingBox,
          confidence: block.recognizedLanguages.isNotEmpty
              ? 1.0 // MLKit 不提供置信度，默认 1.0
              : 0.9,
          language: block.recognizedLanguages.isNotEmpty
              ? block.recognizedLanguages.first
              : null,
        ));
      }

      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds;

      final result = ocr_model.OCRResult(
        fullText: recognizedText.text,
        blocks: blocks,
        imagePath: imagePath,
        processingTimeMs: processingTime,
        languages: const ['auto'], // MLKit 自动检测
      );

      _status = const ocr_model.OCRStatus(
          state: ocr_model.OCRState.completed, progress: 1.0);
      notifyListeners();

      logInfo(
        'MLKit OCR 识别完成: ${recognizedText.text.length} 字符, '
        '${blocks.length} 块, ${processingTime}ms',
        source: 'MLKitOCRService',
      );

      return result;
    } catch (e) {
      _status = ocr_model.OCRStatus(
        state: ocr_model.OCRState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('MLKit OCR 识别失败: $e', source: 'MLKitOCRService');
      rethrow;
    }
  }

  /// 取消当前识别
  void cancelRecognition() {
    if (_status.isProcessing) {
      _status = ocr_model.OCRStatus.idle;
      notifyListeners();
      logInfo('取消 MLKit OCR 识别', source: 'MLKitOCRService');
    }
  }

  /// 重置状态
  void reset() {
    _status = ocr_model.OCRStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    cancelRecognition();
    _textRecognizer?.close();
    _textRecognizer = null;
    super.dispose();
  }
}
