/// 混合 OCR 服务
///
/// 智能选择使用 MLKit、Tesseract 或 VLM 进行文字识别
/// - 印刷体（移动端） → MLKit（快速、准确）
/// - 印刷体（桌面端） → Tesseract（轻量、兼容）
/// - 手写/复杂场景 → VLM（准确、智能）

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/ocr_result.dart';
import '../../utils/app_logger.dart';
import 'mlkit_ocr_service.dart';
import 'vlm_ocr_service.dart';
import 'image_preprocessor.dart';

/// OCR 引擎类型
enum OCREngineType {
  /// MLKit 引擎（移动端主力，适合印刷体）
  mlkit,

  /// VLM 引擎（视觉语言模型，适合手写和复杂场景）
  vlm,

  /// 自动选择（根据图像特征智能选择）
  auto,
}

/// 混合 OCR 服务
class HybridOCRService extends ChangeNotifier {
  static HybridOCRService? _instance;

  static HybridOCRService get instance {
    _instance ??= HybridOCRService._();
    return _instance!;
  }

  HybridOCRService._();

  final MLKitOCRService _mlkitService = MLKitOCRService.instance;
  final VLMOCRService _vlmService = VLMOCRService.instance;

  bool _initialized = false;
  OCREngineType _preferredEngine = OCREngineType.auto;

  bool get isInitialized => _initialized;
  OCREngineType get preferredEngine => _preferredEngine;

  /// 设置首选引擎
  void setPreferredEngine(OCREngineType engine) {
    _preferredEngine = engine;
    notifyListeners();
    logInfo('OCR 引擎设置为: $engine', source: 'HybridOCRService');
  }

  /// 检查 MLKit 是否可用（仅移动端）
  bool get isMLKitAvailable {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 检查 VLM 是否可用
  bool get isVLMAvailable => _vlmService.isModelAvailable;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      logInfo('初始化混合 OCR 服务...', source: 'HybridOCRService');

      // 初始化所有引擎
      final futures = <Future>[];

      if (isMLKitAvailable) {
        futures.add(_mlkitService.initialize());
      }

      futures.add(_vlmService.initialize());

      await Future.wait(futures);

      _initialized = true;
      logInfo('混合 OCR 服务初始化完成', source: 'HybridOCRService');
      logInfo('MLKit 可用: $isMLKitAvailable', source: 'HybridOCRService');
      logInfo('VLM 可用: $isVLMAvailable', source: 'HybridOCRService');
    } catch (e) {
      logError('混合 OCR 服务初始化失败: $e', source: 'HybridOCRService');
      _initialized = true;
    }
  }

  /// 智能识别文字
  ///
  /// 根据设置和图像特征自动选择最佳引擎
  Future<OCRResult> recognizeFromFile(
    String imagePath, {
    OCREngineType? engineType,
    List<String>? languages,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    final engine = engineType ?? _preferredEngine;

    try {
      // 根据引擎类型选择
      switch (engine) {
        case OCREngineType.mlkit:
          return await _recognizeWithMLKit(imagePath);

        case OCREngineType.vlm:
          return await _recognizeWithVLM(imagePath);

        case OCREngineType.auto:
          return await _recognizeAuto(imagePath, languages);
      }
    } catch (e) {
      logError('OCR 识别失败: $e', source: 'HybridOCRService');
      rethrow;
    }
  }

  /// 使用 MLKit 识别
  Future<OCRResult> _recognizeWithMLKit(String imagePath) async {
    if (!isMLKitAvailable) {
      throw Exception('mlkit_not_available');
    }

    logInfo('使用 MLKit 引擎识别', source: 'HybridOCRService');
    return await _mlkitService.recognizeFromFile(imagePath);
  }

  /// 使用 VLM 识别
  Future<OCRResult> _recognizeWithVLM(String imagePath) async {
    if (!isVLMAvailable) {
      throw Exception('vlm_not_available');
    }

    logInfo('使用 VLM 引擎识别', source: 'HybridOCRService');
    return await _vlmService.recognizeFromFile(
      imagePath,
      mode: VLMOCRMode.handwritten, // 默认使用手写模式
    );
  }

  /// 自动选择引擎识别
  Future<OCRResult> _recognizeAuto(
    String imagePath,
    List<String>? languages,
  ) async {
    logInfo('自动选择 OCR 引擎...', source: 'HybridOCRService');

    // 检测图像类型
    final config = await ImagePreprocessor.detectImageType(imagePath);

    // 判断是否为手写
    final isHandwritten = config == PreprocessConfig.handwritten;

    logInfo('图像类型检测: ${isHandwritten ? "手写" : "印刷体"}',
        source: 'HybridOCRService');

    // 决策逻辑：
    // 1. 手写 + VLM 可用 → 使用 VLM
    // 2. 印刷体 + MLKit 可用（移动端） → 使用 MLKit
    // 3. 优先引擎不可用，回退到 MLKit/VLM
    // 4. 回退策略

    if (isHandwritten && isVLMAvailable) {
      logInfo('检测到手写文字，使用 VLM 引擎', source: 'HybridOCRService');
      return await _recognizeWithVLM(imagePath);
    } else if (!isHandwritten && isMLKitAvailable) {
      logInfo('检测到印刷体（移动端），使用 MLKit 引擎', source: 'HybridOCRService');
      return await _recognizeWithMLKit(imagePath);
    } else if (isMLKitAvailable) {
      logInfo('优先引擎不可用，回退到 MLKit', source: 'HybridOCRService');
      return await _recognizeWithMLKit(imagePath);
    } else if (isVLMAvailable) {
      logInfo('MLKit 不可用，回退到 VLM', source: 'HybridOCRService');
      return await _recognizeWithVLM(imagePath);
    } else {
      throw Exception('no_ocr_engine_available');
    }
  }

  /// 使用两个引擎并比较结果（用于调试和对比）
  Future<Map<String, OCRResult>> recognizeWithBoth(
    String imagePath, {
    List<String>? languages,
  }) async {
    final results = <String, OCRResult>{};

    // 并行运行引擎
    final futures = <Future<MapEntry<String, OCRResult>>>[];

    if (isMLKitAvailable) {
      futures.add(
        _recognizeWithMLKit(imagePath)
            .then((r) => MapEntry('mlkit', r))
            .catchError((e) {
          logError('MLKit 识别失败: $e', source: 'HybridOCRService');
          return MapEntry('mlkit', OCRResult.empty);
        }),
      );
    }

    if (isVLMAvailable) {
      futures.add(
        _recognizeWithVLM(imagePath)
            .then((r) => MapEntry('vlm', r))
            .catchError((e) {
          logError('VLM 识别失败: $e', source: 'HybridOCRService');
          return MapEntry('vlm', OCRResult.empty);
        }),
      );
    }

    final entries = await Future.wait(futures);
    for (final entry in entries) {
      results[entry.key] = entry.value;
    }

    return results;
  }

  /// 获取当前使用的引擎
  String getCurrentEngine() {
    if (_preferredEngine == OCREngineType.vlm) {
      return 'VLM (视觉语言模型)';
    } else {
      return '自动选择';
    }
  }

  /// 获取引擎推荐
  String getEngineRecommendation(bool isHandwritten) {
    if (isHandwritten) {
      if (isVLMAvailable) {
        return '推荐使用 VLM 引擎识别手写文字';
      } else {
        return '手写文字建议下载 VLM 模型以获得更好效果';
      }
    } else {
      // 印刷体
      return '推荐使用自动选择';
    }
  }

  @override
  void dispose() {
    // 不直接 dispose 单例服务
    super.dispose();
  }
}
