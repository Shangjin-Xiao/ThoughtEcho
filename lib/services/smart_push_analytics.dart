import 'dart:math';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import 'mmkv_service.dart';

/// 推送检查结果
class PushCheckResult {
  final bool allowed;
  final String? reason;

  const PushCheckResult({required this.allowed, this.reason});

  static const PushCheckResult ok = PushCheckResult(allowed: true);
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
  static const String _fatigueBudgetKey = 'smart_push_fatigue_budget';
  static const String _lastDismissalKey = 'smart_push_last_dismissal';

  // 配置常量
  static const int maxAppOpenRecords = 200; // 保留最近 200 条打开记录
  static const double dailyFatigueBudget = 10.0; // 每日疲劳预算
  static const int cooldownHoursAfterDismiss = 8; // 忽略后冷却小时数
  static const double explorationRate = 0.1; // ε-Greedy 探索率 (10%)

  // 内容类型成本
  static const Map<String, double> contentTypeCosts = {
    'yearAgoToday': 1.0, // 纪念日，高价值低成本
    'sameTimeOfDay': 1.5,
    'sameLocation': 2.0,
    'sameWeather': 2.0,
    'monthAgoToday': 2.5,
    'randomMemory': 3.0,
    'dailyQuote': 1.5,
  };

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
    } catch (e) {
      AppLogger.w('记录 App 打开时间失败', error: e);
    }
  }

  /// 计算用户响应性热图（24小时分布）
  ///
  /// 返回: Map<hour, score> 其中 score 是该小时的响应性得分 (0.0-1.0)
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
      } catch (_) {}
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
      Map<int, double> heatmap, List<String> records) async {
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
      } catch (_) {}
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

      final List<dynamic> list =
          List<dynamic>.from((jsonStr.split(',').where((s) => s.isNotEmpty)));
      return list.cast<String>();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveAppOpenRecords(List<String> records) async {
    await _mmkv.setString(_appOpenTimesKey, records.join(','));
  }

  // ============================================================
  // 2. 疲劳预防系统
  // ============================================================

  /// 检查是否可以发送推送（基于疲劳预算）
  Future<bool> canSendNotification(String contentType) async {
    // 1. 检查冷却期
    if (await _isInCooldown()) {
      AppLogger.d('用户处于冷却期，跳过推送');
      return false;
    }

    // 2. 检查疲劳预算
    final budget = await _getCurrentBudget();
    final cost = contentTypeCosts[contentType] ?? 3.0;

    if (budget < cost) {
      AppLogger.d('疲劳预算不足: $budget < $cost');
      return false;
    }

    return true;
  }

  /// 消费疲劳预算（发送推送后调用）
  Future<void> consumeBudget(String contentType) async {
    final cost = contentTypeCosts[contentType] ?? 3.0;
    final currentBudget = await _getCurrentBudget();
    final newBudget = (currentBudget - cost).clamp(0.0, dailyFatigueBudget);

    await _saveBudget(newBudget);
    AppLogger.d('消费疲劳预算: $cost, 剩余: $newBudget');
  }

  /// 记录用户忽略/关闭通知（触发冷却期）
  Future<void> recordDismissal() async {
    await _mmkv.setString(_lastDismissalKey, DateTime.now().toIso8601String());
    AppLogger.d('记录通知被忽略，进入冷却期');
  }

  /// 记录用户点击通知（正向反馈）
  Future<void> recordInteraction(String contentType) async {
    // 增加该内容类型的成功计数
    final metrics = await _getNotificationMetrics();
    final key = '${contentType}_success';
    metrics[key] = (metrics[key] ?? 0) + 1;
    await _saveNotificationMetrics(metrics);

    AppLogger.d('记录通知交互: $contentType');
  }

  Future<bool> _isInCooldown() async {
    try {
      final lastDismissal = _mmkv.getString(_lastDismissalKey);
      if (lastDismissal == null || lastDismissal.isEmpty) return false;

      final dismissTime = DateTime.parse(lastDismissal);
      final cooldownEnd =
          dismissTime.add(Duration(hours: cooldownHoursAfterDismiss));

      return DateTime.now().isBefore(cooldownEnd);
    } catch (e) {
      return false;
    }
  }

  Future<double> _getCurrentBudget() async {
    try {
      final data = _mmkv.getString(_fatigueBudgetKey);
      if (data == null || data.isEmpty) return dailyFatigueBudget;

      final parts = data.split('|');
      if (parts.length != 2) return dailyFatigueBudget;

      final date = parts[0];
      final budget = double.tryParse(parts[1]) ?? dailyFatigueBudget;

      // 检查是否是新的一天
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (date != today) {
        // 新的一天，重置预算
        await _saveBudget(dailyFatigueBudget);
        return dailyFatigueBudget;
      }

      return budget;
    } catch (e) {
      return dailyFatigueBudget;
    }
  }

  Future<void> _saveBudget(double budget) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _mmkv.setString(_fatigueBudgetKey, '$today|$budget');
  }

  // ============================================================
  // 3. Thompson Sampling 内容选择
  // ============================================================

  /// 使用 Thompson Sampling 选择最佳内容类型
  ///
  /// 实现 ε-Greedy 策略的探索-利用平衡
  Future<String> selectContentType(List<String> availableTypes) async {
    if (availableTypes.isEmpty) return 'randomMemory';
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

    AppLogger.d('更新内容得分: $contentType = $newScore (${success}/${total})');
  }

  Future<Map<String, double>> _getContentScores() async {
    try {
      final jsonStr = _mmkv.getString(_contentScoresKey);
      if (jsonStr == null || jsonStr.isEmpty) return {};

      final Map<String, double> scores = {};
      for (final pair in jsonStr.split(';')) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          scores[parts[0]] = double.tryParse(parts[1]) ?? 0.5;
        }
      }
      return scores;
    } catch (e) {
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
      for (final pair in jsonStr.split(';')) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          metrics[parts[0]] = int.tryParse(parts[1]) ?? 0;
        }
      }
      return metrics;
    } catch (e) {
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
    for (final type in contentTypeCosts.keys) {
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
      'currentBudget': await _getCurrentBudget(),
      'isInCooldown': await _isInCooldown(),
    };
  }

  /// 重置所有分析数据
  Future<void> resetAnalytics() async {
    await _mmkv.remove(_appOpenTimesKey);
    await _mmkv.remove(_notificationMetricsKey);
    await _mmkv.remove(_contentScoresKey);
    await _mmkv.remove(_fatigueBudgetKey);
    await _mmkv.remove(_lastDismissalKey);
    AppLogger.i('智能推送分析数据已重置');
    notifyListeners();
  }
}
