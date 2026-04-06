part of '../database_service.dart';

/// Mixin providing recycle-bin operations for DatabaseService.
mixin _DatabaseTrashMixin on _DatabaseServiceBase {
  // Web平台墓碑记录（内存缓存 + SharedPreferences持久化）
  static Map<String, String>? _webTombstones;
  static const String _webTombstonesKey = 'web_quote_tombstones';

  /// 初始化Web平台墓碑记录
  Future<void> _initWebTombstones() async {
    if (_webTombstones != null) return;
    if (!kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_webTombstonesKey);
      if (json != null && json.isNotEmpty) {
        final decoded = jsonDecode(json);
        final normalized = <String, String>{};
        var needResave = false;
        final fallbackDeletedAt = DateTime.now().toUtc().toIso8601String();

        if (decoded is List) {
          for (final item in decoded) {
            if (item is String) {
              if (item.isNotEmpty) {
                normalized[item] = fallbackDeletedAt;
                needResave = true;
              }
              continue;
            }
            if (item is Map) {
              final quoteId = item['quote_id']?.toString();
              if (quoteId == null || quoteId.isEmpty) {
                continue;
              }
              final rawDeletedAt = item['deleted_at']?.toString();
              final parsedDeletedAt = rawDeletedAt == null
                  ? null
                  : DateTime.tryParse(rawDeletedAt)?.toUtc().toIso8601String();
              normalized[quoteId] = parsedDeletedAt ?? fallbackDeletedAt;
              if (parsedDeletedAt == null) {
                needResave = true;
              }
            }
          }
        } else {
          needResave = true;
        }

        _webTombstones = normalized;
        if (needResave && normalized.isNotEmpty) {
          await _saveWebTombstones();
        }
      } else {
        _webTombstones = <String, String>{};
      }
    } catch (e, stack) {
      UnifiedLogService.instance
          .error('初始化Web墓碑记录失败', error: e, stackTrace: stack);
      _webTombstones = <String, String>{};
    }
  }

  /// 保存Web平台墓碑记录到SharedPreferences
  Future<void> _saveWebTombstones() async {
    if (!kIsWeb || _webTombstones == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(
        _webTombstones!.entries
            .map(
              (entry) => {
                'quote_id': entry.key,
                'deleted_at': entry.value,
              },
            )
            .toList(),
      );
      await prefs.setString(_webTombstonesKey, json);
    } catch (e, stack) {
      UnifiedLogService.instance
          .error('保存Web墓碑记录失败', error: e, stackTrace: stack);
    }
  }

  @override
  Future<List<Quote>> getDeletedQuotes({
    int offset = 0,
    int limit = 20,
    String orderBy = 'deleted_at DESC',
  }) async {
    if (kIsWeb) {
      final items = _memoryStore
          .where((quote) => quote.isDeleted)
          .toList(growable: false);
      items.sort((a, b) {
        final aDeleted = DateTime.tryParse(a.deletedAt ?? '') ?? DateTime(0);
        final bDeleted = DateTime.tryParse(b.deletedAt ?? '') ?? DateTime(0);
        return bDeleted.compareTo(aDeleted);
      });
      final start = offset.clamp(0, items.length);
      final end = (offset + limit).clamp(0, items.length);
      return items.sublist(start, end);
    }

    final db = await safeDatabase;
    final sanitizedOrderBy = sanitizeOrderBy(orderBy, prefix: 'q');
    final maps = await db.rawQuery(
      '''
      SELECT q.*, GROUP_CONCAT(qt.tag_id) as tag_ids
      FROM quotes q
      LEFT JOIN quote_tags qt ON q.id = qt.quote_id
      WHERE q.is_deleted = 1
      GROUP BY q.id
      ORDER BY $sanitizedOrderBy
      LIMIT ? OFFSET ?
      ''',
      [limit, offset],
    );
    return maps.map((map) => Quote.fromJson(map)).toList();
  }

  @override
  Future<int> getDeletedQuotesCount() async {
    if (kIsWeb) {
      return _memoryStore.where((quote) => quote.isDeleted).length;
    }

    final db = await safeDatabase;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM quotes WHERE is_deleted = 1',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  @override
  Future<List<Map<String, dynamic>>> getTombstonesForBackup() async {
    if (kIsWeb) {
      await _initWebTombstones();
      return _webTombstones!.entries
          .map(
            (entry) => {
              'quote_id': entry.key,
              'deleted_at': entry.value,
              'device_id': null,
            },
          )
          .toList();
    }
    final db = await safeDatabase;
    return db.query('quote_tombstones');
  }

  @override
  Future<void> restoreQuote(String id) async {
    if (id.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      await _initWebTombstones();

      // 修复：检查Web墓碑记录
      if (_webTombstones!.containsKey(id)) {
        throw StateError('笔记已被永久删除，无法恢复');
      }

      final index = _memoryStore.indexWhere((quote) => quote.id == id);
      if (index == -1 || !_memoryStore[index].isDeleted) {
        return;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      _memoryStore[index] = _memoryStore[index].copyWith(
        isDeleted: false,
        deletedAt: null,
        lastModified: now,
      );
      clearAllCacheForParts();
      refreshQuotesStreamForParts();
      notifyListeners();
      return;
    }

    await _executeWithLock('restoreQuote_$id', () async {
      final db = await safeDatabase;

      // 修复：检查笔记是否已被永久删除（tombstone存在）
      final tombstone = await db.query(
        'quote_tombstones',
        where: 'quote_id = ?',
        whereArgs: [id],
      );
      if (tombstone.isNotEmpty) {
        throw StateError('笔记已被永久删除，无法恢复');
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final updatedRows = await db.rawUpdate(
        'UPDATE quotes '
        'SET is_deleted = 0, deleted_at = NULL, last_modified = ? '
        'WHERE id = ? AND is_deleted = 1',
        [now, id],
      );

      // 修复：如果没有行被更新，说明笔记不在回收站或已被删除
      if (updatedRows == 0) {
        // 再次检查tombstone（可能在检查和更新之间被删除）
        final tombstone2 = await db.query(
          'quote_tombstones',
          where: 'quote_id = ?',
          whereArgs: [id],
        );
        if (tombstone2.isNotEmpty) {
          throw StateError('笔记已被永久删除，无法恢复');
        }
        logDebug('恢复笔记失败：笔记 $id 不在回收站或不存在');
        return;
      }

      clearAllCacheForParts();
      refreshQuotesStreamForParts();
      notifyListeners();
    });
  }

  @override
  Future<void> permanentlyDeleteQuote(String id) async {
    if (id.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }
    await _hardDeleteQuotes([id]);
  }

  @override
  Future<void> emptyTrash() async {
    if (kIsWeb) {
      final deletedIds = _memoryStore
          .where((quote) => quote.isDeleted && quote.id != null)
          .map((quote) => quote.id!)
          .toList(growable: false);
      if (deletedIds.isEmpty) {
        return;
      }
      await _hardDeleteQuotes(deletedIds);
      return;
    }

    final db = await safeDatabase;
    final rows = await db.rawQuery(
      'SELECT id FROM quotes WHERE is_deleted = 1',
    );
    if (rows.isEmpty) {
      return;
    }
    final ids = rows
        .map((row) => row['id'])
        .whereType<String>()
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    await _hardDeleteQuotes(ids);
  }

  @override
  Future<int> autoCleanupExpiredTrash({required int retentionDays}) async {
    if (!AppSettings.allowedTrashRetentionDays.contains(retentionDays)) {
      throw ArgumentError('无效的回收站保留天数: $retentionDays');
    }

    if (kIsWeb) {
      final now = DateTime.now().toUtc();
      final expiredIds = _memoryStore
          .where((quote) {
            if (!quote.isDeleted ||
                quote.id == null ||
                quote.deletedAt == null) {
              return false;
            }
            final deletedAt = DateTime.tryParse(quote.deletedAt!);
            if (deletedAt == null) {
              return false;
            }
            return now.difference(deletedAt.toUtc()).inDays >= retentionDays;
          })
          .map((quote) => quote.id!)
          .toList(growable: false);
      if (expiredIds.isEmpty) {
        return 0;
      }
      await _hardDeleteQuotes(expiredIds);
      return expiredIds.length;
    }

    final db = await safeDatabase;
    final rows = await db.rawQuery(
      "SELECT id FROM quotes "
      "WHERE is_deleted = 1 "
      "AND deleted_at IS NOT NULL "
      "AND julianday(deleted_at) <= julianday('now', '-$retentionDays days')",
    );

    if (rows.isEmpty) {
      return 0;
    }

    final ids = rows
        .map((row) => row['id'])
        .whereType<String>()
        .toList(growable: false);
    if (ids.isEmpty) {
      return 0;
    }

    await _hardDeleteQuotes(ids);
    return ids.length;
  }

  Future<void> _hardDeleteQuotes(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }

    final uniqueIds = ids.toSet().where((id) => id.isNotEmpty).toList();
    if (uniqueIds.isEmpty) {
      return;
    }

    if (kIsWeb) {
      await _initWebTombstones();
      final targetDeletedIds = _memoryStore
          .where(
            (quote) =>
                quote.id != null &&
                uniqueIds.contains(quote.id) &&
                quote.isDeleted,
          )
          .map((quote) => quote.id!)
          .toSet()
          .toList(growable: false);
      if (targetDeletedIds.isEmpty) {
        return;
      }

      // 修复：添加Web墓碑记录
      final deletedAt = DateTime.now().toUtc().toIso8601String();
      for (final id in targetDeletedIds) {
        _webTombstones!.putIfAbsent(id, () => deletedAt);
      }
      
      // 修复：先从内存中移除，避免与 restoreQuote 的竞态条件
      _memoryStore.removeWhere(
        (quote) => targetDeletedIds.contains(quote.id) && quote.isDeleted,
      );
      
      // 然后持久化墓碑
      await _saveWebTombstones();
      
      for (final id in targetDeletedIds) {
        QuoteContent.removeCacheForQuote(id);
      }
      clearAllCacheForParts();
      refreshQuotesStreamForParts();
      notifyListeners();
      return;
    }

    final mediaCandidates = <String>{};
    final db = await safeDatabase;
    final placeholders = List.filled(uniqueIds.length, '?').join(',');

    final quoteRows = await db.rawQuery(
      'SELECT * FROM quotes WHERE is_deleted = 1 AND id IN ($placeholders)',
      uniqueIds,
    );
    final targetDeletedIds = quoteRows
        .map((row) => row['id'])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (targetDeletedIds.isEmpty) {
      return;
    }
    for (final row in quoteRows) {
      try {
        final quote = Quote.fromJson(row);
        final extracted =
            await MediaReferenceService.extractMediaPathsFromQuote(
          quote,
        );
        mediaCandidates.addAll(extracted);
      } catch (e, stack) {
        UnifiedLogService.instance
            .error('提取已删除笔记媒体路径失败', error: e, stackTrace: stack);
      }
    }

    final referencedByQuote =
        await MediaReferenceService.getReferencedFilesBatch(
      targetDeletedIds,
    );
    for (final files in referencedByQuote.values) {
      mediaCandidates.addAll(files);
    }

    await _executeWithLock('hardDeleteQuotes', () async {
      final db = await safeDatabase;
      final now = DateTime.now().toUtc().toIso8601String();
      var deletedIdsInTxn = <String>[];

      await db.transaction((txn) async {
        final currentDeletedRows = await txn.rawQuery(
          'SELECT id FROM quotes WHERE is_deleted = 1 AND id IN ($placeholders)',
          uniqueIds,
        );
        deletedIdsInTxn = currentDeletedRows
            .map((row) => row['id'])
            .whereType<String>()
            .toSet()
            .toList(growable: false);
        if (deletedIdsInTxn.isEmpty) {
          return;
        }

        final tombstoneBatch = txn.batch();
        for (final id in deletedIdsInTxn) {
          tombstoneBatch.insert(
            'quote_tombstones',
            {
              'quote_id': id,
              'deleted_at': now,
              'device_id': null,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await tombstoneBatch.commit(noResult: true);

        final deletePlaceholders =
            List.filled(deletedIdsInTxn.length, '?').join(',');
        await txn.rawDelete(
          'DELETE FROM quotes WHERE is_deleted = 1 AND id IN ($deletePlaceholders)',
          deletedIdsInTxn,
        );
      });

      if (deletedIdsInTxn.isEmpty) {
        return;
      }

      for (final id in deletedIdsInTxn) {
        QuoteContent.removeCacheForQuote(id);
      }

      // Convert relative media paths to absolute paths before cleanup
      final appDir = await getApplicationDocumentsDirectory();
      final appPath = normalize(appDir.path);

      for (final mediaPath in mediaCandidates) {
        try {
          String absolutePath = mediaPath;
          if (!isAbsolute(absolutePath)) {
            absolutePath = join(appPath, mediaPath);
          }
          await MediaReferenceService.quickCheckAndDeleteIfOrphan(
            absolutePath,
            cachedAppPath: appPath,
          );
        } catch (e, stack) {
          UnifiedLogService.instance
              .error('清理孤儿媒体文件失败: $mediaPath', error: e, stackTrace: stack);
        }
      }

      clearAllCacheForParts();
      refreshQuotesStreamForParts();
      notifyListeners();
    });
  }
}
