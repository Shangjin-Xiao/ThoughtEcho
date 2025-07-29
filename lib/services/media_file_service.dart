import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'large_file_manager.dart';
import 'streaming_file_processor.dart';


/// 媒体文件管理服务
/// 优化版本：支持文件压缩、流式处理和内存优化
class MediaFileService {
  static const String _mediaFolder = 'media';
  static const String _imagesFolder = 'images';
  static const String _videosFolder = 'videos';
  static const String _audiosFolder = 'audios';

  /// 获取媒体文件目录
  static Future<Directory> _getMediaDirectory(String subfolder) async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(path.join(appDir.path, _mediaFolder, subfolder));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  /// 流式保存图片（使用新的流式处理器，彻底防止OOM）
  static Future<String?> saveImage(
    String sourcePath, {
    Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      logDebug('开始保存图片: $sourcePath');

      // 检查源文件
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在: $sourcePath');
      }

      final fileSize = await sourceFile.length();
      logDebug('图片文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

      final imageDir = await _getMediaDirectory(_imagesFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(imageDir.path, fileName);

      // 检查磁盘空间
      if (!await StreamingFileProcessor.hasEnoughDiskSpace(
          targetPath, fileSize)) {
        throw Exception('磁盘空间不足');
      }

      // 使用新的流式处理器复制文件
      await StreamingFileProcessor.copyFileStreaming(
        sourcePath,
        targetPath,
        onProgress: (current, total) {
          cancelToken?.throwIfCancelled();
          if (onProgress != null && total > 0) {
            onProgress(current / total);
          }
        },
        onStatusUpdate: (status) {
          logDebug('图片保存状态: $status');
        },
        shouldCancel: () => cancelToken?.isCancelled == true,
      );

      // 验证文件完整性
      if (!await StreamingFileProcessor.verifyFileCopy(
          sourcePath, targetPath)) {
        throw Exception('文件复制验证失败');
      }

      logDebug('图片保存成功: $targetPath');
      return targetPath;
    } catch (e) {
      logDebug('保存图片失败: $e');
      return null;
    }
  }

  /// 复制视频到私有目录（使用新的流式处理器，彻底防止OOM）
  static Future<String?> saveVideo(
    String sourcePath, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    CancelToken? cancelToken,
  }) async {
    try {
      logDebug('开始保存视频: $sourcePath');

      // 检查源文件
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在: $sourcePath');
      }

      final fileSize = await sourceFile.length();
      final fileSizeMB = fileSize / 1024 / 1024;
      logDebug('视频文件大小: ${fileSizeMB.toStringAsFixed(2)}MB');

      final videoDir = await _getMediaDirectory(_videosFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(videoDir.path, fileName);

      // 检查磁盘空间
      if (!await StreamingFileProcessor.hasEnoughDiskSpace(
          targetPath, fileSize)) {
        throw Exception('磁盘空间不足');
      }

      onStatusUpdate?.call('正在准备视频处理...');

      // 对于所有视频文件都使用流式处理器，不再区分大小
      await StreamingFileProcessor.copyFileStreaming(
        sourcePath,
        targetPath,
        onProgress: (current, total) {
          cancelToken?.throwIfCancelled();
          if (onProgress != null && total > 0) {
            onProgress(current / total);
          }
        },
        onStatusUpdate: (status) {
          onStatusUpdate?.call(status);
          logDebug('视频保存状态: $status');
        },
        shouldCancel: () => cancelToken?.isCancelled == true,
      );

      // 验证文件完整性
      if (!await StreamingFileProcessor.verifyFileCopy(
          sourcePath, targetPath)) {
        throw Exception('视频文件复制验证失败');
      }

      logDebug('视频保存成功: $targetPath');
      return targetPath;
    } catch (e) {
      logDebug('保存视频失败: $e');

      // 提供更详细的错误信息
      String errorMessage;
      if (e is CancelledException) {
        errorMessage = '视频导入已取消';
      } else if (e.toString().contains('内存不足')) {
        errorMessage = '内存不足，请关闭其他应用后重试或选择较小的视频文件';
      } else if (e.toString().contains('空间不足')) {
        errorMessage = '存储空间不足，请清理设备存储后重试';
      } else if (e.toString().contains('权限')) {
        errorMessage = '无法访问文件，请检查文件权限';
      } else {
        errorMessage = '保存失败: ${e.toString()}';
      }

      onStatusUpdate?.call(errorMessage);
      return null;
    }
  }

