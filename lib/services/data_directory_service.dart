import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import 'large_file_manager.dart';

/// 数据目录管理服务（Windows专用）
/// 允许用户自定义应用数据存储位置，并处理数据迁移
class DataDirectoryService {
  static const String _customPathKey = 'custom_data_directory_path';
  static const String _isUsingCustomPathKey = 'is_using_custom_data_directory';

  /// 获取当前使用的数据目录
  static Future<String> getCurrentDataDirectory() async {
    try {
      // 检查是否使用自定义路径
      final prefs = await SharedPreferences.getInstance();
      final isUsingCustomPath = prefs.getBool(_isUsingCustomPathKey) ?? false;

      if (isUsingCustomPath) {
        final customPath = prefs.getString(_customPathKey);
        if (customPath != null && customPath.isNotEmpty) {
          // 验证自定义路径是否仍然有效
          final customDir = Directory(customPath);
          if (await customDir.exists()) {
            return customPath;
          } else {
            // 自定义路径不存在，回退到默认路径
            logError('自定义数据目录不存在，回退到默认路径: $customPath');
            await _resetToDefaultDirectory();
          }
        }
      }

      // 使用默认路径
      final appDir = await getApplicationDocumentsDirectory();
      return appDir.path;
    } catch (e) {
      logError('获取数据目录失败: $e', error: e);
      rethrow;
    }
  }

