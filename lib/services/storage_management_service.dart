import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../utils/app_logger.dart';
import 'database_service.dart';
import 'image_cache_service.dart';
import 'weather_service.dart';
import 'version_check_service.dart';
import 'media_reference_service.dart';
import 'data_directory_service.dart';

/// 存储占用统计数据模型
class StorageStats {
  /// 主数据库大小（字节）
  final int mainDatabaseSize;

  /// 日志数据库大小（字节）
  final int logDatabaseSize;

  /// AI分析数据库大小（字节）
  final int aiDatabaseSize;

  /// 媒体文件总大小（字节）
  final int mediaFilesSize;

  /// 缓存文件大小（字节）
  final int cacheSize;

  /// 总占用空间（字节）
  int get totalSize =>
      mainDatabaseSize +
      logDatabaseSize +
      aiDatabaseSize +
      mediaFilesSize +
      cacheSize;

  /// 媒体文件详细统计
  final MediaFilesBreakdown mediaBreakdown;

  StorageStats({
    required this.mainDatabaseSize,
    required this.logDatabaseSize,
    required this.aiDatabaseSize,
    required this.mediaFilesSize,
    required this.cacheSize,
    required this.mediaBreakdown,
  });

  /// 格式化大小显示
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 媒体文件分类统计
class MediaFilesBreakdown {
  final int imagesSize;
  final int videosSize;
  final int audiosSize;
  final int imagesCount;
  final int videosCount;
  final int audiosCount;

  MediaFilesBreakdown({
    required this.imagesSize,
    required this.videosSize,
    required this.audiosSize,
    required this.imagesCount,
    required this.videosCount,
    required this.audiosCount,
  });
}

/// 存储统计参数（用于传递给 compute isolate）
class _StorageStatsParams {
  final String appDirPath;
  final String tempDirPath;
  final String? mainDbPath;

  _StorageStatsParams({
    required this.appDirPath,
    required this.tempDirPath,
    this.mainDbPath,
  });
}

/// 存储管理服务
/// 负责统计应用存储占用、清理缓存等功能
class StorageManagementService {
  static const String _mediaFolder = 'media';
  static const String _imagesFolder = 'images';
  static const String _videosFolder = 'videos';
  static const String _audiosFolder = 'audios';

