import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import 'large_file_manager.dart';

/// 数据目录管理服务（桌面平台专用）
/// 允许用户自定义应用数据存储位置，并处理数据迁移
class DataDirectoryService {
  static const String _customPathKey = 'custom_data_directory_path';
  static const String _isUsingCustomPathKey = 'is_using_custom_data_directory';
  static const String _legacyMigrationDoneKey = 'legacy_data_migration_done';
  static const String _appDataFolderName = 'ThoughtEcho';

  /// 获取默认的应用数据目录（Documents/ThoughtEcho）
  static Future<String> getDefaultDataDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return path.join(docsDir.path, _appDataFolderName);
  }

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

      // 使用默认路径：Documents/ThoughtEcho
      return await getDefaultDataDirectory();
    } catch (e) {
      logError('获取数据目录失败: $e', error: e);
      rethrow;
    }
  }

  /// 检查并执行旧版数据迁移（从 Documents 根目录迁移到 Documents/ThoughtEcho）
  /// 这是为了兼容旧版本用户，将数据从 Documents 根目录迁移到子文件夹
  static Future<bool> checkAndMigrateLegacyData() async {
    if (kIsWeb || !Platform.isWindows) {
      return true; // 仅 Windows 需要此迁移
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查是否已经完成迁移
      if (prefs.getBool(_legacyMigrationDoneKey) ?? false) {
        return true;
      }

      // 检查是否使用自定义路径（自定义路径用户不需要迁移）
      if (prefs.getBool(_isUsingCustomPathKey) ?? false) {
        await prefs.setBool(_legacyMigrationDoneKey, true);
        return true;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final legacyDbPath = path.join(
        docsDir.path,
        'databases',
        'thoughtecho.db',
      );
      final legacyDbFile = File(legacyDbPath);

      // 检查旧版数据是否存在于 Documents 根目录
      if (!await legacyDbFile.exists()) {
        // 没有旧版数据，标记迁移完成
        await prefs.setBool(_legacyMigrationDoneKey, true);
        logDebug('没有检测到旧版数据，跳过迁移');
        return true;
      }

      // 新路径
      final newDataDir = await getDefaultDataDirectory();
      final newDbPath = path.join(newDataDir, 'databases', 'thoughtecho.db');
      final newDbFile = File(newDbPath);

      // 如果新路径已经有数据库，说明已经迁移过
      if (await newDbFile.exists()) {
        await prefs.setBool(_legacyMigrationDoneKey, true);
        logDebug('新数据目录已存在数据，跳过迁移');
        return true;
      }

      logInfo('检测到旧版数据，开始自动迁移到 $newDataDir');

      // 创建新目录
      await Directory(newDataDir).create(recursive: true);

      // 迁移应用相关的文件和目录
      final itemsToMigrate = ['databases', 'media', 'ai_analyses.db'];

      for (final item in itemsToMigrate) {
        final sourcePath = path.join(docsDir.path, item);
        final targetPath = path.join(newDataDir, item);

        final sourceDir = Directory(sourcePath);
        final sourceFile = File(sourcePath);

        if (await sourceDir.exists()) {
          // 复制目录
          await _copyDirectory(sourceDir, Directory(targetPath));
          logDebug('已迁移目录: $item');
        } else if (await sourceFile.exists()) {
          // 复制文件
          await Directory(path.dirname(targetPath)).create(recursive: true);
          await sourceFile.copy(targetPath);
          logDebug('已迁移文件: $item');
        }
      }

      // 标记迁移完成
      await prefs.setBool(_legacyMigrationDoneKey, true);
      logInfo('旧版数据迁移完成');
      return true;
    } catch (e, stackTrace) {
      logError('旧版数据迁移失败: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 复制目录及其内容
  static Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    await for (final entity in source.list(followLinks: false)) {
      final newPath = path.join(target.path, path.basename(entity.path));

      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
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

      // 3. 只迁移应用相关的文件和目录
      // 使用 isolate 避免阻塞 UI
      final result = await compute(_collectAppFiles, currentPath);
      final filesToCopy = result['files'] as List<String>;
      final errors = result['errors'] as List<String>;

      if (errors.isNotEmpty) {
        logDebug('收集文件时遇到 ${errors.length} 个错误');
      }

      if (filesToCopy.isEmpty) {
        logDebug('没有需要迁移的文件');
        // 即使没有文件，也继续设置新目录
      } else {
        logDebug('需要迁移 ${filesToCopy.length} 个文件');

        // 4. 复制文件到新目录
        int copiedCount = 0;
        for (final filePath in filesToCopy) {
          try {
            final file = File(filePath);
            final relativePath = path.relative(filePath, from: currentPath);
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
          } catch (e) {
            logError('复制文件失败: $filePath, 错误: $e', error: e);
            // 继续复制其他文件
          }
        }

        onStatusUpdate?.call('验证文件完整性...');

        // 5. 验证关键文件是否复制成功
        final criticalFiles = ['databases/thoughtecho.db'];

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

  /// 在 isolate 中收集应用相关的文件（避免阻塞 UI）
  static Future<Map<String, dynamic>> _collectAppFiles(
    String currentPath,
  ) async {
    final filesToCopy = <String>[];
    final errors = <String>[];

    // 只迁移应用相关的目录和文件
    final appItems = [
      'databases', // 数据库目录
      'media', // 媒体文件目录
      'ai_analyses.db', // AI 分析数据库
      'backups', // 备份目录
    ];

    for (final item in appItems) {
      final itemPath = path.join(currentPath, item);
      final itemDir = Directory(itemPath);
      final itemFile = File(itemPath);

      try {
        if (await itemDir.exists()) {
          // 遍历目录中的文件
          await for (final entity in itemDir.list(
            recursive: true,
            followLinks: false,
          )) {
            try {
              if (entity is File) {
                final fileName = path.basename(entity.path).toLowerCase();
                // 跳过系统文件
                if (!_isWindowsSystemFile(fileName)) {
                  filesToCopy.add(entity.path);
                }
              }
            } catch (e) {
              errors.add('无法访问: ${entity.path}');
            }
          }
        } else if (await itemFile.exists()) {
          filesToCopy.add(itemFile.path);
        }
      } catch (e) {
        errors.add('无法访问目录: $itemPath');
      }
    }

    return {'files': filesToCopy, 'errors': errors};
  }

  /// 检查是否是 Windows 系统文件
  static bool _isWindowsSystemFile(String fileName) {
    final systemFiles = ['desktop.ini', 'thumbs.db', 'ntuser.dat', '.ds_store'];
    return systemFiles.contains(fileName);
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
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
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
}
