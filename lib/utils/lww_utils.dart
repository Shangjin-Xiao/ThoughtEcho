/// LWW (Last-Write-Wins) 时间戳比较工具
///
/// 为同步功能提供安全的时间戳比较和解析功能
class LWWUtils {
  static const String _defaultTimestamp = '1970-01-01T00:00:00.000Z';

  /// 解析时间戳，失败时返回Unix纪元时间
  static DateTime parseTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    try {
      return DateTime.parse(timestamp).toUtc();
    } catch (e) {
      // 解析失败，返回Unix纪元时间
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }

  /// 安全地比较两个时间戳
  /// 返回值：
  /// - 正数：remote 更新
  /// - 负数：local 更新
  /// - 0：时间戳相同
  static int compareTimestamps(
      String? localTimestamp, String? remoteTimestamp) {
    final localTime = parseTimestamp(localTimestamp);
    final remoteTime = parseTimestamp(remoteTimestamp);

    return remoteTime.compareTo(localTime);
  }

  /// 判断remote是否比local更新
  /// null 时间戳被视为最旧的时间戳
  static bool shouldUseRemote(String? localTimestamp, String? remoteTimestamp) {
    return compareTimestamps(localTimestamp, remoteTimestamp) > 0;
  }

  /// 判断local是否比remote更新或相等
  static bool shouldKeepLocal(String? localTimestamp, String? remoteTimestamp) {
    return compareTimestamps(localTimestamp, remoteTimestamp) <= 0;
  }

  /// 生成当前时间戳字符串
  static String generateTimestamp() {
    return DateTime.now().toUtc().toIso8601String();
  }

  /// 检查时间戳是否为默认值（表示从未同步过）
  static bool isDefaultTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return true;

    final parsed = parseTimestamp(timestamp);
    final defaultTime = parseTimestamp(_defaultTimestamp);

    return parsed.isAtSameMomentAs(defaultTime);
  }

  /// 格式化时间戳用于显示
  static String formatTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return '未知时间';
    }

    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}天前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}小时前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分钟前';
      } else {
        return '刚刚';
      }
    } catch (e) {
      return '时间格式错误';
    }
  }

  /// 检测可能的时钟偏移
  /// 如果remote时间戳比当前时间超前过多，可能存在时钟偏移
  static Duration? detectClockSkew(String? remoteTimestamp) {
    if (remoteTimestamp == null || remoteTimestamp.isEmpty) {
      return null;
    }

    try {
      final remoteTime = DateTime.parse(remoteTimestamp).toUtc();
      final now = DateTime.now().toUtc();
      final difference = remoteTime.difference(now);

      // 如果remote时间戳超前当前时间5分钟以上，认为可能存在时钟偏移
      if (difference.inMinutes > 5) {
        return difference;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 验证时间戳格式是否正确
  static bool isValidTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return false;
    }

    try {
      DateTime.parse(timestamp);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 标准化时间戳格式（转换为UTC ISO8601）
  static String normalizeTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return _defaultTimestamp;
    }

    try {
      final dateTime = DateTime.parse(timestamp).toUtc();
      return dateTime.toIso8601String();
    } catch (e) {
      return _defaultTimestamp;
    }
  }

  /// 获取两个时间戳中较新的一个
  static String getNewerTimestamp(String? timestamp1, String? timestamp2) {
    if (shouldUseRemote(timestamp1, timestamp2)) {
      return normalizeTimestamp(timestamp2);
    } else {
      return normalizeTimestamp(timestamp1);
    }
  }

  /// 计算时间戳之间的差值（秒）
  static int getTimestampDifferenceSeconds(
      String? timestamp1, String? timestamp2) {
    final time1 = parseTimestamp(timestamp1);
    final time2 = parseTimestamp(timestamp2);

    return time2.difference(time1).inSeconds;
  }
}

/// LWW 合并决策枚举
enum LWWDecision {
  useLocal, // 使用本地数据
  useRemote, // 使用远程数据
  conflict, // 时间戳相同但内容不同
}

/// LWW 合并决策结果
class LWWMergeDecision {
  final LWWDecision decision;
  final String reason;
  final String? localTimestamp;
  final String? remoteTimestamp;
  final Duration? clockSkew;

  const LWWMergeDecision({
    required this.decision,
    required this.reason,
    this.localTimestamp,
    this.remoteTimestamp,
    this.clockSkew,
  });

  bool get shouldUseLocal => decision == LWWDecision.useLocal;
  bool get shouldUseRemote => decision == LWWDecision.useRemote;
  bool get hasConflict => decision == LWWDecision.conflict;

  @override
  String toString() {
    return 'LWWMergeDecision(${decision.name}, $reason)';
  }
}

/// LWW 决策器 - 集成时间戳比较和合并决策逻辑
class LWWDecisionMaker {
  /// 为两个数据项做出合并决策
  static LWWMergeDecision makeDecision({
    required String? localTimestamp,
    required String? remoteTimestamp,
    String? localContent,
    String? remoteContent,
    bool checkContentSimilarity = false,
  }) {
    // 检测时钟偏移
    final clockSkew = LWWUtils.detectClockSkew(remoteTimestamp);

    // 比较时间戳
    final comparison =
        LWWUtils.compareTimestamps(localTimestamp, remoteTimestamp);

    if (comparison > 0) {
      // Remote更新
      return LWWMergeDecision(
        decision: LWWDecision.useRemote,
        reason: 'Remote数据更新 (${LWWUtils.formatTimestamp(remoteTimestamp)})',
        localTimestamp: localTimestamp,
        remoteTimestamp: remoteTimestamp,
        clockSkew: clockSkew,
      );
    } else if (comparison < 0) {
      // Local更新
      return LWWMergeDecision(
        decision: LWWDecision.useLocal,
        reason: 'Local数据更新 (${LWWUtils.formatTimestamp(localTimestamp)})',
        localTimestamp: localTimestamp,
        remoteTimestamp: remoteTimestamp,
        clockSkew: clockSkew,
      );
    } else {
      // 时间戳相同
      if (checkContentSimilarity &&
          localContent != null &&
          remoteContent != null &&
          localContent != remoteContent) {
        // 时间戳相同但内容不同，这是一个冲突
        return LWWMergeDecision(
          decision: LWWDecision.conflict,
          reason: '时间戳相同但内容不同',
          localTimestamp: localTimestamp,
          remoteTimestamp: remoteTimestamp,
          clockSkew: clockSkew,
        );
      } else {
        // 时间戳相同且内容相同（或不检查内容），保持local
        return LWWMergeDecision(
          decision: LWWDecision.useLocal,
          reason: '时间戳相同，保持Local',
          localTimestamp: localTimestamp,
          remoteTimestamp: remoteTimestamp,
          clockSkew: clockSkew,
        );
      }
    }
  }
}
