/// LWW (Last-Write-Wins) 时间戳比较工具
///
/// 为同步功能提供安全的时间戳比较和解析功能
class LWWUtils {
  static const String _defaultTimestamp = '1970-01-01T00:00:00.000Z';
  static const Duration maxFutureSkew = Duration(hours: 24);

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
    String? localTimestamp,
    String? remoteTimestamp,
  ) {
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
  static Duration? detectClockSkew(String? remoteTimestamp, {DateTime? now}) {
    if (remoteTimestamp == null || remoteTimestamp.isEmpty) {
      return null;
    }

    try {
      final remoteTime = DateTime.parse(remoteTimestamp).toUtc();
      final refNow = (now ?? DateTime.now()).toUtc();
      final difference = remoteTime.difference(refNow);

      // 如果remote时间戳超前当前时间5分钟以上，认为可能存在时钟偏移
      if (difference.inMinutes > 5) {
        return difference;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 判断时间戳是否超前当前时间过多（严格超过 [threshold]，默认 24 小时）
  static bool isExcessiveFutureTimestamp(
    String? timestamp, {
    DateTime? now,
    Duration threshold = maxFutureSkew,
  }) {
    if (timestamp == null || timestamp.isEmpty) {
      return false;
    }

    try {
      final parsed = DateTime.parse(timestamp).toUtc();
      final refNow = (now ?? DateTime.now()).toUtc();
      return parsed.difference(refNow) > threshold;
    } catch (e) {
      return false;
    }
  }

  /// 将超前过多的未来时间戳钳制到当前 UTC 时间
  static String clampFutureTimestamp(
    String? timestamp, {
    DateTime? now,
    Duration threshold = maxFutureSkew,
  }) {
    if (!isValidTimestamp(timestamp)) {
      return normalizeTimestamp(timestamp);
    }

    final refNow = (now ?? DateTime.now()).toUtc();
    if (isExcessiveFutureTimestamp(
      timestamp,
      now: refNow,
      threshold: threshold,
    )) {
      return refNow.toIso8601String();
    }

    return normalizeTimestamp(timestamp);
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
    String? timestamp1,
    String? timestamp2,
  ) {
    final time1 = parseTimestamp(timestamp1);
    final time2 = parseTimestamp(timestamp2);

    return time2.difference(time1).inSeconds;
  }

  static final RegExp _canonicalFixedUtcIsoRegex = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
  );
  static final RegExp _canonicalFixedLocalIsoRegex = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}$',
  );
  static final RegExp _explicitTzSuffixRegex = RegExp(
    r'[Tt ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:[Zz]|[+-]\d{2}(?::?\d{2})?)$',
  );

  /// SQLite `GLOB` 模式：匹配已标准化的 6 位小数位 UTC 时间串（`YYYY-MM-DDTHH:mm:ss.ffffffZ`）。
  static const String canonicalFixedUtcGlob =
      '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T'
      '[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9]Z';

  /// SQLite `GLOB` 模式：匹配已定宽保留的无时区本地时间串（`YYYY-MM-DDTHH:mm:ss.ffffff`）。
  static const String canonicalFixedOffsetlessGlob =
      '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T'
      '[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9]';

  /// 将 [dt] 格式化为固定 6 位小数位的 UTC ISO-8601 字符串（`YYYY-MM-DDTHH:mm:ss.ffffffZ`），
  /// 避免 Dart `toIso8601String()` 在零微秒（`.123Z`）与非零微秒（`.123001Z`）之间变长，
  /// 导致 SQLite 文本排序将 `.123001Z` 排在 `.123Z` 之前。
  static String formatFixedUtcIso(DateTime dt) {
    final u = dt.toUtc();
    return '${_formatFixedIsoCore(u)}Z';
  }

  static String _formatFixedIsoCore(DateTime dt) {
    final y = dt.year >= 0
        ? dt.year.toString().padLeft(4, '0')
        : '-${(-dt.year).toString().padLeft(4, '0')}';
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final micros =
        (dt.millisecond * 1000 + dt.microsecond).toString().padLeft(6, '0');
    return '$y-$mo-${d}T$h:$mi:$s.$micros';
  }

  static bool isCanonicalFixedUtcIso(Object? raw) {
    return raw is String && _canonicalFixedUtcIsoRegex.hasMatch(raw);
  }

  static bool isCanonicalFixedOffsetlessIso(Object? raw) {
    return raw is String && _canonicalFixedLocalIsoRegex.hasMatch(raw);
  }

  /// 判断时间字符串是否显式携带时区信息（末尾 `Z`/`z` 或 `±HH[:MM]`）。
  static bool hasExplicitTimezoneOffset(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    return _explicitTzSuffixRegex.hasMatch(trimmed);
  }

  /// 仅当 [raw] 显式携带 `Z` 或数值时区偏移时解析并返回其精确 UTC `DateTime`；
  /// 对无时区（offsetless）墙钟字符串返回 `null`，绝不依赖当前设备时区猜测。
  static DateTime? tryParseExplicitZoneUtc(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (!hasExplicitTimezoneOffset(trimmed)) return null;
    return DateTime.tryParse(trimmed)?.toUtc();
  }

  static DateTime? _parseOffsetlessWallClockAsNaiveUtc(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || hasExplicitTimezoneOffset(trimmed)) return null;
    final normalizedSep = trimmed.contains(' ') && !trimmed.contains('T')
        ? trimmed.replaceFirst(' ', 'T')
        : trimmed;
    return DateTime.tryParse('${normalizedSep}Z');
  }

  /// 当无时区时间串 [offsetlessRaw] 与显式时区时间串 [explicitCounterpartRaw] 代表同一事件时，
  /// 通过两者墙钟刻度与真实 UTC 时刻的整分钟时区差（`[-14h, +14h]` 且秒与微秒完全一致）
  /// 提取精确历史时区偏移；不满足同一事件条件时返回 `null`。
  static Duration? inferOffsetFromSameEventPair(
    Object? offsetlessRaw,
    Object? explicitCounterpartRaw,
  ) {
    if (offsetlessRaw is! String) return null;
    final naiveUtc = _parseOffsetlessWallClockAsNaiveUtc(offsetlessRaw);
    final counterpartUtc = tryParseExplicitZoneUtc(explicitCounterpartRaw);
    if (naiveUtc == null || counterpartUtc == null) return null;
    final diff = naiveUtc.difference(counterpartUtc);
    if (diff.abs() > const Duration(hours: 14)) return null;
    if (diff.inMicroseconds % Duration.microsecondsPerMinute != 0) {
      return null;
    }
    return diff;
  }

  /// 安全归一化时间字符串：
  /// 1. 显式偏移（`Z` 或 `±HH:MM`）直接精确换算为固定 6 位小数位 UTC（`...ffffffZ`）；
  /// 2. 无偏移本地时间若提供同一事件的显式时区对应值 [sameEventCounterpart]（或已知同事件偏移
  ///    [knownSameRowOffset]），则据此精确换算为固定 6 位小数位 UTC；
  /// 3. 无可靠时区依据的无偏移历史本地时间仅补齐固定 6 位小数位（不附加伪造 `Z`），
  ///    避免设备跨时区旅行升级时将当前时区误固化为权威 UTC 历史。
  static String normalizeTimestampPreservingOffsetless(
    Object? raw, {
    Object? sameEventCounterpart,
    Duration? knownSameRowOffset,
  }) {
    if (raw is! String) return '';
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (isCanonicalFixedUtcIso(trimmed)) return trimmed;

    if (hasExplicitTimezoneOffset(trimmed)) {
      final utc = DateTime.tryParse(trimmed)?.toUtc();
      return utc != null ? formatFixedUtcIso(utc) : trimmed;
    }

    final inferredOffset = inferOffsetFromSameEventPair(
          trimmed,
          sameEventCounterpart,
        ) ??
        knownSameRowOffset;
    final naiveUtc = _parseOffsetlessWallClockAsNaiveUtc(trimmed);
    if (naiveUtc == null) return trimmed;
    if (inferredOffset != null) {
      return formatFixedUtcIso(naiveUtc.subtract(inferredOffset));
    }
    return _formatFixedIsoCore(naiveUtc);
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
    DateTime? now,
  }) {
    final refNow = (now ?? DateTime.now()).toUtc();
    // 检测时钟偏移
    final clockSkew = LWWUtils.detectClockSkew(remoteTimestamp, now: refNow);

    final remoteIsExcessiveFuture = LWWUtils.isExcessiveFutureTimestamp(
      remoteTimestamp,
      now: refNow,
    );
    final localIsExcessiveFuture = LWWUtils.isExcessiveFutureTimestamp(
      localTimestamp,
      now: refNow,
    );

    if (remoteIsExcessiveFuture) {
      return LWWMergeDecision(
        decision: LWWDecision.useLocal,
        reason: 'Remote时间戳超前超过24小时，拒绝未来时间戳覆盖 ($remoteTimestamp)',
        localTimestamp: localTimestamp,
        remoteTimestamp: remoteTimestamp,
        clockSkew: clockSkew,
      );
    }

    if (localIsExcessiveFuture &&
        LWWUtils.isValidTimestamp(remoteTimestamp) &&
        !LWWUtils.isDefaultTimestamp(remoteTimestamp)) {
      return LWWMergeDecision(
        decision: LWWDecision.useRemote,
        reason: 'Local时间戳超前超过24小时，允许正常Remote数据覆盖 ($localTimestamp)',
        localTimestamp: localTimestamp,
        remoteTimestamp: remoteTimestamp,
        clockSkew: clockSkew,
      );
    }

    // 比较时间戳
    final comparison = LWWUtils.compareTimestamps(
      localTimestamp,
      remoteTimestamp,
    );

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
