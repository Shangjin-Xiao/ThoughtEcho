import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/periodic_insight.dart';
import '../utils/app_logger.dart';
import '../utils/mmkv_ffi_fix.dart' show kPeriodicInsightsSqliteMigratedKey;
import 'ai_analysis_database_service.dart';
import 'app_preferences_service.dart';
import 'settings_service.dart';

export '../models/periodic_insight.dart';

/// 周期洞察历史服务
/// 专门用于保存和管理周期报告中AI生成的洞察（持久化于 `ai_analyses.db` 的 `periodic_insights` 表）
class InsightHistoryService extends ChangeNotifier {
  static const String _storageKey = 'periodic_insights_history';
  static const int _maxInsights = 50; // 最多保存50条洞察

  SettingsService _settingsService;
  AIAnalysisDatabaseService _aiAnalysisDbService;
  List<PeriodicInsight> _insights = [];
  Future<void>? _loadFuture;

  SettingsService get settingsService => _settingsService;
  AIAnalysisDatabaseService get aiAnalysisDbService => _aiAnalysisDbService;

  /// 原位更新依赖引用（SettingsService / AIAnalysisDatabaseService）。
  ///
  /// 同步且幂等，不触发额外的 notifyListeners()。
  void updateDependencies({
    required SettingsService settingsService,
    AIAnalysisDatabaseService? aiAnalysisDbService,
  }) {
    _settingsService = settingsService;
    if (aiAnalysisDbService != null) {
      _aiAnalysisDbService = aiAnalysisDbService;
    }
  }

  /// 一条 AI 洞察成功落库后触发的后台归纳。
  ///
  /// 用回调而不是直接依赖 DreamingService：洞察历史不该知道记忆库的存在，
  /// 反过来注入也会绕成一个环（DreamingService 要 AIService，AIService 要
  /// 记忆库）。由 Provider 装配时把这根线接上。
  Future<void> Function()? onAiInsightPersisted;

  InsightHistoryService({
    required SettingsService settingsService,
    AIAnalysisDatabaseService? aiAnalysisDbService,
  })  : _settingsService = settingsService,
        _aiAnalysisDbService =
            aiAnalysisDbService ?? AIAnalysisDatabaseService() {
    _loadFuture = _loadInsights();
  }

  List<PeriodicInsight> get insights => List.unmodifiable(_insights);

  /// 确保首次加载与历史 KV 迁移已完成。
  Future<void> ensureLoaded() async {
    await (_loadFuture ??= _loadInsights());
  }

  /// 加载已保存的洞察（必要时先完成一次历史 KV 到 SQLite 的幂等迁移）
  Future<void> _loadInsights() async {
    try {
      await _migrateLegacyKvIfNeeded();
      final loaded = await _aiAnalysisDbService.getPeriodicInsights(
        limit: _maxInsights,
      );
      _insights = List<PeriodicInsight>.from(loaded);
      // 确保内存列表严格按时间倒序排列
      _insights.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e, stack) {
      AppLogger.e(
        '加载洞察历史失败',
        error: e,
        stackTrace: stack,
        source: 'InsightHistoryService',
      );
      _insights = [];
    } finally {
      notifyListeners();
    }
  }

