import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'large_file_manager.dart';
import 'large_video_handler.dart';

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
  }  /// 流式保存图片（使用LargeFileManager，避免内存溢出）
  static Future<String?> saveImage(
    String sourcePath, {
    Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      return await LargeFileManager.executeWithMemoryProtection(
        () async {
          // 使用LargeFileManager的文件检查
          if (!await LargeFileManager.canProcessFile(sourcePath)) {
            throw Exception('文件无法处理或过大');
          }

          final imageDir = await _getMediaDirectory(_imagesFolder);
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
          final targetPath = path.join(imageDir.path, fileName);

          // 使用LargeFileManager的分块复制，支持取消和进度回调
          await LargeFileManager.copyFileInChunks(
            sourcePath, 
            targetPath,
            onProgress: (current, total) {
              cancelToken?.throwIfCancelled();
              if (onProgress != null && total > 0) {
                onProgress(current / total);
              }
            },
          );
          
          return targetPath;
        },
        operationName: '图片保存',
      );
    } catch (e) {
      debugPrint('保存图片失败: $e');
      return null;
    }
  }  /// 复制视频到私有目录（使用增强的大视频处理器）
  static Future<String?> saveVideo(
    String sourcePath, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    CancelToken? cancelToken,
  }) async {
    try {
      return await LargeFileManager.executeWithMemoryProtection(
        () async {
          // 首先检查是否为大视频文件
          final videoInfo = await LargeVideoHandler.getVideoFileInfo(sourcePath);
          if (videoInfo == null) {
            throw Exception('无法获取视频文件信息');
          }
          
          final videoDir = await _getMediaDirectory(_videosFolder);
          
          // 对于大视频文件（超过50MB），使用专门的处理器
          if (videoInfo.fileSizeMB > 50) {
            debugPrint('检测到大视频文件: ${videoInfo.fileSizeMB.toStringAsFixed(1)}MB，使用专用处理器');
            
            return await LargeVideoHandler.importLargeVideoSafely(
              sourcePath,
              videoDir.path,
              onProgress: onProgress,
              onStatusUpdate: onStatusUpdate,
              cancelToken: cancelToken,
            );
          } else {
            // 小视频文件使用原有的处理方式
            if (!await LargeFileManager.canProcessFile(sourcePath)) {
              throw Exception('视频文件无法处理');
            }

            final fileName =
                '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
            final targetPath = path.join(videoDir.path, fileName);

            // 使用LargeFileManager的分块复制
            await LargeFileManager.copyFileInChunks(
              sourcePath, 
              targetPath,
              onProgress: (current, total) {
                cancelToken?.throwIfCancelled();
                if (onProgress != null && total > 0) {
                  onProgress(current / total);
                }
              },
              cancelToken: cancelToken,
            );
            
            return targetPath;
          }
        },
        operationName: '视频保存',
      );
    } catch (e) {
      debugPrint('保存视频失败: $e');
      onStatusUpdate?.call('保存失败: $e');
      return null;
    }
  }  /// 复制音频到私有目录（使用LargeFileManager）
  static Future<String?> saveAudio(
    String sourcePath, {
    Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      return await LargeFileManager.executeWithMemoryProtection(
        () async {
          // 使用LargeFileManager的文件检查
          if (!await LargeFileManager.canProcessFile(sourcePath)) {
            throw Exception('音频文件无法处理或过大');
          }

          final audioDir = await _getMediaDirectory(_audiosFolder);
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
          final targetPath = path.join(audioDir.path, fileName);

          // 使用LargeFileManager的分块复制
          await LargeFileManager.copyFileInChunks(
            sourcePath, 
            targetPath,
            onProgress: (current, total) {
              cancelToken?.throwIfCancelled();
              if (onProgress != null && total > 0) {
                onProgress(current / total);
              }
            },
          );
          
          return targetPath;
        },
        operationName: '音频保存',
      );
    } catch (e) {
      debugPrint('保存音频失败: $e');
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
      if (fileSize > 2 * 1024 * 1024 * 1024) { // 2GB以上记录警告日志
        debugPrint('警告：文件较大: ${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB，请确保有足够存储空间');
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
      if (kDebugMode) {
        print('删除媒体文件失败: $e');
      }
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

  /// 获取所有媒体文件路径（用于备份）
  static Future<List<String>> getAllMediaFilePaths() async {
    try {
      final List<String> allPaths = [];
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(path.join(appDir.path, _mediaFolder));

      if (await mediaDir.exists()) {
        await for (final entity in mediaDir.list(recursive: true)) {
          if (entity is File) {
            allPaths.add(entity.path);
          }
        }
      }

      return allPaths;
    } catch (e) {
      if (kDebugMode) {
        print('获取媒体文件路径失败: $e');
      }
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
          
          if (fileSize > 50 * 1024 * 1024) { // 50MB以上使用分块复制
            debugPrint('检测到大文件 (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)，使用分块复制');
            
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
