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
    final rawInsight = json['insight'];
    if (rawInsight is! String || rawInsight.isEmpty) {
      throw const FormatException('Invalid insight in PeriodicInsight JSON');
    }

    final rawCreatedAt = json['createdAt'];
    final parsedCreatedAt =
        rawCreatedAt is String ? DateTime.tryParse(rawCreatedAt) : null;
    if (parsedCreatedAt == null) {
      throw const FormatException('Invalid createdAt in PeriodicInsight JSON');
    }

    final rawPeriodType = json['periodType'];
    if (rawPeriodType != null && rawPeriodType is! String) {
      throw const FormatException('Invalid periodType in PeriodicInsight JSON');
    }

    final rawPeriodLabel = json['periodLabel'];
    if (rawPeriodLabel != null && rawPeriodLabel is! String) {
      throw const FormatException(
        'Invalid periodLabel in PeriodicInsight JSON',
      );
    }

    final rawIsAi = json['isAiGenerated'];
    final bool isAi;
    if (rawIsAi == null) {
      isAi = false;
    } else if (rawIsAi is bool) {
      isAi = rawIsAi;
    } else if (rawIsAi is int) {
      isAi = rawIsAi != 0;
    } else {
      throw const FormatException(
        'Invalid isAiGenerated in PeriodicInsight JSON',
      );
    }

    final rawSignature = json['dataSignature'];
    final String? signature =
        rawSignature is String && rawSignature.isNotEmpty ? rawSignature : null;

    return PeriodicInsight(
      insight: rawInsight,
      periodType: (rawPeriodType as String?) ?? '',
      periodLabel: (rawPeriodLabel as String?) ?? '',
      createdAt: parsedCreatedAt,
      isAiGenerated: isAi,
      dataSignature: signature,
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
    final rawInsight = row['insight'];
    if (rawInsight is! String || rawInsight.isEmpty) {
      throw const FormatException('Invalid insight in periodic_insights row');
    }

    final rawCreatedAt = row['created_at'];
    final parsedCreatedAt =
        rawCreatedAt is String ? DateTime.tryParse(rawCreatedAt) : null;
    if (parsedCreatedAt == null) {
      throw const FormatException(
        'Invalid created_at in periodic_insights row',
      );
    }

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
      insight: rawInsight,
      periodType: row['period_type']?.toString() ?? '',
      periodLabel: row['period_label']?.toString() ?? '',
      createdAt: parsedCreatedAt,
      isAiGenerated: isAi,
      dataSignature: row['data_signature']?.toString(),
    );
  }
}
