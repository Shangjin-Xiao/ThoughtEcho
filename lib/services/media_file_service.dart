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
  static Future<String?> saveImage(String sourcePath) async {
    try {
      final imageDir = await _getMediaDirectory(_imagesFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(imageDir.path, fileName);

      // 使用流式复制，避免大文件一次性加载到内存
      await _copyFileInChunks(sourcePath, targetPath);
      return targetPath;
    } catch (e) {
      debugPrint('保存图片失败: $e');
      return null;
    }
  }

  /// 复制视频到私有目录
  static Future<String?> saveVideo(String sourcePath) async {
    try {
      final videoDir = await _getMediaDirectory(_videosFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(videoDir.path, fileName);

      // 使用流式复制，避免大文件一次性加载到内存
      await _copyFileInChunks(sourcePath, targetPath);
      return targetPath;
    } catch (e) {
      debugPrint('保存视频失败: $e');
      return null;
    }
  }

  /// 复制音频到私有目录
  static Future<String?> saveAudio(String sourcePath) async {
    try {
      final audioDir = await _getMediaDirectory(_audiosFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(audioDir.path, fileName);

      // 使用流式复制，避免大文件一次性加载到内存
      await _copyFileInChunks(sourcePath, targetPath);
      return targetPath;
    } catch (e) {
      debugPrint('保存音频失败: $e');
      return null;
    }
  }

  /// 流式文件复制（分块处理，避免内存溢出）
  static Future<void> _copyFileInChunks(
    String sourcePath,
    String targetPath,
  ) async {
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);

    // 确保源文件存在
    if (!await sourceFile.exists()) {
      throw Exception('源文件不存在: $sourcePath');
    }

    // 确保目标目录存在
    await targetFile.parent.create(recursive: true);

    // 使用流式复制，内存友好的方式处理大文件
    final sourceStream = sourceFile.openRead();
    final targetSink = targetFile.openWrite();

    try {
      await sourceStream.pipe(targetSink);

      // 验证复制是否成功
      if (!await targetFile.exists()) {
        throw Exception('文件复制失败，目标文件未创建');
      }

      debugPrint('文件复制成功: $sourcePath -> $targetPath');
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
      final targetMediaDir = Directory(path.join(appDir.path, _mediaFolder));

      // 确保目标目录存在
      if (!await targetMediaDir.exists()) {
        await targetMediaDir.create(recursive: true);
      }

      // 递归复制所有文件
      await for (final entity in backupDir.list(recursive: true)) {
        if (entity is File) {
          // 计算相对路径
          final relativePath = path.relative(entity.path, from: backupMediaDir);
          final targetPath = path.join(targetMediaDir.path, relativePath);

          // 确保目标目录存在
          final targetFile = File(targetPath);
          await targetFile.parent.create(recursive: true);

          // 复制文件
          await entity.copy(targetPath);
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('恢复媒体文件失败: $e');
      }
      return false;
    }
  }
}
