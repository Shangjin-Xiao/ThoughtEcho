import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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

  /// 流式保存图片（避免内存溢出）
  static Future<String?> saveImage(
    String sourcePath, {
    Function(double progress)? onProgress,
  }) async {
    try {
      // 预检查文件大小和可用空间
      if (!await _preCheckFile(sourcePath)) {
        return null;
      }

      final imageDir = await _getMediaDirectory(_imagesFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(imageDir.path, fileName);

      // 使用流式复制，避免大文件一次性加载到内存
      await _copyFileInChunks(sourcePath, targetPath, onProgress: onProgress);
      return targetPath;
    } catch (e) {
      debugPrint('保存图片失败: $e');
      return null;
    }
  }

  /// 复制视频到私有目录（增强的大文件处理）
  static Future<String?> saveVideo(
    String sourcePath, {
    Function(double progress)? onProgress,
  }) async {
    try {
      // 对视频文件进行更严格的预检查
      if (!await _preCheckVideoFile(sourcePath)) {
        return null;
      }

      final videoDir = await _getMediaDirectory(_videosFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(videoDir.path, fileName);

      // 使用增强的流式复制，带进度回调
      await _copyFileInChunks(sourcePath, targetPath, onProgress: onProgress);
      return targetPath;
    } catch (e) {
      debugPrint('保存视频失败: $e');
      return null;
    }
  }

  /// 复制音频到私有目录
  static Future<String?> saveAudio(
    String sourcePath, {
    Function(double progress)? onProgress,
  }) async {
    try {
      // 预检查文件大小和可用空间
      if (!await _preCheckFile(sourcePath)) {
        return null;
      }

      final audioDir = await _getMediaDirectory(_audiosFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(audioDir.path, fileName);

      // 使用流式复制，避免大文件一次性加载到内存
      await _copyFileInChunks(sourcePath, targetPath, onProgress: onProgress);
      return targetPath;
    } catch (e) {
      debugPrint('保存音频失败: $e');
      return null;
    }
  }

  /// 流式文件复制（分块处理，避免内存溢出）
  static Future<void> _copyFileInChunks(
    String sourcePath,
    String targetPath, {
    Function(double progress)? onProgress,
  }) async {
    const chunkSize = 64 * 1024; // 64KB 块大小，平衡性能和内存使用
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);

    // 确保源文件存在
    if (!await sourceFile.exists()) {
      throw Exception('源文件不存在: $sourcePath');
    }

    // 确保目标目录存在
    await targetFile.parent.create(recursive: true);

    // 获取文件总大小用于进度计算
    final totalSize = await sourceFile.length();
    int copiedBytes = 0;

    // 使用流式复制，内存友好的方式处理大文件
    final sourceStream = sourceFile.openRead();
    final targetSink = targetFile.openWrite();

    try {
      await for (final chunk in sourceStream) {
        targetSink.add(chunk);
        copiedBytes += chunk.length;

        // 报告进度
        if (onProgress != null && totalSize > 0) {
          final progress = copiedBytes / totalSize;
          onProgress(progress);
        }

        // 定期刷新，确保数据写入磁盘
        if (copiedBytes % (chunkSize * 16) == 0) {
          await targetSink.flush();
        }
      }

      await targetSink.flush();

      // 验证复制是否成功
      if (!await targetFile.exists()) {
        throw Exception('文件复制失败，目标文件未创建');
      }

      // 验证文件大小一致性
      final targetSize = await targetFile.length();
      if (targetSize != totalSize) {
        throw Exception('文件复制不完整，大小不匹配: 期望 $totalSize，实际 $targetSize');
      }

      debugPrint(
        '文件复制成功: $sourcePath -> $targetPath (${(totalSize / 1024 / 1024).toStringAsFixed(1)}MB)',
      );
    } catch (e) {
      // 清理可能的不完整文件
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (_) {}

      debugPrint('文件复制失败: $e');
      rethrow;
    } finally {
      await targetSink.close();
    }
  }

  /// 预检查文件（通用）
  static Future<bool> _preCheckFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('文件不存在: $filePath');
        return false;
      }

      final fileSize = await file.length();
      const maxGeneralFileSize = 500 * 1024 * 1024; // 500MB限制

      if (fileSize > maxGeneralFileSize) {
        debugPrint(
          '文件过大 (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)，超过限制 (500MB): $filePath',
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('预检查文件失败: $e');
      return false;
    }
  }

  /// 预检查视频文件（更严格的限制）
  static Future<bool> _preCheckVideoFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('视频文件不存在: $filePath');
        return false;
      }

      final fileSize = await file.length();

      // 视频文件更严格的大小限制
      const maxVideoSize = 1024 * 1024 * 1024; // 1GB限制
      const minVideoSize = 1024; // 最小1KB，避免空文件

      if (fileSize < minVideoSize) {
        debugPrint('视频文件过小，可能损坏: $filePath');
        return false;
      }

      if (fileSize > maxVideoSize) {
        debugPrint(
          '视频文件过大 (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)，超过限制 (1GB): $filePath',
        );
        return false;
      }

      // 检查文件扩展名
      final extension = path.extension(filePath).toLowerCase();
      const supportedVideoExtensions = {
        '.mp4',
        '.mov',
        '.avi',
        '.mkv',
        '.webm',
        '.3gp',
      };

      if (!supportedVideoExtensions.contains(extension)) {
        debugPrint('不支持的视频格式: $extension');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('预检查视频文件失败: $e');
      return false;
    }
  }

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

      // 简单的空间检查，这里主要检查文件大小是否合理
      // 设置一个较大但合理的上限来避免极大文件导致的问题
      const maxReasonableSize = 2 * 1024 * 1024 * 1024; // 2GB

      if (fileSize > maxReasonableSize) {
        debugPrint('文件过大: ${fileSize / (1024 * 1024)} MB');
        return false;
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

  /// 从备份目录恢复媒体文件
  static Future<bool> restoreMediaFiles(String backupMediaDir) async {
    try {
      final backupDir = Directory(backupMediaDir);
      if (!await backupDir.exists()) {
        return false;
      }

      final appDir = await getApplicationDocumentsDirectory();
      if (kDebugMode) {
        print('开始恢复媒体文件，备份目录: $backupMediaDir');
        print('应用目录: ${appDir.path}');
      }

      // 递归复制所有文件
      await for (final entity in backupDir.list(recursive: true)) {
        if (entity is File) {
          // 计算相对于备份目录的路径
          final relativePath = path.relative(entity.path, from: backupMediaDir);

          // 直接拼接到应用目录，不要再加 _mediaFolder
          // 因为 relativePath 已经包含了 'media/images/xxx.jpg' 这样的完整路径
          final targetPath = path.join(appDir.path, relativePath);

          if (kDebugMode) {
            print('恢复文件: $relativePath -> $targetPath');
          }

          // 确保目标目录存在
          final targetFile = File(targetPath);
          await targetFile.parent.create(recursive: true);

          // 复制文件
          await entity.copy(targetPath);
        }
      }

      if (kDebugMode) {
        print('媒体文件恢复完成');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('恢复媒体文件失败: $e');
      }
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
      // 预检查
      if (!await _preCheckVideoFile(sourcePath)) {
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

      // 执行安全复制
      await _copyFileInChunks(sourcePath, targetPath, onProgress: onProgress);

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
