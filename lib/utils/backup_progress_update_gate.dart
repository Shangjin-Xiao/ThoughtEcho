import 'package:thoughtecho/services/backup_service.dart';

/// 备份进度阶段常量。
///
/// 每个阶段对应 [BackupService] 中的进度边界值。
class BackupProgressStages {
  static const String collect = 'collect';
  static const String note = 'note';
  static const String media = 'media';
  static const String zip = 'zip';
  static const String verify = 'verify';
}

String resolveBackupStageKey(int progressPercent) {
  final normalizedPercent = progressPercent.clamp(0, 100);
  if (normalizedPercent < BackupService.stageCollectEnd) {
    return BackupProgressStages.collect;
  }
  if (normalizedPercent < BackupService.stageNoteEnd) {
    return BackupProgressStages.note;
  }
  if (normalizedPercent < BackupService.stageMediaEnd) {
    return BackupProgressStages.media;
  }
  if (normalizedPercent < BackupService.stageZipEnd) {
    return BackupProgressStages.zip;
  }
  return BackupProgressStages.verify;
}

/// 备份进度更新节流门控。
///
/// **注意**：此类是有状态的工具类，保留在 `lib/utils/` 是因为它是专门用于
/// 备份进度回调的节流辅助，不包含业务逻辑，只负责决定是否应该发送 UI 更新。
/// 每次备份操作应创建新实例或调用 [reset] 方法。
class BackupProgressUpdateGate {
  BackupProgressUpdateGate({
    this.minUpdateInterval = const Duration(milliseconds: 80),
  });

  final Duration minUpdateInterval;

  DateTime? _lastUpdateAt;
  int _lastProgressPercent = -1;
  String _lastStageKey = '';

  bool shouldUpdate({
    required int progressPercent,
    required String stageKey,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final normalizedPercent = _normalizePercent(progressPercent);
    final isFirstUpdate = _lastUpdateAt == null;
    final isStageChanged = stageKey != _lastStageKey;
    final isProgressChanged = normalizedPercent != _lastProgressPercent;
    final isCompleted = normalizedPercent >= 100;
    final isIntervalPassed = _lastUpdateAt == null ||
        currentTime.difference(_lastUpdateAt!) >= minUpdateInterval;

    final shouldEmit = isFirstUpdate ||
        isStageChanged ||
        isCompleted ||
        (isProgressChanged && isIntervalPassed);

    if (shouldEmit) {
      _lastUpdateAt = currentTime;
      _lastProgressPercent = normalizedPercent;
      _lastStageKey = stageKey;
    }

    return shouldEmit;
  }

  void reset() {
    _lastUpdateAt = null;
    _lastProgressPercent = -1;
    _lastStageKey = '';
  }

  int _normalizePercent(int value) {
    if (value < 0) return 0;
    if (value > 100) return 100;
    return value;
  }
}
