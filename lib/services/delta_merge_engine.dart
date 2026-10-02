import 'package:sqflite/sqflite.dart';
import '../utils/app_logger.dart';
import '../utils/lww_utils.dart';
import 'delta_log_service.dart';

class DeltaMergeResult {
  final int appliedCount;
  final int skippedCount;
  final int errorCount;
  final int maxAppliedSeq;

  const DeltaMergeResult({
    required this.appliedCount,
    required this.skippedCount,
    required this.errorCount,
    required this.maxAppliedSeq,
  });

  @override
  String toString() =>
      'DeltaMergeResult(applied: $appliedCount, skipped: $skippedCount, errors: $errorCount, maxSeq: $maxAppliedSeq)';
}

/// Engine responsible for replaying incremental delta batches using LWW semantics.
class DeltaMergeEngine {
  /// Applies a list of delta items to the database within a transaction.
  /// If [isFromSync] is true, avoids re-logging these applied changes into `sync_delta_log`.
  static Future<DeltaMergeResult> applyDeltaBatch(
    Database db,
    List<Map<String, dynamic>> deltas, {
    bool isFromSync = true,
  }) async {
    if (deltas.isEmpty) {
      return const DeltaMergeResult(
        appliedCount: 0,
        skippedCount: 0,
        errorCount: 0,
        maxAppliedSeq: 0,
      );
    }

    int applied = 0;
    int skipped = 0;
    int errors = 0;
    int maxAppliedSeq = 0;

    await db.transaction((txn) async {
      for (final item in deltas) {
        final seq = item['seq'] is int ? item['seq'] as int : 0;
        final entityType = item['entity_type'] as String? ?? '';
        final entityId = item['entity_id'] as String? ?? '';
        final action = item['action'] as String? ?? '';
        final timestamp =
            item['timestamp'] as String? ?? LWWUtils.generateTimestamp();

        Map<String, dynamic> payload = {};
        if (item['payload'] is Map) {
          payload = Map<String, dynamic>.from(item['payload'] as Map);
        }

        try {
          bool isApplied = false;
          switch (entityType) {
            case 'quote':
              isApplied = await _mergeQuoteDelta(
                txn,
                entityId,
                action,
                payload,
                timestamp,
                isFromSync: isFromSync,
              );
              break;
            case 'category':
              isApplied = await _mergeCategoryDelta(
                txn,
                entityId,
                action,
                payload,
                timestamp,
                isFromSync: isFromSync,
              );
              break;
            case 'tombstone':
              isApplied = await _mergeTombstoneDelta(
                txn,
                entityId,
                action,
                payload,
                timestamp,
                isFromSync: isFromSync,
              );
              break;
            case 'media_reference':
              isApplied = await _mergeMediaReferenceDelta(
                txn,
                entityId,
                action,
                payload,
                timestamp,
              );
              break;
            default:
              logWarning(
                'Unknown delta entity_type: $entityType',
                source: 'DeltaMergeEngine',
              );
              skipped++;
              continue;
          }

          if (isApplied) {
            applied++;
            if (seq > maxAppliedSeq) maxAppliedSeq = seq;
          } else {
            skipped++;
          }
        } catch (e, stackTrace) {
          logError(
            'Failed to merge delta seq $seq [$entityType:$entityId]: $e',
            error: e,
            stackTrace: stackTrace,
            source: 'DeltaMergeEngine',
          );
          errors++;
        }
      }
    });

    logInfo(
      'Delta merge completed: applied $applied, skipped $skipped, errors $errors, maxSeq $maxAppliedSeq',
      source: 'DeltaMergeEngine',
    );

    return DeltaMergeResult(
      appliedCount: applied,
      skippedCount: skipped,
      errorCount: errors,
      maxAppliedSeq: maxAppliedSeq,
    );
  }

