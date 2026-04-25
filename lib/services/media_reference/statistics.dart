part of '../media_reference_service.dart';

/// Extension for statistics and migration
extension MediaStatistics on MediaReferenceService {
  /// 获取媒体引用统计信息
  static Future<Map<String, dynamic>> getMediaReferenceStats() async {
    try {
      final db = await database;

      // 总引用数
      final totalRefsResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName',
      );
      final totalRefs = totalRefsResult.first['count'] as int;

      // 被引用的文件数
      final referencedFilesResult = await db.rawQuery(
        'SELECT COUNT(DISTINCT file_path) as count FROM $_tableName',
      );
      final referencedFiles = referencedFilesResult.first['count'] as int;

      // 总媒体文件数
      final allMediaFiles = await _getAllMediaFiles();
      final totalFiles = allMediaFiles.length;

      // 孤儿文件数
      final orphanFiles = totalFiles - referencedFiles;

      return {
        'totalReferences': totalRefs,
        'referencedFiles': referencedFiles,
        'totalFiles': totalFiles,
        'orphanFiles': orphanFiles,
      };
    } catch (e) {
      logDebug('获取媒体引用统计信息失败: $e');
      return {
        'totalReferences': 0,
        'referencedFiles': 0,
        'totalFiles': 0,
        'orphanFiles': 0,
      };
    }
  }

  /// 迁移现有笔记的媒体文件引用
  static Future<int> migrateExistingQuotes() async {
    try {
      logDebug('开始迁移现有笔记的媒体文件引用...');

      final databaseService = DatabaseService();
      // 媒体引用迁移需要处理所有笔记（包括隐藏笔记）
      // 修复：使用分页加载以避免内存溢出
      int migratedCount = 0;
      const int pageSize = 200;
      var offset = 0;

      // 获取应用目录路径缓存
      final appDir = await getApplicationDocumentsDirectory();
      final appPath = path.normalize(appDir.path);

      while (true) {
        final quotes = await databaseService.getUserQuotes(
          offset: offset,
          limit: pageSize,
          excludeHiddenNotes: false,
          includeDeleted: true,
        );
        if (quotes.isEmpty) break;

        for (final quote in quotes) {
          final success = await MediaQuoteSync.syncQuoteMediaReferences(
            quote,
            cachedAppPath: appPath,
          );
          if (success) {
            migratedCount++;
          }
        }

        offset += quotes.length;
        if (quotes.length < pageSize) break;

        // 让出事件循环，避免长时间阻塞UI
        await Future.delayed(const Duration(milliseconds: 0));
      }

      logDebug('迁移完成，共处理 $migratedCount 个笔记');
      return migratedCount;
    } catch (e) {
      logDebug('迁移现有笔记媒体文件引用失败: $e');
      return 0;
    }
  }

  /// 获取所有媒体文件路径
  static Future<List<String>> _getAllMediaFiles() async {
    final mediaFiles = <String>[];

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(path.join(appDir.path, 'media'));

      if (!await mediaDir.exists()) {
        return mediaFiles;
      }

      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          mediaFiles.add(entity.path);
        }
      }
    } catch (e) {
      logDebug('获取所有媒体文件失败: $e');
    }

    return mediaFiles;
  }
}
