import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'settings_service.dart';

/// 周期洞察记录
class PeriodicInsight {
  final String insight;
  final String periodType; // 'week', 'month', 'year'
  final String periodLabel; // '本周', '本月', '2024年'
  final DateTime createdAt;
  final bool isAiGenerated; // 区分AI生成和本地生成
  final String? dataSignature; // 数据签名，用于去重

  PeriodicInsight({
    required this.insight,
    required this.periodType,
    required this.periodLabel,
    required this.createdAt,
    required this.isAiGenerated,
    this.dataSignature,
  });

  Map<String, dynamic> toJson() {
    return {
      'insight': insight,
      'periodType': periodType,
      'periodLabel': periodLabel,
      'createdAt': createdAt.toIso8601String(),
      'isAiGenerated': isAiGenerated,
      if (dataSignature != null) 'dataSignature': dataSignature,
    };
  }

  static PeriodicInsight fromJson(Map<String, dynamic> json) {
    return PeriodicInsight(
      insight: json['insight'] ?? '',
      periodType: json['periodType'] ?? '',
      periodLabel: json['periodLabel'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      isAiGenerated: json['isAiGenerated'] ?? false,
      dataSignature: json['dataSignature'],
    );
  }
}

/// 周期洞察历史服务
/// 专门用于保存和管理周期报告中AI生成的洞察
class InsightHistoryService extends ChangeNotifier {
  static const String _storageKey = 'periodic_insights_history';
  static const int _maxInsights = 50; // 最多保存50条洞察

  final SettingsService _settingsService;
  List<PeriodicInsight> _insights = [];

  InsightHistoryService({required SettingsService settingsService})
      : _settingsService = settingsService {
    _loadInsights();
  }

  List<PeriodicInsight> get insights => List.unmodifiable(_insights);

  /// 加载已保存的洞察
  Future<void> _loadInsights() async {
    try {
      final jsonString = await _settingsService.getCustomString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _insights =
            jsonList.map((json) => PeriodicInsight.fromJson(json)).toList();

        // 按时间倒序排列
        _insights.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载洞察历史失败: $e');
      _insights = [];
    }
  }

  /// 保存洞察到历史记录
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

      final newInsight = PeriodicInsight(
        insight: insight,
        periodType: periodType,
        periodLabel: periodLabel,
        createdAt: DateTime.now(),
        isAiGenerated: isAiGenerated,
        dataSignature: dataSignature,
      );

      _insights.insert(0, newInsight);

      // 限制数量
      if (_insights.length > _maxInsights) {
        _insights = _insights.take(_maxInsights).toList();
      }

      await _saveInsights();
      notifyListeners();
    } catch (e) {
      debugPrint('保存洞察失败: $e');
    }
  }

  /// 保存到存储
  Future<void> _saveInsights() async {
    try {
      final jsonList = _insights.map((insight) => insight.toJson()).toList();
      final jsonString = json.encode(jsonList);
      await _settingsService.setCustomString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('保存洞察到存储失败: $e');
    }
  }

  /// 根据数据签名获取洞察
  PeriodicInsight? getInsightBySignature(String signature) {
    try {
      return _insights
          .firstWhere((insight) => insight.dataSignature == signature);
    } catch (e) {
      return null;
    }
  }

  /// 获取历史洞察上下文（用于AI分析）
  /// 仅返回最近的 [limit] 条**周报(week)**洞察，以避免无效数据干扰
  String getPreviousInsightsContext({int limit = 3}) {
    if (_insights.isEmpty) return '';

    // 过滤出AI生成的周报洞察
    final weeklyInsights = _insights
        .where((i) => i.isAiGenerated && i.periodType == 'week')
        .take(limit)
        .toList();

    if (weeklyInsights.isEmpty) return '';

    final buffer = StringBuffer();
    // 移除这行重复的标题，因为 AIPromptManager 已经添加了【历史洞察参考】标题
    // buffer.writeln('【历史洞察参考】');
    // buffer.writeln('以下是该用户之前的周期性洞察记录，可帮助你了解其长期思考模式：');

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
    // 确保已加载数据
    if (_insights.isEmpty) {
      await _loadInsights();
    }

    final recentInsight = getRecentPeriodInsight();
    return formatInsightForPrompt(recentInsight);
  }

  /// 清除过期的洞察（超过3个月）
  Future<void> cleanOldInsights() async {
    final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
    final originalLength = _insights.length;

    _insights.removeWhere(
      (insight) => insight.createdAt.isBefore(threeMonthsAgo),
    );

    if (_insights.length != originalLength) {
      await _saveInsights();
      notifyListeners();
    }
  }
}
