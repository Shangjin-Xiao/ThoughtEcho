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

/// 存储管理服务
/// 负责统计应用存储占用、清理缓存等功能
class StorageManagementService {
  static const String _mediaFolder = 'media';
  static const String _imagesFolder = 'images';
  static const String _videosFolder = 'videos';
  static const String _audiosFolder = 'audios';

  /// 获取存储统计信息
  static Future<StorageStats> getStorageStats() async {
    try {
      logDebug('开始统计存储占用...');

      // 并行获取各项统计
      final results = await Future.wait([
        _getMainDatabaseSize(),
        _getLogDatabaseSize(),
        _getAIDatabaseSize(),
        _getMediaFilesSize(),
        _getCacheSize(),
      ]);

      final stats = StorageStats(
        mainDatabaseSize: results[0] as int,
        logDatabaseSize: results[1] as int,
        aiDatabaseSize: results[2] as int,
        mediaFilesSize: (results[3] as Map<String, dynamic>)['total'] as int,
        cacheSize: results[4] as int,
        mediaBreakdown: (results[3] as Map<String, dynamic>)['breakdown']
            as MediaFilesBreakdown,
      );

      logDebug('存储统计完成: 总占用 ${StorageStats.formatBytes(stats.totalSize)}');
      return stats;
    } catch (e, stackTrace) {
      logError('获取存储统计失败: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 获取主数据库大小
  static Future<int> _getMainDatabaseSize() async {
    try {
      if (kIsWeb) return 0; // Web 平台使用内存存储

      final dbService = DatabaseService();
      final db = dbService.database;

      // 获取数据库文件路径
      final dbPath = db.path;
      if (dbPath.isEmpty) {
        logDebug('主数据库路径为空');
        return 0;
      }

      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        logDebug('主数据库文件不存在: $dbPath');
        return 0;
      }

      final size = await dbFile.length();
      logDebug('主数据库大小: ${StorageStats.formatBytes(size)}');
      return size;
    } catch (e) {
      logDebug('获取主数据库大小失败: $e');
      return 0;
    }
  }

  /// 获取日志数据库大小
  static Future<int> _getLogDatabaseSize() async {
    try {
      if (kIsWeb) return 0; // Web 平台使用 SharedPreferences

      // 日志数据库路径
      final appDir = await getApplicationDocumentsDirectory();
      final logDbPath = path.join(appDir.path, 'databases', 'logs.db');

      final logDbFile = File(logDbPath);
      if (!await logDbFile.exists()) {
        logDebug('日志数据库文件不存在: $logDbPath');
        return 0;
      }

      final size = await logDbFile.length();
      logDebug('日志数据库大小: ${StorageStats.formatBytes(size)}');
      return size;
    } catch (e) {
      logDebug('获取日志数据库大小失败: $e');
      return 0;
    }
  }

  /// 获取AI分析数据库大小
  static Future<int> _getAIDatabaseSize() async {
    try {
      if (kIsWeb) return 0; // Web 平台使用内存存储

      // AI分析数据库路径
      final appDir = await getApplicationDocumentsDirectory();
      final aiDbPath = path.join(appDir.path, 'ai_analyses.db');

      final aiDbFile = File(aiDbPath);
      if (!await aiDbFile.exists()) {
        logDebug('AI分析数据库文件不存在: $aiDbPath');
        return 0;
      }

      final size = await aiDbFile.length();
      logDebug('AI分析数据库大小: ${StorageStats.formatBytes(size)}');
      return size;
    } catch (e) {
      logDebug('获取AI分析数据库大小失败: $e');
      return 0;
    }
  }

  /// 获取媒体文件大小（包含详细分类）
  static Future<Map<String, dynamic>> _getMediaFilesSize() async {
    try {
      if (kIsWeb) {
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

      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(path.join(appDir.path, _mediaFolder));

      if (!await mediaDir.exists()) {
        logDebug('媒体文件夹不存在');
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
      final imagesStats = await _getDirectorySize(
        path.join(mediaDir.path, _imagesFolder),
      );
      final videosStats = await _getDirectorySize(
        path.join(mediaDir.path, _videosFolder),
      );
      final audiosStats = await _getDirectorySize(
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

      logDebug('媒体文件统计: 图片 ${StorageStats.formatBytes(breakdown.imagesSize)} '
          '(${breakdown.imagesCount}个), '
          '视频 ${StorageStats.formatBytes(breakdown.videosSize)} '
          '(${breakdown.videosCount}个), '
          '音频 ${StorageStats.formatBytes(breakdown.audiosSize)} '
          '(${breakdown.audiosCount}个)');

      return {
        'total': totalSize,
        'breakdown': breakdown,
      };
    } catch (e) {
      logDebug('获取媒体文件大小失败: $e');
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

  /// 获取目录大小和文件数量
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
            logDebug('获取文件大小失败: ${entity.path}, 错误: $e');
          }
        }
      }

      return {'size': totalSize, 'count': fileCount};
    } catch (e) {
      logDebug('获取目录大小失败: $dirPath, 错误: $e');
      return {'size': 0, 'count': 0};
    }
  }

  /// 获取缓存大小（包含临时文件和各种缓存）
  static Future<int> _getCacheSize() async {
    try {
      if (kIsWeb) return 0;

      int totalSize = 0;

      // 1. 临时目录
      try {
        final tempDir = await getTemporaryDirectory();
        final tempStats = await _getDirectorySize(tempDir.path);
        totalSize += tempStats['size'] as int;
        logDebug(
            '临时目录大小: ${StorageStats.formatBytes(tempStats['size'] as int)}');
      } catch (e) {
        logDebug('获取临时目录大小失败: $e');
      }

      // 2. 图片缓存（内存缓存无法准确统计，这里暂不计入）
      // ImageCacheService 是内存缓存，不占用磁盘空间

      logDebug('缓存总大小: ${StorageStats.formatBytes(totalSize)}');
      return totalSize;
    } catch (e) {
      logDebug('获取缓存大小失败: $e');
      return 0;
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
              '临时文件已清理: ${StorageStats.formatBytes(beforeSize - afterSize)}');
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
  static Future<String> getAppDataDirectory() async {
    try {
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