  /// 检查是否正在使用自定义数据目录
  static Future<bool> isUsingCustomDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_isUsingCustomPathKey) ?? false;
    } catch (e) {
      logError('检查自定义目录状态失败: $e', error: e);
      return false;
    }
  }

  /// 获取自定义数据目录路径（如果有）
  static Future<String?> getCustomDataDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_customPathKey);
    } catch (e) {
      logError('获取自定义目录路径失败: $e', error: e);
      return null;
    }
  }

  /// 验证目录是否可用于存储数据
  static Future<bool> validateDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);

      // 检查目录是否存在
      if (!await dir.exists()) {
        // 尝试创建目录
        try {
          await dir.create(recursive: true);
        } catch (e) {
          logError('无法创建目录: $e', error: e);
          return false;
        }
      }

      // 检查是否有写权限
      final testFile = File(path.join(dirPath, '.write_test'));
      try {
        await testFile.writeAsString('test');
        await testFile.delete();
      } catch (e) {
        logError('目录没有写权限: $e', error: e);
        return false;
      }

      // 检查可用空间（至少需要 100MB）
      // 注意: Flutter 没有直接 API 检查磁盘空间，这里简化处理
      // 实际使用中可以集成 disk_space 插件

      return true;
    } catch (e) {
      logError('验证目录失败: $e', error: e);
      return false;
    }
  }

  /// 迁移数据到新目录
  /// 返回是否成功
  static Future<bool> migrateDataDirectory(
    String newPath, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Web平台不支持数据目录迁移');
    }

    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError('仅支持桌面平台');
    }

    try {
      onStatusUpdate?.call('正在验证新目录...');
      logDebug('开始迁移数据到: $newPath');

      // 1. 验证新目录
      if (!await validateDirectory(newPath)) {
        throw Exception('新目录不可用或没有写权限');
      }

      // 2. 获取当前目录
      final currentPath = await getCurrentDataDirectory();
      if (currentPath == newPath) {
        throw Exception('新目录与当前目录相同');
      }

      onStatusUpdate?.call('正在准备迁移...');
      final currentDir = Directory(currentPath);
      if (!await currentDir.exists()) {
        throw Exception('当前数据目录不存在');
      }

      // 3. 计算需要复制的文件
      final filesToCopy = <FileSystemEntity>[];
      try {
        await for (final entity in currentDir.list(
          recursive: true,
          followLinks: false, // 不跟随符号链接，避免访问系统文件夹
        )) {
          try {
            if (entity is File) {
              // 排除 Windows 特殊文件夹（My Music, My Videos 等）
              final relativePath = path.relative(
                entity.path,
                from: currentPath,
              );
              if (!_isSystemFolder(relativePath)) {
                filesToCopy.add(entity);
              }
            }
          } catch (e) {
            // 跳过无法访问的单个文件
            logDebug('跳过无法访问的文件: ${entity.path}, 错误: $e');
          }
        }
      } catch (e) {
        // 如果整个目录遍历失败，记录错误但继续
        logError('遍历目录时遇到错误: $e', error: e);
        // 如果没有收集到任何文件，抛出错误
        if (filesToCopy.isEmpty) {
          throw Exception('无法读取当前数据目录中的文件: $e');
        }
      }

      if (filesToCopy.isEmpty) {
        logDebug('没有需要迁移的文件');
        // 即使没有文件，也继续设置新目录
      } else {
        logDebug('需要迁移 ${filesToCopy.length} 个文件');

        // 4. 复制文件到新目录
        int copiedCount = 0;
        for (final entity in filesToCopy) {
          if (entity is! File) continue;

          final file = entity;
          final relativePath = path.relative(file.path, from: currentPath);
          final targetPath = path.join(newPath, relativePath);

          onStatusUpdate?.call('正在复制: $relativePath');

          // 确保目标目录存在
          final targetDir = Directory(path.dirname(targetPath));
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }

          // 使用 LargeFileManager 复制文件（支持大文件）
          await LargeFileManager.copyFileInChunks(
            file.path,
            targetPath,
            onProgress: (current, total) {
              if (onProgress != null && total > 0) {
                final fileProgress = current / total;
                final totalProgress =
                    (copiedCount + fileProgress) / filesToCopy.length;
                onProgress(totalProgress);
              }
            },
          );

          copiedCount++;
          onProgress?.call(copiedCount / filesToCopy.length);
        }

        onStatusUpdate?.call('验证文件完整性...');

        // 5. 验证关键文件是否复制成功
        final criticalFiles = [
          'databases/notes.db',
          'databases/logs.db',
          'ai_analyses.db',
        ];

        for (final relPath in criticalFiles) {
          final sourceFile = File(path.join(currentPath, relPath));
          final targetFile = File(path.join(newPath, relPath));

          if (await sourceFile.exists()) {
            if (!await targetFile.exists()) {
              throw Exception('关键文件复制失败: $relPath');
            }

            final sourceSize = await sourceFile.length();
            final targetSize = await targetFile.length();
            if (sourceSize != targetSize) {
              throw Exception('文件大小不匹配: $relPath');
            }
          }
        }
      }

      onStatusUpdate?.call('更新配置...');

      // 6. 保存新路径配置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customPathKey, newPath);
      await prefs.setBool(_isUsingCustomPathKey, true);

      logDebug('数据迁移成功完成');
      onStatusUpdate?.call('迁移完成');

      // 7. 提示用户重启应用
      // 注意：实际应用中，需要重启应用才能生效新路径

      return true;
    } catch (e, stackTrace) {
      logError('数据迁移失败: $e', error: e, stackTrace: stackTrace);
      onStatusUpdate?.call('迁移失败: $e');
      return false;
    }
  }

  /// 重置到默认数据目录
  static Future<void> _resetToDefaultDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_customPathKey);
      await prefs.setBool(_isUsingCustomPathKey, false);
      logDebug('已重置到默认数据目录');
    } catch (e) {
      logError('重置数据目录失败: $e', error: e);
    }
  }

  /// 清除自定义数据目录配置（不删除文件）
  static Future<void> clearCustomDirectoryConfig() async {
    try {
      await _resetToDefaultDirectory();
      logDebug('已清除自定义数据目录配置');
    } catch (e) {
      logError('清除配置失败: $e', error: e);
      rethrow;
    }
  }

  /// 获取建议的数据目录路径（Windows）
  static Future<List<String>> getSuggestedDirectories() async {
    if (!Platform.isWindows) {
      return [];
    }

    try {
      final suggestions = <String>[];

      // 1. 当前文档目录
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        suggestions.add(docsDir.path);
      } catch (e) {
        logDebug('无法获取文档目录: $e');
      }

      // 2. 用户主目录下的 Documents/ThoughtEcho
      try {
        final homeDir = Platform.environment['USERPROFILE'];
        if (homeDir != null) {
          suggestions.add(path.join(homeDir, 'Documents', 'ThoughtEcho'));
        }
      } catch (e) {
        logDebug('无法获取用户主目录: $e');
      }

      // 3. D盘（如果存在）
      try {
        final dDrive = Directory('D:\\ThoughtEcho');
        if (await Directory('D:\\').exists()) {
          suggestions.add(dDrive.path);
        }
      } catch (e) {
        logDebug('D盘不可用: $e');
      }

      return suggestions;
    } catch (e) {
      logError('获取建议目录失败: $e', error: e);
      return [];
    }
  }

  /// 计算目录大小（用于迁移前估算）
  static Future<int> calculateDirectorySize(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (e) {
            logDebug('获取文件大小失败: ${entity.path}');
          }
        }
      }

      return totalSize;
    } catch (e) {
      logError('计算目录大小失败: $e', error: e);
      return 0;
    }
  }

  /// 检查是否是 Windows 系统文件夹（如 My Music, My Videos 等）
  static bool _isSystemFolder(String relativePath) {
    if (!Platform.isWindows) return false;

    final lowerPath = relativePath.toLowerCase();
    final systemFolders = [
      'my music',
      'my videos',
      'my pictures',
      'my documents',
      'desktop.ini',
      'thumbs.db',
    ];

    return systemFolders.any((folder) => lowerPath.contains(folder));
  }
}
