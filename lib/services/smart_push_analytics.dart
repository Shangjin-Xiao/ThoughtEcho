import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/smart_push_settings.dart';
import '../utils/app_logger.dart';
import 'mmkv_service.dart';

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
  double get qualityFloor =>
      todayCount == 0 ? 0 : profile.extraQualityFloor;
}

/// SOTA 智能推送分析服务
class SmartPushAnalytics extends ChangeNotifier {
  final MMKVService _mmkv;
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

  SmartPushAnalytics({MMKVService? mmkvService})
      : _mmkv = mmkvService ?? MMKVService();

  // ============================================================
  // 1. 响应性热图 - 用户 App 打开时间分析
  // ============================================================

  /// 记录用户打开 App 的时间
  Future<void> recordAppOpen() async {
    try {
      final now = DateTime.now();
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
        hourCounts[dt.hour] = (hourCounts[dt.hour] ?? 0) + 1;
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
          recentCounts[dt.hour] = (recentCounts[dt.hour] ?? 0) + 1;
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

  Future<List<String>> _getAppOpenRecords() async {
    try {
      final jsonStr = _mmkv.getString(_appOpenTimesKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final List<dynamic> list = List<dynamic>.from(
        (jsonStr.split(',').where((s) => s.isNotEmpty)),
      );
      return list.cast<String>();
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
  Future<void> recordDismissal() async {
    await _mmkv.setString(_lastDismissalKey, DateTime.now().toIso8601String());
    AppLogger.d('记录通知被忽略，进入冷却期');
  }

  /// 记录用户点击通知（正向反馈）
  ///
  /// 只在待结算记录上打个「已点击」标记，真正的分数更新和连续未点击复位
  /// 交给下一次推送前的 [settlePendingSend]。这样点击与未点击走同一条
  /// 结算路径，不会出现「点击加了 success 计数但分数没动」的断裂。
  Future<void> recordInteraction(String contentType) async {
    final raw = _mmkv.getString(_pendingSendKey);
    if (raw != null && raw.isNotEmpty && raw.startsWith('$contentType|')) {
      await _mmkv.setString(_pendingSendKey, '$contentType|1');
      AppLogger.d('记录通知交互: $contentType（已标记待结算为已点击）');
      return;
    }

    // 待结算记录已被清掉或类型对不上（如冷启动后点击旧通知）：
    // 至少把连续未点击计数复位 —— 用户明确回应了，不该继续降级。
    await _setUnengagedStreak(0);
    await updateContentScore(contentType, true);
    AppLogger.d('记录通知交互: $contentType（无匹配待结算，直接复位）');
  }

  Future<bool> _isInCooldown() async {
    try {
      final lastDismissal = _mmkv.getString(_lastDismissalKey);
      if (lastDismissal == null || lastDismissal.isEmpty) return false;

      final dismissTime = DateTime.parse(lastDismissal);
      final cooldownEnd = dismissTime.add(
        Duration(hours: cooldownHoursAfterDismiss),
      );

      return DateTime.now().isBefore(cooldownEnd);
    } catch (e, stack) {
      AppLogger.e(
        '解析忽略时间记录失败',
        error: e,
        stackTrace: stack,
        source: 'SmartPushAnalytics',
      );
      return false;
    }
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
  Future<EngagementTier> getEngagementTier() async {
    final records = await _getAppOpenRecords();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: engagementWindowDays));

    final openDays = <String>{};
    for (final record in records) {
      final dt = DateTime.tryParse(record);
      if (dt == null || dt.isBefore(cutoff)) continue;
      openDays.add(dt.toIso8601String().substring(0, 10));
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

  /// 当前连续未点击次数对应的冷却时长
  Future<Duration> getHabituationCooldown() async {
    final streak = await getUnengagedStreak();
    final index = streak.clamp(0, habituationCooldownHours.length - 1);
    return Duration(hours: habituationCooldownHours[index]);
  }

  /// 今日已推送条数
  Future<int> getTodayPushCount() async {
    final raw = _mmkv.getString(_dailyCountKey);
    if (raw == null || raw.isEmpty) return 0;

    final parts = raw.split('|');
    if (parts.length != 2) return 0;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (parts[0] != today) return 0; // 跨天自动归零

    return int.tryParse(parts[1]) ?? 0;
  }

  Future<void> _incrementTodayPushCount() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final count = await getTodayPushCount();
    await _mmkv.setString(_dailyCountKey, '$today|${count + 1}');
  }

  /// 结算上一条推送的效果，并推进/复位连续未点击计数。
  ///
  /// 必须在**下一次推送发出前**调用：只有到这时才知道用户到底点没点。
  /// 老代码在发送瞬间就 `updateContentScore(type, false)` 记一次失败，
  /// 点击时又只加 `_success` 计数不重算分数，导致所有内容分单调趋近 0、
  /// Thompson Sampling 退化成纯随机 —— 这里把闭环接回来。
  Future<void> settlePendingSend() async {
    final raw = _mmkv.getString(_pendingSendKey);
    if (raw == null || raw.isEmpty) return;

    final parts = raw.split('|');
    if (parts.length != 2) {
      await _mmkv.setString(_pendingSendKey, '');
      return;
    }

    final contentType = parts[0];
    final engaged = parts[1] == '1';

    await updateContentScore(contentType, engaged);

    if (engaged) {
      await _setUnengagedStreak(0);
      AppLogger.d('结算上一条推送: $contentType 已点击，连续未点击计数复位');
    } else {
      final streak = await getUnengagedStreak();
      await _setUnengagedStreak(streak + 1);
      AppLogger.d('结算上一条推送: $contentType 未点击，连续未点击 ${streak + 1} 次');
    }

    await _mmkv.setString(_pendingSendKey, '');
  }

  /// 登记一条刚发出的推送（等待下次结算）
  Future<void> markSent(String contentType) async {
    await _mmkv.setString(_pendingSendKey, '$contentType|0');
    await _incrementTodayPushCount();
  }

  /// 裁定这次推送能不能发，以及要多好才配发。
  ///
  /// [lastPushTime] 来自 SmartPushSettings，用于最小间隔天数判定。
  Future<PushAllowance> checkPushAllowance({
    required PushIntensity intensity,
    DateTime? lastPushTime,
  }) async {
    final tier = await getEngagementTier();
    final profile = intensity.quotaFor(tier);
    final todayCount = await getTodayPushCount();

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
      final gap = DateTime.now().difference(lastPushTime).inDays;
      if (gap < profile.minGapDays) {
        return deny('未到最小间隔 ($gap 天 < ${profile.minGapDays} 天)');
      }
    }

    // 3. 连续未点击衰减
    final habituation = await getHabituationCooldown();
    if (habituation > Duration.zero && lastPushTime != null) {
      final since = DateTime.now().difference(lastPushTime);
      if (since < habituation) {
        final streak = await getUnengagedStreak();
        return deny(
          '连续 $streak 次未点击，冷却中 (${habituation.inHours}h，已过 ${since.inHours}h)',
        );
      }
    }

    // 4. 刚打开过 App —— 他已经想起来了
    final lastOpen = await getLastAppOpen();
    if (lastOpen != null) {
      final sinceOpen = DateTime.now().difference(lastOpen);
      if (sinceOpen < const Duration(hours: recentOpenSuppressHours)) {
        return deny('${sinceOpen.inMinutes} 分钟前刚用过 App，跳过本次推送');
      }
    }

    // 5. 被手动忽略后的冷却
    if (await _isInCooldown()) {
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
  Future<void> updateContentScore(String contentType, bool wasEngaged) async {
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
    await _mmkv.remove(_appOpenTimesKey);
    await _mmkv.remove(_notificationMetricsKey);
    await _mmkv.remove(_contentScoresKey);
    await _mmkv.remove(_unengagedStreakKey);
    await _mmkv.remove(_pendingSendKey);
    await _mmkv.remove(_dailyCountKey);
    await _mmkv.remove(_lastDismissalKey);
    AppLogger.i('智能推送分析数据已重置');
    notifyListeners();
  }
}
