import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/utils/backup_media_processor.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/utils/zip_stream_processor.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/device_memory_manager.dart';
import 'package:thoughtecho/models/merge_report.dart';
import 'streaming_backup_processor.dart';
import 'package:meta/meta.dart';

/// 备份与恢复服务
///
/// 负责协调各个数据服务，将应用数据打包成一个.zip文件进行备份，
/// 或从备份文件中恢复数据。
class BackupService {
  final DatabaseService _databaseService;
  final SettingsService _settingsService;
  final AIAnalysisDatabaseService _aiAnalysisDbService;

  BackupService({
    required DatabaseService databaseService,
    required SettingsService settingsService,
    required AIAnalysisDatabaseService aiAnalysisDbService,
  })  : _databaseService = databaseService,
        _settingsService = settingsService,
        _aiAnalysisDbService = aiAnalysisDbService;

  static const String _backupDataFile = 'backup_data.json';
  static const String _backupVersion = '1.2.0'; // 版本更新，因为数据结构变化

  /// 导出所有应用数据（增强版，支持大文件安全处理）
  ///
  /// [includeMediaFiles] - 是否在备份中包含媒体文件（图片等）
  /// [customPath] - 可选的自定义保存路径。如果提供，将保存到指定路径；否则创建在临时目录
  /// [onProgress] - 进度回调函数，接收 (current, total) 参数
  /// [cancelToken] - 取消令牌，支持取消操作
  /// 返回最终备份文件的路径
  Future<String> exportAllData({
    required bool includeMediaFiles,
    String? customPath,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // 预先检查内存状态
    final memoryManager = DeviceMemoryManager();
    final memoryPressure = await memoryManager.getMemoryPressureLevel();

    if (memoryPressure >= 3) {
      // 临界状态
      throw Exception('内存不足，无法执行备份操作。请关闭其他应用后重试。');
    }

    return await LargeFileManager.executeWithMemoryProtection(
          () async => _performExportWithProtection(
            includeMediaFiles: includeMediaFiles,
            customPath: customPath,
            onProgress: onProgress,
            cancelToken: cancelToken,
          ),
          operationName: '数据备份',
          maxRetries: memoryPressure >= 2 ? 0 : 1, // 高内存压力时不重试
        ) ??
        (throw Exception('备份操作失败'));
  }

  /// 执行受保护的导出操作
  Future<String> _performExportWithProtection({
    required bool includeMediaFiles,
    String? customPath,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final backupId = DateTime.now().millisecondsSinceEpoch;
    final archivePath = customPath ??
        path.join(tempDir.path, 'thoughtecho_backup_$backupId.zip');

    File? jsonFile;

    try {
      cancelToken?.throwIfCancelled();

      // 1. 导出结构化数据 (笔记, 设置, AI历史) 到 JSON
      logDebug('开始收集结构化数据...');
      onProgress?.call(5, 100); // 更新进度

      // 让UI有机会更新
      await Future.delayed(const Duration(milliseconds: 50));

      final backupData = await _gatherStructuredData(includeMediaFiles);

      cancelToken?.throwIfCancelled();
      onProgress?.call(15, 100); // 更新进度

      // 2. 使用流式JSON写入避免大JSON一次性加载到内存
      jsonFile = File(path.join(tempDir.path, _backupDataFile));
      logDebug('开始流式写入JSON数据...');

      // 让UI有机会更新
      await Future.delayed(const Duration(milliseconds: 50));

      await LargeFileManager.encodeJsonToFileStreaming(
        backupData,
        jsonFile,
        onProgress: (current, total) {
          // JSON写入进度占总进度的15%
          final jsonProgress = (current * 15).round();
          onProgress?.call(15 + jsonProgress, 100);
        },
      );

      cancelToken?.throwIfCancelled();
      onProgress?.call(30, 100); // 更新进度

      // 3. 准备ZIP文件列表
      final filesToZip = <String, String>{};

      // 添加JSON文件
      filesToZip[_backupDataFile] = jsonFile.path;

      // 4. (可选) 收集媒体文件 - 使用优化的媒体处理器
      final mediaFilesMap =
          await BackupMediaProcessor.collectMediaFilesForBackup(
        includeMediaFiles: includeMediaFiles,
        onProgress: (current, total) {
          // 媒体文件收集进度占总进度的25% (35% - 60%)
          final mediaProgress = (current / 100 * 25).round();
          onProgress?.call(35 + mediaProgress, 100);
        },
        onStatusUpdate: (status) {
          logDebug('媒体处理状态: $status');
        },
        cancelToken: cancelToken,
      );

      // 将媒体文件添加到ZIP列表
      filesToZip.addAll(mediaFilesMap);

      logDebug(
          '准备备份 ${filesToZip.length} 个文件 (包含 ${mediaFilesMap.length} 个媒体文件)');

      cancelToken?.throwIfCancelled();
      onProgress?.call(60, 100); // 更新进度

      // 5. 使用流式ZIP创建
      logDebug('开始创建ZIP文件，包含 ${filesToZip.length} 个文件...');

      // 让UI有机会更新
      await Future.delayed(const Duration(milliseconds: 50));

      await ZipStreamProcessor.createZipStreaming(
        archivePath,
        filesToZip,
        onProgress: (current, total) {
          // ZIP创建进度占总进度的35%
          final zipProgress = (current / total * 35).round();
          onProgress?.call(60 + zipProgress, 100);
        },
        cancelToken: cancelToken,
      );

      onProgress?.call(95, 100); // 更新进度
      logDebug('数据导出成功，路径: $archivePath');

      // 让UI有机会更新
      await Future.delayed(const Duration(milliseconds: 50));

      // 验证生成的ZIP文件
      final isValid = await ZipStreamProcessor.validateZipFile(archivePath);
      if (!isValid) {
        throw Exception('生成的备份文件验证失败');
      }

      onProgress?.call(100, 100); // 完成
      return archivePath;
    } catch (e, s) {
      // 清理可能创建的不完整文件
      try {
        final archiveFile = File(archivePath);
        if (await archiveFile.exists()) {
          await archiveFile.delete();
        }
      } catch (_) {}

      if (e is CancelledException) {
        logDebug('备份操作已取消');
        rethrow;
      }

      AppLogger.e('数据导出失败', error: e, stackTrace: s, source: 'BackupService');
      rethrow;
    } finally {
      // 清理临时JSON文件
      try {
        if (jsonFile != null && await jsonFile.exists()) {
          await jsonFile.delete();
        }
      } catch (_) {}
    }
  }

  /// 从备份文件导入数据（增强版，支持大文件安全处理）
  ///
  /// [filePath] - 备份文件的路径 (.zip 或旧版 .json)
  /// [clearExisting] - 是否在导入前清空现有数据
  /// [onProgress] - 进度回调函数，接收 (current, total) 参数
  /// [cancelToken] - 取消令牌，支持取消操作
  Future<MergeReport?> importData(
    String filePath, {
    bool clearExisting = true,
    bool merge = false, // 新增：是否使用LWW合并；与 clearExisting=true 互斥
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
    String? sourceDevice,
  }) async {
    if (merge && clearExisting) {
      // 合并模式不允许清空现有数据
      logDebug(
          'importData 参数冲突: merge=true 与 clearExisting=true 互斥，自动将 clearExisting 设为 false');
      clearExisting = false;
    }

    if (merge) {
      // 走 LWW 合并路径
      return await importDataWithLWWMerge(
        filePath,
        onProgress: onProgress,
        cancelToken: cancelToken,
        sourceDevice: sourceDevice,
      );
    } else {
      await LargeFileManager.executeWithMemoryProtection(
        () async => _performImportWithProtection(
          filePath,
          clearExisting: clearExisting,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
        operationName: '数据导入',
      );
      try {
        _databaseService.refreshAllData();
      } catch (e) {
        logWarning('导入后刷新数据库失败: $e', source: 'BackupService');
      }
      return null; // 旧模式无 MergeReport
    }
  }

  /// 执行受保护的导入操作（流式处理版）
  Future<void> _performImportWithProtection(
    String filePath, {
    bool clearExisting = true,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    logDebug('开始流式导入备份文件: $filePath');

    // 检查内存状态
    final memoryManager = DeviceMemoryManager();
    final memoryPressure = await memoryManager.getMemoryPressureLevel();

    if (memoryPressure >= 3) {
      throw Exception('内存不足，无法执行导入操作。请关闭其他应用后重试。');
    }

    // 获取备份文件信息
    final backupInfo = await StreamingBackupProcessor.getBackupInfo(filePath);
    logDebug('备份文件信息: $backupInfo');

    // 验证备份文件
    if (!await StreamingBackupProcessor.validateBackupFile(filePath)) {
      throw Exception('备份文件损坏或格式不正确');
    }

    Map<String, dynamic> backupData;

    // 根据文件类型使用相应的流式处理器
    if (backupInfo['type'] == 'json') {
      logDebug('使用流式JSON处理器...');
      backupData = await StreamingBackupProcessor.parseJsonBackupStreaming(
        filePath,
        onStatusUpdate: (status) => logDebug('JSON处理状态: $status'),
        shouldCancel: () => cancelToken?.isCancelled == true,
      );
    } else if (backupInfo['type'] == 'zip') {
      logDebug('使用流式ZIP处理器...');
      backupData = await StreamingBackupProcessor.processZipBackupStreaming(
        filePath,
        onStatusUpdate: (status) => logDebug('ZIP处理状态: $status'),
        onProgress: onProgress,
        shouldCancel: () => cancelToken?.isCancelled == true,
      );
    } else {
      throw Exception('不支持的备份文件格式: ${backupInfo['type']}');
    }

    // 处理导入数据
    await _processImportDataStreaming(backupData, clearExisting, cancelToken);
  }

  /// 流式处理导入数据
  Future<void> _processImportDataStreaming(
    Map<String, dynamic> backupData,
    bool clearExisting,
    CancelToken? cancelToken,
  ) async {
    logDebug('开始流式处理导入数据...');

    try {
      cancelToken?.throwIfCancelled();

      // 如果选择清空，则先清空所有相关数据
      if (clearExisting) {
        logDebug('清空现有数据...');
        await _databaseService.importDataFromMap({
          'categories': [],
          'quotes': [],
        }, clearExisting: true);
        await _aiAnalysisDbService.deleteAllAnalyses();
      }

      cancelToken?.throwIfCancelled();

      // 恢复笔记数据
      if (backupData.containsKey('notes')) {
        logDebug('恢复笔记数据...');
        var notesData = Map<String, dynamic>.from(backupData['notes']);

        // 检查是否包含媒体文件
        final hasMediaFiles = await _checkBackupHasMediaFiles(backupData);
        if (hasMediaFiles) {
          notesData = await _convertMediaPathsInNotesForRestore(notesData);
        }

        await _databaseService.importDataFromMap(
          notesData,
          clearExisting: false,
        );
      }

      cancelToken?.throwIfCancelled();

      // 恢复设置（使用现有的方法）
      if (backupData.containsKey('settings')) {
        logDebug('恢复设置数据...');
        await _settingsService.restoreAllSettingsFromBackup(
          backupData['settings'] as Map<String, dynamic>,
        );
      }

      cancelToken?.throwIfCancelled();

      // 恢复AI分析数据（使用现有的方法）
      if (backupData.containsKey('ai_analysis')) {
        logDebug('恢复AI分析数据...');
        await _aiAnalysisDbService.importAnalysesFromList(
          (backupData['ai_analysis'] as List).cast<Map<String, dynamic>>(),
        );
      }

      logDebug('流式导入数据完成');
    } catch (e) {
      logDebug('流式导入数据失败: $e');
      rethrow;
    }
  }

  /// 验证备份文件是否有效
  Future<bool> validateBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      // 验证新的 zip 格式
      if (path.extension(filePath).toLowerCase() == '.zip') {
        // 使用流式处理器验证
        final isValid = await ZipStreamProcessor.validateZipFile(filePath);
        if (!isValid) return false;

        // 检查是否包含必需的文件
        return await ZipStreamProcessor.containsFile(filePath, _backupDataFile);
      }

      // 验证旧的 json 格式
      if (path.extension(filePath).toLowerCase() == '.json') {
        return await _databaseService.validateBackupFile(filePath);
      }

      return false;
    } catch (e) {
      AppLogger.e('无效的备份文件', error: e, source: 'BackupService');
      return false;
    }
  }

  /// 聚合所有结构化数据到一个Map中
  Future<Map<String, dynamic>> _gatherStructuredData(
    bool includeMediaFiles,
  ) async {
    final notesData = await _databaseService.exportDataAsMap();
    final settingsData = _settingsService.getAllSettingsForBackup();
    final aiAnalysisData = await _aiAnalysisDbService.exportAnalysesAsList();
    final deviceId = settingsData['device_id'];

    // 处理笔记数据中的媒体文件路径
    Map<String, dynamic> processedNotesData = notesData;
    if (includeMediaFiles) {
      processedNotesData = await _convertMediaPathsInNotesForBackup(notesData);
    }

    return {
      'version': _backupVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'device_id': deviceId,
      'notes': processedNotesData,
      'settings': settingsData,
      'ai_analysis': aiAnalysisData,
    };
  }

  /// 检查备份数据是否包含媒体文件
  Future<bool> _checkBackupHasMediaFiles(
    Map<String, dynamic> backupData,
  ) async {
    // 检查版本信息和备份内容来判断是否包含媒体文件
    final version = backupData['version'] as String?;
    return version == _backupVersion;
  }

  /// 在备份时将笔记数据中的媒体文件绝对路径转换为相对路径
  Future<Map<String, dynamic>> _convertMediaPathsInNotesForBackup(
    Map<String, dynamic> notesData,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = appDir.path;

    // 深拷贝数据
    final processedData = Map<String, dynamic>.from(notesData);

    if (processedData.containsKey('quotes')) {
      final quotes = List<Map<String, dynamic>>.from(processedData['quotes']);

      for (final quote in quotes) {
        if (quote.containsKey('deltaContent') &&
            quote['deltaContent'] != null) {
          final deltaContent = quote['deltaContent'] as String;
          try {
            // 使用流式JSON处理避免大内容OOM
            if (deltaContent.length > 10 * 1024 * 1024) {
              // 10MB以上
              logDebug('富文本内容过大，跳过媒体路径转换');
              // 保留原内容，避免OOM
            } else {
              final deltaJson =
                  await LargeFileManager.processLargeJson<Map<String, dynamic>>(
                deltaContent,
                encode: false,
              );
              final convertedDelta = _convertDeltaMediaPaths(
                deltaJson,
                appPath,
                true,
              );
              quote['deltaContent'] =
                  await LargeFileManager.processLargeJson<String>(
                convertedDelta,
                encode: true,
              );
            }
          } catch (e) {
            logDebug('处理笔记 ${quote['id']} 的富文本内容时出错: $e');
            // 如果处理失败，保持原内容不变
          }
        }
      }

      processedData['quotes'] = quotes;
    }

    return processedData;
  }

  /// 在还原时将笔记数据中的媒体文件相对路径转换为当前环境的绝对路径
  Future<Map<String, dynamic>> _convertMediaPathsInNotesForRestore(
    Map<String, dynamic> notesData,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = appDir.path;

    // 深拷贝数据
    final processedData = Map<String, dynamic>.from(notesData);

    if (processedData.containsKey('quotes')) {
      final quotes = List<Map<String, dynamic>>.from(processedData['quotes']);

      for (final quote in quotes) {
        if (quote.containsKey('deltaContent') &&
            quote['deltaContent'] != null) {
          final deltaContent = quote['deltaContent'] as String;
          try {
            // 使用流式JSON处理避免大内容OOM
            if (deltaContent.length > 10 * 1024 * 1024) {
              // 10MB以上
              logDebug('富文本内容过大，跳过媒体路径转换');
              // 保留原内容，避免OOM
            } else {
              final deltaJson =
                  await LargeFileManager.processLargeJson<Map<String, dynamic>>(
                deltaContent,
                encode: false,
              );
              final convertedDelta = _convertDeltaMediaPaths(
                deltaJson,
                appPath,
                false,
              );
              quote['deltaContent'] =
                  await LargeFileManager.processLargeJson<String>(
                convertedDelta,
                encode: true,
              );
            }
          } catch (e) {
            logDebug('处理笔记 ${quote['id']} 的富文本内容时出错: $e');
            // 如果处理失败，保持原内容不变
          }
        }
      }

      processedData['quotes'] = quotes;
    }

    return processedData;
  }

  /// 递归处理 Delta JSON 中的媒体文件路径
  // 提取为 static 便于测试；递归转换 Delta 中的媒体路径
  static dynamic _convertDeltaMediaPaths(
    dynamic deltaJson,
    String appPath,
    bool toRelative,
  ) {
    if (deltaJson is Map) {
      final convertedMap = <String, dynamic>{};
      for (final entry in deltaJson.entries) {
        if (entry.key == 'insert' && entry.value is Map) {
          final insertMap = entry.value as Map;
          if (insertMap.containsKey('image') ||
              insertMap.containsKey('video')) {
            final convertedInsert = Map<String, dynamic>.from(insertMap);

            // 处理图片路径
            if (convertedInsert.containsKey('image')) {
              convertedInsert['image'] = _convertSingleMediaPath(
                convertedInsert['image'] as String,
                appPath,
                toRelative,
              );
            }

            // 处理视频路径
            if (convertedInsert.containsKey('video')) {
              convertedInsert['video'] = _convertSingleMediaPath(
                convertedInsert['video'] as String,
                appPath,
                toRelative,
              );
            }

            convertedMap[entry.key] = convertedInsert;
          } else if (insertMap.containsKey('custom')) {
            // 处理自定义embed (如音频)
            final customMap = insertMap['custom'] as Map?;
            if (customMap?.containsKey('audio') == true) {
              final convertedCustom = Map<String, dynamic>.from(customMap!);
              convertedCustom['audio'] = _convertSingleMediaPath(
                convertedCustom['audio'] as String,
                appPath,
                toRelative,
              );

              final convertedInsert = Map<String, dynamic>.from(insertMap);
              convertedInsert['custom'] = convertedCustom;
              convertedMap[entry.key] = convertedInsert;
            } else {
              convertedMap[entry.key] = entry.value;
            }
          } else {
            convertedMap[entry.key] = entry.value;
          }
        } else {
          convertedMap[entry.key] = _convertDeltaMediaPaths(
            entry.value,
            appPath,
            toRelative,
          );
        }
      }
      return convertedMap;
    } else if (deltaJson is List) {
      return deltaJson
          .map((item) => _convertDeltaMediaPaths(item, appPath, toRelative))
          .toList();
    } else {
      return deltaJson;
    }
  }

  /// 测试辅助：直接转换一段 Delta JSON 的媒体路径（不访问文件系统）
  /// toRelative=true 模拟备份阶段，false 模拟还原阶段。
  @visibleForTesting
  static dynamic testConvertDeltaMediaPaths(
    dynamic deltaJson, {
    required String appPath,
    required bool toRelative,
  }) {
    return _convertDeltaMediaPaths(deltaJson, appPath, toRelative);
  }

  /// 转换单个媒体文件路径 (static 便于测试)
  static String _convertSingleMediaPath(
    String originalPath,
    String appPath,
    bool toRelative,
  ) {
    try {
      if (toRelative) {
        // 备份时：绝对路径 -> 相对路径
        if (originalPath.startsWith(appPath)) {
          return path.relative(originalPath, from: appPath);
        }
        return originalPath; // 如果不是应用内路径，保持不变
      } else {
        // 还原时：相对路径 -> 绝对路径
        if (!path.isAbsolute(originalPath)) {
          return path.join(appPath, originalPath);
        }
        return originalPath; // 如果已经是绝对路径，保持不变
      }
    } catch (e) {
      logDebug('转换媒体文件路径失败: $originalPath, 错误: $e');
      return originalPath; // 如果转换失败，返回原路径
    }
  }

  /// 使用LWW策略导入数据
  ///
  /// [filePath] - 备份文件路径
  /// [onProgress] - 进度回调
  /// [cancelToken] - 取消令牌
  /// [sourceDevice] - 源设备标识符（可选）
  /// 返回 [MergeReport] 包含合并统计信息
  Future<MergeReport> importDataWithLWWMerge(
    String filePath, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
    String? sourceDevice,
  }) async {
    try {
      final result = await LargeFileManager.executeWithMemoryProtection(
        () async => _performLWWImportWithProtection(
          filePath,
          onProgress: onProgress,
          cancelToken: cancelToken,
          sourceDevice: sourceDevice,
        ),
        operationName: 'LWW数据导入',
      );
      return result ??
          MergeReport.start(sourceDevice: sourceDevice)
              .addError('内存保护操作返回空结果')
              .completed();
    } catch (e) {
      logError('LWW导入包装过程出错: $e', error: e, source: 'BackupService');
      return MergeReport.start(sourceDevice: sourceDevice)
          .addError('导入包装过程出错: $e')
          .completed();
    } finally {
      // 无论成功失败都尝试刷新，以确保UI更新
      try {
        _databaseService.refreshAllData();
      } catch (e) {
        logWarning('LWW导入后刷新数据库失败: $e', source: 'BackupService');
      }
    }
  }

  /// 执行受保护的LWW导入操作
  Future<MergeReport> _performLWWImportWithProtection(
    String filePath, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
    String? sourceDevice,
  }) async {
    logDebug('开始LWW导入备份文件: $filePath');

    // 检查内存状态
    final memoryManager = DeviceMemoryManager();
    final memoryPressure = await memoryManager.getMemoryPressureLevel();

    if (memoryPressure >= 3) {
      final report = MergeReport.start(sourceDevice: sourceDevice);
      return report.addError('内存不足，无法执行导入操作。请关闭其他应用后重试。').completed();
    }

    // 获取并验证备份文件
    final backupInfo = await StreamingBackupProcessor.getBackupInfo(filePath);
    logDebug('备份文件信息: $backupInfo');

    if (!await StreamingBackupProcessor.validateBackupFile(filePath)) {
      final report = MergeReport.start(sourceDevice: sourceDevice);
      return report.addError('备份文件损坏或格式不正确').completed();
    }

    try {
      Map<String, dynamic> backupData;

      // 根据文件类型使用相应的流式处理器
      if (backupInfo['type'] == 'json') {
        logDebug('使用流式JSON处理器...');
        backupData = await StreamingBackupProcessor.parseJsonBackupStreaming(
          filePath,
          onStatusUpdate: (status) => logDebug('JSON处理状态: $status'),
          shouldCancel: () => cancelToken?.isCancelled == true,
        );
      } else if (backupInfo['type'] == 'zip') {
        logDebug('使用流式ZIP处理器...');
        backupData = await StreamingBackupProcessor.processZipBackupStreaming(
          filePath,
          onStatusUpdate: (status) => logDebug('ZIP处理状态: $status'),
          onProgress: onProgress,
          shouldCancel: () => cancelToken?.isCancelled == true,
        );
      } else {
        final report = MergeReport.start(sourceDevice: sourceDevice);
        return report.addError('不支持的备份文件格式: ${backupInfo['type']}').completed();
      }

      // 处理媒体文件路径转换
      if (backupData.containsKey('notes')) {
        final hasMediaFiles = await _checkBackupHasMediaFiles(backupData);
        if (hasMediaFiles) {
          final notesData = Map<String, dynamic>.from(backupData['notes']);
          backupData['notes'] =
              await _convertMediaPathsInNotesForRestore(notesData);
        }
      }

      // 使用LWW策略合并数据
      return await _databaseService.importDataWithLWWMerge(
        backupData.containsKey('notes') ? backupData['notes'] : backupData,
        sourceDevice: sourceDevice,
      );
    } catch (e) {
      logError('LWW导入过程出错: $e', error: e, source: 'BackupService');
      final report = MergeReport.start(sourceDevice: sourceDevice);
      return report.addError('导入过程出错: $e').completed();
    }
  }
}
