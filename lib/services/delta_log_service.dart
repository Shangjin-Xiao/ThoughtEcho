import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../utils/app_logger.dart';
import 'database_schema_manager.dart';

/// Service responsible for append-only delta logging into `sync_delta_log`.
class DeltaLogService {
  static const String tableName = 'sync_delta_log';

  /// Records a mutation event into `sync_delta_log`.
  /// Must be called within an active SQLite transaction/executor.
  static Future<int> recordChange(
    DatabaseExecutor executor, {
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
    String? timestamp,
  }) async {
    final utcTime = timestamp ?? DateTime.now().toUtc().toIso8601String();
    final jsonPayload = jsonEncode(payload);

    int seq;
    try {
      seq = await executor.insert(tableName, {
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'payload': jsonPayload,
        'timestamp': utcTime,
      });
    } catch (e) {
      if (e.toString().contains('no such table: sync_delta_log')) {
        await DatabaseSchemaDefinitions().ensureSyncDeltaLogTable(executor);
        seq = await executor.insert(tableName, {
          'entity_type': entityType,
          'entity_id': entityId,
          'action': action,
          'payload': jsonPayload,
          'timestamp': utcTime,
        });
      } else {
        rethrow;
      }
    }

    logDebug(
      'Recorded delta log entry #$seq [$action $entityType:$entityId]',
      source: 'DeltaLogService',
    );
    return seq;
  }

  /// Retrieves delta log entries after [fromSeq] in ascending sequence order.
  static Future<List<Map<String, dynamic>>> getDeltasAfterSequence(
    DatabaseExecutor executor,
    int fromSeq, {
    int limit = 1000,
  }) async {
    final List<Map<String, Object?>> rows;
    try {
      rows = await executor.query(
        tableName,
        where: 'seq > ?',
        whereArgs: [fromSeq],
        orderBy: 'seq ASC',
        limit: limit,
      );
    } catch (e) {
      if (e.toString().contains('no such table: sync_delta_log')) {
        return [];
      }
      rethrow;
    }

    return rows.map((row) {
      Map<String, dynamic> parsedPayload = {};
      try {
        final rawPayload = row['payload'] as String?;
        if (rawPayload != null && rawPayload.isNotEmpty) {
          parsedPayload = Map<String, dynamic>.from(jsonDecode(rawPayload));
        }
      } catch (e) {
        logError(
          'Failed to parse delta log payload for seq ${row['seq']}: $e',
          source: 'DeltaLogService',
        );
      }

      return <String, dynamic>{
        'seq': row['seq'] as int,
        'entity_type': row['entity_type'] as String,
        'entity_id': row['entity_id'] as String,
        'action': row['action'] as String,
        'payload': parsedPayload,
        'timestamp': row['timestamp'] as String,
      };
    }).toList();
  }

  /// Gets the highest sequence ID present in `sync_delta_log`.
  static Future<int> getMaxSequence(DatabaseExecutor executor) async {
    try {
      final result = await executor.rawQuery(
        'SELECT MAX(seq) as max_seq FROM $tableName',
      );
      if (result.isNotEmpty && result.first['max_seq'] != null) {
        return result.first['max_seq'] as int;
      }
    } catch (e) {
      if (e.toString().contains('no such table: sync_delta_log')) {
        return 0;
      }
      rethrow;
    }
    return 0;
  }

  /// Gets the lowest sequence ID present in `sync_delta_log`.
  static Future<int> getMinSequence(DatabaseExecutor executor) async {
    try {
      final result = await executor.rawQuery(
        'SELECT MIN(seq) as min_seq FROM $tableName',
      );
      if (result.isNotEmpty && result.first['min_seq'] != null) {
        return result.first['min_seq'] as int;
      }
    } catch (e) {
      if (e.toString().contains('no such table: sync_delta_log')) {
        return 0;
      }
      rethrow;
    }
    return 0;
  }

  /// Gets total row count in `sync_delta_log`.
  static Future<int> getDeltaCount(DatabaseExecutor executor) async {
    try {
      final result = await executor.rawQuery(
        'SELECT COUNT(*) as cnt FROM $tableName',
      );
      if (result.isNotEmpty && result.first['cnt'] != null) {
        return result.first['cnt'] as int;
      }
    } catch (e) {
      if (e.toString().contains('no such table: sync_delta_log')) {
        return 0;
      }
      rethrow;
    }
    return 0;
  }

  /// Purges delta entries with `seq <= upToSeq`.
  static Future<int> deleteDeltasUpToSequence(
    DatabaseExecutor executor,
    int upToSeq,
  ) async {
    try {
      return await executor.delete(
        tableName,
        where: 'seq <= ?',
        whereArgs: [upToSeq],
      );
    } catch (e) {
      if (e.toString().contains('no such table: sync_delta_log')) {
        return 0;
      }
      rethrow;
    }
  }

  /// Purges all delta log records.
  static Future<int> clearAllDeltas(DatabaseExecutor executor) async {
    try {
      return await executor.delete(tableName);
    } catch (e) {
      if (e.toString().contains('no such table: sync_delta_log')) {
        return 0;
      }
      rethrow;
    }
  }
}
