import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../utils/app_logger.dart';

/// ONNX Runtime 推理服务
/// 
/// 负责加载和运行 ONNX 模型进行推理
class ONNXInferenceService extends ChangeNotifier {
  static final ONNXInferenceService _instance = ONNXInferenceService._internal();
  factory ONNXInferenceService() => _instance;
  ONNXInferenceService._internal();

  /// 已加载的模型会话缓存
  final Map<String, OrtSession> _sessions = {};
  
  /// 模型加载状态
  final Map<String, bool> _loadingStatus = {};
  
  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 初始化 ONNX Runtime 环境
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _isInitialized = true;
      logInfo('ONNX Runtime 环境初始化成功', source: 'ONNXInferenceService');
    } catch (e, stackTrace) {
      logError(
        'ONNX Runtime 环境初始化失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'ONNXInferenceService',
      );
      rethrow;
    }
  }

  /// 从 assets 或文件系统加载模型
  /// 
  /// [modelId] 模型的唯一标识符
  /// [modelPath] 模型文件路径（assets 路径或文件系统路径）
  /// [isAsset] 是否为 asset 资源
  Future<void> loadModel(
    String modelId,
    String modelPath, {
    bool isAsset = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // 检查是否正在加载或已加载
    if (_loadingStatus[modelId] == true) {
      logDebug('模型 $modelId 正在加载中...', source: 'ONNXInferenceService');
      return;
    }
    
    if (_sessions.containsKey(modelId)) {
      logDebug('模型 $modelId 已加载', source: 'ONNXInferenceService');
      return;
    }

    _loadingStatus[modelId] = true;
    notifyListeners();

    try {
      Uint8List modelBytes;
      
      if (isAsset) {
        // 从 assets 加载
        final ByteData data = await rootBundle.load(modelPath);
        modelBytes = data.buffer.asUint8List();
      } else {
        // 从文件系统加载
        final file = File(modelPath);
        if (!await file.exists()) {
          throw FileSystemException('模型文件不存在', modelPath);
        }
        modelBytes = await file.readAsBytes();
      }

      // 创建会话选项
      final sessionOptions = OrtSessionOptions();
      
      // 创建会话
      final session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _sessions[modelId] = session;
      
      logInfo(
        '模型 $modelId 加载成功, 输入数: ${session.inputCount}, 输出数: ${session.outputCount}',
        source: 'ONNXInferenceService',
      );
    } catch (e, stackTrace) {
      logError(
        '加载模型 $modelId 失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'ONNXInferenceService',
      );
      rethrow;
    } finally {
      _loadingStatus[modelId] = false;
      notifyListeners();
    }
  }

  /// 从 URL 下载并加载模型
  Future<void> loadModelFromUrl(
    String modelId,
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory(path.join(appDir.path, 'models'));
    await modelDir.create(recursive: true);
    
    final modelFile = File(path.join(modelDir.path, '$modelId.onnx'));
    
    // 如果模型已存在，直接加载
    if (await modelFile.exists()) {
      await loadModel(modelId, modelFile.path);
      return;
    }

    // 下载模型
    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw HttpException('下载模型失败: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final sink = modelFile.openWrite();
      
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }
      
      await sink.close();
      httpClient.close();
      
      // 加载下载的模型
      await loadModel(modelId, modelFile.path);
    } catch (e) {
      // 清理失败的下载
      if (await modelFile.exists()) {
        await modelFile.delete();
      }
      rethrow;
    }
  }

  /// 运行模型推理
  /// 
  /// [modelId] 模型标识符
  /// [inputs] 输入张量映射，key 为输入名称
  /// 
  /// 返回输出张量映射
  Future<Map<String, OrtValue>> runInference(
    String modelId,
    Map<String, OrtValue> inputs,
  ) async {
    final session = _sessions[modelId];
    if (session == null) {
      throw StateError('模型 $modelId 未加载');
    }

    try {
      final runOptions = OrtRunOptions();
      final results = await session.runAsync(runOptions, inputs);
      
      // 转换结果为 Map
      final outputMap = <String, OrtValue>{};
      if (results != null) {
        for (var i = 0; i < results.length; i++) {
          final outputName = session.outputNames[i];
          if (results[i] != null) {
            outputMap[outputName] = results[i]!;
          }
        }
      }
      
      return outputMap;
    } catch (e, stackTrace) {
      logError(
        '模型 $modelId 推理失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'ONNXInferenceService',
      );
      rethrow;
    }
  }

  /// 获取模型输入信息
  List<String> getInputNames(String modelId) {
    final session = _sessions[modelId];
    if (session == null) {
      throw StateError('模型 $modelId 未加载');
    }
    return session.inputNames;
  }

  /// 获取模型输出信息
  List<String> getOutputNames(String modelId) {
    final session = _sessions[modelId];
    if (session == null) {
      throw StateError('模型 $modelId 未加载');
    }
    return session.outputNames;
  }

  /// 检查模型是否已加载
  bool isModelLoaded(String modelId) => _sessions.containsKey(modelId);

  /// 检查模型是否正在加载
  bool isModelLoading(String modelId) => _loadingStatus[modelId] == true;

  /// 卸载模型
  void unloadModel(String modelId) {
    final session = _sessions.remove(modelId);
    if (session != null) {
      session.release();
      logInfo('模型 $modelId 已卸载', source: 'ONNXInferenceService');
      notifyListeners();
    }
  }

  /// 卸载所有模型
  void unloadAllModels() {
    for (final entry in _sessions.entries) {
      entry.value.release();
    }
    _sessions.clear();
    _loadingStatus.clear();
    logInfo('所有模型已卸载', source: 'ONNXInferenceService');
    notifyListeners();
  }

  /// 获取已加载模型列表
  List<String> get loadedModels => _sessions.keys.toList();

  @override
  void dispose() {
    unloadAllModels();
    super.dispose();
  }
}
