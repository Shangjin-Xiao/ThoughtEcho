/// 本地 AI 模型管理器
///
/// 负责模型的下载、存储、加载和生命周期管理

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../models/local_ai_model.dart';
import '../../utils/app_logger.dart';

/// 模型管理器
class ModelManager extends ChangeNotifier {
  static ModelManager? _instance;

  /// 单例实例
  static ModelManager get instance {
    _instance ??= ModelManager._();
    return _instance!;
  }

  ModelManager._();

  /// 模型存储目录
  String? _modelsDirectory;

  /// 当前模型状态
  final Map<String, LocalAIModelInfo> _modelStates = {};

  /// 下载任务
  final Map<String, _DownloadTask> _downloadTasks = {};

  /// 是否已初始化
  bool _initialized = false;

  /// 获取是否已初始化
  bool get isInitialized => _initialized;

  /// 获取模型目录
  String? get modelsDirectory => _modelsDirectory;

  /// 获取所有模型状态
  List<LocalAIModelInfo> get models => _modelStates.values.toList();

  /// 获取指定类型的模型
  List<LocalAIModelInfo> getModelsByType(LocalAIModelType type) {
    return _modelStates.values.where((m) => m.type == type).toList();
  }

  /// 获取已下载的模型
  List<LocalAIModelInfo> get downloadedModels {
    return _modelStates.values
        .where(
          (m) =>
              m.status == LocalAIModelStatus.downloaded ||
              m.status == LocalAIModelStatus.loaded,
        )
        .toList();
  }

  /// 初始化模型管理器
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 获取模型存储目录
      final appDir = await getApplicationDocumentsDirectory();
      _modelsDirectory = path.join(appDir.path, 'local_ai_models');

