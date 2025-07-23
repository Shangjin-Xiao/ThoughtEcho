import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/large_file_manager.dart' as lfm;
import '../services/media_reference_service.dart';
import 'app_logger.dart';

/// 备份媒体处理器
///
/// 专门处理备份过程中的媒体文件操作，优化性能和内存使用
class BackupMediaProcessor {
  /// 智能收集媒体文件用于备份
  ///
  /// [includeMediaFiles] - 是否包含媒体文件
  /// [onProgress] - 进度回调 (current, total)
  /// [onStatusUpdate] - 状态更新回调
  /// [cancelToken] - 取消令牌
  /// 返回 Map<relativePath, absolutePath>
  static Future<Map<String, String>> collectMediaFilesForBackup({
    required bool includeMediaFiles,
    Function(int current, int total)? onProgress,
    Function(String status)? onStatusUpdate,
    lfm.CancelToken? cancelToken,
  }) async {
    final filesToZip = <String, String>{};

    if (!includeMediaFiles) {
      return filesToZip;
    }

    try {
      logDebug('开始智能收集媒体文件...');
      onStatusUpdate?.call('正在扫描媒体文件...');

      // 使用媒体引用服务获取被引用的媒体文件
      final referencedFiles = await _getReferencedMediaFiles();

      // 如果没有被引用的媒体文件，直接返回
      if (referencedFiles.isEmpty) {
        logDebug('没有发现被引用的媒体文件');
        onStatusUpdate?.call('没有发现被引用的媒体文件');
        onProgress?.call(100, 100);
        return filesToZip;
      }

      final mediaFiles = referencedFiles;

      if (mediaFiles.isEmpty) {
        logDebug('没有发现媒体文件');
        onStatusUpdate?.call('没有发现媒体文件');
        onProgress?.call(100, 100);
        return filesToZip;
      }

      logDebug('发现 ${mediaFiles.length} 个媒体文件，开始分析...');
      onStatusUpdate?.call('发现 ${mediaFiles.length} 个媒体文件，正在分析...');

      // 先分析文件大小分布
      final fileStats = await _analyzeMediaFiles(mediaFiles);
      final totalSizeMB = (fileStats['totalSize'] as int) / 1024 / 1024;
      final largeFiles = fileStats['largeFiles'] as int;
      final hugeFiles = fileStats['hugeFiles'] as int;

      logDebug(
          '媒体文件统计: 总大小 ${totalSizeMB.toStringAsFixed(1)}MB, 大文件 $largeFiles 个, 超大文件 $hugeFiles 个');

      if (hugeFiles > 0) {
        onStatusUpdate?.call('检测到 $hugeFiles 个超大文件，将使用流式处理确保备份完整性');
      }

      final appDir = await getApplicationDocumentsDirectory();

      // 根据文件大小调整处理策略
      final batchSize = _calculateOptimalBatchSize(fileStats);
      double processedFiles = 0;
      final totalFiles = mediaFiles.length;

      onStatusUpdate?.call('正在处理媒体文件 (0/$totalFiles)...');

      for (int i = 0; i < mediaFiles.length; i += batchSize) {
        cancelToken?.throwIfCancelled();

        final batch = mediaFiles.skip(i).take(batchSize).toList();

        // 并行处理当前批次
        final batchResults = await _processBatchFiles(
          batch,
          appDir.path,
          cancelToken,
        );

        // 添加有效结果
        filesToZip.addAll(batchResults);

        processedFiles += batch.length;

        // 更新进度和状态
        final processProgress = 30 + (processedFiles / totalFiles * 70).round();
        onProgress?.call(processProgress, 100);
        onStatusUpdate?.call('正在处理媒体文件 ($processedFiles/$totalFiles)...');

        // 让UI有机会更新，并进行内存管理
        await Future.delayed(const Duration(milliseconds: 15));

        // 每处理几个批次进行一次内存检查
        if (i % (batchSize * 2) == 0) {
          await _checkMemoryPressure();
        }
      }

      final validFiles = filesToZip.length;
      final skippedFiles = totalFiles - validFiles;

      logDebug('媒体文件收集完成，有效文件: $validFiles, 跳过文件: $skippedFiles');
      onStatusUpdate?.call('媒体文件处理完成，包含 $validFiles 个文件');
      onProgress?.call(100, 100);
      return filesToZip;
    } catch (e) {
      if (e is lfm.CancelledException) {
        logDebug('媒体文件收集已取消');
        onStatusUpdate?.call('媒体文件收集已取消');
        rethrow;
      }

      logDebug('收集媒体文件失败: $e');
      onStatusUpdate?.call('媒体文件收集出现错误，使用部分结果');
      // 返回已收集的部分结果
      return filesToZip;
    }
  }

