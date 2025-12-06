/// 合并报告 - LWW 同步结果统计（扩展版）
///
/// 新增字段：
/// - insertedQuotes / updatedQuotes 区分新增与更新
/// - insertedCategories / updatedCategories 区分类别新增与更新
/// - sameTimestampDiffQuotes 统计时间戳相同但内容不同（冲突保留本地）的条目
///
/// 兼容性：保留 appliedQuotes/appliedCategories 语义（= inserted + updated），
/// 旧代码仍可使用 addAppliedQuote/addAppliedCategory（标记为 @deprecated）。
class MergeReport {
  // 旧统计（兼容）: 应用的笔记与分类（新增 + 更新）
  final int appliedQuotes;
  final int appliedCategories;

  // 新增：细分统计
  final int insertedQuotes; // 新增的笔记
  final int updatedQuotes; // 覆盖/更新的笔记
  final int skippedQuotes; // 因本地较新而跳过的笔记
  final int sameTimestampDiffQuotes; // 时间戳相同但内容不同，被认定冲突且保留本地

  final int insertedCategories; // 新增的分类
  final int updatedCategories; // 更新的分类
  final int skippedCategories; // 跳过的分类

  /// 处理过程中的错误列表（前 N 条，外部可限制长度）
  final List<String> errors;

  /// 处理开始与结束时间
  final DateTime startTime;
  final DateTime? endTime;

  /// 源设备指纹（可选）
  final String? sourceDevice;

