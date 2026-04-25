part of '../media_reference_service.dart';

/// Extension for quote media synchronization
extension MediaQuoteSync on MediaReferenceService {
  /// 从笔记内容中提取媒体文件路径
  static Future<List<String>> extractMediaPathsFromQuote(
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
  static Future<bool> syncQuoteMediaReferences(
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
      await MediaReferenceOperations.removeAllReferencesForQuote(quoteId);

      // 从笔记内容中提取媒体文件路径
      final mediaPaths = await extractMediaPathsFromQuote(
        quote,
        cachedAppPath: appPath,
      );

      // 添加新的引用
      for (final mediaPath in mediaPaths) {
        await MediaReferenceOperations.addReference(
          mediaPath,
          quoteId,
          cachedAppPath: appPath,
        );
      }

      logDebug('同步笔记媒体文件引用完成: $quoteId, 共 ${mediaPaths.length} 个文件');
      return true;
    } catch (e) {
      logDebug('同步笔记媒体文件引用失败: $e');
      return false;
    }
  }

  /// 同步笔记的媒体文件引用（事务内版本）
  static Future<bool> syncQuoteMediaReferencesWithTransaction(
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
        _tableName,
        where: 'quote_id = ?',
        whereArgs: [quoteId],
      );

      // 从笔记内容中提取媒体文件路径
      final mediaPaths = await extractMediaPathsFromQuote(
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
          _tableName,
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
}
