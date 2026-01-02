/// OCR 文字识别服务
///
/// 使用 flutter_tesseract_ocr 进行设备端图像文字识别

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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

  /// Tesseract 数据目录
  String? _tessDataPath;

  /// 支持的语言
  final List<String> _supportedLanguages = ['chi_sim', 'eng'];

  /// 获取当前状态
  OCRStatus get status => _status;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 获取支持的语言
  List<String> get supportedLanguages => List.unmodifiable(_supportedLanguages);

  /// 检查 OCR 模型是否可用
  /// 只要有任意一个语言模型可用即返回 true
  bool get isModelAvailable {
    return _modelManager.isModelDownloaded('tesseract-chi-sim') ||
        _modelManager.isModelDownloaded('tesseract-eng');
  }

  /// 检查特定语言是否可用
  bool isLanguageAvailable(String lang) {
    if (lang == 'chi_sim') {
      return _modelManager.isModelDownloaded('tesseract-chi-sim');
    } else if (lang == 'eng') {
      return _modelManager.isModelDownloaded('tesseract-eng');
    }
    return false;
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 确保模型管理器已初始化
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 设置 tessdata 目录
      await _setupTessDataPath();

      // 同步已下载的 traineddata 到 tessdata，并刷新可用语言
      await _syncTrainedDataToTessdata();
      await _refreshAvailableLanguages();

      // 检查是否有可用的 OCR 模型
      if (!isModelAvailable) {
        logInfo('OCR 模型未下载，文字识别功能暂不可用', source: 'OCRService');
      }

      _initialized = true;
      logInfo('OCR 服务初始化完成', source: 'OCRService');
    } catch (e) {
      logError('OCR 服务初始化失败: $e', source: 'OCRService');
      // 不抛出错误，允许服务继续运行
      _initialized = true;
    }
  }

  /// 设置 tessdata 路径
  Future<void> _setupTessDataPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    _tessDataPath = path.join(appDir.path, 'local_ai_models', 'tessdata');
    
    final dir = Directory(_tessDataPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 将 ModelManager 下载的 *.traineddata 同步到 tessdata 目录。
  ///
  /// flutter_tesseract_ocr 依赖 tessdata 目录结构；而 ModelManager 的下载默认落在
  /// local_ai_models 根目录，因此这里做一次复制/覆盖，保证 OCR 真正可用。
  Future<void> _syncTrainedDataToTessdata() async {
    if (_tessDataPath == null || !_modelManager.isInitialized) return;
    final modelsDir = _modelManager.modelsDirectory;
    if (modelsDir == null) return;

    try {
      final dir = Directory(modelsDir);
      if (!await dir.exists()) return;

      final trainedDataFiles = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.traineddata'))
          .cast<File>()
          .toList();

      if (trainedDataFiles.isEmpty) return;

      for (final file in trainedDataFiles) {
        final fileName = path.basename(file.path);
        final destPath = path.join(_tessDataPath!, fileName);
        final destFile = File(destPath);

        // 只有在目标不存在或大小不一致时才复制，减少 IO。
        final srcSize = await file.length();
        final destExists = await destFile.exists();
        final destSize = destExists ? await destFile.length() : -1;

        if (!destExists || destSize != srcSize) {
          await file.copy(destPath);
          logInfo('同步 tessdata 文件: $fileName', source: 'OCRService');
        }
      }
    } catch (e) {
      // 同步失败不应阻断初始化，后续仍可提示用户重新下载/导入。
      logError('同步 tessdata 失败: $e', source: 'OCRService');
    }
  }

  /// 刷新可用语言列表：仅保留 tessdata 下存在的 traineddata。
  Future<void> _refreshAvailableLanguages() async {
    if (_tessDataPath == null) return;

    try {
      final available = <String>[];
      for (final lang in ['chi_sim', 'eng']) {
        final trainedData = File(path.join(_tessDataPath!, '$lang.traineddata'));
        if (await trainedData.exists()) {
          available.add(lang);
        }
      }

      if (available.isNotEmpty) {
        _supportedLanguages
          ..clear()
          ..addAll(available);
      }
    } catch (e) {
      logError('刷新 OCR 可用语言失败: $e', source: 'OCRService');
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

    final requestedLangs = languages ?? _supportedLanguages;
    final langs = await _filterAvailableLanguages(requestedLangs);
    final startTime = DateTime.now();

    try {
      _status = const OCRStatus(state: OCRState.processing, progress: 0.0);
      notifyListeners();

      String recognizedText = '';

      if (isModelAvailable && _tessDataPath != null) {
        // 使用 flutter_tesseract_ocr 进行识别
        logInfo('开始 OCR 识别: $imagePath, 语言: $langs', source: 'OCRService');
        
        _status = _status.copyWith(progress: 0.3);
        notifyListeners();

        // 调用 Tesseract OCR
        recognizedText = await FlutterTesseractOcr.extractText(
          imagePath,
          language: langs.join('+'),
          args: {
            'tessdata': _tessDataPath!,
            'psm': '3', // 自动页面分割
            'oem': '1', // LSTM 引擎
          },
        );

        _status = _status.copyWith(progress: 0.9);
        notifyListeners();
      } else {
        // 模型不可用，提示用户下载
        recognizedText = '请先下载 OCR 模型';
        logInfo('OCR 模型未下载', source: 'OCRService');
      }

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      final result = OCRResult(
        fullText: recognizedText,
        imagePath: imagePath,
        processingTimeMs: processingTime,
        languages: langs,
      );

      _status = const OCRStatus(state: OCRState.completed, progress: 1.0);
      notifyListeners();

      logInfo('OCR 识别完成: ${recognizedText.length} 字符', source: 'OCRService');
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

    final requestedLangs = languages ?? _supportedLanguages;
    final langs = await _filterAvailableLanguages(requestedLangs);
    final startTime = DateTime.now();

    try {
      _status = const OCRStatus(state: OCRState.processing, progress: 0.0);
      notifyListeners();

      String recognizedText = '';
      List<TextBlock> blocks = [];

      if (isModelAvailable && _tessDataPath != null) {
        logInfo('开始 OCR 区域识别: $imagePath', source: 'OCRService');

        // 使用 flutter_tesseract_ocr 进行识别
        recognizedText = await FlutterTesseractOcr.extractText(
          imagePath,
          language: langs.join('+'),
          args: {
            'tessdata': _tessDataPath!,
            'psm': '3',
            'oem': '1',
          },
        );

        // 将识别结果作为单个文本块
        if (recognizedText.isNotEmpty) {
          blocks = [
            TextBlock(
              text: recognizedText,
              // flutter_tesseract_ocr 暂不提供区域坐标，这里用占位 Rect。
              // UI 侧如果需要区域选择，可在后续接入支持 bbox 的 OCR 引擎时完善。
              boundingBox: const Rect.fromLTWH(0, 0, 1, 1),
              confidence: 0.9,
            ),
          ];
        }
      } else {
        recognizedText = '请先下载 OCR 模型';
      }

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      final result = OCRResult(
        fullText: recognizedText,
        blocks: blocks,
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

      // 将字节数据保存为临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(tempDir.path, 'ocr_temp_${DateTime.now().millisecondsSinceEpoch}.png'));
      await tempFile.writeAsBytes(imageBytes);

      try {
        // 使用文件路径进行识别
        final result = await recognizeFromFile(
          tempFile.path,
          languages: languages,
        );

        return result;
      } finally {
        // 清理临时文件
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
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

  /// 过滤掉当前 tessdata 中不存在的语言。
  ///
  /// 若全部不可用，则回退到当前 _supportedLanguages；若仍为空则保持原样，交由底层报错。
  Future<List<String>> _filterAvailableLanguages(List<String> langs) async {
    if (_tessDataPath == null) return langs;

    try {
      final filtered = <String>[];
      for (final lang in langs) {
        final trainedData = File(path.join(_tessDataPath!, '$lang.traineddata'));
        if (await trainedData.exists()) {
          filtered.add(lang);
        }
      }

      if (filtered.isNotEmpty) return filtered;
      return _supportedLanguages.isNotEmpty ? List.unmodifiable(_supportedLanguages) : langs;
    } catch (_) {
      return langs;
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
