import 'package:thoughtecho/services/backup_service.dart';

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
