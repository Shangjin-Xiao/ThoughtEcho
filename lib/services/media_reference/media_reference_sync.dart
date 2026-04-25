part of '../media_reference_service.dart';

/// 提供给备份使用的引用快照（避免重复全量扫描）
Future<ReferenceSnapshot> _buildReferenceSnapshotForBackup() async {
  return _buildReferenceSnapshot();
}

/// 备份/恢复使用的路径标准化（避免重复获取目录）
Future<String> _normalizePathForBackup(
  String filePath, {
  required String appPath,
}) async {
  try {
    if (filePath.isEmpty) {
      return filePath;
    }

    var sanitized = filePath.trim();

    if (sanitized.startsWith('file://')) {
      final uri = Uri.tryParse(sanitized);
      if (uri != null && uri.scheme == 'file') {
        sanitized = uri.toFilePath();
      }
    }

    sanitized = path.normalize(sanitized);

    if (sanitized.startsWith(appPath)) {
      return path.normalize(path.relative(sanitized, from: appPath));
    }

    return sanitized;
  } catch (_) {
    return filePath;
  }
}

/// 备份/恢复使用的统一比较Key
String _canonicalKeyForBackup(String value) {
  return _canonicalComparisonKey(value);
}

Future<ReferenceSnapshot> _buildReferenceSnapshot() async {
  final storedIndex = await _fetchStoredReferenceIndex();
  final quoteIndex = await _collectQuoteReferenceIndex();
  return ReferenceSnapshot(storedIndex: storedIndex, quoteIndex: quoteIndex);
}

Future<Map<String, Map<String, Set<String>>>>
    _fetchStoredReferenceIndex() async {
  final db = await MediaReferenceService.database;
  final rows = await db.query(MediaReferenceService._tableName, columns: ['file_path', 'quote_id']);

  final index = <String, Map<String, Set<String>>>{};

  for (final row in rows) {
    final filePath = row['file_path'] as String?;
    final quoteId = row['quote_id'] as String?;
    if (filePath == null || quoteId == null || quoteId.isEmpty) {
      continue;
    }

    final variantPath = path.normalize(filePath);
    final key = _canonicalComparisonKey(variantPath);

    final variants = index.putIfAbsent(key, () => <String, Set<String>>{});
    final quoteSet = variants.putIfAbsent(variantPath, () => <String>{});
    quoteSet.add(quoteId);
  }

  return index;
}

Future<Map<String, Map<String, Set<String>>>>
    _collectQuoteReferenceIndex() async {
  final databaseService = DatabaseService();
  // 媒体引用索引需要包含所有笔记（包括隐藏笔记）
  final quotes = await databaseService.getAllQuotes(
    excludeHiddenNotes: false,
    includeDeleted: true,
  );

  final index = <String, Map<String, Set<String>>>{};

  // 获取应用目录路径缓存，避免循环中多次获取
  final appDir = await getApplicationDocumentsDirectory();
  final appPath = path.normalize(appDir.path);

  for (final quote in quotes) {
    final quoteId = quote.id;
    if (quoteId == null || quoteId.isEmpty) {
      continue;
    }

    final mediaPaths = await _extractMediaPathsFromQuote(
      quote,
      cachedAppPath: appPath,
    );

    for (final mediaPath in mediaPaths) {
      final variantPath = path.normalize(mediaPath);
      final key = _canonicalComparisonKey(variantPath);

      final variants = index.putIfAbsent(key, () => <String, Set<String>>{});
      final quoteSet = variants.putIfAbsent(variantPath, () => <String>{});
      quoteSet.add(quoteId);
    }
  }

  return index;
}

/// 流式收集引用索引，避免一次性加载全部笔记
Future<Map<String, Map<String, Set<String>>>>
    _collectQuoteReferenceIndexStreamed() async {
  final databaseService = DatabaseService();
  final index = <String, Map<String, Set<String>>>{};
  const int pageSize = 200;
  var offset = 0;

  // 获取应用目录路径缓存，避免循环中多次获取
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
      final quoteId = quote.id;
      if (quoteId == null || quoteId.isEmpty) {
        continue;
      }

      final mediaPaths = await _extractMediaPathsFromQuote(
        quote,
        cachedAppPath: appPath,
      );

      for (final mediaPath in mediaPaths) {
        final variantPath = path.normalize(mediaPath);
        final key = _canonicalComparisonKey(variantPath);

        final variants =
            index.putIfAbsent(key, () => <String, Set<String>>{});
        final quoteSet = variants.putIfAbsent(variantPath, () => <String>{});
        quoteSet.add(quoteId);
      }
    }

    offset += quotes.length;
    if (quotes.length < pageSize) break;
  }

  return index;
}

