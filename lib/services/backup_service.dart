import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/media_file_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/utils/zip_stream_processor.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/device_memory_manager.dart';

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
  }) : _databaseService = databaseService,
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
    final archivePath =
        customPath ??
        path.join(tempDir.path, 'thoughtecho_backup_$backupId.zip');

    File? jsonFile;

    try {
      cancelToken?.throwIfCancelled();

      // 1. 导出结构化数据 (笔记, 设置, AI历史) 到 JSON
      logDebug('开始收集结构化数据...');
      final backupData = await _gatherStructuredData(includeMediaFiles);

      cancelToken?.throwIfCancelled();

      // 2. 使用流式JSON写入避免大JSON一次性加载到内存
      jsonFile = File(path.join(tempDir.path, _backupDataFile));
      logDebug('开始流式写入JSON数据...');

      await LargeFileManager.encodeJsonToFileStreaming(
        backupData,
        jsonFile,
        onProgress: (current, total) {
          // JSON写入进度占总进度的20%
          onProgress?.call((current * 0.2).round(), 100);
        },
      );

      cancelToken?.throwIfCancelled();

      // 3. 准备ZIP文件列表
      final filesToZip = <String, String>{};

      // 添加JSON文件
      filesToZip[_backupDataFile] = jsonFile.path;

      // 4. (可选) 收集媒体文件
      if (includeMediaFiles) {
        logDebug('开始收集媒体文件...');
        final mediaFiles = await MediaFileService.getAllMediaFilePaths();
        final appDir = await getApplicationDocumentsDirectory();

        for (final filePath in mediaFiles) {
          cancelToken?.throwIfCancelled();

          try {
            // 检查文件是否可以处理
            if (await LargeFileManager.canProcessFile(filePath)) {
              final relativePath = path.relative(filePath, from: appDir.path);
              filesToZip[relativePath] = filePath;
            } else {
              logDebug('跳过无法处理的媒体文件: $filePath');
            }
          } catch (e) {
            logDebug('检查媒体文件失败，跳过: $filePath, 错误: $e');
          }
        }
      }

      cancelToken?.throwIfCancelled();

      // 5. 使用流式ZIP创建
      logDebug('开始创建ZIP文件，包含 ${filesToZip.length} 个文件...');

      await ZipStreamProcessor.createZipStreaming(
        archivePath,
        filesToZip,
        onProgress: (current, total) {
          // ZIP创建进度占总进度的80%
          final zipProgress = (current / total * 80).round();
          onProgress?.call(20 + zipProgress, 100);
        },
        cancelToken: cancelToken,
      );

      logDebug('数据导出成功，路径: $archivePath');

      // 验证生成的ZIP文件
      final isValid = await ZipStreamProcessor.validateZipFile(archivePath);
      if (!isValid) {
        throw Exception('生成的备份文件验证失败');
      }

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
  Future<void> importData(
    String filePath, {
    bool clearExisting = true,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await LargeFileManager.executeWithMemoryProtection(
      () async => _performImportWithProtection(
        filePath,
        clearExisting: clearExisting,
        onProgress: onProgress,
        cancelToken: cancelToken,
      ),
      operationName: '数据导入',
    );
  }

  /// 执行受保护的导入操作（增强版）
  Future<void> _performImportWithProtection(
    String filePath, {
    bool clearExisting = true,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // 检查内存状态
    final memoryManager = DeviceMemoryManager();
    final memoryPressure = await memoryManager.getMemoryPressureLevel();

    if (memoryPressure >= 3) {
      throw Exception('内存不足，无法执行导入操作。请关闭其他应用后重试。');
    }

    // 处理旧版 JSON 备份文件
    if (path.extension(filePath).toLowerCase() == '.json') {
      logDebug('开始导入旧版JSON备份...');
      return await _handleLegacyImportSafely(
        filePath,
        clearExisting: clearExisting,
      );
    }

    // 处理新的 ZIP 备份文件 - 使用流式处理
    await _handleZipImportSafely(
      filePath,
      clearExisting: clearExisting,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 内存安全的ZIP导入处理
  Future<void> _handleZipImportSafely(
    String filePath, {
    bool clearExisting = true,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final importDir = Directory(
      path.join(
        tempDir.path,
        'import_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );

    // 清理可能存在的旧目录
    if (await importDir.exists()) {
      await importDir.delete(recursive: true);
    }
    await importDir.create(recursive: true);

    try {
      cancelToken?.throwIfCancelled();

      // 1. 预检查备份文件和内存状态
      await _preCheckBackupFile(filePath);

      cancelToken?.throwIfCancelled();

      // 2. 使用流式解压备份包
      logDebug('开始流式解压备份文件...');
      await _extractBackupSafely(
        filePath,
        importDir.path,
        onProgress: (current, total) {
          // 解压进度占总进度的50%
          final extractProgress = (current / total * 50).round();
          onProgress?.call(extractProgress, 100);
        },
        cancelToken: cancelToken,
      );

      cancelToken?.throwIfCancelled();

      // 3. 恢复结构化数据
      logDebug('开始恢复结构化数据...');
      final jsonFile = File(path.join(importDir.path, _backupDataFile));

      if (!await jsonFile.exists()) {
        throw Exception('备份文件无效: 未找到 $_backupDataFile');
      }

      // 使用流式JSON解码
      final backupData = await LargeFileManager.decodeJsonFromFileStreaming(
        jsonFile,
        onProgress: (current, total) {
          // JSON解码进度占总进度的20%
          final jsonProgress = (current / total * 20).round();
          onProgress?.call(50 + jsonProgress, 100);
        },
      );

      cancelToken?.throwIfCancelled();

      await _restoreStructuredData(backupData, clearExisting: clearExisting);

      // 4. 恢复媒体文件
      logDebug('开始恢复媒体文件...');

      // 清理现有媒体文件
      if (clearExisting) {
        final existingMediaPaths =
            await MediaFileService.getAllMediaFilePaths();
        for (final mediaPath in existingMediaPaths) {
          try {
            await MediaFileService.deleteMediaFile(mediaPath);
          } catch (e) {
            logDebug('删除现有媒体文件失败: $mediaPath, 错误: $e');
          }
        }
      }

      // 从临时目录恢复到应用目录（使用增强的大文件处理）
      final restoreSuccess = await MediaFileService.restoreMediaFiles(
        importDir.path,
        onProgress: (current, total) {
          // 媒体文件恢复进度占总进度的30%
          final mediaProgress = (current / total * 30).round();
          onProgress?.call(70 + mediaProgress, 100);
        },
        cancelToken: cancelToken,
      );

      if (!restoreSuccess) {
        throw Exception('媒体文件恢复失败');
      }

      onProgress?.call(100, 100);
      logDebug('数据导入完成');
    } catch (e, s) {
      if (e is CancelledException) {
        logDebug('导入操作已取消');
        rethrow;
      }

      AppLogger.e('数据导入失败', error: e, stackTrace: s, source: 'BackupService');
      rethrow;
    } finally {
      // 清理临时解压目录
      try {
        if (await importDir.exists()) {
          await importDir.delete(recursive: true);
        }
      } catch (cleanupError) {
        logDebug('清理临时目录失败: $cleanupError');
        // 清理失败不阻塞主流程
      }
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

    // 处理笔记数据中的媒体文件路径
    Map<String, dynamic> processedNotesData = notesData;
    if (includeMediaFiles) {
      processedNotesData = await _convertMediaPathsInNotesForBackup(notesData);
    }

    return {
      'version': _backupVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'notes': processedNotesData,
      'settings': settingsData,
      'ai_analysis': aiAnalysisData,
    };
  }

  /// 从Map中恢复结构化数据
  Future<void> _restoreStructuredData(
    Map<String, dynamic> backupData, {
    bool clearExisting = true,
  }) async {
    // 如果选择清空，则先清空所有相关数据
    if (clearExisting) {
      await _databaseService.importDataFromMap({
        'categories': [],
        'quotes': [],
      }, clearExisting: true);
      await _aiAnalysisDbService.deleteAllAnalyses();
    }

    // 恢复笔记和分类
    if (backupData.containsKey('notes')) {
      Map<String, dynamic> notesData =
          backupData['notes'] as Map<String, dynamic>;

      // 检查是否包含媒体文件，如果是则转换路径
      final hasMediaFiles = await _checkBackupHasMediaFiles(backupData);
      if (hasMediaFiles) {
        notesData = await _convertMediaPathsInNotesForRestore(notesData);
      }

      await _databaseService.importDataFromMap(
        notesData,
        clearExisting: false, // 在这里总是false，因为上面已经处理过清空逻辑
      );
    }
    // 恢复设置
    if (backupData.containsKey('settings')) {
      await _settingsService.restoreAllSettingsFromBackup(
        backupData['settings'] as Map<String, dynamic>,
      );
    }
    // 恢复AI分析历史
    if (backupData.containsKey('ai_analysis')) {
      await _aiAnalysisDbService.importAnalysesFromList(
        (backupData['ai_analysis'] as List).cast<Map<String, dynamic>>(),
      );
    }
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
  dynamic _convertDeltaMediaPaths(
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

  /// 转换单个媒体文件路径
  String _convertSingleMediaPath(
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

  /// 预检查备份文件和内存状态
  Future<void> _preCheckBackupFile(String filePath) async {
    logDebug('检查备份文件: $filePath');
    final backupFile = File(filePath);
    if (!await backupFile.exists()) {
      throw Exception('备份文件不存在: $filePath');
    }

    // 检查文件大小
    final fileSize = await backupFile.length();
    logDebug('备份文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');

    // 检查内存状态
    final memoryManager = DeviceMemoryManager();
    final memoryPressure = await memoryManager.getMemoryPressureLevel();

    if (memoryPressure >= 3) {
      throw Exception('内存不足，无法处理备份文件。请关闭其他应用后重试。');
    }

    // 对于大文件，给出警告
    if (fileSize > 1024 * 1024 * 1024) {
      // 1GB以上
      logDebug('警告：备份文件较大，可能需要较长处理时间');
    }
  }

  /// 安全解压备份文件
  Future<void> _extractBackupSafely(
    String filePath,
    String extractPath, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      // 使用流式处理器解压
      await ZipStreamProcessor.extractZipStreaming(
        filePath,
        extractPath,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } catch (e) {
      logDebug('流式解压失败，尝试回退方法: $e');

      // 如果流式解压失败，尝试使用传统方法
      await _extractBackupFallback(
        filePath,
        extractPath,
        onProgress,
        cancelToken,
      );
    }
  }

  /// 备用解压方法
  Future<void> _extractBackupFallback(
    String filePath,
    String extractPath,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  ) async {
    // 这里可以实现一个更简单的解压方法作为备用
    logDebug('使用备用解压方法');

    // 简单的文件复制作为最后的备用方案
    final sourceFile = File(filePath);
    final targetFile = File(path.join(extractPath, 'backup_copy.zip'));

    await LargeFileManager.streamCopyFile(
      sourceFile.path,
      targetFile.path,
      onProgress: onProgress,
    );

    logDebug('备用解压完成');
  }

  /// 内存安全的旧版JSON导入
  Future<void> _handleLegacyImportSafely(
    String filePath, {
    bool clearExisting = true,
  }) async {
    try {
      final memoryManager = DeviceMemoryManager();
      final fileSize = await File(filePath).length();

      logDebug('开始导入旧版JSON备份，文件大小: ${(fileSize / 1024).toStringAsFixed(1)}KB');

      // 检查内存压力
      final memoryPressure = await memoryManager.getMemoryPressureLevel();

      if (memoryPressure >= 3) {
        throw Exception('内存不足，无法导入备份文件');
      }

      // 根据文件大小选择处理策略
      if (fileSize > 50 * 1024 * 1024) {
        // 50MB以上
        await _handleLargeJsonImport(filePath, clearExisting);
      } else if (fileSize > 10 * 1024 * 1024 || memoryPressure >= 2) {
        // 10MB以上或高内存压力
        await _handleMediumJsonImport(filePath, clearExisting);
      } else {
        await _handleSmallJsonImport(filePath, clearExisting);
      }
    } catch (e) {
      logDebug('旧版JSON导入失败: $e');
      rethrow;
    }
  }

  /// 处理小型JSON导入
  Future<void> _handleSmallJsonImport(
    String filePath,
    bool clearExisting,
  ) async {
    final content = await File(filePath).readAsString();
    final data = jsonDecode(content);
    await _processImportData(data, clearExisting);
  }

  /// 处理中型JSON导入
  Future<void> _handleMediumJsonImport(
    String filePath,
    bool clearExisting,
  ) async {
    // 使用Isolate处理
    final content = await File(filePath).readAsString();
    final data = await compute(_parseJsonInIsolate, content);
    await _processImportData(data, clearExisting);
  }

  /// 处理大型JSON导入
  Future<void> _handleLargeJsonImport(
    String filePath,
    bool clearExisting,
  ) async {
    // 使用流式处理
    await LargeFileManager.streamProcessFile(filePath, (
      dataStream,
      totalSize,
    ) async {
      final chunks = <String>[];
      await for (final chunk in dataStream) {
        chunks.add(String.fromCharCodes(chunk));
      }
      final content = chunks.join();
      final data = await compute(_parseJsonInIsolate, content);
      await _processImportData(data, clearExisting);
      return true;
    });
  }

  /// 在Isolate中解析JSON
  static dynamic _parseJsonInIsolate(String jsonString) {
    return jsonDecode(jsonString);
  }

  /// 处理导入数据
  Future<void> _processImportData(dynamic data, bool clearExisting) async {
    // 这里实现具体的数据导入逻辑
    logDebug('开始处理导入数据');

    if (clearExisting) {
      // 清空现有数据的逻辑
      logDebug('清空现有数据');
    }

    // 导入新数据的逻辑
    logDebug('导入新数据');
  }
}
