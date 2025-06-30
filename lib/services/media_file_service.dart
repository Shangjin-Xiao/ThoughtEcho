import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 媒体文件管理服务
/// 简化实现：直接复制文件到私有目录
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

  /// 复制图片到私有目录
  static Future<String?> saveImage(String sourcePath) async {
    try {
      final imageDir = await _getMediaDirectory(_imagesFolder);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(imageDir.path, fileName);

      final sourceFile = File(sourcePath);
      await sourceFile.copy(targetPath);

      return targetPath;
    } catch (e) {
      if (kDebugMode) {
        print('保存图片失败: $e');
      }
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

      final sourceFile = File(sourcePath);
      await sourceFile.copy(targetPath);

      return targetPath;
    } catch (e) {
      if (kDebugMode) {
        print('保存视频失败: $e');
      }
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

      final sourceFile = File(sourcePath);
      await sourceFile.copy(targetPath);

      return targetPath;
    } catch (e) {
      if (kDebugMode) {
        print('保存音频失败: $e');
      }
      return null;
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
}