Future<int> _healMissingReferences(
  Map<String, Map<String, Set<String>>> missingIndex,
) async {
  int healed = 0;

  try {
    final db = await MediaReferenceService.database;
    final batch = db.batch();

    // 获取应用目录路径缓存，避免循环中多次获取
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = path.normalize(appDir.path);

    int batchCount = 0;

    for (final variants in missingIndex.values) {
      for (final entry in variants.entries) {
        final filePath = entry.key;

        // 使用缓存的 appPath 进行标准化
        final normalizedPath = await _normalizeFilePath(
          filePath,
          cachedAppPath: appPath,
        );

        for (final quoteId in entry.value) {
          batch.insert(
            MediaReferenceService._tableName,
            {
              'id': const Uuid().v4(),
              'file_path': normalizedPath,
              'quote_id': quoteId,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore, // 忽略重复引用
          );
          batchCount++;
        }
      }
    }

    if (batchCount > 0) {
      await batch.commit(noResult: true);
      healed = batchCount;
      logDebug('批量修复完成，共处理 $healed 条引用');
    }
  } catch (e) {
    logDebug('批量修复媒体引用失败: $e');
  }

  return healed;
}

String _canonicalComparisonKey(String value) {
  if (value.isEmpty) {
    return value;
  }

  var key = value.trim();
  key = key.replaceAll('\\', '/');

  while (key.contains('//')) {
    key = key.replaceAll('//', '/');
  }

  if (key.startsWith('./')) {
    key = key.substring(2);
  }

  return key;
}

/// 从笔记内容中提取媒体文件路径
Future<List<String>> _extractMediaPathsFromQuote(
  Quote quote, {
  String? cachedAppPath,
}) async {
  final mediaPaths = <String>[];

  try {
    // 如果有富文本内容，从Delta中提取
    if (quote.deltaContent != null && quote.deltaContent!.isNotEmpty) {
      final deltaJson = jsonDecode(quote.deltaContent!);
      if (deltaJson is List) {
        for (final op in deltaJson) {
          if (op is Map && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is Map) {
              // 检查图片
              if (insert.containsKey('image')) {
                final imagePath = insert['image'] as String?;
                if (imagePath != null) {
                  final normalizedPath = await _normalizeFilePath(
                    imagePath,
                    cachedAppPath: cachedAppPath,
                  );
                  mediaPaths.add(normalizedPath);
                }
              }

              // 检查视频
              if (insert.containsKey('video')) {
                final videoPath = insert['video'] as String?;
                if (videoPath != null) {
                  final normalizedPath = await _normalizeFilePath(
                    videoPath,
                    cachedAppPath: cachedAppPath,
                  );
                  mediaPaths.add(normalizedPath);
                }
              }

              // 检查自定义嵌入（如音频）
              if (insert.containsKey('custom')) {
                final custom = insert['custom'];
                if (custom is Map && custom.containsKey('audio')) {
                  final audioPath = custom['audio'] as String?;
                  if (audioPath != null) {
                    final normalizedPath = await _normalizeFilePath(
                      audioPath,
                      cachedAppPath: cachedAppPath,
                    );
                    mediaPaths.add(normalizedPath);
                  }
                }
              }
            }
          }
        }
      }
    }
  } catch (e) {
    logDebug('从笔记内容提取媒体文件路径失败: $e');
  }

  return mediaPaths.toSet().toList(); // 去重
}

