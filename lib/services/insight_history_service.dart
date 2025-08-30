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

  PeriodicInsight({
    required this.insight,
    required this.periodType,
    required this.periodLabel,
    required this.createdAt,
    required this.isAiGenerated,
  });

  Map<String, dynamic> toJson() {
    return {
      'insight': insight,
      'periodType': periodType,
      'periodLabel': periodLabel,
      'createdAt': createdAt.toIso8601String(),
      'isAiGenerated': isAiGenerated,
    };
  }

  static PeriodicInsight fromJson(Map<String, dynamic> json) {
    return PeriodicInsight(
      insight: json['insight'] ?? '',
      periodType: json['periodType'] ?? '',
      periodLabel: json['periodLabel'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      isAiGenerated: json['isAiGenerated'] ?? false,
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
        .where((insight) =>
            insight.isAiGenerated && insight.createdAt.isAfter(weekAgo))
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

    _insights
        .removeWhere((insight) => insight.createdAt.isBefore(threeMonthsAgo));

    if (_insights.length != originalLength) {
      await _saveInsights();
      notifyListeners();
    }
  }
}
