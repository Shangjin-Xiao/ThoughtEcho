import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../utils/app_logger.dart';
import 'media_reference_service.dart';
import 'temporary_media_service.dart';
import 'database_service.dart';

/// 媒体文件清理服务
///
/// 负责媒体文件的垃圾回收和清理工作，包括：
/// - 清理孤儿文件
/// - 清理过期临时文件
/// - 迁移现有笔记的媒体引用
/// - 定期维护任务
class MediaCleanupService {
  static Timer? _periodicCleanupTimer;
  static bool _isInitialized = false;

  /// 初始化清理服务
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      logDebug('初始化媒体清理服务...');

      // 启动定期清理任务（每24小时执行一次）
      _startPeriodicCleanup();

      _isInitialized = true;
      logDebug('媒体清理服务初始化完成');
    } catch (e) {
      logDebug('媒体清理服务初始化失败: $e');
    }
  }

  /// 停止清理服务
  static void dispose() {
    _periodicCleanupTimer?.cancel();
    _periodicCleanupTimer = null;
    _isInitialized = false;
    logDebug('媒体清理服务已停止');
  }

  /// 启动定期清理任务
  static void _startPeriodicCleanup() {
    _periodicCleanupTimer?.cancel();

    // 每24小时执行一次清理
    _periodicCleanupTimer = Timer.periodic(
      const Duration(hours: 24),
      (timer) async {
        await performPeriodicCleanup();
      },
    );

    logDebug('定期清理任务已启动');
  }

  /// 执行定期清理
  static Future<Map<String, int>> performPeriodicCleanup() async {
    try {
      logDebug('开始执行定期清理...');

      final results = <String, int>{};

      // 1. 清理过期临时文件
      final expiredTempFiles =
          await TemporaryMediaService.cleanupExpiredTemporaryFiles();
      results['expiredTempFiles'] = expiredTempFiles;

      // 2. 清理孤儿媒体文件
      final orphanFiles = await MediaReferenceService.cleanupOrphanFiles();
      results['orphanFiles'] = orphanFiles;

      logDebug('定期清理完成: $results');
      return results;
    } catch (e) {
      logDebug('定期清理失败: $e');
      return {'error': 1};
    }
  }

  /// 执行完整的媒体文件清理
  static Future<Map<String, dynamic>> performFullCleanup({
    bool dryRun = false,
  }) async {
    try {
      logDebug('开始执行完整清理 (dryRun: $dryRun)...');

      final results = <String, dynamic>{};

      // 1. 获取清理前的统计信息
      final beforeStats = await getMediaStats();
      results['beforeStats'] = beforeStats;

      // 2. 清理所有临时文件
      final tempFiles = dryRun
          ? (await TemporaryMediaService.getTemporaryFilesStats())['totalFiles']
              as int
          : await TemporaryMediaService.cleanupAllTemporaryFiles();
      results['tempFilesCleared'] = tempFiles;

      // 3. 清理孤儿媒体文件
      final orphanFiles =
          await MediaReferenceService.cleanupOrphanFiles(dryRun: dryRun);
      results['orphanFilesCleared'] = orphanFiles;

      // 4. 获取清理后的统计信息
      if (!dryRun) {
        final afterStats = await getMediaStats();
        results['afterStats'] = afterStats;

        // 计算节省的空间
        final spaceSaved =
            beforeStats['totalSizeMB'] - afterStats['totalSizeMB'];
        results['spaceSavedMB'] = spaceSaved;
      }

      logDebug('完整清理完成: $results');
      return results;
    } catch (e) {
      logDebug('完整清理失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 迁移现有笔记的媒体引用
  static Future<Map<String, dynamic>> migrateExistingNotes() async {
    try {
      logDebug('开始迁移现有笔记的媒体引用...');

      final results = <String, dynamic>{};

      // 1. 获取迁移前的统计信息
      final beforeStats = await MediaReferenceService.getMediaReferenceStats();
      results['beforeStats'] = beforeStats;

      // 2. 执行迁移
      final migratedCount = await MediaReferenceService.migrateExistingQuotes();
      results['migratedQuotes'] = migratedCount;

      // 3. 获取迁移后的统计信息
      final afterStats = await MediaReferenceService.getMediaReferenceStats();
      results['afterStats'] = afterStats;

      // 4. 检测孤儿文件
      final orphanFiles = await MediaReferenceService.detectOrphanFiles();
      results['orphanFilesDetected'] = orphanFiles.length;
      results['orphanFilesList'] = orphanFiles;

      logDebug('迁移完成: $results');
      return results;
    } catch (e) {
      logDebug('迁移失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 获取媒体文件统计信息
  static Future<Map<String, dynamic>> getMediaStats() async {
    try {
      final stats = <String, dynamic>{};

      // 1. 媒体引用统计
      final refStats = await MediaReferenceService.getMediaReferenceStats();
      stats.addAll(refStats);

      // 2. 临时文件统计
      final tempStats = await TemporaryMediaService.getTemporaryFilesStats();
      stats['tempFiles'] = tempStats;

      // 3. 媒体文件大小统计
      final sizeStats = await _calculateMediaFilesSizes();
      stats.addAll(sizeStats);

      return stats;
    } catch (e) {
      logDebug('获取媒体统计信息失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 计算媒体文件大小统计
  static Future<Map<String, dynamic>> _calculateMediaFilesSizes() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(path.join(appDir.path, 'media'));

      if (!await mediaDir.exists()) {
        return {
          'totalSizeMB': 0.0,
          'imagesSizeMB': 0.0,
          'videosSizeMB': 0.0,
          'audiosSizeMB': 0.0,
        };
      }

      int totalSize = 0;
      int imagesSize = 0;
      int videosSize = 0;
      int audiosSize = 0;

      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final fileSize = await entity.length();
            totalSize += fileSize;

            final relativePath =
                path.relative(entity.path, from: mediaDir.path);
            if (relativePath.startsWith('images')) {
              imagesSize += fileSize;
            } else if (relativePath.startsWith('videos')) {
              videosSize += fileSize;
            } else if (relativePath.startsWith('audios')) {
              audiosSize += fileSize;
            }
          } catch (e) {
            logDebug('获取文件大小失败: ${entity.path}, 错误: $e');
          }
        }
      }

      return {
        'totalSizeMB': totalSize / 1024 / 1024,
        'imagesSizeMB': imagesSize / 1024 / 1024,
        'videosSizeMB': videosSize / 1024 / 1024,
        'audiosSizeMB': audiosSize / 1024 / 1024,
      };
    } catch (e) {
      logDebug('计算媒体文件大小失败: $e');
      return {
        'totalSizeMB': 0.0,
        'imagesSizeMB': 0.0,
        'videosSizeMB': 0.0,
        'audiosSizeMB': 0.0,
      };
    }
  }

  /// 验证媒体文件完整性
  static Future<Map<String, dynamic>> verifyMediaIntegrity() async {
    try {
      logDebug('开始验证媒体文件完整性...');

      final results = <String, dynamic>{};
      final issues = <String>[];

      // 1. 检查引用表中的文件是否存在
      final databaseService = DatabaseService();
      final quotes = await databaseService.getAllQuotes();

      int checkedReferences = 0;
      int missingFiles = 0;

      for (final quote in quotes) {
        final mediaPaths =
            await MediaReferenceService.extractMediaPathsFromQuote(quote);

        for (final mediaPath in mediaPaths) {
          checkedReferences++;

          // 转换为绝对路径
          final appDir = await getApplicationDocumentsDirectory();
          final absolutePath = path.isAbsolute(mediaPath)
              ? mediaPath
              : path.join(appDir.path, mediaPath);

          if (!await File(absolutePath).exists()) {
            missingFiles++;
            issues.add('笔记 ${quote.id} 引用的文件不存在: $mediaPath');
          }
        }
      }

      results['checkedReferences'] = checkedReferences;
      results['missingFiles'] = missingFiles;
      results['issues'] = issues;
      results['isHealthy'] = missingFiles == 0;

      logDebug('媒体文件完整性验证完成: $results');
      return results;
    } catch (e) {
      logDebug('验证媒体文件完整性失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 修复媒体文件引用
  static Future<Map<String, dynamic>> repairMediaReferences() async {
    try {
      logDebug('开始修复媒体文件引用...');

      final results = <String, dynamic>{};

      // 1. 重新同步所有笔记的媒体引用
      final migrateResult = await migrateExistingNotes();
      results['migration'] = migrateResult;

      // 2. 验证修复结果
      final verifyResult = await verifyMediaIntegrity();
      results['verification'] = verifyResult;

      logDebug('媒体文件引用修复完成: $results');
      return results;
    } catch (e) {
      logDebug('修复媒体文件引用失败: $e');
      return {'error': e.toString()};
    }
  }
}