/// 同步笔记的媒体文件引用
Future<bool> _syncQuoteMediaReferences(
  Quote quote, {
  String? cachedAppPath,
}) async {
  try {
    final quoteId = quote.id;
    if (quoteId == null) {
      logDebug('笔记ID为空，跳过媒体引用同步');
      return false;
    }

    // 获取应用目录路径缓存，避免循环中多次获取
    final appPath = cachedAppPath ??
        path.normalize((await getApplicationDocumentsDirectory()).path);

    // 先移除该笔记的所有现有引用
    await MediaReferenceService.removeAllReferencesForQuote(quoteId);

    // 从笔记内容中提取媒体文件路径
    final mediaPaths = await _extractMediaPathsFromQuote(
      quote,
      cachedAppPath: appPath,
    );

    // 添加新的引用
    for (final mediaPath in mediaPaths) {
      await MediaReferenceService.addReference(mediaPath, quoteId, cachedAppPath: appPath);
    }

    logDebug('同步笔记媒体文件引用完成: $quoteId, 共 ${mediaPaths.length} 个文件');
    return true;
  } catch (e) {
    logDebug('同步笔记媒体文件引用失败: $e');
    return false;
  }
}

/// 同步笔记的媒体文件引用（事务内版本）
Future<bool> _syncQuoteMediaReferencesWithTransaction(
  DatabaseExecutor txn,
  Quote quote,
) async {
  try {
    final quoteId = quote.id;
    if (quoteId == null) {
      logDebug('笔记ID为空，跳过媒体引用同步');
      return false;
    }

    // 获取应用目录路径缓存，避免循环中多次获取
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = path.normalize(appDir.path);

    // 先移除该笔记的所有现有引用
    await txn.delete(
      MediaReferenceService._tableName,
      where: 'quote_id = ?',
      whereArgs: [quoteId],
    );

    // 从笔记内容中提取媒体文件路径
    final mediaPaths = await _extractMediaPathsFromQuote(
      quote,
      cachedAppPath: appPath,
    );

    // 添加新的引用
    for (final mediaPath in mediaPaths) {
      final normalizedPath = await _normalizeFilePath(
        mediaPath,
        cachedAppPath: appPath,
      );
      await txn.insert(
        MediaReferenceService._tableName,
        {
          'id': const Uuid().v4(),
          'file_path': normalizedPath,
          'quote_id': quoteId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    logDebug('同步笔记媒体文件引用完成: $quoteId, 共 ${mediaPaths.length} 个文件');
    return true;
  } catch (e) {
    logDebug('同步笔记媒体文件引用失败: $e');
    return false;
  }
}

/// 获取所有媒体文件路径
Future<List<String>> _getAllMediaFiles() async {
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

/// 标准化文件路径（转换为相对路径）
Future<String> _normalizeFilePath(
  String filePath, {
  String? cachedAppPath,
}) async {
  try {
    if (filePath.isEmpty) {
      return filePath;
    }

    var sanitized = filePath.trim();

    if (sanitized.startsWith('file://')) {
      final uri = Uri.tryParse(sanitized);
      if (uri != null && uri.scheme == 'file') {
        sanitized = uri.toFilePath();
      }
    }

    sanitized = path.normalize(sanitized);

    final appPath = cachedAppPath ??
        path.normalize((await getApplicationDocumentsDirectory()).path);

    if (sanitized.startsWith(appPath)) {
      return path.normalize(path.relative(sanitized, from: appPath));
    }

    return sanitized;
  } catch (_) {
    return filePath;
  }
}

/// 获取媒体引用统计信息
Future<Map<String, dynamic>> _getMediaReferenceStats() async {
  try {
    final db = await MediaReferenceService.database;

    // 总引用数
    final totalRefsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${MediaReferenceService._tableName}',
    );
    final totalRefs = totalRefsResult.first['count'] as int;

    // 被引用的文件数
    final referencedFilesResult = await db.rawQuery(
      'SELECT COUNT(DISTINCT file_path) as count FROM ${MediaReferenceService._tableName}',
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
Future<int> _migrateExistingQuotes() async {
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
        final success = await _syncQuoteMediaReferences(
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

class ReferenceSnapshot {
  final Map<String, Map<String, Set<String>>> storedIndex;
  final Map<String, Map<String, Set<String>>> quoteIndex;

  const ReferenceSnapshot({
    required this.storedIndex,
    required this.quoteIndex,
  });
}
