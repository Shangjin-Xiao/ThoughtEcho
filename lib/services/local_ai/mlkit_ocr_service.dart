/// MLKit OCR 文字识别服务
///
/// 使用 Google MLKit 进行设备端图像文字识别
/// 适合印刷体文字，准确率高、速度快

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../models/ocr_result.dart';
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
  OCRStatus _status = OCRStatus.idle;

  /// 是否已初始化
  bool _initialized = false;

  /// 识别脚本（语言）
  TextRecognitionScript _script = TextRecognitionScript.chinese;

  /// 获取当前状态
  OCRStatus get status => _status;

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
      _initialized = true; // 允许继续
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
  Future<OCRResult> recognizeFromFile(
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
      _status = const OCRStatus(state: OCRState.processing, progress: 0.0);
      notifyListeners();

      logInfo('开始 MLKit OCR 识别: $imagePath', source: 'MLKitOCRService');

      // 创建输入图像
      final inputImage = InputImage.fromFilePath(imagePath);

      _status = _status.copyWith(progress: 0.3);
      notifyListeners();

      // 执行识别
      final recognizedText = await _textRecognizer!.processImage(inputImage);

      _status = _status.copyWith(progress: 0.8);
      notifyListeners();

      // 转换结果
      final blocks = <TextBlock>[];
      for (final block in recognizedText.blocks) {
        blocks.add(TextBlock(
          text: block.text,
          boundingBox: block.boundingBox,
          confidence: block.recognizedLanguages.isNotEmpty
              ? 1.0 // MLKit 不提供置信度，默认 1.0
              : 0.9,
          language: block.recognizedLanguages.isNotEmpty
              ? block.recognizedLanguages.first.languageCode
              : null,
        ));
      }

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      final result = OCRResult(
        fullText: recognizedText.text,
        blocks: blocks,
        imagePath: imagePath,
        processingTimeMs: processingTime,
        languages: const ['auto'], // MLKit 自动检测
      );

      _status = const OCRStatus(state: OCRState.completed, progress: 1.0);
      notifyListeners();

      logInfo(
        'MLKit OCR 识别完成: ${recognizedText.text.length} 字符, '
        '${blocks.length} 块, ${processingTime}ms',
        source: 'MLKitOCRService',
      );

      return result;
    } catch (e) {
      _status = OCRStatus(
        state: OCRState.error,
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
      _status = OCRStatus.idle;
      notifyListeners();
      logInfo('取消 MLKit OCR 识别', source: 'MLKitOCRService');
    }
  }

  /// 重置状态
  void reset() {
    _status = OCRStatus.idle;
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
