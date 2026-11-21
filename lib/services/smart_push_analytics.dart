import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/smart_push_settings.dart';
import '../utils/platform_helper.dart';
import '../utils/string_utils.dart';
import '../utils/app_logger.dart';
import 'app_preferences_service.dart';

/// 推送检查结果
class PushCheckResult {
  final bool allowed;
  final String? reason;

  const PushCheckResult({required this.allowed, this.reason});

  static const PushCheckResult ok = PushCheckResult(allowed: true);
}

/// 一次推送尝试的配额裁定结果
///
/// 由 [SmartPushAnalytics.checkPushAllowance] 产出，把「能不能推」和
/// 「这一条要多好才配推」一次算清，避免调用方各自拼判断。
class PushAllowance {
  final bool allowed;
  final String? reason;
  final EngagementTier tier;
  final PushQuotaProfile profile;

  /// 今天已经推了几条
  final int todayCount;

  const PushAllowance({
    required this.allowed,
    required this.tier,
    required this.profile,
    required this.todayCount,
    this.reason,
  });

  /// 这一条需要跨过的最低价值分。
  ///
  /// 当天第一条没有门槛；第 2 条起要过 [PushQuotaProfile.extraQualityFloor]，
  /// 这就是「宁可不推也不推垃圾」的落点。
  double get qualityFloor => todayCount == 0 ? 0 : profile.extraQualityFloor;
}

/// SOTA 智能推送分析服务
class SmartPushAnalytics extends ChangeNotifier {
  static const String _crossIsolateLockName = 'smart_push_analytics_v1';
  static final Object _analyticsLockZoneKey = Object();

  final AppPreferencesService _mmkv;
  final String? _lockFilePathOverride;
  final Random _random = Random();

  // 存储键
  static const String _appOpenTimesKey = 'smart_push_app_open_times';
  static const String _notificationMetricsKey =
      'smart_push_notification_metrics';
  static const String _contentScoresKey = 'smart_push_content_scores';
  static const String _lastDismissalKey = 'smart_push_last_dismissal';
  static const String _unengagedStreakKey = 'smart_push_unengaged_streak';
  static const String _pendingSendKey = 'smart_push_pending_send';
  static const String _dailyCountKey = 'smart_push_daily_count';
  static const String _clickedNotificationIdsKey =
      'smart_push_clicked_notification_ids_v1';
  static const String _settledUnengagedIdsKey =
      'smart_push_settled_unengaged_ids_v1';
  static const String _settledEngagedIdsKey =
      'smart_push_settled_engaged_ids_v1';
  static const String _sentNotificationIdsKey =
      'smart_push_sent_notification_ids_v1';
  static const int _maxTrackedNotificationIds = 100;

  // 配置常量
  static const int maxAppOpenRecords = 200; // 保留最近 200 条打开记录
  static const int cooldownHoursAfterDismiss = 8; // 忽略后冷却小时数
  static const double explorationRate = 0.1; // ε-Greedy 探索率 (10%)

  /// 参与度分档的观察窗口
  static const int engagementWindowDays = 7;

  /// 活跃档门槛：窗口内打开过多少天算活跃
  static const int activeOpenDaysThreshold = 4;

  /// 刚打开过 App 就别推了 —— 他已经想起来了，再推就是打扰
  static const int recentOpenSuppressHours = 4;

  /// 连续未点击 → 冷却时长阶梯（小时）
  ///
  /// 索引即连续未点击次数，超出末尾一律按最后一档。点一次立刻复位到 0。
  /// 这是整套防轰炸里性价比最高的单点：用户不理你，你自己就该退。
  static const List<int> habituationCooldownHours = [0, 2, 8, 24, 72];

  /// 参与效果统计的内容类型
  static const List<String> _trackedContentTypes = [
    'yearAgoToday',
    'monthAgoToday',
    'weekAgoToday',
    'sameLocation',
    'sameWeather',
    'sameTimeOfDay',
    'dailyQuote',
    'pastNote',
  ];

  SmartPushAnalytics({
    AppPreferencesService? mmkvService,
    @visibleForTesting String? lockFilePathOverride,
  })  : _mmkv = mmkvService ?? AppPreferencesService(),
        _lockFilePathOverride = lockFilePathOverride;

  Future<void> _reloadSharedStorage() async {
    try {
      await _mmkv.reload();
    } catch (_) {}
  }

  Future<T> _withAnalyticsLock<T>(Future<T> Function() action) {
    if (Zone.current[_analyticsLockZoneKey] == true) {
      return action();
    }
    return PlatformHelper.withCrossIsolateLock<T>(
      _crossIsolateLockName,
      () async {
        await _reloadSharedStorage();
        return await runZoned(
          action,
          zoneValues: <Object?, Object?>{_analyticsLockZoneKey: true},
        );
      },
      customLockFilePath: _lockFilePathOverride,
    );
  }

  // ============================================================
  // 1. 响应性热图 - 用户 App 打开时间分析
  // ============================================================

