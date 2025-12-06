import '../gen_l10n/app_localizations.dart';

/// 文件状态枚举（UI 文案通过 l10n 获取）
enum FileStatus {
  queue,
  sending,
  finished,
  failed,
  skipped,
}

extension FileStatusExtension on FileStatus {
  /// 获取本地化名称（在 UI 层调用并传入 l10n）
  String localized(AppLocalizations l10n) {
    switch (this) {
      case FileStatus.queue:
        return l10n.fileStatusQueued;
      case FileStatus.sending:
        return l10n.fileStatusSending;
      case FileStatus.finished:
        return l10n.fileStatusCompleted;
      case FileStatus.failed:
        return l10n.fileStatusFailed;
      case FileStatus.skipped:
        return l10n.fileStatusSkipped;
    }
  }

  bool get isActive => this == FileStatus.sending;

  bool get isCompleted =>
      this == FileStatus.finished ||
      this == FileStatus.failed ||
      this == FileStatus.skipped;
}