  /// 获取存储统计信息
  /// 使用 compute isolate 在后台线程执行，避免阻塞 UI
  static Future<StorageStats> getStorageStats() async {
    try {
      logDebug('开始统计存储占用...');

      if (kIsWeb) {
        // Web 平台直接返回空统计
        return StorageStats(
          mainDatabaseSize: 0,
          logDatabaseSize: 0,
          aiDatabaseSize: 0,
          mediaFilesSize: 0,
          cacheSize: 0,
          mediaBreakdown: MediaFilesBreakdown(
            imagesSize: 0,
            videosSize: 0,
            audiosSize: 0,
            imagesCount: 0,
            videosCount: 0,
            audiosCount: 0,
          ),
        );
      }

      // 预先获取所有需要的路径（这些调用很快）
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();

      // 获取数据库路径
      String? mainDbPath;
      try {
        final dbService = DatabaseService();
        mainDbPath = dbService.database.path;
      } catch (e) {
        logDebug('获取主数据库路径失败: $e');
      }

      // 在后台 isolate 中执行耗时的文件统计
      final stats = await compute(
        _computeStorageStats,
        _StorageStatsParams(
          appDirPath: appDir.path,
          tempDirPath: tempDir.path,
          mainDbPath: mainDbPath,
        ),
      );

      logDebug('存储统计完成: 总占用 ${StorageStats.formatBytes(stats.totalSize)}');
      return stats;
    } catch (e, stackTrace) {
      logError('获取存储统计失败: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 在后台 isolate 中计算存储统计的入口函数
  static Future<StorageStats> _computeStorageStats(
    _StorageStatsParams params,
  ) async {
    // 并行获取各项统计
    final results = await Future.wait([
      _getMainDatabaseSizeIsolate(params.mainDbPath),
      _getLogDatabaseSizeIsolate(params.appDirPath),
      _getAIDatabaseSizeIsolate(params.appDirPath),
      _getMediaFilesSizeIsolate(params.appDirPath),
      _getCacheSizeIsolate(params.tempDirPath),
    ]);

    return StorageStats(
      mainDatabaseSize: results[0] as int,
      logDatabaseSize: results[1] as int,
      aiDatabaseSize: results[2] as int,
      mediaFilesSize: (results[3] as Map<String, dynamic>)['total'] as int,
      cacheSize: results[4] as int,
      mediaBreakdown: (results[3] as Map<String, dynamic>)['breakdown']
          as MediaFilesBreakdown,
    );
  }

  /// Isolate 版本：获取主数据库大小
  static Future<int> _getMainDatabaseSizeIsolate(String? dbPath) async {
    try {
      if (dbPath == null || dbPath.isEmpty) return 0;
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return 0;
      return await dbFile.length();
    } catch (e) {
      return 0;
    }
  }

  /// Isolate 版本：获取日志数据库大小
  static Future<int> _getLogDatabaseSizeIsolate(String appDirPath) async {
    try {
      final logDbPath = path.join(appDirPath, 'databases', 'logs.db');
      final logDbFile = File(logDbPath);
      if (!await logDbFile.exists()) return 0;
      return await logDbFile.length();
    } catch (e) {
      return 0;
    }
  }

  /// Isolate 版本：获取AI分析数据库大小
  static Future<int> _getAIDatabaseSizeIsolate(String appDirPath) async {
    try {
      final aiDbPath = path.join(appDirPath, 'ai_analyses.db');
      final aiDbFile = File(aiDbPath);
      if (!await aiDbFile.exists()) return 0;
      return await aiDbFile.length();
    } catch (e) {
      return 0;
    }
  }

  /// Isolate 版本：获取媒体文件大小
  static Future<Map<String, dynamic>> _getMediaFilesSizeIsolate(
    String appDirPath,
  ) async {
    try {
      final mediaDir = Directory(path.join(appDirPath, _mediaFolder));

      if (!await mediaDir.exists()) {
        return {
          'total': 0,
          'breakdown': MediaFilesBreakdown(
            imagesSize: 0,
            videosSize: 0,
            audiosSize: 0,
            imagesCount: 0,
            videosCount: 0,
            audiosCount: 0,
          ),
        };
      }

      // 分别统计各类媒体文件
      final imagesStats = await _getDirectorySizeIsolate(
        path.join(mediaDir.path, _imagesFolder),
      );
      final videosStats = await _getDirectorySizeIsolate(
        path.join(mediaDir.path, _videosFolder),
      );
      final audiosStats = await _getDirectorySizeIsolate(
        path.join(mediaDir.path, _audiosFolder),
      );

      final breakdown = MediaFilesBreakdown(
        imagesSize: imagesStats['size'] as int,
        videosSize: videosStats['size'] as int,
        audiosSize: audiosStats['size'] as int,
        imagesCount: imagesStats['count'] as int,
        videosCount: videosStats['count'] as int,
        audiosCount: audiosStats['count'] as int,
      );

      final totalSize =
          breakdown.imagesSize + breakdown.videosSize + breakdown.audiosSize;

      return {'total': totalSize, 'breakdown': breakdown};
    } catch (e) {
      return {
        'total': 0,
        'breakdown': MediaFilesBreakdown(
          imagesSize: 0,
          videosSize: 0,
          audiosSize: 0,
          imagesCount: 0,
          videosCount: 0,
          audiosCount: 0,
        ),
      };
    }
  }

  /// Isolate 版本：获取目录大小（无需 yield，因为在独立 isolate 中）
  static Future<Map<String, int>> _getDirectorySizeIsolate(
    String dirPath,
  ) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return {'size': 0, 'count': 0};
      }

      int totalSize = 0;
      int fileCount = 0;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
            fileCount++;
          } catch (e) {
            // 忽略单个文件的错误
          }
        }
      }