  /// 并行处理一批文件
  static Future<Map<String, String>> _processBatchFiles(
    List<String> filePaths,
    String appDirPath,
    lfm.CancelToken? cancelToken,
  ) async {
    final results = <String, String>{};

    // 创建并行任务
    final futures = filePaths.map((filePath) async {
      try {
        cancelToken?.throwIfCancelled();

        // 快速检查文件是否存在
        if (!await File(filePath).exists()) {
          return null;
        }

        // 检查文件是否可以处理（使用缓存的结果）
        if (await _canProcessFileQuickly(filePath)) {
          final relativePath = path.relative(filePath, from: appDirPath);
          return MapEntry(relativePath, filePath);
        }

        return null;
      } catch (e) {
        logDebug('处理文件失败，跳过: $filePath, 错误: $e');
        return null;
      }
    }).toList();

    // 等待所有任务完成
    final batchResults = await Future.wait(futures);

    // 收集有效结果
    for (final result in batchResults) {
      if (result != null) {
        results[result.key] = result.value;
      }
    }

    return results;
  }

  /// 快速检查文件是否可以处理（优化版本）
  static Future<bool> _canProcessFileQuickly(String filePath) async {
    try {
      // 首先进行基本检查
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      // 获取文件大小
      final fileSize = await file.length();

      // 对于空文件，跳过
      if (fileSize == 0) {
        logDebug('跳过空文件: $filePath');
        return false;
      }

      // 对于超大文件，记录警告但仍然包含在备份中
      if (fileSize > 2 * 1024 * 1024 * 1024) {
        logDebug(
            '检测到超大文件: $filePath (${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(1)}GB) - 将使用流式处理');
      }

      // 简单的文件访问测试
      try {
        final randomAccessFile = await file.open(mode: FileMode.read);
        await randomAccessFile.close();
        return true;
      } catch (e) {
        logDebug('文件访问测试失败: $filePath, 错误: $e');
        return false;
      }
    } catch (e) {
      logDebug('快速文件检查失败: $filePath, 错误: $e');
      return false;
    }
  }

  /// 检查内存压力并进行必要的清理
  static Future<void> _checkMemoryPressure() async {
    try {
      // 触发垃圾回收建议
      await lfm.LargeFileManager.emergencyMemoryCleanup();
    } catch (e) {
      logDebug('内存压力检查失败: $e');
    }
  }

