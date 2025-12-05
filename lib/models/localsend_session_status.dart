// TODO: Display strings should be internationalized at the UI layer, not in the model
/// 会话状态枚举
enum SessionStatus {
  /// 等待中
  waiting,

  /// 正在发送
  sending,

  /// 正在接收
  receiving,

  /// 已完成
  finished,

  /// 已取消
  cancelled,

  /// 被拒绝
  declined,

  /// 发生错误
  error,
}

extension SessionStatusExtension on SessionStatus {
  String get displayName {
    switch (this) {
      case SessionStatus.waiting:
        return '等待中';
      case SessionStatus.sending:
        return '正在发送';
      case SessionStatus.receiving:
        return '正在接收';
      case SessionStatus.finished:
        return '已完成';
      case SessionStatus.cancelled:
        return '已取消';
      case SessionStatus.declined:
        return '被拒绝';
      case SessionStatus.error:
        return '发生错误';
    }
  }

  bool get isActive {
    return this == SessionStatus.sending || this == SessionStatus.receiving;
  }

  bool get isCompleted {
    return this == SessionStatus.finished ||
        this == SessionStatus.cancelled ||
        this == SessionStatus.declined ||
        this == SessionStatus.error;
  }
}
