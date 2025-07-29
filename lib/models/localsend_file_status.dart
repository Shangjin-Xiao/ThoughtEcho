/// 文件状态枚举
enum FileStatus {
  /// 队列中
  queue,
  /// 正在发送
  sending,
  /// 已完成
  finished,
  /// 失败
  failed,
  /// 已跳过
  skipped,
}

extension FileStatusExtension on FileStatus {
  String get displayName {
    switch (this) {
      case FileStatus.queue:
        return '队列中';
      case FileStatus.sending:
        return '正在发送';
      case FileStatus.finished:
        return '已完成';
      case FileStatus.failed:
        return '失败';
      case FileStatus.skipped:
        return '已跳过';
    }
  }

  bool get isActive {
    return this == FileStatus.sending;
  }

  bool get isCompleted {
    return this == FileStatus.finished || 
           this == FileStatus.failed || 
           this == FileStatus.skipped;
  }
}