  /// 估算媒体文件总大小
  static Future<int> estimateMediaFilesSize(List<String> filePaths) async {
    int totalSize = 0;
    int checkedFiles = 0;
    const maxFilesToCheck = 100; // 最多检查100个文件来估算

    try {
      for (final filePath in filePaths.take(maxFilesToCheck)) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final size = await file.length();
            totalSize += size;
            checkedFiles++;
          }
        } catch (e) {
          // 忽略单个文件的错误
        }
      }

      // 如果检查的文件数少于总数，按比例估算
      if (checkedFiles > 0 && filePaths.length > maxFilesToCheck) {
        final averageSize = totalSize / checkedFiles;
        totalSize = (averageSize * filePaths.length).round();
      }

      logDebug('估算媒体文件总大小: ${(totalSize / 1024 / 1024).toStringAsFixed(1)}MB');
      return totalSize;
    } catch (e) {
      logDebug('估算媒体文件大小失败: $e');
      return 0;
    }
  }

  /// 通用的媒体文件分析方法
  static Future<Map<String, dynamic>> _analyzeMediaFilesCommon(
    List<String> filePaths, {
    int? maxSampleSize,
  }) async {
    int totalFiles = 0;
    int totalSize = 0;
    int largeFiles = 0; // >100MB
    int hugeFiles = 0; // >1GB
    final Map<String, int> typeCount = {};

    const largeFileThreshold = 100 * 1024 * 1024; // 100MB
    const hugeFileThreshold = 1024 * 1024 * 1024; // 1GB

    try {
      // 确定要分析的文件列表
      final filesToAnalyze = maxSampleSize != null
          ? filePaths.take(maxSampleSize).toList()
          : filePaths;

      for (final filePath in filesToAnalyze) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final size = await file.length();
            totalSize += size;
            totalFiles++;

            if (size > hugeFileThreshold) {
              hugeFiles++;
            } else if (size > largeFileThreshold) {
              largeFiles++;
            }

            // 统计文件类型
            final extension = path.extension(filePath).toLowerCase();
            typeCount[extension] = (typeCount[extension] ?? 0) + 1;
          }
        } catch (e) {
          // 忽略单个文件的错误
        }
      }

      // 如果是采样模式且采样数量少于总数，按比例估算
      if (maxSampleSize != null &&
          totalFiles > 0 &&
          filePaths.length > maxSampleSize) {
        final scaleFactor = filePaths.length / totalFiles;
        totalSize = (totalSize * scaleFactor).round();
        largeFiles = (largeFiles * scaleFactor).round();
        hugeFiles = (hugeFiles * scaleFactor).round();
      }

      return {
        'totalFiles': maxSampleSize != null ? filePaths.length : totalFiles,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / 1024 / 1024).toStringAsFixed(1),
        'largeFiles': largeFiles,
        'hugeFiles': hugeFiles,
        'typeCount': typeCount,
        'sampledFiles': totalFiles,
      };
    } catch (e) {
      logDebug('分析媒体文件失败: $e');
      return {
        'totalFiles': maxSampleSize != null ? filePaths.length : 0,
        'totalSize': 0,
        'totalSizeMB': '0.0',
        'largeFiles': 0,
        'hugeFiles': 0,
        'typeCount': <String, int>{},
        'sampledFiles': 0,
      };
    }
  }

  /// 分析媒体文件（快速版本，只检查前100个文件来估算）
  static Future<Map<String, dynamic>> _analyzeMediaFiles(
      List<String> filePaths) async {
    const maxSampleSize = 100; // 最多检查100个文件来快速估算
    return await _analyzeMediaFilesCommon(filePaths,
        maxSampleSize: maxSampleSize);
  }

  /// 根据文件统计计算最优批次大小
  static int _calculateOptimalBatchSize(Map<String, dynamic> fileStats) {
    final hugeFiles = fileStats['hugeFiles'] as int;
    final largeFiles = fileStats['largeFiles'] as int;
    final totalFiles = fileStats['totalFiles'] as int;

    // 根据大文件数量调整批次大小
    if (hugeFiles > totalFiles * 0.1) {
      // 如果超大文件占比超过10%，使用很小的批次
      return 3;
    } else if (largeFiles > totalFiles * 0.2) {
      // 如果大文件占比超过20%，使用小批次
      return 5;
    } else if (totalFiles > 1000) {
      // 文件数量很多时，使用中等批次
      return 15;
    } else {
      // 默认批次大小
      return 10;
    }
  }

  /// 获取媒体文件统计信息（完整版本）
  static Future<Map<String, dynamic>> getMediaFilesStats(
      List<String> filePaths) async {
    try {
      final result = await _analyzeMediaFilesCommon(filePaths);
      // 移除 sampledFiles 字段，因为完整版本不需要这个字段
      result.remove('sampledFiles');
      return result;
    } catch (e) {
      logDebug('获取媒体文件统计失败: $e');
      return {
        'totalFiles': 0,
        'totalSize': 0,
        'totalSizeMB': '0.0',
        'largeFiles': 0,
        'hugeFiles': 0,
        'typeCount': <String, int>{},
      };
    }
  }

  /// 获取所有被引用的媒体文件路径
  static Future<List<String>> _getReferencedMediaFiles() async {
    try {
      logDebug('开始获取被引用的媒体文件...');

      // 获取媒体引用统计信息
      final stats = await MediaReferenceService.getMediaReferenceStats();
      logDebug('媒体引用统计: $stats');

      // 获取所有媒体文件
      final allMediaFiles = await _getAllMediaFiles();
      final referencedFiles = <String>[];

      // 检查每个文件的引用计数
      for (final filePath in allMediaFiles) {
        final refCount =
            await MediaReferenceService.getReferenceCount(filePath);
        if (refCount > 0) {
          referencedFiles.add(filePath);
        }
      }

      logDebug('找到 ${referencedFiles.length} 个被引用的媒体文件');
      return referencedFiles;
    } catch (e) {
      logDebug('获取被引用媒体文件失败: $e');
      return [];
    }
  }

  /// 获取所有媒体文件路径
  static Future<List<String>> _getAllMediaFiles() async {
    final mediaFiles = <String>[];

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(path.join(appDir.path, 'media'));

      if (!await mediaDir.exists()) {
        return mediaFiles;
      }

      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          mediaFiles.add(entity.path);
        }
      }
    } catch (e) {
      logDebug('获取所有媒体文件失败: $e');
    }

    return mediaFiles;
  }
}
