/// 合并报告 - 用于LWW同步的结果统计
///
/// 简化版本：只关注覆盖(applied)、跳过(skipped)、错误(errors)
class MergeReport {
  /// 成功应用的笔记数量（新增或覆盖）
  final int appliedQuotes;

  /// 因本地较新而跳过的笔记数量
  final int skippedQuotes;

  /// 成功应用的分类数量
  final int appliedCategories;

  /// 跳过的分类数量
  final int skippedCategories;

  /// 处理过程中的错误列表
  final List<String> errors;

  /// 处理开始时间
  final DateTime startTime;

  /// 处理结束时间
  final DateTime? endTime;

  /// 设备指纹（用于审计）
  final String? sourceDevice;

  const MergeReport({
    this.appliedQuotes = 0,
    this.skippedQuotes = 0,
    this.appliedCategories = 0,
    this.skippedCategories = 0,
    this.errors = const [],
    required this.startTime,
    this.endTime,
    this.sourceDevice,
  });

  /// 创建空的初始报告
  factory MergeReport.start({String? sourceDevice}) {
    return MergeReport(startTime: DateTime.now(), sourceDevice: sourceDevice);
  }

  /// 完成处理，设置结束时间
  MergeReport completed() {
    return copyWith(endTime: DateTime.now());
  }

  /// 添加成功应用的笔记
  MergeReport addAppliedQuote() {
    return copyWith(appliedQuotes: appliedQuotes + 1);
  }

  /// 添加跳过的笔记
  MergeReport addSkippedQuote() {
    return copyWith(skippedQuotes: skippedQuotes + 1);
  }

  /// 添加成功应用的分类
  MergeReport addAppliedCategory() {
    return copyWith(appliedCategories: appliedCategories + 1);
  }

  /// 添加跳过的分类
  MergeReport addSkippedCategory() {
    return copyWith(skippedCategories: skippedCategories + 1);
  }

  /// 添加错误信息
  MergeReport addError(String error) {
    return copyWith(errors: [...errors, error]);
  }

  /// 复制并修改
  MergeReport copyWith({
    int? appliedQuotes,
    int? skippedQuotes,
    int? appliedCategories,
    int? skippedCategories,
    List<String>? errors,
    DateTime? startTime,
    DateTime? endTime,
    String? sourceDevice,
  }) {
    return MergeReport(
      appliedQuotes: appliedQuotes ?? this.appliedQuotes,
      skippedQuotes: skippedQuotes ?? this.skippedQuotes,
      appliedCategories: appliedCategories ?? this.appliedCategories,
      skippedCategories: skippedCategories ?? this.skippedCategories,
      errors: errors ?? this.errors,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sourceDevice: sourceDevice ?? this.sourceDevice,
    );
  }

  /// 总处理项目数
  int get totalProcessed => appliedQuotes + skippedQuotes;

  /// 总成功数
  int get totalApplied => appliedQuotes + appliedCategories;

  /// 总跳过数
  int get totalSkipped => skippedQuotes + skippedCategories;

  /// 是否有错误
  bool get hasErrors => errors.isNotEmpty;

  /// 处理耗时（毫秒）
  int get durationMs {
    if (endTime == null) return 0;
    return endTime!.difference(startTime).inMilliseconds;
  }

  /// 生成简洁的摘要文本
  String get summary {
    final parts = <String>[];

    if (appliedQuotes > 0) {
      parts.add('应用 $appliedQuotes 条笔记');
    }
    if (skippedQuotes > 0) {
      parts.add('跳过 $skippedQuotes 条笔记');
    }
    if (appliedCategories > 0) {
      parts.add('应用 $appliedCategories 个分类');
    }
    if (hasErrors) {
      parts.add('${errors.length} 个错误');
    }

    if (parts.isEmpty) {
      return '无变更';
    }

    return parts.join('，');
  }

  /// 生成详细日志信息
  String get detailedLog {
    final buffer = StringBuffer();
    buffer.writeln('=== 合并报告 ===');
    buffer.writeln('开始时间: ${startTime.toIso8601String()}');
    if (endTime != null) {
      buffer.writeln('结束时间: ${endTime!.toIso8601String()}');
      buffer.writeln('耗时: ${durationMs}ms');
    }
    if (sourceDevice != null) {
      buffer.writeln('源设备: $sourceDevice');
    }
    buffer.writeln('');

    buffer.writeln('笔记处理:');
    buffer.writeln('  应用: $appliedQuotes');
    buffer.writeln('  跳过: $skippedQuotes');
    buffer.writeln('');

    buffer.writeln('分类处理:');
    buffer.writeln('  应用: $appliedCategories');
    buffer.writeln('  跳过: $skippedCategories');
    buffer.writeln('');

    if (hasErrors) {
      buffer.writeln('错误列表:');
      for (int i = 0; i < errors.length; i++) {
        buffer.writeln('  ${i + 1}. ${errors[i]}');
      }
    }

    return buffer.toString();
  }

  @override
  String toString() {
    return 'MergeReport($summary, 耗时: ${durationMs}ms)';
  }

  /// 转换为JSON（用于日志记录）
  Map<String, dynamic> toJson() {
    return {
      'appliedQuotes': appliedQuotes,
      'skippedQuotes': skippedQuotes,
      'appliedCategories': appliedCategories,
      'skippedCategories': skippedCategories,
      'errors': errors,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'sourceDevice': sourceDevice,
      'durationMs': durationMs,
    };
  }
}

/// 可变的合并报告构建器，用于在合并过程中累积统计信息
class MergeReportBuilder {
  int _appliedQuotes = 0;
  int _skippedQuotes = 0;
  int _appliedCategories = 0;
  int _skippedCategories = 0;
  final List<String> _errors = [];

  final DateTime _startTime;
  final String? _sourceDevice;

  MergeReportBuilder({String? sourceDevice})
    : _startTime = DateTime.now(),
      _sourceDevice = sourceDevice;

  // 笔记操作统计
  void addAppliedQuote() => _appliedQuotes++;
  void addSkippedQuote() => _skippedQuotes++;

  // 分类操作统计
  void addAppliedCategory() => _appliedCategories++;
  void addSkippedCategory() => _skippedCategories++;

  // 添加错误
  void addError(String error) => _errors.add(error);

  /// 构建最终报告
  MergeReport build() {
    return MergeReport(
      appliedQuotes: _appliedQuotes,
      skippedQuotes: _skippedQuotes,
      appliedCategories: _appliedCategories,
      skippedCategories: _skippedCategories,
      errors: List.unmodifiable(_errors),
      startTime: _startTime,
      endTime: DateTime.now(),
      sourceDevice: _sourceDevice,
    );
  }
}
