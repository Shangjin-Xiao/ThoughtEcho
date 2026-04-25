part of '../media_reference_service.dart';

/// Extension for basic reference operations
extension MediaReferenceOperations on MediaReferenceService {
  /// 添加媒体文件引用
  static Future<bool> addReference(
    String filePath,
    String quoteId, {
    String? cachedAppPath,
  }) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(
        filePath,
        cachedAppPath: cachedAppPath,
      );

      await db.insert(
        _tableName,
        {
          'id': const Uuid().v4(),
          'file_path': normalizedPath,
          'quote_id': quoteId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore, // 忽略重复引用
      );

      logDebug('添加媒体文件引用: $normalizedPath -> $quoteId');
      return true;
    } catch (e) {
      logDebug('添加媒体文件引用失败: $e');
      return false;
    }
  }

  /// 移除媒体文件引用
  static Future<bool> removeReference(
    String filePath,
    String quoteId, {
    String? cachedAppPath,
  }) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(
        filePath,
        cachedAppPath: cachedAppPath,
      );

      final result = await db.delete(
        _tableName,
        where: 'file_path = ? AND quote_id = ?',
        whereArgs: [normalizedPath, quoteId],
      );

      logDebug('移除媒体文件引用: $normalizedPath -> $quoteId (删除了 $result 条记录)');
      return result > 0;
    } catch (e) {
      logDebug('移除媒体文件引用失败: $e');
      return false;
    }
  }

  /// 移除笔记的所有媒体文件引用
  static Future<int> removeAllReferencesForQuote(String quoteId) async {
    try {
      final db = await database;

      final result = await db.delete(
        _tableName,
        where: 'quote_id = ?',
        whereArgs: [quoteId],
      );

      logDebug('移除笔记的所有媒体文件引用: $quoteId (删除了 $result 条记录)');
      return result;
    } catch (e) {
      logDebug('移除笔记媒体文件引用失败: $e');
      return 0;
    }
  }

  /// 获取媒体文件的引用计数
  static Future<int> getReferenceCount(
    String filePath, {
    String? cachedAppPath,
  }) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(
        filePath,
        cachedAppPath: cachedAppPath,
      );

      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName WHERE file_path = ?',
        [normalizedPath],
      );

      final count = result.first['count'] as int;
      return count;
    } catch (e) {
      logDebug('获取媒体文件引用计数失败: $e');
      return 0;
    }
  }

  /// 获取笔记引用的所有媒体文件
  static Future<List<String>> getReferencedFiles(String quoteId) async {
    try {
      final db = await database;

      final result = await db.query(
        _tableName,
        columns: ['file_path'],
        where: 'quote_id = ?',
        whereArgs: [quoteId],
      );

      return result.map((row) => row['file_path'] as String).toList();
    } catch (e) {
      logDebug('获取笔记引用的媒体文件失败: $e');
      return [];
    }
  }

  /// 批量获取多个笔记引用的媒体文件
  static Future<Map<String, List<String>>> getReferencedFilesBatch(
    Iterable<String> quoteIds,
  ) async {
    const int maxChunkSize = 900;
    final uniqueIds = quoteIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) {
      return {};
    }

    try {
      final db = await database;
      final grouped = <String, List<String>>{};

      for (var start = 0; start < uniqueIds.length; start += maxChunkSize) {
        final end = math.min(start + maxChunkSize, uniqueIds.length);
        final chunk = uniqueIds.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final result = await db.query(
          _tableName,
          columns: ['quote_id', 'file_path'],
          where: 'quote_id IN ($placeholders)',
          whereArgs: chunk,
        );

        for (final row in result) {
          final quoteId = row['quote_id'] as String?;
          final filePath = row['file_path'] as String?;
          if (quoteId == null || filePath == null) {
            continue;
          }
          grouped.putIfAbsent(quoteId, () => <String>[]).add(filePath);
        }
      }
      return grouped;
    } catch (e, stackTrace) {
      logError(
        '批量获取笔记引用的媒体文件失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'MediaReferenceService',
      );
      rethrow;
    }
  }
}