  /// 记录用户打开 App 的时间
  Future<void> recordAppOpen({DateTime? openedAt}) {
    return _withAnalyticsLock(() async {
      try {
        final now = openedAt ?? DateTime.now();
        final records = await _getAppOpenRecords();

        records.add(now.toIso8601String());

        // 保持记录数量在限制内
        while (records.length > maxAppOpenRecords) {
          records.removeAt(0);
        }

        await _saveAppOpenRecords(records);
        AppLogger.d('记录 App 打开时间: ${now.hour}:${now.minute}');
      } catch (e, stack) {
        AppLogger.e(
          '记录 App 打开时间失败',
          error: e,
          stackTrace: stack,
          source: 'SmartPushAnalytics',
        );
      }
    });
  }

  /// 计算用户响应性热图（24小时分布）
  ///
  /// 返回: `Map<hour, score>` 其中 score 是该小时的响应性得分 (0.0-1.0)
  Future<Map<int, double>> calculateResponsivenessHeatmap() async {
    final records = await _getAppOpenRecords();
    final heatmap = <int, double>{};

    // 初始化所有小时
    for (int h = 0; h < 24; h++) {
      heatmap[h] = 0.0;
    }

    if (records.isEmpty) {
      // 没有数据时返回默认热图
      return _getDefaultHeatmap();
    }

    // 统计每小时的打开次数
    final hourCounts = <int, int>{};
    for (int h = 0; h < 24; h++) {
      hourCounts[h] = 0;
    }

    for (final record in records) {
      try {
        final dt = DateTime.parse(record);
        final hour = _extractRecordWallHour(record, dt);
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      } catch (e, stack) {
        AppLogger.e(
          '解析应用打开记录失败',
          error: e,
          stackTrace: stack,
          source: 'SmartPushAnalytics',
        );
      }
    }

    // 找到最大值用于归一化
    final maxCount = hourCounts.values.reduce(max);
    if (maxCount == 0) return _getDefaultHeatmap();

    // 归一化到 0.0-1.0
    for (int h = 0; h < 24; h++) {
      heatmap[h] = (hourCounts[h] ?? 0) / maxCount;
    }

    // 应用时间衰减：最近的记录权重更高
    await _applyTimeDecay(heatmap, records);

    return heatmap;
  }

  /// 获取最佳推送时间窗口
  ///
  /// 返回: 按得分排序的 (hour, score) 列表，过滤掉用户不活跃的时段
  Future<List<MapEntry<int, double>>> getOptimalPushWindows({
    int count = 3,
    double minScore = 0.2,
  }) async {
    final heatmap = await calculateResponsivenessHeatmap();

    // 过滤并排序
    final validWindows = heatmap.entries
        .where((e) => e.value >= minScore)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 确保时间间隔至少 3 小时
    final selected = <MapEntry<int, double>>[];
    for (final window in validWindows) {
      if (selected.length >= count) break;

      bool hasConflict = false;
      for (final s in selected) {
        final diff = (window.key - s.key).abs();
        if (diff < 3 || diff > 21) {
          // 考虑跨午夜
          hasConflict = true;
          break;
        }
      }

      if (!hasConflict) {
        selected.add(window);
      }
    }

    // 按时间排序
    selected.sort((a, b) => a.key.compareTo(b.key));

    return selected;
  }

  Map<int, double> _getDefaultHeatmap() {
    // 默认热图：基于典型用户行为
    return {
      0: 0.1,
      1: 0.05,
      2: 0.02,
      3: 0.01,
      4: 0.01,
      5: 0.05,
      6: 0.2,
      7: 0.5,
      8: 0.7,
      9: 0.6,
      10: 0.5,
      11: 0.4,
      12: 0.6,
      13: 0.5,
      14: 0.4,
      15: 0.4,
      16: 0.5,
      17: 0.6,
      18: 0.7,
      19: 0.8,
      20: 0.9,
      21: 0.8,
      22: 0.5,
      23: 0.3,
    };
  }

  Future<void> _applyTimeDecay(
    Map<int, double> heatmap,
    List<String> records,
  ) async {
    // 简化的时间衰减：最近 7 天的记录权重 2x
    final now = DateTime.now();
    final recentCutoff = now.subtract(const Duration(days: 7));

    final recentCounts = <int, int>{};
    for (int h = 0; h < 24; h++) {
      recentCounts[h] = 0;
    }

    for (final record in records) {
      try {
        final dt = DateTime.parse(record);
        if (dt.isAfter(recentCutoff)) {
          final hour = _extractRecordWallHour(record, dt);
          recentCounts[hour] = (recentCounts[hour] ?? 0) + 1;
        }
      } catch (e, stack) {
        AppLogger.e(
          '解析应用打开记录(时间衰减)失败',
          error: e,
          stackTrace: stack,
          source: 'SmartPushAnalytics',
        );
      }
    }

    final maxRecent = recentCounts.values.fold(1, max);

    // 混合全部数据和最近数据
    for (int h = 0; h < 24; h++) {
      final recentScore = (recentCounts[h] ?? 0) / maxRecent;
      heatmap[h] = (heatmap[h]! * 0.4) + (recentScore * 0.6);
    }
  }

  int _extractRecordWallHour(String record, DateTime parsed) {
    if (record.length >= 13 && record.codeUnitAt(10) == 0x54) {
      final hour = int.tryParse(record.substring(11, 13));
      if (hour != null && hour >= 0 && hour < 24) {
        return hour;
      }
    }
    return parsed.hour;
  }