  const MergeReport({
    this.appliedQuotes = 0,
    this.appliedCategories = 0,
    this.insertedQuotes = 0,
    this.updatedQuotes = 0,
    this.skippedQuotes = 0,
    this.sameTimestampDiffQuotes = 0,
    this.insertedCategories = 0,
    this.updatedCategories = 0,
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

  /// 添加：新增笔记
  MergeReport addInsertedQuote() {
    return copyWith(
      insertedQuotes: insertedQuotes + 1,
      appliedQuotes: appliedQuotes + 1,
    );
  }

  /// 添加：更新笔记
  MergeReport addUpdatedQuote() {
    return copyWith(
      updatedQuotes: updatedQuotes + 1,
      appliedQuotes: appliedQuotes + 1,
    );
  }

  /// 添加：跳过笔记
  MergeReport addSkippedQuote() {
    return copyWith(skippedQuotes: skippedQuotes + 1);
  }

  /// 添加：时间戳相同但内容不同冲突笔记（保留本地）
  MergeReport addSameTimestampDiffQuote() {
    return copyWith(sameTimestampDiffQuotes: sameTimestampDiffQuotes + 1);
  }

  /// 添加：新增分类
  MergeReport addInsertedCategory() {
    return copyWith(
      insertedCategories: insertedCategories + 1,
      appliedCategories: appliedCategories + 1,
    );
  }

  /// 添加：更新分类
  MergeReport addUpdatedCategory() {
    return copyWith(
      updatedCategories: updatedCategories + 1,
      appliedCategories: appliedCategories + 1,
    );
  }

  /// 添加：跳过分类
  MergeReport addSkippedCategory() {
    return copyWith(skippedCategories: skippedCategories + 1);
  }

  /// 兼容旧API：添加成功应用的笔记（默认视为更新）
  @Deprecated(
    'Use addInsertedQuote or addUpdatedQuote; this wrapper will be removed',
  )
  MergeReport addAppliedQuote() => addUpdatedQuote();

  /// 兼容旧API：添加成功应用的分类（默认视为更新）
  @Deprecated(
    'Use addInsertedCategory or addUpdatedCategory; this wrapper will be removed',
  )
  MergeReport addAppliedCategory() => addUpdatedCategory();

  /// 添加错误信息
  MergeReport addError(String error) {
    return copyWith(errors: [...errors, error]);
  }

  /// 复制并修改
  MergeReport copyWith({
    int? appliedQuotes,
    int? insertedQuotes,
    int? updatedQuotes,
    int? skippedQuotes,
    int? sameTimestampDiffQuotes,
    int? appliedCategories,
    int? insertedCategories,
    int? updatedCategories,
    int? skippedCategories,
    List<String>? errors,
    DateTime? startTime,
    DateTime? endTime,
    String? sourceDevice,
  }) {
    return MergeReport(
      appliedQuotes: appliedQuotes ?? this.appliedQuotes,
      insertedQuotes: insertedQuotes ?? this.insertedQuotes,
      updatedQuotes: updatedQuotes ?? this.updatedQuotes,
      skippedQuotes: skippedQuotes ?? this.skippedQuotes,
      sameTimestampDiffQuotes:
          sameTimestampDiffQuotes ?? this.sameTimestampDiffQuotes,
      appliedCategories: appliedCategories ?? this.appliedCategories,
      insertedCategories: insertedCategories ?? this.insertedCategories,
      updatedCategories: updatedCategories ?? this.updatedCategories,
      skippedCategories: skippedCategories ?? this.skippedCategories,
      errors: errors ?? this.errors,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sourceDevice: sourceDevice ?? this.sourceDevice,
    );
  }

  /// 总处理笔记（不含分类）
  int get totalProcessedQuotes =>
      appliedQuotes + skippedQuotes + sameTimestampDiffQuotes;

  /// 总处理分类
  int get totalProcessedCategories => appliedCategories + skippedCategories;

  /// 总成功数（笔记+分类）
  int get totalApplied => appliedQuotes + appliedCategories;

  /// 总跳过数（笔记+分类，不含冲突）
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

    if (insertedQuotes > 0) parts.add('新增 $insertedQuotes');
    if (updatedQuotes > 0) parts.add('更新 $updatedQuotes');
    if (skippedQuotes > 0) {
      parts.add('跳过 $skippedQuotes 条笔记');
    }
    if (sameTimestampDiffQuotes > 0) {
      parts.add('冲突(同时间不同内容) $sameTimestampDiffQuotes');
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

    buffer.writeln('笔记统计:');
    buffer.writeln('  新增: $insertedQuotes');
    buffer.writeln('  更新: $updatedQuotes');
    buffer.writeln('  跳过: $skippedQuotes');
    buffer.writeln('  冲突(同时间不同内容保留本地): $sameTimestampDiffQuotes');
    buffer.writeln('');

    buffer.writeln('分类统计:');
    buffer.writeln('  新增: $insertedCategories');
    buffer.writeln('  更新: $updatedCategories');
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
      'insertedQuotes': insertedQuotes,
      'updatedQuotes': updatedQuotes,
      'skippedQuotes': skippedQuotes,
      'sameTimestampDiffQuotes': sameTimestampDiffQuotes,
      'appliedCategories': appliedCategories,
      'insertedCategories': insertedCategories,
      'updatedCategories': updatedCategories,
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
  int _appliedQuotes = 0; // 兼容旧逻辑
  int _insertedQuotes = 0;
  int _updatedQuotes = 0;
  int _sameTimestampDiffQuotes = 0;
  int _skippedQuotes = 0;

  int _appliedCategories = 0; // 兼容旧逻辑
  int _insertedCategories = 0;
  int _updatedCategories = 0;
  int _skippedCategories = 0;
  final List<String> _errors = [];

  final DateTime _startTime;
  final String? _sourceDevice;

  MergeReportBuilder({String? sourceDevice})
      : _startTime = DateTime.now(),
        _sourceDevice = sourceDevice;

  // 兼容旧方法（默认视为更新）
  void addAppliedQuote() => addUpdatedQuote();
  void addAppliedCategory() => addUpdatedCategory();

  // 新增细分方法
  void addInsertedQuote() {
    _insertedQuotes++;
    _appliedQuotes++;
  }

  void addUpdatedQuote() {
    _updatedQuotes++;
    _appliedQuotes++;
  }

  void addSameTimestampDiffQuote() {
    _sameTimestampDiffQuotes++;
  }

  void addSkippedQuote() => _skippedQuotes++;

  void addInsertedCategory() {
    _insertedCategories++;
    _appliedCategories++;
  }

  void addUpdatedCategory() {
    _updatedCategories++;
    _appliedCategories++;
  }

  void addSkippedCategory() => _skippedCategories++;

  // 添加错误
  void addError(String error) => _errors.add(error);

  /// 构建最终报告
  MergeReport build() {
    return MergeReport(
      appliedQuotes: _appliedQuotes,
      insertedQuotes: _insertedQuotes,
      updatedQuotes: _updatedQuotes,
      skippedQuotes: _skippedQuotes,
      sameTimestampDiffQuotes: _sameTimestampDiffQuotes,
      appliedCategories: _appliedCategories,
      insertedCategories: _insertedCategories,
      updatedCategories: _updatedCategories,
      skippedCategories: _skippedCategories,
      errors: List.unmodifiable(_errors),
      startTime: _startTime,
      endTime: DateTime.now(),
      sourceDevice: _sourceDevice,
    );
  }
}
