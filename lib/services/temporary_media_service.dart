import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../utils/app_logger.dart';
import '../services/streaming_file_processor.dart';
import '../services/large_file_manager.dart' as lfm;
import 'draft_service.dart'; // 导入草稿服务

/// 临时媒体文件管理服务
///
/// 负责管理编辑过程中的临时媒体文件，包括：
/// - 导入时存储到临时目录
/// - 保存笔记时移动到永久目录
/// - 取消编辑时清理临时文件
/// - 定期清理过期临时文件
class TemporaryMediaService {
  static const String _tempMediaFolder = 'temp_media';
  static const String _tempImagesFolder = 'temp_images';
  static const String _tempVideosFolder = 'temp_videos';
  static const String _tempAudiosFolder = 'temp_audios';

  // 临时文件过期时间（24小时）
  static const Duration _tempFileExpiration = Duration(hours: 24);

  /// 获取临时媒体文件目录
  static Future<Directory> _getTempMediaDirectory(String subfolder) async {
    final appDir = await getApplicationDocumentsDirectory();
    final tempDir = Directory(
      path.join(appDir.path, _tempMediaFolder, subfolder),
    );
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }

  /// 获取永久媒体文件目录
  static Future<Directory> _getPermanentMediaDirectory(String subfolder) async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(path.join(appDir.path, 'media', subfolder));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  /// 保存图片到临时目录
  static Future<String?> saveImageToTemporary(
    String sourcePath, {
    Function(double progress)? onProgress,
    lfm.CancelToken? cancelToken,
  }) async {
    return await _saveToTemporary(
      sourcePath,
      _tempImagesFolder,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 保存视频到临时目录
  static Future<String?> saveVideoToTemporary(
    String sourcePath, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    lfm.CancelToken? cancelToken,
  }) async {
    return await _saveToTemporary(
      sourcePath,
      _tempVideosFolder,
      onProgress: onProgress,
      onStatusUpdate: onStatusUpdate,
      cancelToken: cancelToken,
    );
  }

  /// 保存音频到临时目录
  static Future<String?> saveAudioToTemporary(
    String sourcePath, {
    Function(double progress)? onProgress,
    lfm.CancelToken? cancelToken,
  }) async {
    return await _saveToTemporary(
      sourcePath,
      _tempAudiosFolder,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 通用的临时文件保存方法
  static Future<String?> _saveToTemporary(
    String sourcePath,
    String subfolder, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    lfm.CancelToken? cancelToken,
  }) async {
    try {
      logDebug('开始保存文件到临时目录: $sourcePath');

      // 检查源文件
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在: $sourcePath');
      }

      final fileSize = await sourceFile.length();
      logDebug('文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

      final tempDir = await _getTempMediaDirectory(subfolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(tempDir.path, fileName);

      // 检查磁盘空间
      if (!await StreamingFileProcessor.hasEnoughDiskSpace(
        targetPath,
        fileSize,
      )) {
        throw Exception('磁盘空间不足');
      }

      onStatusUpdate?.call('正在保存到临时目录...');

      // 使用流式处理器复制文件
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
          logDebug('临时文件保存状态: $status');
        },
        shouldCancel: () => cancelToken?.isCancelled == true,
      );

      // 验证文件完整性
      if (!await StreamingFileProcessor.verifyFileCopy(
        sourcePath,
        targetPath,
      )) {
        throw Exception('临时文件复制验证失败');
      }

      logDebug('文件已保存到临时目录: $targetPath');
      return targetPath;
    } catch (e) {
      logDebug('保存临时文件失败: $e');
      return null;
    }
  }

  /// 将临时文件移动到永久目录
  static Future<String?> moveToPermament(
    String tempPath, {
    Function(double progress)? onProgress,
    lfm.CancelToken? cancelToken,
    bool deleteSource = true,
  }) async {
    try {
      logDebug('开始移动临时文件到永久目录: $tempPath');

      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        throw Exception('临时文件不存在: $tempPath');
      }

      // 确定文件类型和目标目录
      final extension = path.extension(tempPath).toLowerCase();
      String permanentSubfolder;

      if ({
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.bmp',
        '.webp',
      }.contains(extension)) {
        permanentSubfolder = 'images';
      } else if ({
        '.mp4',
        '.mov',
        '.avi',
        '.mkv',
        '.webm',
        '.3gp',
      }.contains(extension)) {
        permanentSubfolder = 'videos';
      } else if ({
        '.mp3',
        '.wav',
        '.aac',
        '.flac',
        '.ogg',
      }.contains(extension)) {
        permanentSubfolder = 'audios';
      } else {
        throw Exception('不支持的文件类型: $extension');
      }

      final permanentDir = await _getPermanentMediaDirectory(
        permanentSubfolder,
      );
      final fileName = path.basename(tempPath);
      final permanentPath = path.join(permanentDir.path, fileName);

      // 检查目标文件是否已存在
      if (await File(permanentPath).exists()) {
        logDebug('永久文件已存在，直接删除临时文件: $permanentPath');
        await tempFile.delete();
        return permanentPath;
      }

      final fileSize = await tempFile.length();

      // 检查磁盘空间
      if (!await StreamingFileProcessor.hasEnoughDiskSpace(
        permanentPath,
        fileSize,
      )) {
        throw Exception('磁盘空间不足');
      }

      // 使用流式处理器移动文件
      await StreamingFileProcessor.copyFileStreaming(
        tempPath,
        permanentPath,
        onProgress: (current, total) {
          cancelToken?.throwIfCancelled();
          if (onProgress != null && total > 0) {
            onProgress(current / total);
          }
        },
        onStatusUpdate: (status) {
          logDebug('文件移动状态: $status');
        },
        shouldCancel: () => cancelToken?.isCancelled == true,
      );

      // 验证文件完整性
      if (!await StreamingFileProcessor.verifyFileCopy(
        tempPath,
        permanentPath,
      )) {
        throw Exception('文件移动验证失败');
      }

      // 删除临时文件（可配置）
      if (deleteSource) {
        await tempFile.delete();
      }

      logDebug('文件已移动到永久目录: $permanentPath');
      return permanentPath;
    } catch (e) {
      logDebug('移动临时文件失败: $e');
      return null;
    }
  }

