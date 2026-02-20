/// 本地 AI 模型管理器
///
/// 负责模型的下载、存储、加载和生命周期管理
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide CancelToken;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_ai_model.dart';
import '../../utils/app_logger.dart';
import 'model_extractor.dart';

/// 模型管理器
class ModelManager extends ChangeNotifier {
  static ModelManager? _instance;

  /// 单例实例
  static ModelManager get instance {
    _instance ??= ModelManager._();
    return _instance!;
  }

  ModelManager._();

  /// HTTP 客户端
  final Dio _dio = Dio();

  /// 模型存储目录
  String? _modelsDirectory;

  // ==================== flutter_gemma 托管模型支持 ====================

  static const String _prefsKeyGemmaManagedUrlPrefix =
      'local_ai.managed.flutter_gemma.url.';
  static const String _prefsKeyGemmaActiveModelId =
      'local_ai.managed.flutter_gemma.active_model_id';

  /// flutter_gemma 当前“激活”的模型 id（用于避免多个托管模型同时被标记为已下载）
  String? _flutterGemmaActiveModelId;

  /// 解压后的模型目录（例如 Whisper 解压后的文件夹）
  final Map<String, String> _extractedModelPaths = {};

  /// 当前模型状态
  final Map<String, LocalAIModelInfo> _modelStates = {};

  /// 下载任务
  final Map<String, _DownloadTask> _downloadTasks = {};

  /// 取消令牌
  final Map<String, CancelToken> _cancelTokens = {};

  /// 是否已初始化
  bool _initialized = false;

  /// 获取是否已初始化
  bool get isInitialized => _initialized;

  /// 获取模型目录
  String? get modelsDirectory => _modelsDirectory;

  /// 获取解压后的模型路径
  String? getExtractedModelPath(String modelId) =>
      _extractedModelPaths[modelId];

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
      final prefs = await SharedPreferences.getInstance();
      _flutterGemmaActiveModelId = prefs.getString(_prefsKeyGemmaActiveModelId);

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