  static Future<bool> _mergeQuoteDelta(
    Transaction txn,
    String quoteId,
    String action,
    Map<String, dynamic> payload,
    String timestamp, {
    required bool isFromSync,
  }) async {
    if (quoteId.isEmpty) return false;

    final existingRows = await txn.query(
      'quotes',
      where: 'id = ?',
      whereArgs: [quoteId],
      limit: 1,
    );

    final localLastModified = existingRows.isNotEmpty
        ? existingRows.first['last_modified'] as String?
        : null;

    if (action == 'delete') {
      if (existingRows.isEmpty) return false;
      if (LWWUtils.shouldUseRemote(localLastModified, timestamp) ||
          localLastModified == null) {
        await txn.update(
          'quotes',
          {
            'is_deleted': 1,
            'deleted_at': timestamp,
            'last_modified': timestamp,
          },
          where: 'id = ?',
          whereArgs: [quoteId],
        );
        if (!isFromSync) {
          await DeltaLogService.recordChange(
            txn,
            entityType: 'quote',
            entityId: quoteId,
            action: 'delete',
            payload: {'id': quoteId, 'timestamp': timestamp},
            timestamp: timestamp,
          );
        }
        return true;
      }
      return false;
    }

    // Handle insert / update
    final remoteLastModified = payload['last_modified'] as String? ?? timestamp;

    if (existingRows.isNotEmpty) {
      if (!LWWUtils.shouldUseRemote(localLastModified, remoteLastModified)) {
        // Local data is newer or equal, skip remote update
        return false;
      }
    }

    // Extract tag_ids and clean quote fields
    List<String> tagIds = [];
    if (payload.containsKey('tag_ids')) {
      final rawTags = payload['tag_ids'];
      if (rawTags is List) {
        tagIds = rawTags.map((e) => e.toString()).toList();
      } else if (rawTags is String && rawTags.isNotEmpty) {
        tagIds = rawTags
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }

    final quoteData = Map<String, dynamic>.from(payload);
    quoteData.remove('tag_ids');
    quoteData['id'] = quoteId;
    quoteData['content'] ??= '';
    quoteData['date'] ??= timestamp;
    quoteData['last_modified'] = remoteLastModified;

    // Filter to known quote columns only
    final quoteColumns = await _getQuoteColumns(txn);
    quoteData.removeWhere((key, _) => !quoteColumns.contains(key));

    await txn.insert(
      'quotes',
      quoteData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Update tags
    await txn.delete('quote_tags', where: 'quote_id = ?', whereArgs: [quoteId]);
    if (tagIds.isNotEmpty) {
      final batch = txn.batch();
      for (final tagId in tagIds) {
        batch.insert(
          'quote_tags',
          {'quote_id': quoteId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    }

    if (!isFromSync) {
      final logPayload = Map<String, dynamic>.from(quoteData);
      logPayload['tag_ids'] = tagIds;
      await DeltaLogService.recordChange(
        txn,
        entityType: 'quote',
        entityId: quoteId,
        action: existingRows.isEmpty ? 'insert' : 'update',
        payload: logPayload,
        timestamp: remoteLastModified,
      );
    }

    return true;
  }

  static Future<bool> _mergeCategoryDelta(
    Transaction txn,
    String categoryId,
    String action,
    Map<String, dynamic> payload,
    String timestamp, {
    required bool isFromSync,
  }) async {
    if (categoryId.isEmpty) return false;

    if (action == 'delete') {
      await txn.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
      if (!isFromSync) {
        await DeltaLogService.recordChange(
          txn,
          entityType: 'category',
          entityId: categoryId,
          action: 'delete',
          payload: {'id': categoryId, 'timestamp': timestamp},
          timestamp: timestamp,
        );
      }
      return true;
    }

    final existingRows = await txn.query(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );

    final localLastModified = existingRows.isNotEmpty
        ? existingRows.first['last_modified'] as String?
        : null;

    final remoteLastModified = payload['last_modified'] as String? ?? timestamp;

    if (existingRows.isNotEmpty &&
        !LWWUtils.shouldUseRemote(localLastModified, remoteLastModified)) {
      return false;
    }

    final categoryMap = Map<String, dynamic>.from(payload);
    categoryMap['id'] = categoryId;
    categoryMap['name'] ??= 'Uncategorized';
    categoryMap['is_default'] =
        (categoryMap['is_default'] == true || categoryMap['is_default'] == 1)
            ? 1
            : 0;
    categoryMap['last_modified'] = remoteLastModified;

    await txn.insert(
      'categories',
      categoryMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (!isFromSync) {
      await DeltaLogService.recordChange(
        txn,
        entityType: 'category',
        entityId: categoryId,
        action: existingRows.isEmpty ? 'insert' : 'update',
        payload: categoryMap,
        timestamp: remoteLastModified,
      );
    }

    return true;
  }

  static Future<bool> _mergeTombstoneDelta(
    Transaction txn,
    String quoteId,
    String action,
    Map<String, dynamic> payload,
    String timestamp, {
    required bool isFromSync,
  }) async {
    if (quoteId.isEmpty) return false;

    final deletedAt = payload['deleted_at'] as String? ?? timestamp;
    final deviceId = payload['device_id'] as String?;

    await txn.insert(
      'quote_tombstones',
      {
        'quote_id': quoteId,
        'deleted_at': deletedAt,
        'device_id': deviceId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Hard delete quote if present
    await txn.delete('quote_tags', where: 'quote_id = ?', whereArgs: [quoteId]);
    await txn.delete('quotes', where: 'id = ?', whereArgs: [quoteId]);

    if (!isFromSync) {
      await DeltaLogService.recordChange(
        txn,
        entityType: 'tombstone',
        entityId: quoteId,
        action: 'insert',
        payload: {
          'quote_id': quoteId,
          'deleted_at': deletedAt,
          'device_id': deviceId
        },
        timestamp: deletedAt,
      );
    }

    return true;
  }

  static Future<bool> _mergeMediaReferenceDelta(
    Transaction txn,
    String mediaId,
    String action,
    Map<String, dynamic> payload,
    String timestamp,
  ) async {
    if (mediaId.isEmpty) return false;

    final filePath = payload['file_path'] as String?;
    final quoteId = payload['quote_id'] as String?;
    final createdAt = payload['created_at'] as String? ?? timestamp;

    if (filePath == null || quoteId == null) return false;

    if (action == 'delete') {
      await txn
          .delete('media_references', where: 'id = ?', whereArgs: [mediaId]);
      return true;
    }

    await txn.insert(
      'media_references',
      {
        'id': mediaId,
        'file_path': filePath,
        'quote_id': quoteId,
        'created_at': createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return true;
  }

  static Future<Set<String>> _getQuoteColumns(Transaction txn) async {
    final rows =
        await txn.rawQuery('SELECT name FROM pragma_table_info(?)', ['quotes']);
    return rows.map((r) => r['name'] as String).toSet();
  }
}