  /// 清理指定的临时文件
  static Future<bool> cleanupTemporaryFile(String tempPath) async {
    try {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
        logDebug('已清理临时文件: $tempPath');
        return true;
      }
      return false;
    } catch (e) {
      logDebug('清理临时文件失败: $e');
      return false;
    }
  }

  /// 清理所有过期的临时文件
  static Future<int> cleanupExpiredTemporaryFiles() async {
    int cleanedCount = 0;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempMediaDir = Directory(path.join(appDir.path, _tempMediaFolder));

      if (!await tempMediaDir.exists()) {
        return 0;
      }

      final now = DateTime.now();

      // 获取所有草稿中引用的媒体文件，防止误删
      final draftMediaPaths = await DraftService().getAllMediaPathsInDrafts();
      logDebug('发现 ${draftMediaPaths.length} 个被草稿引用的媒体文件，将跳过清理');

      await for (final entity in tempMediaDir.list(recursive: true)) {
        if (entity is File) {
          try {
            // 如果文件被草稿引用，跳过清理
            if (draftMediaPaths.contains(entity.path)) {
              continue;
            }

            final stat = await entity.stat();
            final age = now.difference(stat.modified);

            if (age > _tempFileExpiration) {
              await entity.delete();
              cleanedCount++;
              logDebug('已清理过期临时文件: ${entity.path}');
            }
          } catch (e) {
            logDebug('清理临时文件失败: ${entity.path}, 错误: $e');
          }
        }
      }

      logDebug('清理完成，共清理 $cleanedCount 个过期临时文件');
    } catch (e) {
      logDebug('清理过期临时文件失败: $e');
    }

    return cleanedCount;
  }

  /// 清理所有临时文件（强制清理）
  static Future<int> cleanupAllTemporaryFiles() async {
    int cleanedCount = 0;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempMediaDir = Directory(path.join(appDir.path, _tempMediaFolder));

      if (!await tempMediaDir.exists()) {
        return 0;
      }

      await for (final entity in tempMediaDir.list(recursive: true)) {
        if (entity is File) {
          try {
            await entity.delete();
            cleanedCount++;
            logDebug('已清理临时文件: ${entity.path}');
          } catch (e) {
            logDebug('清理临时文件失败: ${entity.path}, 错误: $e');
          }
        }
      }

      logDebug('强制清理完成，共清理 $cleanedCount 个临时文件');
    } catch (e) {
      logDebug('强制清理临时文件失败: $e');
    }

    return cleanedCount;
  }

  /// 检查文件是否为临时文件
  static Future<bool> isTemporaryFile(String filePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempMediaPath = path.join(appDir.path, _tempMediaFolder);
      return filePath.startsWith(tempMediaPath);
    } catch (e) {
      return false;
    }
  }

  /// 获取临时文件的统计信息
  static Future<Map<String, dynamic>> getTemporaryFilesStats() async {
    int totalFiles = 0;
    int totalSize = 0;
    int expiredFiles = 0;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempMediaDir = Directory(path.join(appDir.path, _tempMediaFolder));

      if (!await tempMediaDir.exists()) {
        return {
          'totalFiles': 0,
          'totalSize': 0,
          'expiredFiles': 0,
          'totalSizeMB': 0.0,
        };
      }

      final now = DateTime.now();

      await for (final entity in tempMediaDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            totalFiles++;
            totalSize += stat.size;

            final age = now.difference(stat.modified);
            if (age > _tempFileExpiration) {
              expiredFiles++;
            }
          } catch (e) {
            logDebug('获取文件统计信息失败: ${entity.path}, 错误: $e');
          }
        }
      }
    } catch (e) {
      logDebug('获取临时文件统计信息失败: $e');
    }

    return {
      'totalFiles': totalFiles,
      'totalSize': totalSize,
      'expiredFiles': expiredFiles,
      'totalSizeMB': totalSize / 1024 / 1024,
    };
  }
}