  /// 复制音频到私有目录（使用新的流式处理器，彻底防止OOM）
  static Future<String?> saveAudio(
    String sourcePath, {
    Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      logDebug('开始保存音频: $sourcePath');

      // 检查源文件
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在: $sourcePath');
      }

      final fileSize = await sourceFile.length();
      logDebug('音频文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

      final audioDir = await _getMediaDirectory(_audiosFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(audioDir.path, fileName);

      // 检查磁盘空间
      if (!await StreamingFileProcessor.hasEnoughDiskSpace(
          targetPath, fileSize)) {
        throw Exception('磁盘空间不足');
      }

      // 使用新的流式处理器复制文件
      await StreamingFileProcessor.copyFileStreaming(
        sourcePath,
        targetPath,
        onProgress: (current, total) {
          cancelToken?.throwIfCancelled();
          if (onProgress != null && total > 0) {
            onProgress(current / total);
          }
        },
        onStatusUpdate: (status) {
          logDebug('音频保存状态: $status');
        },
        shouldCancel: () => cancelToken?.isCancelled == true,
      );

      // 验证文件完整性
      if (!await StreamingFileProcessor.verifyFileCopy(
          sourcePath, targetPath)) {
        throw Exception('音频文件复制验证失败');
      }

      logDebug('音频保存成功: $targetPath');
      return targetPath;
    } catch (e) {
      logDebug('保存音频失败: $e');
      return null;
    }
  }

  /// 使用LargeFileManager替代原有的复制逻辑，已迁移到上面的方法中
  /// 保留一些辅助方法用于向后兼容和其他功能

  /// 安全检查文件大小（不读取整个文件内容）
  static Future<int> getFileSizeSecurely(String filePath) async {
    try {
      final file = File(filePath);
      final stat = await file.stat();
      return stat.size;
    } catch (e) {
      debugPrint('获取文件大小失败: $e');
      return 0;
    }
  }

  /// 检查可用存储空间
  static Future<bool> hasEnoughSpace(String filePath) async {
    try {
      final fileSize = await getFileSizeSecurely(filePath);

      // 移除大小限制，只记录日志
      if (fileSize > 2 * 1024 * 1024 * 1024) {
        // 2GB以上记录警告日志
        debugPrint(
          '警告：文件较大: ${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB，请确保有足够存储空间',
        );
      }

      return true;
    } catch (e) {
      debugPrint('检查存储空间失败: $e');
      return false;
    }
  }

  /// 删除媒体文件
  static Future<bool> deleteMediaFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.e('删除媒体文件失败: $e', error: e, source: 'MediaFileService');
      return false;
    }
  }

  /// 检查文件是否存在
  static Future<bool> fileExists(String filePath) async {
    try {
      return await File(filePath).exists();
    } catch (e) {
      return false;
    }
  }

  /// 获取所有媒体文件路径（用于备份）- 优化版，避免阻塞主线程
  static Future<List<String>> getAllMediaFilePaths({
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final List<String> allPaths = [];
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(path.join(appDir.path, _mediaFolder));

      if (!await mediaDir.exists()) {
        return [];
      }

      logDebug('开始收集媒体文件路径: ${mediaDir.path}');

      // 先收集所有文件实体，避免在遍历过程中阻塞
      final List<FileSystemEntity> allEntities = [];

      await for (final entity in mediaDir.list(recursive: true)) {
        cancelToken?.throwIfCancelled();

        if (entity is File) {
          allEntities.add(entity);
        }

        // 每收集100个实体就让UI有机会更新
        if (allEntities.length % 100 == 0) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }

      logDebug('发现 ${allEntities.length} 个媒体文件');

      // 分批处理文件路径，避免一次性处理太多
      const batchSize = 50;
      int processedCount = 0;
      final totalCount = allEntities.length;

      for (int i = 0; i < allEntities.length; i += batchSize) {
        cancelToken?.throwIfCancelled();

        final batch = allEntities.skip(i).take(batchSize);

        for (final entity in batch) {
          try {
            // 检查文件是否仍然存在（可能在遍历过程中被删除）
            if (await entity.exists()) {
              allPaths.add(entity.path);
            }
            processedCount++;
          } catch (e) {
            logDebug('检查媒体文件失败，跳过: ${entity.path}, 错误: $e');
            processedCount++;
          }
        }

        // 更新进度
        onProgress?.call(processedCount, totalCount);

        // 让UI有机会更新
        await Future.delayed(const Duration(milliseconds: 10));
      }

      logDebug('成功收集 ${allPaths.length} 个有效媒体文件路径');
      return allPaths;
    } catch (e) {
      if (e is CancelledException) {
        logDebug('媒体文件路径收集已取消');
        rethrow;
      }

      logDebug('获取媒体文件路径失败: $e');
      return [];
    }
  }

  /// 从备份目录恢复媒体文件（增强版，支持大文件安全处理）
  static Future<bool> restoreMediaFiles(
    String backupMediaDir, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final backupDir = Directory(backupMediaDir);
      if (!await backupDir.exists()) {
        return false;
      }

      final appDir = await getApplicationDocumentsDirectory();
      debugPrint('开始恢复媒体文件，备份目录: $backupMediaDir');
      debugPrint('应用目录: ${appDir.path}');

      // 先收集所有需要恢复的文件
      final List<File> filesToRestore = [];
      await for (final entity in backupDir.list(recursive: true)) {
        if (entity is File) {
          filesToRestore.add(entity);
        }
      }

      final totalFiles = filesToRestore.length;
      int processedFiles = 0;

      // 使用内存保护机制逐个恢复文件
      for (final file in filesToRestore) {
        cancelToken?.throwIfCancelled();

        try {
          // 计算相对于备份目录的路径
          final relativePath = path.relative(file.path, from: backupMediaDir);
          final targetPath = path.join(appDir.path, relativePath);

          debugPrint('恢复文件: $relativePath -> $targetPath');

          // 确保目标目录存在
          final targetFile = File(targetPath);
          await targetFile.parent.create(recursive: true);

          // 检查文件大小，决定使用哪种复制方法
          final fileSize = await file.length();

          if (fileSize > 50 * 1024 * 1024) {
            // 50MB以上使用分块复制
            debugPrint(
              '检测到大文件 (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)，使用分块复制',
            );

            await LargeFileManager.copyFileInChunks(
              file.path,
              targetPath,
              onProgress: (current, total) {
                // 这里可以添加单个文件的进度回调
              },
              cancelToken: cancelToken,
            );
          } else {
            // 小文件使用标准复制
            await file.copy(targetPath);
          }

          processedFiles++;
          onProgress?.call(processedFiles, totalFiles);
        } catch (e) {
          debugPrint('恢复单个文件失败: ${file.path}, 错误: $e');
          // 继续处理其他文件，不因单个文件失败而中断整个恢复过程
        }
      }

      debugPrint('媒体文件恢复完成，成功恢复 $processedFiles/$totalFiles 个文件');
      return true;
    } catch (e) {
      debugPrint('恢复媒体文件失败: $e');
      return false;
    }
  }

  /// 安全导入大文件工具（带进度和取消支持）
  static Future<String?> importLargeFileSecurely(
    String sourcePath,
    String targetDirectory, {
    Function(double progress)? onProgress,
    Function()? onCancel,
  }) async {
    try {
      // 使用LargeFileManager进行预检查
      if (!await LargeFileManager.canProcessFile(sourcePath)) {
        return null;
      }

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(targetDirectory, fileName);

      // 检查是否被取消
      if (onCancel != null && onCancel()) {
        return null;
      }

      // 创建目标目录
      final targetDir = Directory(targetDirectory);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // 使用LargeFileManager执行安全复制
      await LargeFileManager.copyFileInChunks(
        sourcePath,
        targetPath,
        onProgress: (current, total) {
          if (onProgress != null && total > 0) {
            onProgress(current / total);
          }
        },
      );

      return targetPath;
    } catch (e) {
      debugPrint('安全导入大文件失败: $e');
      return null;
    }
  }

  /// 批量导入文件（内存安全版本）
  static Future<List<String>> importFilesSecurely(
    List<String> sourcePaths, {
    Function(int current, int total)? onProgress,
    Function()? onCancel,
  }) async {
    final results = <String>[];
    final total = sourcePaths.length;

    for (int i = 0; i < sourcePaths.length; i++) {
      // 检查是否被取消
      if (onCancel != null && onCancel()) {
        break;
      }

      final sourcePath = sourcePaths[i];
      String? targetPath;

      // 根据文件类型选择合适的保存方法
      final extension = path.extension(sourcePath).toLowerCase();

      if ({
        '.mp4',
        '.mov',
        '.avi',
        '.mkv',
        '.webm',
        '.3gp',
      }.contains(extension)) {
        targetPath = await saveVideo(sourcePath);
      } else if ({
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.bmp',
        '.webp',
      }.contains(extension)) {
        targetPath = await saveImage(sourcePath);
      } else if ({
        '.mp3',
        '.wav',
        '.aac',
        '.flac',
        '.ogg',
      }.contains(extension)) {
        targetPath = await saveAudio(sourcePath);
      }

      if (targetPath != null) {
        results.add(targetPath);
      }

      // 报告进度
      onProgress?.call(i + 1, total);

      // 添加小延迟，让UI有机会更新
      if (i < sourcePaths.length - 1) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    return results;
  }

  /// 获取内存使用建议
  static String getMemoryUsageAdvice(List<String> filePaths) {
    int totalSize = 0;
    int largeFileCount = 0;
    const largeFileThreshold = 100 * 1024 * 1024; // 100MB

    for (final filePath in filePaths) {
      try {
        final file = File(filePath);
        final stat = file.statSync();
        totalSize += stat.size;

        if (stat.size > largeFileThreshold) {
          largeFileCount++;
        }
      } catch (_) {
        // 忽略无法访问的文件
      }
    }

    final totalSizeMB = totalSize / (1024 * 1024);

    if (totalSizeMB > 1024) {
      return '警告: 文件总大小超过1GB (${totalSizeMB.toStringAsFixed(1)}MB)，建议分批导入';
    } else if (largeFileCount > 5) {
      return '建议: 检测到$largeFileCount个大文件，建议逐个导入以确保稳定性';
    } else if (totalSizeMB > 500) {
      return '提示: 文件较大 (${totalSizeMB.toStringAsFixed(1)}MB)，导入过程中请勿操作其他功能';
    } else {
      return '文件大小适中 (${totalSizeMB.toStringAsFixed(1)}MB)，可以正常导入';
    }
  }
}