        // 如果模型已下载且需要解压，检查解压后的路径
        if (status == LocalAIModelStatus.downloaded) {
          await _checkExtractedPath(model);
        }
      }

      _initialized = true;
      logInfo('模型管理器初始化完成', source: 'ModelManager');
      notifyListeners();
    } catch (e) {
      logError('模型管理器初始化失败: $e', source: 'ModelManager');
      rethrow;
    }
  }

  /// 刷新所有模型状态（用于 pull-to-refresh）
  Future<void> refreshModelStatuses() async {
    if (!_initialized || _modelsDirectory == null) return;

    try {
      for (final model in LocalAIModels.all) {
        final status = await _checkModelStatus(model);
        final current = _modelStates[model.id];
        if (current != null && current.status != status) {
          _modelStates[model.id] = current.copyWith(status: status);
        }
        if (status == LocalAIModelStatus.downloaded) {
          await _checkExtractedPath(model);
        }
      }
      notifyListeners();
      logInfo('模型状态已刷新', source: 'ModelManager');
    } catch (e) {
      logError('刷新模型状态失败: $e', source: 'ModelManager');
    }
  }

  /// 检查并记录已解压的模型路径
  Future<void> _checkExtractedPath(LocalAIModelInfo model) async {
    if (_modelsDirectory == null) return;

    final fileName = model.fileName;
    // 检查是否是压缩文件
    if (fileName.endsWith('.tar.bz2') || fileName.endsWith('.tar.gz')) {
      // 解压目录名：去掉扩展名
      String extractDirName = fileName;
      if (fileName.endsWith('.tar.bz2')) {
        extractDirName = fileName.replaceAll('.tar.bz2', '');
      } else if (fileName.endsWith('.tar.gz')) {
        extractDirName = fileName.replaceAll('.tar.gz', '');
      }

      final extractedPath = path.join(_modelsDirectory!, extractDirName);
      final extractedDir = Directory(extractedPath);

      if (await extractedDir.exists()) {
        _extractedModelPaths[model.id] = extractedPath;
        logInfo('找到已解压的模型: ${model.id} -> $extractedPath',
            source: 'ModelManager');
      }
    }
  }

  /// 检查模型状态
  Future<LocalAIModelStatus> _checkModelStatus(LocalAIModelInfo model) async {
    if (_modelsDirectory == null) return LocalAIModelStatus.notDownloaded;

    // flutter_gemma 托管模型：只要本地文件存在且与当前 active id 匹配，就认为已下载。
    if (model.downloadUrl.startsWith('managed://flutter_gemma/')) {
      final managedPath = path.join(_modelsDirectory!, model.fileName);
      if (await File(managedPath).exists()) {
        // 验证是否是当前激活的模型
        if (_flutterGemmaActiveModelId == model.id) {
          return LocalAIModelStatus.downloaded;
        }
      }
      return LocalAIModelStatus.notDownloaded;
    }

    final modelPath = path.join(_modelsDirectory!, model.fileName);
    final file = File(modelPath);

    if (await file.exists()) {
      // 如果是压缩文件，还需要检查是否已解压
      if (model.fileName.endsWith('.tar.bz2') ||
          model.fileName.endsWith('.tar.gz')) {
        String extractDirName = model.fileName;
        if (model.fileName.endsWith('.tar.bz2')) {
          extractDirName = model.fileName.replaceAll('.tar.bz2', '');
        } else if (model.fileName.endsWith('.tar.gz')) {
          extractDirName = model.fileName.replaceAll('.tar.gz', '');
        }

        final extractedPath = path.join(_modelsDirectory!, extractDirName);
        final extractedDir = Directory(extractedPath);

        // 如果解压目录存在，才算真正下载完成
        if (await extractedDir.exists()) {
          return LocalAIModelStatus.downloaded;
        }
        // 压缩文件存在但未解压，需要解压
        return LocalAIModelStatus.downloaded; // 仍然返回 downloaded，因为文件已存在
      }
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

      // 执行实际下载
      logInfo('开始下载模型 $modelId', source: 'ModelManager');
      await _executeDownload(task);
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

  /// 执行实际的模型下载
  Future<void> _executeDownload(_DownloadTask task) async {
    // 检查是否是由特定包管理的模型
    if (task.url.startsWith('managed://')) {
      // 目前仅实现 flutter_gemma 托管模型。
      if (task.url.startsWith('managed://flutter_gemma/')) {
        await _executeFlutterGemmaManagedDownload(task);
        return;
      }

      // 其它 managed:// 仍然按“未实现”处理。
      task.onError(errorManagedModel);
      return;
    }

    final cancelToken = CancelToken();
    _cancelTokens[task.modelId] = cancelToken;

    try {
      // 确保保存目录存在
      final saveDir = Directory(path.dirname(task.savePath));
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      logInfo('开始下载模型: ${task.url}', source: 'ModelManager');

      // 使用 Dio 下载文件
      await _dio.download(
        task.url,
        task.savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (task.isCancelled) {
            cancelToken.cancel('用户取消下载');
            return;
          }
          if (total > 0) {
            // 下载占 80%，解压占 20%
            final progress = received / total * 0.8;
            task.onProgress?.call(progress);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(hours: 2), // 大文件可能需要较长时间
        ),
      );

      if (!task.isCancelled) {
        // 验证下载的文件
        final downloadedFile = File(task.savePath);
        if (await downloadedFile.exists()) {
          final fileSize = await downloadedFile.length();
          if (fileSize > 0) {
            // 检查是否需要解压
            if (task.savePath.endsWith('.tar.bz2') ||
                task.savePath.endsWith('.tar.gz')) {
              logInfo('开始解压模型: ${task.savePath}', source: 'ModelManager');
              task.onProgress?.call(0.85);

              try {
                final extractedPath = await ModelExtractor.extract(
                  task.savePath,
                  path.dirname(task.savePath),
                  onProgress: (progress) {
                    // 解压进度占 80%-100%
                    task.onProgress?.call(0.8 + progress * 0.2);
                  },
                );

                // 记录解压后的路径
                _extractedModelPaths[task.modelId] = extractedPath;
                logInfo('模型解压完成: $extractedPath', source: 'ModelManager');
              } catch (e) {
                logError('模型解压失败: $e', source: 'ModelManager');
                // 解压失败，删除下载的文件
                await downloadedFile.delete();
                throw Exception('extract_failed');
              }
            }

            task.onComplete?.call();
          } else {
            throw Exception('下载的文件为空');
          }
        } else {
          throw Exception('下载的文件不存在');
        }
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        logInfo('模型下载已取消: ${task.modelId}', source: 'ModelManager');
        task.onError(errorCancelled);
      } else {
        final errorCode = _getDioErrorCode(e);
        logError('模型下载失败: $errorCode', source: 'ModelManager');
        task.onError(errorCode);
      }
    } catch (e) {
      logError('模型下载失败: $e', source: 'ModelManager');
      task.onError(errorDownloadFailed);
    } finally {
      _cancelTokens.remove(task.modelId);
    }
  }

  /// 下载错误代码
  static const String errorConnectionTimeout = 'connection_timeout';
  static const String errorSendTimeout = 'send_timeout';
  static const String errorReceiveTimeout = 'receive_timeout';
  static const String errorModelNotFound = 'model_not_found';
  static const String errorAccessDenied = 'access_denied';
  static const String errorServerError = 'server_error';
  static const String errorCancelled = 'download_cancelled';
  static const String errorConnectionFailed = 'connection_failed';
  static const String errorDownloadFailed = 'download_failed';
  static const String errorManagedModel = 'managed_model';
  static const String errorManagedModelUrlMissing = 'managed_model_url_missing';
  static const String errorExtractFailed = 'extract_failed';

  Future<void> setFlutterGemmaManagedModelUrl(
      String modelId, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsKeyGemmaManagedUrlPrefix$modelId', url);
  }

  Future<String?> getFlutterGemmaManagedModelUrl(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefsKeyGemmaManagedUrlPrefix$modelId');
  }

  Future<void> _setFlutterGemmaActiveModelId(String modelId) async {
    _flutterGemmaActiveModelId = modelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyGemmaActiveModelId, modelId);
  }

  Future<void> _clearFlutterGemmaActiveModelIdIfMatches(String modelId) async {
    if (_flutterGemmaActiveModelId != modelId) return;
    _flutterGemmaActiveModelId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyGemmaActiveModelId);
  }

  /// FlutterGemma 全局初始化标记
  static bool _flutterGemmaInitialized = false;

  /// 确保 FlutterGemma 插件已全局初始化
  Future<void> _ensureFlutterGemmaInitialized() async {
    if (_flutterGemmaInitialized) return;
    try {
      await FlutterGemma.initialize();
      _flutterGemmaInitialized = true;
      logInfo('FlutterGemma 全局初始化完成', source: 'ModelManager');
    } catch (e) {
      logError('FlutterGemma 全局初始化失败: $e', source: 'ModelManager');
    }
  }

  Future<void> _executeFlutterGemmaManagedDownload(_DownloadTask task) async {
    if (_modelsDirectory == null) {
      task.onError(errorDownloadFailed);
      return;
    }

    // 获取真实下载地址（由用户在 UI 中配置）
    final realUrl = await getFlutterGemmaManagedModelUrl(task.modelId);
    if (realUrl == null || realUrl.trim().isEmpty) {
      task.onError(errorManagedModelUrlMissing);
      return;
    }

    // 继续沿用现有 Dio 下载流程，确保文件保存路径可控。
    final cancelToken = CancelToken();
    _cancelTokens[task.modelId] = cancelToken;

    try {
      // 确保保存目录存在
      final saveDir = Directory(path.dirname(task.savePath));
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      logInfo('开始下载 flutter_gemma 托管模型: $realUrl', source: 'ModelManager');

      await _dio.download(
        realUrl,
        task.savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (task.isCancelled) {
            cancelToken.cancel('用户取消下载');
            return;
          }
          if (total > 0) {
            final progress = received / total;
            task.onProgress?.call(progress);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(hours: 2),
        ),
      );

      if (task.isCancelled) return;

      final downloadedFile = File(task.savePath);
      if (!await downloadedFile.exists() ||
          await downloadedFile.length() <= 0) {
        throw Exception('下载的文件为空');
      }

      // 下载完成后，告诉 flutter_gemma 该模型文件路径
      await _ensureFlutterGemmaInitialized();
      final modelInfo = _modelStates[task.modelId];
      final modelType = modelInfo?.type == LocalAIModelType.embedding
          ? null // embedding 模型使用不同的安装流程
          : ModelType.gemmaIt;
      if (modelType != null) {
        await FlutterGemma.installModel(modelType: modelType)
            .fromFile(task.savePath)
            .install();
      }

      // 标记当前激活模型
      await _setFlutterGemmaActiveModelId(task.modelId);

      task.onProgress?.call(1.0);
      task.onComplete?.call();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.onError(errorCancelled);
      } else {
        task.onError(_getDioErrorCode(e));
      }
    } catch (e) {
      logError('flutter_gemma 托管模型下载失败: $e', source: 'ModelManager');
      task.onError(errorDownloadFailed);
    } finally {
      _cancelTokens.remove(task.modelId);
    }
  }

  /// 获取 Dio 错误代码
  String _getDioErrorCode(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return errorConnectionTimeout;
      case DioExceptionType.sendTimeout:
        return errorSendTimeout;
      case DioExceptionType.receiveTimeout:
        return errorReceiveTimeout;
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 404) {
          return errorModelNotFound;
        } else if (statusCode == 403) {
          return errorAccessDenied;
        }
        return '$errorServerError:$statusCode';
      case DioExceptionType.cancel:
        return errorCancelled;
      case DioExceptionType.connectionError:
        return errorConnectionFailed;
      default:
        return errorDownloadFailed;
    }
  }

  /// 取消下载
  Future<void> cancelDownload(String modelId) async {
    // 取消 Dio 下载
    final cancelToken = _cancelTokens[modelId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('cancelled');
    }
    _cancelTokens.remove(modelId);

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
      // flutter_gemma 托管模型：同时清理 flutter_gemma 的当前模型文件。
      if (model.downloadUrl.startsWith('managed://flutter_gemma/')) {
        // flutter_gemma 的 deleteModel API 在不同版本差异较大，
        // 这里不强依赖其删除能力：我们只清理本地文件并清除 active id。
        await _clearFlutterGemmaActiveModelIdIfMatches(modelId);
      }

      final modelPath = path.join(_modelsDirectory!, model.fileName);
      final file = File(modelPath);

      if (await file.exists()) {
        await file.delete();
      }

      // 删除解压后的目录（如果存在）
      final extractedPath = _extractedModelPaths[modelId];
      if (extractedPath != null) {
        final extractedDir = Directory(extractedPath);
        if (await extractedDir.exists()) {
          await extractedDir.delete(recursive: true);
        }
        _extractedModelPaths.remove(modelId);
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

      // flutter_gemma 托管模型：导入后设置模型路径，并记录 active id。
      if (model.downloadUrl.startsWith('managed://flutter_gemma/')) {
        await _ensureFlutterGemmaInitialized();
        if (model.type == LocalAIModelType.llm) {
          await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
              .fromFile(targetPath)
              .install();
        }
        await _setFlutterGemmaActiveModelId(modelId);
      }

      // 如果是压缩文件，需要解压
      if (targetPath.endsWith('.tar.bz2') || targetPath.endsWith('.tar.gz')) {
        logInfo('开始解压导入的模型: $targetPath', source: 'ModelManager');
        final extractedPath = await ModelExtractor.extract(
          targetPath,
          _modelsDirectory!,
        );
        _extractedModelPaths[modelId] = extractedPath;
        logInfo('模型解压完成: $extractedPath', source: 'ModelManager');
      }

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
  ///
  /// 对于压缩文件类型的模型（如 Whisper），返回解压后的目录路径
  /// 对于单文件模型（如 Tesseract traineddata），返回文件路径
  String? getModelPath(String modelId) {
    final model = _modelStates[modelId];
    if (model == null || _modelsDirectory == null) return null;

    if (!isModelDownloaded(modelId)) return null;

    // 如果有解压后的路径，优先返回
    final extractedPath = _extractedModelPaths[modelId];
    if (extractedPath != null) {
      return extractedPath;
    }

    return path.join(_modelsDirectory!, model.fileName);
  }

  /// 手动触发模型解压（用于已下载但未解压的模型）
  Future<void> extractModelIfNeeded(String modelId) async {
    final model = _modelStates[modelId];
    if (model == null || _modelsDirectory == null) return;

    // 已有解压路径，跳过
    if (_extractedModelPaths.containsKey(modelId)) return;

    final modelPath = path.join(_modelsDirectory!, model.fileName);

    // 检查是否是压缩文件
    if (modelPath.endsWith('.tar.bz2') || modelPath.endsWith('.tar.gz')) {
      final file = File(modelPath);
      if (!await file.exists()) return;

      logInfo('手动解压模型: $modelPath', source: 'ModelManager');
      try {
        final extractedPath = await ModelExtractor.extract(
          modelPath,
          _modelsDirectory!,
        );
        _extractedModelPaths[modelId] = extractedPath;
        logInfo('模型解压完成: $extractedPath', source: 'ModelManager');
        notifyListeners();
      } catch (e) {
        logError('模型解压失败: $e', source: 'ModelManager');
        rethrow;
      }
    }
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
      // flutter_gemma 的 deleteModel API 在不同版本差异较大，
      // 这里不强依赖其删除能力：我们只清理本地文件与本地记录。
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyGemmaActiveModelId);
      _flutterGemmaActiveModelId = null;

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