  Future<List<String>> _getAppOpenRecords() async {
    try {
      final jsonStr = _mmkv.getString(_appOpenTimesKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      return StringUtils.parseCommaSeparatedString(jsonStr);
    } catch (e, stack) {
      AppLogger.e(
        '获取应用打开记录异常',
        error: e,
        stackTrace: stack,
        source: 'SmartPushAnalytics',
      );
      return [];
    }
  }

  Future<void> _saveAppOpenRecords(List<String> records) async {
    await _mmkv.setString(_appOpenTimesKey, records.join(','));
  }

  // ============================================================
  // 2. 疲劳预防系统
  // ============================================================

  /// 获取内容类型点击学习得分快照，供候选排序使用。
  Future<Map<String, double>> getContentTypeScores() async {
    return Map.unmodifiable(await _getContentScores());
  }

  /// 记录用户忽略/关闭通知（触发冷却期）
  Future<void> recordDismissal() {
    return _withAnalyticsLock(() async {
      await _mmkv.setString(
        _lastDismissalKey,
        DateTime.now().toIso8601String(),
      );
      AppLogger.d('记录通知被忽略，进入冷却期');
    });
  }

  /// 记录用户点击通知（正向反馈）
  ///
  /// 支持按 [notificationId] 追踪点击状态：
  /// - 若点击的是当前待结算通知，将其标记为已点击并立即复位连续未点击计数；
  /// - 若点击的是尚未补记发送的预调度通知（[deferScoreUntilAccounted] 为 true），
  ///   持久化该通知 ID 的已点击状态，待补记发送时直接按“已点击”结算，防止随后 `markSent` 覆盖为未点击；
  /// - 若点击的是此前已按“未点击”结算过的历史通知，修正成功次数与得分并复位连续未点击计数，不重复累加发送总数。
  Future<void> recordInteraction(
    String contentType, {
    int? notificationId,
    bool deferScoreUntilAccounted = false,
  }) {
    return _withAnalyticsLock(() async {
      if (notificationId != null) {
        final settledEngagedIds = _getTrackedIdList(_settledEngagedIdsKey);
        if (settledEngagedIds.contains(notificationId)) {
          await _setUnengagedStreak(0);
          AppLogger.d(
            '记录通知交互: $contentType (ID: $notificationId 已结算过点击，跳过重复计分)',
          );
          return;
        }

        final pending = _parsePendingSend(_mmkv.getString(_pendingSendKey));
        if (pending != null &&
            (pending.notificationId == notificationId ||
                (!deferScoreUntilAccounted &&
                    pending.notificationId == null &&
                    pending.contentType == contentType))) {
          await _removeTrackedId(_clickedNotificationIdsKey, notificationId);
          await _mmkv.setString(
            _pendingSendKey,
            '${pending.contentType}|1|$notificationId',
          );
          await _setUnengagedStreak(0);
          AppLogger.d(
            '记录通知交互: ${pending.contentType} (ID: $notificationId 已标记待结算为已点击)',
          );
          return;
        }

        final settledUnengagedIds = _getTrackedIdList(_settledUnengagedIdsKey);
        if (settledUnengagedIds.contains(notificationId)) {
          await _removeTrackedId(_settledUnengagedIdsKey, notificationId);
          await _appendTrackedId(_settledEngagedIdsKey, notificationId);
          await _setUnengagedStreak(0);
          await _upgradeUnengagedScoreToEngaged(contentType);
          AppLogger.d(
            '记录通知交互: $contentType (ID: $notificationId 修正历史未点击结算为已点击)',
          );
          return;
        }

        if (deferScoreUntilAccounted) {
          await _appendTrackedId(_clickedNotificationIdsKey, notificationId);
          await _setUnengagedStreak(0);
          AppLogger.d(
            '记录通知交互: $contentType (ID: $notificationId 已保存点击状态，等待补记发送时结算)',
          );
          return;
        }

        await _appendTrackedId(_settledEngagedIdsKey, notificationId);
        await _setUnengagedStreak(0);
        await updateContentScore(contentType, true);
        AppLogger.d('记录通知交互: $contentType (ID: $notificationId 直接结算点击)');
        return;
      }

      final pending = _parsePendingSend(_mmkv.getString(_pendingSendKey));
      if (pending != null && pending.contentType == contentType) {
        final updatedPending = pending.notificationId != null
            ? '$contentType|1|${pending.notificationId}'
            : '$contentType|1';
        await _mmkv.setString(_pendingSendKey, updatedPending);
        await _setUnengagedStreak(0);
        AppLogger.d('记录通知交互: $contentType（已标记待结算为已点击）');
        return;
      }

      // 待结算记录已被清掉或类型对不上（如冷启动后点击旧通知）：
      // 至少把连续未点击计数复位 —— 用户明确回应了，不该继续降级。
      await _setUnengagedStreak(0);
      await updateContentScore(contentType, true);
      AppLogger.d('记录通知交互: $contentType（无匹配待结算，直接复位）');
    });
  }

  /// 消费指定通知 ID 在补记发送前已发生的点击标记
  Future<bool> consumeClickedNotification(int notificationId) {
    return _withAnalyticsLock(() async {
      final clicked = _getTrackedIdList(_clickedNotificationIdsKey);
      if (!clicked.contains(notificationId)) {
        return false;
      }
      await _removeTrackedId(_clickedNotificationIdsKey, notificationId);
      return true;
    });
  }

  /// 判断某次通知发送实例是否已完成配额计数登记（防止并发补记中断后重试时重复计数）
  bool hasRecordedSentNotification(int notificationId, {DateTime? sentAt}) {
    if (notificationId <= 0) return false;
    final tokens = _getTrackedStringList(_sentNotificationIdsKey);
    if (tokens.isEmpty) return false;
    final exactToken =
        _buildSentNotificationToken(notificationId, sentAt: sentAt);
    if (tokens.contains(exactToken)) {
      return true;
    }
    if (sentAt == null) {
      return tokens.any(
        (token) =>
            token == '$notificationId' || token.startsWith('$notificationId@'),
      );
    }
    return tokens.contains('$notificationId');
  }

  /// 当同一确定性通知 ID 被重新调度到新的未来时间点时，先结算同 ID 挂起记录，再清理旧实例遗留的点击与结算状态
  Future<void> resetTrackedNotificationState(int notificationId) {
    return _withAnalyticsLock(() async {
      if (notificationId <= 0) return;
      final pending = _parsePendingSend(_mmkv.getString(_pendingSendKey));
      if (pending != null && pending.notificationId == notificationId) {
        await settlePendingSend();
      }
      await _removeTrackedId(_clickedNotificationIdsKey, notificationId);
      await _removeTrackedId(_settledUnengagedIdsKey, notificationId);
      await _removeTrackedId(_settledEngagedIdsKey, notificationId);
    });
  }

  String _buildSentNotificationToken(int notificationId, {DateTime? sentAt}) {
    if (sentAt != null) {
      return '$notificationId@${sentAt.millisecondsSinceEpoch}';
    }
    return '$notificationId';
  }

  List<String> _getTrackedStringList(String key) {
    final raw = _mmkv.getString(key);
    if (raw == null || raw.isEmpty) return <String>[];
    final result = <String>[];
    for (final token in raw.split(',')) {
      final trimmed = token.trim();
      if (trimmed.isNotEmpty) {
        result.add(trimmed);
      }
    }
    return result;
  }

  Future<void> _appendTrackedString(String key, String value) async {
    final tokens = _getTrackedStringList(key)..remove(value);
    tokens.add(value);
    while (tokens.length > _maxTrackedNotificationIds) {
      tokens.removeAt(0);
    }
    if (tokens.isEmpty) {
      await _mmkv.remove(key);
      return;
    }
    await _mmkv.setString(key, tokens.join(','));
  }

  ({String contentType, bool engaged, int? notificationId})? _parsePendingSend(
    String? raw,
  ) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 2 && parts.length != 3) return null;
    final contentType = parts[0];
    if (contentType.isEmpty) return null;
    final engaged = parts[1] == '1';
    final notificationId = parts.length == 3 ? int.tryParse(parts[2]) : null;
    return (
      contentType: contentType,
      engaged: engaged,
      notificationId: notificationId,
    );
  }

  List<int> _getTrackedIdList(String key) {
    final raw = _mmkv.getString(key);
    if (raw == null || raw.isEmpty) return <int>[];
    final result = <int>[];
    for (final token in raw.split(',')) {
      final parsed = int.tryParse(token.trim());
      if (parsed != null && parsed > 0) {
        result.add(parsed);
      }
    }
    return result;
  }

  Future<void> _saveTrackedIdList(String key, List<int> ids) async {
    if (ids.isEmpty) {
      await _mmkv.remove(key);
      return;
    }
    await _mmkv.setString(key, ids.join(','));
  }

  Future<void> _appendTrackedId(String key, int id) async {
    final ids = _getTrackedIdList(key)..remove(id);
    ids.add(id);
    while (ids.length > _maxTrackedNotificationIds) {
      ids.removeAt(0);
    }
    await _saveTrackedIdList(key, ids);
  }

  Future<void> _removeTrackedId(String key, int id) async {
    final ids = _getTrackedIdList(key);
    if (!ids.remove(id)) return;
    await _saveTrackedIdList(key, ids);
  }

  Future<void> _upgradeUnengagedScoreToEngaged(String contentType) async {
    final scores = await _getContentScores();
    final metrics = await _getNotificationMetrics();
    final totalKey = '${contentType}_total';
    final successKey = '${contentType}_success';

    final currentTotal = metrics[totalKey] ?? 0;
    final currentSuccess = metrics[successKey] ?? 0;
    final total = currentTotal > 0 ? currentTotal : 1;
    final success = min(total, currentSuccess + 1);

    metrics[totalKey] = total;
    metrics[successKey] = success;
    await _saveNotificationMetrics(metrics);

    final newScore = (success + 1) / (total + 2);
    scores[contentType] = newScore;
    await _saveContentScores(scores);
  }

  /// 获取手动忽略通知后的冷却结束时间（未处于忽略记录中时返回 null）
  DateTime? getDismissalCooldownEnd() {
    try {
      final lastDismissal = _mmkv.getString(_lastDismissalKey);
      if (lastDismissal == null || lastDismissal.isEmpty) return null;

      final dismissTime = DateTime.parse(lastDismissal);
      return dismissTime.add(
        const Duration(hours: cooldownHoursAfterDismiss),
      );
    } catch (e, stack) {
      AppLogger.e(
        '解析忽略时间记录失败',
        error: e,
        stackTrace: stack,
        source: 'SmartPushAnalytics',
      );
      return null;
    }
  }

  Future<bool> _isInCooldown({DateTime? now}) async {
    final cooldownEnd = getDismissalCooldownEnd();
    if (cooldownEnd == null) return false;
    return (now ?? DateTime.now()).isBefore(cooldownEnd);
  }

  // ============================================================
  // 2b. 参与度分档 + 配额闸门
  //
  // 设计原则：拨盘定天花板，这里只做减法，永远不做加法。
  // 用户拨到最右也不会突破连续未点击的降级 —— 拨盘是上限，不是承诺。
  // ============================================================

  /// 最近一次打开 App 的时间
  Future<DateTime?> getLastAppOpen() async {
    final records = await _getAppOpenRecords();
    for (int i = records.length - 1; i >= 0; i--) {
      final dt = DateTime.tryParse(records[i]);
      if (dt != null) return dt;
    }
    return null;
  }

  /// 按最近 [engagementWindowDays] 天打开 App 的**天数**分档
  ///
  /// 用天数而不是次数：一天疯狂开 20 次的人和连开 4 天的人，
  /// 后者才是真的把它当日常，前者可能只是在找某条笔记。
  Future<EngagementTier> getEngagementTier({DateTime? now}) async {
    final records = await _getAppOpenRecords();
    final currentNow = now ?? DateTime.now();
    final cutoff = currentNow.subtract(
      const Duration(days: engagementWindowDays),
    );

    final openDays = <String>{};
    for (final record in records) {
      final dt = DateTime.tryParse(record);
      if (dt == null || dt.isBefore(cutoff) || dt.isAfter(currentNow)) continue;
      final dayPart = (record.length >= 10 &&
              record.codeUnitAt(4) == 0x2D &&
              record.codeUnitAt(7) == 0x2D)
          ? record.substring(0, 10)
          : dt.toIso8601String().substring(0, 10);
      openDays.add(dayPart);
    }

    if (openDays.length >= activeOpenDaysThreshold) {
      return EngagementTier.active;
    }
    if (openDays.isNotEmpty) return EngagementTier.light;
    return EngagementTier.dormant;
  }

  /// 连续未点击次数
  Future<int> getUnengagedStreak() async {
    final raw = _mmkv.getString(_unengagedStreakKey);
    if (raw == null || raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  Future<void> _setUnengagedStreak(int value) async {
    await _mmkv.setString(_unengagedStreakKey, value.toString());
  }

  /// 根据连续未点击次数计算对应的冷却时长
  static Duration cooldownForStreak(int streak) {
    final safeStreak = streak < 0 ? 0 : streak;
    final index = safeStreak.clamp(0, habituationCooldownHours.length - 1);
    return Duration(hours: habituationCooldownHours[index]);
  }

  /// 非消费式检查某条通知是否已被用户点击（不清除点击标记）
  bool hasClickedNotification(int notificationId) {
    if (notificationId <= 0) return false;
    return _getTrackedIdList(_clickedNotificationIdsKey)
        .contains(notificationId);
  }

  /// 当前连续未点击次数对应的冷却时长
  Future<Duration> getHabituationCooldown() async {
    final streak = await getUnengagedStreak();
    return cooldownForStreak(streak);
  }

  /// 预测下一次推送发出前结算挂起记录后的连续未点击次数（纯只读：不消费点击记录、不重复落盘）
  Future<int> getProjectedUnengagedStreak() async {
    final settledStreak = await getUnengagedStreak();
    final pending = _parsePendingSend(_mmkv.getString(_pendingSendKey));
    if (pending == null) return settledStreak;

    final isPendingEngaged = pending.engaged ||
        (pending.notificationId != null &&
            hasClickedNotification(pending.notificationId!));
    if (isPendingEngaged) {
      return 0;
    }
    return settledStreak + 1;
  }

  /// 预测未来槽位判定时的连续未点击冷却时长（计入尚未结算的上一条已送达提醒）
  Future<Duration> getProjectedHabituationCooldown({
    int additionalUnengaged = 0,
  }) async {
    final projectedStreak =
        await getProjectedUnengagedStreak() + additionalUnengaged;
    return cooldownForStreak(projectedStreak);
  }

  /// 今日已推送条数
  Future<int> getTodayPushCount({DateTime? now}) async {
    final raw = _mmkv.getString(_dailyCountKey);
    if (raw == null || raw.isEmpty) return 0;

    final parts = raw.split('|');
    if (parts.length != 2) return 0;

    final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    if (parts[0] != today) return 0; // 跨天自动归零

    return int.tryParse(parts[1]) ?? 0;
  }

  Future<void> _incrementTodayPushCount({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();
    final today = currentNow.toIso8601String().substring(0, 10);
    final count = await getTodayPushCount(now: currentNow);
    await _mmkv.setString(_dailyCountKey, '$today|${count + 1}');
  }

  /// 结算上一条推送的效果，并推进/复位连续未点击计数。
  ///
  /// 必须在**下一次推送发出前**调用：只有到这时才知道用户到底点没点。
  /// 老代码在发送瞬间就 `updateContentScore(type, false)` 记一次失败，
  /// 点击时又只加 `_success` 计数不重算分数，导致所有内容分单调趋近 0、
  /// Thompson Sampling 退化成纯随机 —— 这里把闭环接回来。
  Future<void> settlePendingSend() {
    return _withAnalyticsLock(() async {
      final raw = _mmkv.getString(_pendingSendKey);
      if (raw == null || raw.isEmpty) return;

      final pending = _parsePendingSend(raw);
      if (pending == null) {
        await _mmkv.setString(_pendingSendKey, '');
        return;
      }

      final contentType = pending.contentType;
      final notificationId = pending.notificationId;
      var engaged = pending.engaged;
      if (!engaged && notificationId != null) {
        engaged = await consumeClickedNotification(notificationId);
      }

      await updateContentScore(contentType, engaged);

      if (engaged) {
        if (notificationId != null) {
          await _appendTrackedId(_settledEngagedIdsKey, notificationId);
        }
        await _setUnengagedStreak(0);
        AppLogger.d('结算上一条推送: $contentType 已点击，连续未点击计数复位');
      } else {
        if (notificationId != null) {
          await _appendTrackedId(_settledUnengagedIdsKey, notificationId);
        }
        final streak = await getUnengagedStreak();
        await _setUnengagedStreak(streak + 1);
        AppLogger.d('结算上一条推送: $contentType 未点击，连续未点击 ${streak + 1} 次');
      }

      await _mmkv.setString(_pendingSendKey, '');
    });
  }

  /// 跨 Isolate 原子执行预调度通知送达补记：
  /// 在同一互斥临界区内刷新最新共享存储、校验发送令牌、结算挂起项、消费预点击记录并登记发送，
  /// 确保后台补记与前台点击结算不会相互覆盖。
  Future<void> recordDeliveredNotification(
    String contentType, {
    required int notificationId,
    DateTime? sentAt,
    bool alreadyEngaged = false,
  }) {
    return _withAnalyticsLock(() async {
      final alreadyRecorded = hasRecordedSentNotification(
        notificationId,
        sentAt: sentAt,
      );
      if (!alreadyRecorded) {
        await settlePendingSend();
      }
      final wasClicked = await consumeClickedNotification(notificationId);
      await markSent(
        contentType,
        sentAt: sentAt,
        notificationId: notificationId,
        alreadyEngaged: alreadyEngaged || wasClicked,
      );
    });
  }

  /// 登记一条刚发出的推送（等待下次结算；若补记前已被用户点击则立即按已点击结算）
  Future<void> markSent(
    String contentType, {
    DateTime? sentAt,
    int? notificationId,
    bool alreadyEngaged = false,
  }) {
    return _withAnalyticsLock(() async {
      if (notificationId != null &&
          hasRecordedSentNotification(notificationId, sentAt: sentAt)) {
        final engagedOnRetry =
            alreadyEngaged || await consumeClickedNotification(notificationId);
        if (engagedOnRetry) {
          final pending = _parsePendingSend(_mmkv.getString(_pendingSendKey));
          if (pending != null && pending.notificationId == notificationId) {
            if (!pending.engaged) {
              await _mmkv.setString(
                _pendingSendKey,
                '${pending.contentType}|1|$notificationId',
              );
            }
            await _setUnengagedStreak(0);
          } else if (_getTrackedIdList(_settledUnengagedIdsKey)
              .contains(notificationId)) {
            await _removeTrackedId(_settledUnengagedIdsKey, notificationId);
            await _appendTrackedId(_settledEngagedIdsKey, notificationId);
            await _setUnengagedStreak(0);
            await _upgradeUnengagedScoreToEngaged(contentType);
          } else if (!_getTrackedIdList(_settledEngagedIdsKey)
              .contains(notificationId)) {
            await updateContentScore(contentType, true);
            await _appendTrackedId(_settledEngagedIdsKey, notificationId);
            await _setUnengagedStreak(0);
          }
        }
        return;
      }

      final hadPriorTokenForSameId = notificationId != null &&
          notificationId > 0 &&
          hasRecordedSentNotification(notificationId);
      final currentPending =
          _parsePendingSend(_mmkv.getString(_pendingSendKey));
      final alreadySettledEngagedCurrentInstance = notificationId != null &&
          !hadPriorTokenForSameId &&
          _getTrackedIdList(_settledEngagedIdsKey).contains(notificationId);
      final alreadyPendingEngagedCurrentInstance = notificationId != null &&
          !hadPriorTokenForSameId &&
          currentPending != null &&
          currentPending.notificationId == notificationId &&
          currentPending.engaged;

      await _incrementTodayPushCount(now: sentAt);
      if (notificationId != null && notificationId > 0) {
        await _appendTrackedString(
          _sentNotificationIdsKey,
          _buildSentNotificationToken(notificationId, sentAt: sentAt),
        );
      }

      var engaged = alreadyEngaged ||
          alreadySettledEngagedCurrentInstance ||
          alreadyPendingEngagedCurrentInstance;
      if (!engaged && notificationId != null) {
        engaged = await consumeClickedNotification(notificationId);
      }

      if (engaged) {
        if (notificationId != null) {
          await _removeTrackedId(_settledUnengagedIdsKey, notificationId);
          final settledEngagedIds = _getTrackedIdList(_settledEngagedIdsKey);
          if (!settledEngagedIds.contains(notificationId)) {
            await updateContentScore(contentType, true);
            await _appendTrackedId(_settledEngagedIdsKey, notificationId);
          }
        } else {
          await updateContentScore(contentType, true);
        }
        await _setUnengagedStreak(0);
        if (currentPending == null ||
            currentPending.notificationId == null ||
            currentPending.notificationId == notificationId) {
          await _mmkv.setString(_pendingSendKey, '');
        }
        return;
      }

      if (notificationId != null) {
        await _removeTrackedId(_settledUnengagedIdsKey, notificationId);
        await _removeTrackedId(_settledEngagedIdsKey, notificationId);
      }

      final pendingValue = notificationId != null
          ? '$contentType|0|$notificationId'
          : '$contentType|0';
      await _mmkv.setString(_pendingSendKey, pendingValue);
    });
  }

  /// 裁定这次推送能不能发，以及要多好才配发。
  ///
  /// [lastPushTime] 来自 SmartPushSettings，用于最小间隔天数判定。
  Future<PushAllowance> checkPushAllowance({
    required PushIntensity intensity,
    DateTime? lastPushTime,
    DateTime? now,
  }) async {
    final currentNow = now ?? DateTime.now();
    final tier = await getEngagementTier(now: currentNow);
    final profile = intensity.quotaFor(tier);
    final todayCount = await getTodayPushCount(now: currentNow);

    PushAllowance deny(String reason) => PushAllowance(
          allowed: false,
          reason: reason,
          tier: tier,
          profile: profile,
          todayCount: todayCount,
        );

    // 1. 今日配额
    if (todayCount >= profile.dailyCap) {
      return deny(
        '今日配额已用尽 (${tier.name}/${intensity.name}: $todayCount/${profile.dailyCap})',
      );
    }

    // 2. 最小间隔天数（沉睡档靠这个把节奏拉到 3 天/周/更长）
    if (profile.minGapDays > 0 && lastPushTime != null) {
      final gap = currentNow.difference(lastPushTime).inDays;
      if (gap < profile.minGapDays) {
        return deny('未到最小间隔 ($gap 天 < ${profile.minGapDays} 天)');
      }
    }

    // 3. 连续未点击衰减
    final habituation = await getHabituationCooldown();
    if (habituation > Duration.zero && lastPushTime != null) {
      final since = currentNow.difference(lastPushTime);
      if (since < habituation) {
        final streak = await getUnengagedStreak();
        return deny(
          '连续 $streak 次未点击，冷却中 (${habituation.inHours}h，已过 ${since.inHours}h)',
        );
      }
    }

    // 4. 刚打开过 App —— 他已经想起来了
    final lastOpen = await getLastAppOpen();
    if (lastOpen != null && !currentNow.isBefore(lastOpen)) {
      final sinceOpen = currentNow.difference(lastOpen);
      if (sinceOpen < const Duration(hours: recentOpenSuppressHours)) {
        return deny('${sinceOpen.inMinutes} 分钟前刚用过 App，跳过本次推送');
      }
    }

    // 5. 被手动忽略后的冷却
    if (await _isInCooldown(now: currentNow)) {
      return deny('用户处于忽略冷却期');
    }

    return PushAllowance(
      allowed: true,
      tier: tier,
      profile: profile,
      todayCount: todayCount,
    );
  }

  // ============================================================
  // 3. Thompson Sampling 内容选择
  // ============================================================

  /// 使用 Thompson Sampling 选择最佳内容类型
  ///
  /// 实现 ε-Greedy 策略的探索-利用平衡
  Future<String> selectContentType(List<String> availableTypes) async {
    if (availableTypes.isEmpty) return 'dailyQuote';
    if (availableTypes.length == 1) return availableTypes.first;

    // ε-Greedy: 10% 概率探索（随机选择）
    if (_random.nextDouble() < explorationRate) {
      final selected = availableTypes[_random.nextInt(availableTypes.length)];
      AppLogger.d('Thompson Sampling 探索: $selected');
      return selected;
    }

    // 90% 概率利用（选择历史最佳）
    final scores = await _getContentScores();

    String bestType = availableTypes.first;
    double bestScore = -1;

    for (final type in availableTypes) {
      final score = scores[type] ?? 0.5; // 默认得分 0.5

      // 添加少量随机噪声避免总是选择同一个
      final adjustedScore = score + (_random.nextDouble() * 0.1);

      if (adjustedScore > bestScore) {
        bestScore = adjustedScore;
        bestType = type;
      }
    }

    AppLogger.d('Thompson Sampling 利用: $bestType (score: $bestScore)');
    return bestType;
  }

  /// 更新内容类型得分（基于用户反馈）
  Future<void> updateContentScore(String contentType, bool wasEngaged) {
    return _withAnalyticsLock(() async {
      final scores = await _getContentScores();
      final metrics = await _getNotificationMetrics();

      // 获取该类型的历史数据
      final totalKey = '${contentType}_total';
      final successKey = '${contentType}_success';

      final total = (metrics[totalKey] ?? 0) + 1;
      final success = (metrics[successKey] ?? 0) + (wasEngaged ? 1 : 0);

      // 更新计数
      metrics[totalKey] = total;
      metrics[successKey] = success;
      await _saveNotificationMetrics(metrics);

      // 计算新得分（使用贝叶斯估计的平滑）
      // Beta(success + 1, total - success + 1) 的均值
      final newScore = (success + 1) / (total + 2);
      scores[contentType] = newScore;
      await _saveContentScores(scores);

      AppLogger.d('更新内容得分: $contentType = $newScore ($success/$total)');
    });
  }

  Future<Map<String, double>> _getContentScores() async {
    try {
      final jsonStr = _mmkv.getString(_contentScoresKey);
      if (jsonStr == null || jsonStr.isEmpty) return {};

      final Map<String, double> scores = {};
      int start = 0;
      while (start < jsonStr.length) {
        int end = jsonStr.indexOf(';', start);
        if (end == -1) end = jsonStr.length;

        int colon = jsonStr.indexOf(':', start);
        if (colon != -1 && colon < end) {
          final key = jsonStr.substring(start, colon);
          final valueStr = jsonStr.substring(colon + 1, end);
          scores[key] = double.tryParse(valueStr) ?? 0.5;
        }
        start = end + 1;
      }
      return scores;
    } catch (e, stack) {
      AppLogger.e(
        '解析内容得分配置失败',
        error: e,
        stackTrace: stack,
        source: 'SmartPushAnalytics',
      );
      return {};
    }
  }

  Future<void> _saveContentScores(Map<String, double> scores) async {
    final str = scores.entries.map((e) => '${e.key}:${e.value}').join(';');
    await _mmkv.setString(_contentScoresKey, str);
  }

  Future<Map<String, int>> _getNotificationMetrics() async {
    try {
      final jsonStr = _mmkv.getString(_notificationMetricsKey);
      if (jsonStr == null || jsonStr.isEmpty) return {};

      final Map<String, int> metrics = {};
      int start = 0;
      while (start < jsonStr.length) {
        int end = jsonStr.indexOf(';', start);
        if (end == -1) end = jsonStr.length;

        int colon = jsonStr.indexOf(':', start);
        if (colon != -1 && colon < end) {
          final key = jsonStr.substring(start, colon);
          final valueStr = jsonStr.substring(colon + 1, end);
          metrics[key] = int.tryParse(valueStr) ?? 0;
        }
        start = end + 1;
      }
      return metrics;
    } catch (e, stack) {
      AppLogger.e(
        '解析推送统计指标失败',
        error: e,
        stackTrace: stack,
        source: 'SmartPushAnalytics',
      );
      return {};
    }
  }

  Future<void> _saveNotificationMetrics(Map<String, int> metrics) async {
    final str = metrics.entries.map((e) => '${e.key}:${e.value}').join(';');
    await _mmkv.setString(_notificationMetricsKey, str);
  }

  // ============================================================
  // 4. 效果追踪与统计
  // ============================================================

  /// 获取推送效果统计
  Future<Map<String, dynamic>> getAnalyticsStats() async {
    final metrics = await _getNotificationMetrics();
    final scores = await _getContentScores();
    final optimalWindows = await getOptimalPushWindows();

    // 计算整体点击率
    int totalSent = 0;
    int totalEngaged = 0;
    for (final type in _trackedContentTypes) {
      totalSent += metrics['${type}_total'] ?? 0;
      totalEngaged += metrics['${type}_success'] ?? 0;
    }

    final overallCtr = totalSent > 0 ? totalEngaged / totalSent : 0.0;

    return {
      'totalNotificationsSent': totalSent,
      'totalEngagements': totalEngaged,
      'overallClickRate': (overallCtr * 100).toStringAsFixed(1),
      'contentTypeScores': scores,
      'optimalHours': optimalWindows.map((e) => e.key).toList(),
      'engagementTier': (await getEngagementTier()).name,
      'todayPushCount': await getTodayPushCount(),
      'unengagedStreak': await getUnengagedStreak(),
      'habituationCooldownHours': (await getHabituationCooldown()).inHours,
      'isInCooldown': await _isInCooldown(),
    };
  }

  /// 重置所有分析数据
  Future<void> resetAnalytics() async {
    await _withAnalyticsLock(() async {
      await _mmkv.remove(_appOpenTimesKey);
      await _mmkv.remove(_notificationMetricsKey);
      await _mmkv.remove(_contentScoresKey);
      await _mmkv.remove(_unengagedStreakKey);
      await _mmkv.remove(_pendingSendKey);
      await _mmkv.remove(_dailyCountKey);
      await _mmkv.remove(_lastDismissalKey);
      await _mmkv.remove(_clickedNotificationIdsKey);
      await _mmkv.remove(_settledUnengagedIdsKey);
      await _mmkv.remove(_settledEngagedIdsKey);
      await _mmkv.remove(_sentNotificationIdsKey);
      AppLogger.i('智能推送分析数据已重置');
    });
    notifyListeners();
  }
}
