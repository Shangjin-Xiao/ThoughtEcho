import 'package:sqflite/sqflite.dart';
import '../utils/app_logger.dart';
import 'delta_log_service.dart';

class CompactionSummary {
  final int compactedUpToSeq;
  final int deletedCount;
  final String timestamp;

  const CompactionSummary({
    required this.compactedUpToSeq,
    required this.deletedCount,
    required this.timestamp,
  });

  @override
  String toString() =>
      'CompactionSummary(upToSeq: $compactedUpToSeq, deletedCount: $deletedCount, timestamp: $timestamp)';
}

/// Service managing compaction and sequence continuity checks for incremental sync delta logs.
class DeltaCompactionService {
  /// Default threshold of delta records before triggering automatic compaction.
  static const int defaultMaxDeltaThreshold = 500;

  /// Checks if delta log exceeds the threshold and needs compaction.
  static Future<bool> shouldCompact(
    DatabaseExecutor executor, {
    int maxDeltaThreshold = defaultMaxDeltaThreshold,
  }) async {
    final count = await DeltaLogService.getDeltaCount(executor);
    return count >= maxDeltaThreshold;
  }

  /// Compacts delta log up to [maxSeq] after creating/updating baseline snapshot.
  static Future<CompactionSummary> compactDeltas(
    Database db, {
    int? maxSeq,
  }) async {
    final targetSeq = maxSeq ?? await DeltaLogService.getMaxSequence(db);
    if (targetSeq <= 0) {
      return CompactionSummary(
        compactedUpToSeq: 0,
        deletedCount: 0,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
    }

    final deletedCount = await DeltaLogService.deleteDeltasUpToSequence(
      db,
      targetSeq,
    );
    final timestamp = DateTime.now().toUtc().toIso8601String();

    logInfo(
      'Compacted delta log up to seq $targetSeq (deleted $deletedCount rows)',
      source: 'DeltaCompactionService',
    );

    return CompactionSummary(
      compactedUpToSeq: targetSeq,
      deletedCount: deletedCount,
      timestamp: timestamp,
    );
  }

  /// Detects whether a sequence gap exists for a requested [fromSeq].
  /// Returns `true` if requested sequence is older than available minimum sequence,
  /// indicating historical logs were compacted or missing and full snapshot fallback is required.
  static Future<bool> hasSequenceGap(
    DatabaseExecutor executor,
    int requestedFromSeq,
  ) async {
    if (requestedFromSeq <= 0) return false;

    final minSeq = await DeltaLogService.getMinSequence(executor);
    final totalCount = await DeltaLogService.getDeltaCount(executor);

    if (totalCount == 0) {
      // Delta logs were completely cleared/compacted
      return true;
    }

    // If requested sequence is strictly lower than available min sequence minus 1, gap exists
    if (requestedFromSeq < minSeq - 1) {
      logWarning(
        'Sequence gap detected: requested $requestedFromSeq, but minimum available sequence is $minSeq',
        source: 'DeltaCompactionService',
      );
      return true;
    }

    return false;
  }
}
