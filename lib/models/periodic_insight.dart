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

  Map<String, Object?> toDbMap() {
    return {
      'insight': insight,
      'period_type': periodType,
      'period_label': periodLabel,
      'created_at': createdAt.toIso8601String(),
      'is_ai_generated': isAiGenerated ? 1 : 0,
      'data_signature': dataSignature,
    };
  }

  static PeriodicInsight fromDbMap(Map<String, Object?> row) {
    final rawIsAi = row['is_ai_generated'];
    final bool isAi;
    if (rawIsAi is int) {
      isAi = rawIsAi != 0;
    } else if (rawIsAi is bool) {
      isAi = rawIsAi;
    } else {
      isAi = false;
    }

    return PeriodicInsight(
      insight: row['insight']?.toString() ?? '',
      periodType: row['period_type']?.toString() ?? '',
      periodLabel: row['period_label']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isAiGenerated: isAi,
      dataSignature: row['data_signature']?.toString(),
    );
  }
}
