/// OCR 文字识别服务
///
/// 使用 flutter_tesseract_ocr 进行设备端图像文字识别

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/ocr_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';

/// OCR 服务
class OCRService extends ChangeNotifier {
  static OCRService? _instance;

  /// 单例实例
  static OCRService get instance {
    _instance ??= OCRService._();
    return _instance!;
  }

  OCRService._();

  /// 模型管理器
  final ModelManager _modelManager = ModelManager.instance;

  /// 当前状态
  OCRStatus _status = OCRStatus.idle;

  /// 是否已初始化
  bool _initialized = false;

  /// 支持的语言
  final List<String> _supportedLanguages = ['chi_sim', 'eng'];

  /// 获取当前状态
  OCRStatus get status => _status;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 获取支持的语言
  List<String> get supportedLanguages => List.unmodifiable(_supportedLanguages);

  /// 检查 OCR 模型是否可用
  bool get isModelAvailable {
    return _modelManager.isModelDownloaded('tesseract-chi-sim-eng');
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 确保模型管理器已初始化
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 检查是否有可用的 OCR 模型
      if (!isModelAvailable) {
        logInfo('OCR 模型未下载，文字识别功能暂不可用', source: 'OCRService');
      }

      _initialized = true;
      logInfo('OCR 服务初始化完成', source: 'OCRService');
    } catch (e) {
      logError('OCR 服务初始化失败: $e', source: 'OCRService');
      rethrow;
    }
  }

  /// 从图片文件识别文字
  Future<OCRResult> recognizeFromFile(
    String imagePath, {
    List<String>? languages,
  }) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    final langs = languages ?? _supportedLanguages;
    final startTime = DateTime.now();

    try {
      _status = const OCRStatus(state: OCRState.processing, progress: 0.0);
      notifyListeners();

      // TODO: 集成 flutter_tesseract_ocr 进行实际识别
      logInfo(
        '从文件识别文字（占位实现）: $imagePath, 语言: $langs',
        source: 'OCRService',
      );

      // 模拟识别过程
      for (var i = 0; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        _status = _status.copyWith(progress: i / 10);
        notifyListeners();
      }

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      final result = OCRResult(
        fullText: 'OCR 功能需要下载 Tesseract 模型后使用\n请在设置 > 本地 AI 功能 > 模型管理中下载 OCR 模型',
        imagePath: imagePath,
        processingTimeMs: processingTime,
        languages: langs,
      );

      _status = const OCRStatus(state: OCRState.completed, progress: 1.0);
      notifyListeners();

      return result;
    } catch (e) {
      _status = OCRStatus(
        state: OCRState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('OCR 识别失败: $e', source: 'OCRService');
      rethrow;
    }
  }

  /// 从图片文件识别文字并返回区域信息
  Future<OCRResult> recognizeWithRegions(
    String imagePath, {
    List<String>? languages,
  }) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    final langs = languages ?? _supportedLanguages;
    final startTime = DateTime.now();

    try {
      _status = const OCRStatus(state: OCRState.processing, progress: 0.0);
      notifyListeners();

      // TODO: 集成 flutter_tesseract_ocr 进行实际识别（带区域信息）
      logInfo(
        '从文件识别文字区域（占位实现）: $imagePath',
        source: 'OCRService',
      );

      // 模拟识别过程
      await Future.delayed(const Duration(milliseconds: 500));

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      // 返回模拟的区域结果
      final result = OCRResult(
        fullText: 'OCR 区域识别功能需要集成 flutter_tesseract_ocr 后实现',
        blocks: const [],
        imagePath: imagePath,
        processingTimeMs: processingTime,
        languages: langs,
      );

      _status = const OCRStatus(state: OCRState.completed, progress: 1.0);
      notifyListeners();

      return result;
    } catch (e) {
      _status = OCRStatus(
        state: OCRState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('OCR 区域识别失败: $e', source: 'OCRService');
      rethrow;
    }
  }

  /// 从字节数据识别文字
  Future<OCRResult> recognizeFromBytes(
    Uint8List imageBytes, {
    List<String>? languages,
  }) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    try {
      _status = const OCRStatus(state: OCRState.processing, progress: 0.0);
      notifyListeners();

      // TODO: 集成 flutter_tesseract_ocr 进行实际识别
      logInfo(
        '从字节数据识别文字（占位实现）: ${imageBytes.length} bytes',
        source: 'OCRService',
      );

      await Future.delayed(const Duration(milliseconds: 300));

      final result = OCRResult(
        fullText: 'OCR 功能需要下载 Tesseract 模型后使用',
        languages: languages ?? _supportedLanguages,
      );

      _status = const OCRStatus(state: OCRState.completed, progress: 1.0);
      notifyListeners();

      return result;
    } catch (e) {
      _status = OCRStatus(
        state: OCRState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('OCR 识别失败: $e', source: 'OCRService');
      rethrow;
    }
  }

  /// 取消当前识别
  void cancelRecognition() {
    if (_status.isProcessing) {
      _status = OCRStatus.idle;
      notifyListeners();
      logInfo('取消 OCR 识别', source: 'OCRService');
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
    super.dispose();
  }
}