  Future<void> _migrateLegacyKvIfNeeded() async {
    final prefs = AppPreferencesService();
    var prefsReady = false;
    try {
      await prefs.init();
      prefsReady = true;
      if (prefs.getBool(kPeriodicInsightsSqliteMigratedKey) == true) {
        return;
      }
    } catch (e) {
      // 无 SharedPreferences mock 的精简组件测试会走到这里，继续通过 SettingsService 检查
      AppLogger.w(
        '检查周期洞察迁移标记失败: $e',
        source: 'InsightHistoryService',
      );
    }

    final jsonString = await _settingsService.getCustomString(_storageKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      final dynamic decoded = json.decode(jsonString);
      if (decoded is List && decoded.isNotEmpty) {
        final legacyItems = decoded
            .whereType<Map>()
            .map(
              (item) => PeriodicInsight.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList(growable: false);
        if (legacyItems.isNotEmpty) {
          await _aiAnalysisDbService.importPeriodicInsights(
            legacyItems,
            maxRetention: _maxInsights,
          );
        }
      }
      await _removeLegacyStorageKey(prefs, prefsReady);
    }

    if (prefsReady) {
      await prefs.setBool(kPeriodicInsightsSqliteMigratedKey, true);
    }
  }

  Future<void> _removeLegacyStorageKey(
    AppPreferencesService prefs,
    bool prefsReady,
  ) async {
    if (prefsReady) {
      await prefs.remove(_storageKey);
      return;
    }
    await _settingsService.removeCustomKey(_storageKey);
  }

  /// 保存洞察到历史记录
  ///
  /// 同一个 [dataSignature] 只留最新的一条：签名相同就是同一份数据生成的
  /// 同一条洞察，原来每次生成都无脑 insert，重复能攒到几十条，把 50 条的
  /// 上限吃光，真正有用的历史反而被自己的副本顶掉，getPreviousInsightsContext
  /// 取到的「最近三条」也可能全是同一周的复读。
  Future<void> addInsight({
    required String insight,
    required String periodType,
    required String periodLabel,
    bool isAiGenerated = true,
    String? dataSignature,
  }) async {
    try {
      // 只保存AI生成的洞察
      if (!isAiGenerated) return;

      await ensureLoaded();

      final newInsight = PeriodicInsight(
        insight: insight,
        periodType: periodType,
        periodLabel: periodLabel,
        createdAt: DateTime.now(),
        isAiGenerated: isAiGenerated,
        dataSignature: dataSignature,
      );

      // 先落库持久化，成功后再更新内存列表并通知监听器
      await _aiAnalysisDbService.savePeriodicInsight(
        newInsight,
        maxRetention: _maxInsights,
      );

      if (dataSignature != null && dataSignature.isNotEmpty) {
        _insights.removeWhere((i) => i.dataSignature == dataSignature);
      }
      _insights.insert(0, newInsight);

      // 限制数量
      if (_insights.length > _maxInsights) {
        _insights = _insights.take(_maxInsights).toList();
      }

      notifyListeners();
      _triggerBackgroundConsolidation();
    } catch (e, stack) {
      AppLogger.e(
        '保存洞察失败',
        error: e,
        stackTrace: stack,
        source: 'InsightHistoryService',
      );
    }
  }

  /// 触发后台归纳，**不等它跑完**。
  ///
  /// 这里是唯一正确的挂载点：它是服务不是页面 State，上面已经过滤掉
  /// `isAiGenerated == false`（本地兜底文案不该触发归纳——那时模型根本没跑），
  /// 且每条 AI 洞察成功落库恰好触发一次。
  ///
  /// 归纳失败一律吞掉：它是增益，绝不能让一次后台失败影响到洞察本身已经
  /// 保存成功这件事，更不能冒泡成用户可见的错误。
  void _triggerBackgroundConsolidation() {
    final callback = onAiInsightPersisted;
    if (callback == null) return;
    unawaited(
      callback().catchError((Object error, StackTrace stack) {
        AppLogger.w(
          '后台归纳触发失败（${error.runtimeType}），本轮跳过',
          source: 'InsightHistoryService',
        );
      }),
    );
  }

  /// 根据数据签名获取洞察
  ///
  /// 只认 AI 生成的：本地兜底文本不该在下次进来时冒充缓存好的 AI 洞察。
  PeriodicInsight? getInsightBySignature(String signature) {
    if (signature.isEmpty) return null;
    for (final insight in _insights) {
      if (insight.isAiGenerated && insight.dataSignature == signature) {
        return insight;
      }
    }
    return null;
  }

  /// 获取历史洞察上下文（用于AI分析）
  /// 仅返回最近的 [limit] 条**周报(week)**洞察，以避免无效数据干扰
  String getPreviousInsightsContext({int limit = 3}) {
    if (_insights.isEmpty) return '';

    // 过滤出AI生成的周报洞察。同一个周期只取一条：把同一周的多条历史一起
    // 喂回去，模型就是在参考自己刚写过的东西，越写越同质。
    //
    // 按周期去重，不按签名：签名里带了模型和提示词版本，同一周换个模型重算
    // 就是另一个签名，两版会一起进上下文，模型收到同一周的多个说法。老数据
    // 那时每一周都存成「本周」，靠标签折叠正好把那批重复也收在一起。
    // _insights 是按时间倒序的，所以每个周期留下的是最新那条。
    final seenPeriods = <String>{};
    final weeklyInsights = _insights
        .where((i) => i.isAiGenerated && i.periodType == 'week')
        .where((i) => seenPeriods.add('${i.periodType}:${i.periodLabel}'))
        .take(limit)
        .toList();

    if (weeklyInsights.isEmpty) return '';

    final buffer = StringBuffer();
    // 直接输出内容，让 PromptManager 统一控制标题格式
    for (var i = 0; i < weeklyInsights.length; i++) {
      final insight = weeklyInsights[i];
      // 简化格式，只保留内容，因为 PromptManager 会包裹它
      buffer.writeln('- [${insight.periodLabel}] ${insight.insight}');
    }

    return buffer.toString();
  }

  /// 获取最近的周期洞察（本周、上周、本月、上月）用于今日思考
  String? getRecentPeriodInsight() {
    if (_insights.isEmpty) return null;

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = DateTime(now.year, now.month - 1, now.day);

    // 查找最近的周期洞察
    for (final insight in _insights) {
      if (!insight.isAiGenerated) continue;

      // 检查是否是最近的周期（本周、上周、本月、上月）
      if (insight.createdAt.isAfter(monthAgo)) {
        // 优先返回周期类型为week或month的洞察
        if (insight.periodType == 'week' || insight.periodType == 'month') {
          return insight.insight;
        }
      }
    }

    // 如果没有找到周或月的洞察，返回最近的任何AI洞察
    final recentAiInsight = _insights
        .where(
          (insight) =>
              insight.isAiGenerated && insight.createdAt.isAfter(weekAgo),
        )
        .firstOrNull;

    return recentAiInsight?.insight;
  }

  /// 格式化历史洞察用于提示词
  String formatInsightForPrompt(String? insight) {
    if (insight == null || insight.isEmpty) {
      return '';
    }

    return '''

【参考洞察】
你可以选择性地参考这句最近生成的周期洞察：
"$insight"

注意：这句话是基于用户最近一段时间的笔记生成的洞察，你可以作为了解用户思考模式的参考，但不必直接引用。''';
  }

  /// 为今日思考提示词格式化最近洞察
  Future<String> formatRecentInsightsForDailyPrompt() async {
    await ensureLoaded();

    final recentInsight = getRecentPeriodInsight();
    return formatInsightForPrompt(recentInsight);
  }

  /// 清除过期的洞察（超过3个月）
  Future<void> cleanOldInsights() async {
    try {
      await ensureLoaded();
      final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
      final deletedCount = await _aiAnalysisDbService
          .deletePeriodicInsightsOlderThan(threeMonthsAgo);
      final originalLength = _insights.length;

      _insights.removeWhere(
        (insight) => insight.createdAt.isBefore(threeMonthsAgo),
      );

      if (deletedCount > 0 || _insights.length != originalLength) {
        notifyListeners();
      }
    } catch (e, stack) {
      AppLogger.e(
        '清理过期洞察失败',
        error: e,
        stackTrace: stack,
        source: 'InsightHistoryService',
      );
    }
  }
}