      return {'size': totalSize, 'count': fileCount};
    } catch (e) {
      return {'size': 0, 'count': 0};
    }
  }

  /// Isolate 版本：获取缓存大小
  static Future<int> _getCacheSizeIsolate(String tempDirPath) async {
    try {
      final tempStats = await _getDirectorySizeIsolate(tempDirPath);
      return tempStats['size'] as int;
    } catch (e) {
      return 0;
    }
  }

  /// 获取目录大小和文件数量（用于清理缓存时计算大小变化）
  static Future<Map<String, int>> _getDirectorySize(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return {'size': 0, 'count': 0};
      }

      int totalSize = 0;
      int fileCount = 0;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
            fileCount++;
          } catch (e) {
            // 忽略单个文件错误
          }
        }
      }

      return {'size': totalSize, 'count': fileCount};
    } catch (e) {
      return {'size': 0, 'count': 0};
    }
  }

  /// 清理应用缓存
  /// 返回清理的字节数
  static Future<int> clearCache({
    WeatherService? weatherService,
    DatabaseService? databaseService,
  }) async {
    try {
      logDebug('开始清理缓存...');
      int clearedBytes = 0;

      // 1. 清理图片缓存（内存缓存）
      try {
        ImageCacheService().clearCache();
        logDebug('图片缓存已清除');
      } catch (e) {
        logDebug('清理图片缓存失败: $e');
      }

      // 2. 清理天气缓存
      if (weatherService != null) {
        try {
          await weatherService.clearCache();
          logDebug('天气缓存已清除');
        } catch (e) {
          logDebug('清理天气缓存失败: $e');
        }
      }

      // 3. 清理版本检查缓存
      try {
        VersionCheckService.clearCache();
        logDebug('版本检查缓存已清除');
      } catch (e) {
        logDebug('清理版本检查缓存失败: $e');
      }

      // 4. 刷新数据库内存缓存（不删除数据）
      if (databaseService != null) {
        try {
          databaseService.refreshAllData();
          logDebug('数据库内存缓存已刷新');
        } catch (e) {
          logDebug('刷新数据库缓存失败: $e');
        }
      }

      // 5. 清理临时文件
      if (!kIsWeb) {
        try {
          final tempDir = await getTemporaryDirectory();
          final beforeSize =
              (await _getDirectorySize(tempDir.path))['size'] as int;

          // 清理临时目录中的所有文件
          await for (final entity in tempDir.list()) {
            try {
              if (entity is File) {
                await entity.delete();
              } else if (entity is Directory) {
                await entity.delete(recursive: true);
              }
            } catch (e) {
              logDebug('删除临时文件失败: ${entity.path}, 错误: $e');
            }
          }

          final afterSize =
              (await _getDirectorySize(tempDir.path))['size'] as int;
          clearedBytes += (beforeSize - afterSize);
          logDebug(
            '临时文件已清理: ${StorageStats.formatBytes(beforeSize - afterSize)}',
          );
        } catch (e) {
          logDebug('清理临时文件失败: $e');
        }
      }

      logDebug('缓存清理完成，共清理: ${StorageStats.formatBytes(clearedBytes)}');
      return clearedBytes;
    } catch (e, stackTrace) {
      logError('清理缓存失败: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 清理孤儿媒体文件
  /// 返回清理的文件数量
  static Future<int> cleanupOrphanFiles() async {
    try {
      logDebug('开始清理孤儿媒体文件...');
      final orphanCount = await MediaReferenceService.cleanupOrphanFiles();
      logDebug('孤儿媒体文件清理完成: 清理了 $orphanCount 个文件');
      return orphanCount;
    } catch (e, stackTrace) {
      logError('清理孤儿媒体文件失败: $e', error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  /// 获取应用数据目录路径
  /// Windows 平台使用 Documents/ThoughtEcho，其他平台使用 Documents
  static Future<String> getAppDataDirectory() async {
    try {
      if (!kIsWeb && Platform.isWindows) {
        return await DataDirectoryService.getCurrentDataDirectory();
      }
      final appDir = await getApplicationDocumentsDirectory();
      return appDir.path;
    } catch (e) {
      logError('获取应用数据目录失败: $e', error: e);
      rethrow;
    }
  }

  /// 获取可用磁盘空间（字节）
  /// 注意：Flutter 没有直接的跨平台 API 获取磁盘空间
  /// 如需精确信息可集成 disk_space 插件，当前返回 null
  static Future<int?> getAvailableDiskSpace() async {
    return null;
  }
}
