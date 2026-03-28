part of '../database_service.dart';

/// Mixin providing recycle-bin operations for DatabaseService.
mixin _DatabaseTrashMixin on _DatabaseServiceBase {
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
      return const [];
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
      final now = DateTime.now().toUtc().toIso8601String();
      await db.rawUpdate(
        'UPDATE quotes '
        'SET is_deleted = 0, deleted_at = NULL, last_modified = ? '
        'WHERE id = ? AND is_deleted = 1',
        [now, id],
      );

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
      _memoryStore.removeWhere((quote) => uniqueIds.contains(quote.id));
      for (final id in uniqueIds) {
        QuoteContent.removeCacheForQuote(id);
      }
      clearAllCacheForParts();
      refreshQuotesStreamForParts();
      notifyListeners();
      return;
    }

    final mediaCandidates = <String>{};
    for (final id in uniqueIds) {
      final quote = await getQuoteById(id, includeDeleted: true);
      if (quote != null) {
        final extracted =
            await MediaReferenceService.extractMediaPathsFromQuote(
          quote,
        );
        mediaCandidates.addAll(extracted);
      }
      final referenced = await MediaReferenceService.getReferencedFiles(id);
      mediaCandidates.addAll(referenced);
    }

    await _executeWithLock('hardDeleteQuotes', () async {
      final db = await safeDatabase;
      final now = DateTime.now().toUtc().toIso8601String();

      await db.transaction((txn) async {
        final tombstoneBatch = txn.batch();
        for (final id in uniqueIds) {
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

        final placeholders = List.filled(uniqueIds.length, '?').join(',');
        await txn.rawDelete(
          'DELETE FROM quotes WHERE id IN ($placeholders)',
          uniqueIds,
        );
      });

      for (final id in uniqueIds) {
        QuoteContent.removeCacheForQuote(id);
      }

      for (final mediaPath in mediaCandidates) {
        await MediaReferenceService.quickCheckAndDeleteIfOrphan(mediaPath);
      }

      clearAllCacheForParts();
      refreshQuotesStreamForParts();
      notifyListeners();
    });
  }
}