      // 确保目录存在
      final dir = Directory(_modelsDirectory!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 初始化预定义模型状态
      for (final model in LocalAIModels.all) {
        final status = await _checkModelStatus(model);
        _modelStates[model.id] = model.copyWith(status: status);
      }

      _initialized = true;
      logInfo('模型管理器初始化完成', source: 'ModelManager');
      notifyListeners();
    } catch (e) {
      logError('模型管理器初始化失败: $e', source: 'ModelManager');
      rethrow;
    }
  }

  /// 检查模型状态
  Future<LocalAIModelStatus> _checkModelStatus(LocalAIModelInfo model) async {
    if (_modelsDirectory == null) return LocalAIModelStatus.notDownloaded;

    final modelPath = path.join(_modelsDirectory!, model.fileName);
    final file = File(modelPath);

    if (await file.exists()) {
      return LocalAIModelStatus.downloaded;
    }

    return LocalAIModelStatus.notDownloaded;
  }

  /// 获取模型信息
  LocalAIModelInfo? getModel(String modelId) {
    return _modelStates[modelId];
  }

  /// 检查模型是否已下载
  bool isModelDownloaded(String modelId) {
    final model = _modelStates[modelId];
    return model != null &&
        (model.status == LocalAIModelStatus.downloaded ||
            model.status == LocalAIModelStatus.loaded);
  }

  /// 检查模型是否已加载
  bool isModelLoaded(String modelId) {
    final model = _modelStates[modelId];
    return model != null && model.status == LocalAIModelStatus.loaded;
  }

  /// 开始下载模型
  Future<void> downloadModel(
    String modelId, {
    void Function(double progress)? onProgress,
    void Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    final model = _modelStates[modelId];
    if (model == null) {
      onError?.call('模型不存在: $modelId');
      return;
    }

    if (model.status == LocalAIModelStatus.downloading) {
      logDebug('模型 $modelId 正在下载中', source: 'ModelManager');
      return;
    }

    if (model.status == LocalAIModelStatus.downloaded ||
        model.status == LocalAIModelStatus.loaded) {
      logDebug('模型 $modelId 已下载', source: 'ModelManager');
      onComplete?.call();
      return;
    }

    // 更新状态为下载中
    _updateModelState(
      modelId,
      model.copyWith(
        status: LocalAIModelStatus.downloading,
        downloadProgress: 0.0,
      ),
    );

    try {
      // 创建下载任务
      final task = _DownloadTask(
        modelId: modelId,
        url: model.downloadUrl,
        savePath: path.join(_modelsDirectory!, model.fileName),
        onProgress: (progress) {
          _updateModelState(
            modelId,
            _modelStates[modelId]!.copyWith(downloadProgress: progress),
          );
          onProgress?.call(progress);
        },
        onComplete: () {
          _updateModelState(
            modelId,
            _modelStates[modelId]!.copyWith(
              status: LocalAIModelStatus.downloaded,
              downloadProgress: 1.0,
            ),
          );
          _downloadTasks.remove(modelId);
          onComplete?.call();
          logInfo('模型 $modelId 下载完成', source: 'ModelManager');
        },
        onError: (error) {
          _updateModelState(
            modelId,
            _modelStates[modelId]!.copyWith(
              status: LocalAIModelStatus.error,
              errorMessage: error,
            ),
          );
          _downloadTasks.remove(modelId);
          onError?.call(error);
          logError('模型 $modelId 下载失败: $error', source: 'ModelManager');
        },
      );

      _downloadTasks[modelId] = task;

      // 注意：实际下载需要集成具体的下载库
      // 这里提供占位实现，等待后续集成 flutter_gemma 等库
      logInfo('开始下载模型 $modelId (占位实现)', source: 'ModelManager');

      // 模拟下载进度（实际实现时替换为真实下载逻辑）
      await _simulateDownload(task);
    } catch (e) {
      _updateModelState(
        modelId,
        model.copyWith(
          status: LocalAIModelStatus.error,
          errorMessage: e.toString(),
        ),
      );
      onError?.call(e.toString());
    }
  }

  /// 模拟下载（占位实现）
  Future<void> _simulateDownload(_DownloadTask task) async {
    // 实际实现时，这里应该使用 HTTP 客户端下载文件
    // 目前仅作为占位，返回错误提示需要集成具体的模型库
    // Note: Error message intentionally in English for logging - UI should use localization
    task.onError('Model download requires flutter_gemma, sherpa_onnx integration');
  }

  /// 取消下载
  Future<void> cancelDownload(String modelId) async {
    final task = _downloadTasks[modelId];
    if (task != null) {
      task.cancel();
      _downloadTasks.remove(modelId);

      final model = _modelStates[modelId];
      if (model != null) {
        _updateModelState(
          modelId,
          model.copyWith(
            status: LocalAIModelStatus.notDownloaded,
            downloadProgress: 0.0,
          ),
        );
      }

      logInfo('取消下载模型 $modelId', source: 'ModelManager');
    }
  }

  /// 删除模型
  Future<void> deleteModel(String modelId) async {
    final model = _modelStates[modelId];
    if (model == null || _modelsDirectory == null) return;

    try {
      final modelPath = path.join(_modelsDirectory!, model.fileName);
      final file = File(modelPath);

      if (await file.exists()) {
        await file.delete();
      }

      _updateModelState(
        modelId,
        model.copyWith(
          status: LocalAIModelStatus.notDownloaded,
          downloadProgress: 0.0,
        ),
      );

      logInfo('删除模型 $modelId', source: 'ModelManager');
    } catch (e) {
      logError('删除模型 $modelId 失败: $e', source: 'ModelManager');
      rethrow;
    }
  }

  /// 从本地文件导入模型
  Future<void> importModel(String modelId, String filePath) async {
    final model = _modelStates[modelId];
    if (model == null || _modelsDirectory == null) {
      throw Exception('模型不存在或管理器未初始化');
    }

    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在');
      }

      final targetPath = path.join(_modelsDirectory!, model.fileName);
      await sourceFile.copy(targetPath);

      _updateModelState(
        modelId,
        model.copyWith(status: LocalAIModelStatus.downloaded),
      );

      logInfo('导入模型 $modelId 从 $filePath', source: 'ModelManager');
    } catch (e) {
      logError('导入模型 $modelId 失败: $e', source: 'ModelManager');
      rethrow;
    }
  }

  /// 获取模型文件路径
  String? getModelPath(String modelId) {
    final model = _modelStates[modelId];
    if (model == null || _modelsDirectory == null) return null;

    if (!isModelDownloaded(modelId)) return null;

    return path.join(_modelsDirectory!, model.fileName);
  }

  /// 更新模型状态
  void _updateModelState(String modelId, LocalAIModelInfo model) {
    _modelStates[modelId] = model;
    notifyListeners();
  }

  /// 获取总存储占用
  Future<int> getTotalStorageUsage() async {
    if (_modelsDirectory == null) return 0;

    int total = 0;
    final dir = Directory(_modelsDirectory!);

    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }

    return total;
  }

  /// 清理所有模型
  Future<void> clearAllModels() async {
    if (_modelsDirectory == null) return;

    try {
      final dir = Directory(_modelsDirectory!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }

      // 重置所有模型状态
      for (final modelId in _modelStates.keys.toList()) {
        final model = _modelStates[modelId]!;
        _modelStates[modelId] = model.copyWith(
          status: LocalAIModelStatus.notDownloaded,
          downloadProgress: 0.0,
        );
      }

      notifyListeners();
      logInfo('清理所有模型完成', source: 'ModelManager');
    } catch (e) {
      logError('清理模型失败: $e', source: 'ModelManager');
      rethrow;
    }
  }

  @override
  void dispose() {
    // 取消所有下载任务
    for (final task in _downloadTasks.values) {
      task.cancel();
    }
    _downloadTasks.clear();
    super.dispose();
  }
}

/// 下载任务
class _DownloadTask {
  final String modelId;
  final String url;
  final String savePath;
  final void Function(double progress)? onProgress;
  final void Function()? onComplete;
  final void Function(String error) onError;

  bool _cancelled = false;

  _DownloadTask({
    required this.modelId,
    required this.url,
    required this.savePath,
    this.onProgress,
    this.onComplete,
    required this.onError,
  });

  void cancel() {
    _cancelled = true;
  }

  bool get isCancelled => _cancelled;
}
