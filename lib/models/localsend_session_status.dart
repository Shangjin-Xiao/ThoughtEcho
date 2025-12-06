import '../gen_l10n/app_localizations.dart';

/// 会话状态枚举（UI 文案通过 l10n 获取）
enum SessionStatus {
  waiting,
  sending,
  receiving,
  finished,
  cancelled,
  declined,
  error,
}

extension SessionStatusExtension on SessionStatus {
  /// 获取本地化名称（在 UI 层调用并传入 l10n）
  String localized(AppLocalizations l10n) {
    switch (this) {
      case SessionStatus.waiting:
        return l10n.sessionStatusWaiting;
      case SessionStatus.sending:
        return l10n.sessionStatusSending;
      case SessionStatus.receiving:
        return l10n.sessionStatusReceiving;
      case SessionStatus.finished:
        return l10n.sessionStatusCompleted;
      case SessionStatus.cancelled:
        return l10n.sessionStatusCancelled;
      case SessionStatus.declined:
        return l10n.sessionStatusRejected;
      case SessionStatus.error:
        return l10n.sessionStatusError;
    }
  }

  bool get isActive =>
      this == SessionStatus.sending || this == SessionStatus.receiving;

  bool get isCompleted =>
      this == SessionStatus.finished ||
      this == SessionStatus.cancelled ||
      this == SessionStatus.declined ||
      this == SessionStatus.error;
}
