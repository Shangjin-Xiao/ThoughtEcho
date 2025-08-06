/// 合并报告数据模型
/// 
/// 记录在备份导入时的详细合并统计信息，包括插入、更新、跳过的条目数量，
/// 以及遇到的警告和错误信息。用于向用户提供透明的合并反馈。
class MergeReport {
  // 笔记相关统计
  final int insertedQuotes;
  final int updatedQuotes;
  final int skippedQuotes;
  
  // 分类和标签统计
  final int insertedCategories;
  final int updatedCategories;
  final int skippedCategories;
  final int insertedTags;
  final int updatedTags;
  final int skippedTags;
  
  // 媒体文件统计
  final int mediaCopied;
  final int mediaOverwritten;
  final int mediaSkipped;
  
  // 冲突和特殊情况
  final int sameTimestampConflicts; // 时间戳相同但内容不同的冲突
  final int timestampParseErrors;   // 时间戳解析失败的条目
  final int missingDependencies;    // 缺少依赖（如分类、标签）的笔记
  
  // 性能指标
  final Duration processingTime;
  final int totalProcessedItems;
  
  // 时钟偏移检测
  final bool clockSkewDetected;
  final Duration? estimatedClockSkew;
  
  // 错误和警告信息
  final List<String> warnings;
  final List<String> errors;
  final List<ConflictInfo> conflicts;

  const MergeReport({
    this.insertedQuotes = 0,
    this.updatedQuotes = 0,
    this.skippedQuotes = 0,
    this.insertedCategories = 0,
    this.updatedCategories = 0,
    this.skippedCategories = 0,
    this.insertedTags = 0,
    this.updatedTags = 0,
    this.skippedTags = 0,
    this.mediaCopied = 0,
    this.mediaOverwritten = 0,
    this.mediaSkipped = 0,
    this.sameTimestampConflicts = 0,
    this.timestampParseErrors = 0,
    this.missingDependencies = 0,
    this.processingTime = Duration.zero,
    this.totalProcessedItems = 0,
    this.clockSkewDetected = false,
    this.estimatedClockSkew,
    this.warnings = const [],
    this.errors = const [],
    this.conflicts = const [],
  });

  factory MergeReport.empty() => const MergeReport();

  /// 获取总的笔记操作数量
  int get totalQuoteOperations => insertedQuotes + updatedQuotes + skippedQuotes;
  
  /// 获取总的分类操作数量
  int get totalCategoryOperations => insertedCategories + updatedCategories + skippedCategories;
  
  /// 获取总的标签操作数量
  int get totalTagOperations => insertedTags + updatedTags + skippedTags;
  
  /// 获取总的媒体文件操作数量
  int get totalMediaOperations => mediaCopied + mediaOverwritten + mediaSkipped;
  
  /// 检查是否有任何错误
  bool get hasErrors => errors.isNotEmpty;
  
  /// 检查是否有任何警告
  bool get hasWarnings => warnings.isNotEmpty || clockSkewDetected || conflicts.isNotEmpty;
  
  /// 检查是否成功（无错误）
  bool get isSuccessful => !hasErrors;
  
  /// 获取处理速度（条目/秒）
  double get processingRate {
    if (processingTime.inMilliseconds == 0) return 0;
    return totalProcessedItems / (processingTime.inMilliseconds / 1000.0);
  }

  /// 复制并更新部分字段
  MergeReport copyWith({
    int? insertedQuotes,
    int? updatedQuotes,
    int? skippedQuotes,
    int? insertedCategories,
    int? updatedCategories,
    int? skippedCategories,
    int? insertedTags,
    int? updatedTags,
    int? skippedTags,
    int? mediaCopied,
    int? mediaOverwritten,
    int? mediaSkipped,
    int? sameTimestampConflicts,
    int? timestampParseErrors,
    int? missingDependencies,
    Duration? processingTime,
    int? totalProcessedItems,
    bool? clockSkewDetected,
    Duration? estimatedClockSkew,
    List<String>? warnings,
    List<String>? errors,
    List<ConflictInfo>? conflicts,
  }) {
    return MergeReport(
      insertedQuotes: insertedQuotes ?? this.insertedQuotes,
      updatedQuotes: updatedQuotes ?? this.updatedQuotes,
      skippedQuotes: skippedQuotes ?? this.skippedQuotes,
      insertedCategories: insertedCategories ?? this.insertedCategories,
      updatedCategories: updatedCategories ?? this.updatedCategories,
      skippedCategories: skippedCategories ?? this.skippedCategories,
      insertedTags: insertedTags ?? this.insertedTags,
      updatedTags: updatedTags ?? this.updatedTags,
      skippedTags: skippedTags ?? this.skippedTags,
      mediaCopied: mediaCopied ?? this.mediaCopied,
      mediaOverwritten: mediaOverwritten ?? this.mediaOverwritten,
      mediaSkipped: mediaSkipped ?? this.mediaSkipped,
      sameTimestampConflicts: sameTimestampConflicts ?? this.sameTimestampConflicts,
      timestampParseErrors: timestampParseErrors ?? this.timestampParseErrors,
      missingDependencies: missingDependencies ?? this.missingDependencies,
      processingTime: processingTime ?? this.processingTime,
      totalProcessedItems: totalProcessedItems ?? this.totalProcessedItems,
      clockSkewDetected: clockSkewDetected ?? this.clockSkewDetected,
      estimatedClockSkew: estimatedClockSkew ?? this.estimatedClockSkew,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
      conflicts: conflicts ?? this.conflicts,
    );
  }

  /// 生成简洁的摘要文本
  String get summary {
    final parts = <String>[];
    
    if (totalQuoteOperations > 0) {
      parts.add('笔记: 新增$insertedQuotes, 更新$updatedQuotes, 跳过$skippedQuotes');
    }
    
    if (totalCategoryOperations > 0) {
      parts.add('分类: 新增$insertedCategories, 更新$updatedCategories, 跳过$skippedCategories');
    }
    
    if (totalTagOperations > 0) {
      parts.add('标签: 新增$insertedTags, 更新$updatedTags, 跳过$skippedTags');
    }
    
    if (totalMediaOperations > 0) {
      parts.add('媒体: 复制$mediaCopied, 覆盖$mediaOverwritten, 跳过$mediaSkipped');
    }
    
    if (parts.isEmpty) {
      return '未处理任何数据';
    }
    
    return parts.join('\n');
  }

  /// 生成详细的报告文本
  String get detailedReport {
    final buffer = StringBuffer();
    
    buffer.writeln('=== 合并报告 ===');
    buffer.writeln('处理时间: ${processingTime.inMilliseconds}ms');
    buffer.writeln('处理速度: ${processingRate.toStringAsFixed(1)} 条目/秒');
    buffer.writeln();
    
    buffer.writeln(summary);
    
    if (sameTimestampConflicts > 0) {
      buffer.writeln('\n⚠️ 时间戳冲突: $sameTimestampConflicts 个');
    }
    
    if (timestampParseErrors > 0) {
      buffer.writeln('\n❌ 时间戳解析错误: $timestampParseErrors 个');
    }
    
    if (missingDependencies > 0) {
      buffer.writeln('\n⚠️ 缺少依赖: $missingDependencies 个');
    }
    
    if (clockSkewDetected) {
      buffer.writeln('\n⏰ 检测到时钟偏移');
      if (estimatedClockSkew != null) {
        buffer.writeln('   估计偏移: ${estimatedClockSkew!.inMinutes} 分钟');
      }
    }
    
    if (warnings.isNotEmpty) {
      buffer.writeln('\n⚠️ 警告:');
      for (final warning in warnings) {
        buffer.writeln('  - $warning');
      }
    }
    
    if (errors.isNotEmpty) {
      buffer.writeln('\n❌ 错误:');
      for (final error in errors) {
        buffer.writeln('  - $error');
      }
    }
    
    if (conflicts.isNotEmpty) {
      buffer.writeln('\n🔄 冲突详情:');
      for (final conflict in conflicts) {
        buffer.writeln('  - ${conflict.description}');
      }
    }
    
    return buffer.toString();
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'insertedQuotes': insertedQuotes,
      'updatedQuotes': updatedQuotes,
      'skippedQuotes': skippedQuotes,
      'insertedCategories': insertedCategories,
      'updatedCategories': updatedCategories,
      'skippedCategories': skippedCategories,
      'insertedTags': insertedTags,
      'updatedTags': updatedTags,
      'skippedTags': skippedTags,
      'mediaCopied': mediaCopied,
      'mediaOverwritten': mediaOverwritten,
      'mediaSkipped': mediaSkipped,
      'sameTimestampConflicts': sameTimestampConflicts,
      'timestampParseErrors': timestampParseErrors,
      'missingDependencies': missingDependencies,
      'processingTimeMs': processingTime.inMilliseconds,
      'totalProcessedItems': totalProcessedItems,
      'clockSkewDetected': clockSkewDetected,
      'estimatedClockSkewMs': estimatedClockSkew?.inMilliseconds,
      'warnings': warnings,
      'errors': errors,
      'conflicts': conflicts.map((c) => c.toJson()).toList(),
    };
  }

  /// 从JSON创建
  factory MergeReport.fromJson(Map<String, dynamic> json) {
    return MergeReport(
      insertedQuotes: json['insertedQuotes'] ?? 0,
      updatedQuotes: json['updatedQuotes'] ?? 0,
      skippedQuotes: json['skippedQuotes'] ?? 0,
      insertedCategories: json['insertedCategories'] ?? 0,
      updatedCategories: json['updatedCategories'] ?? 0,
      skippedCategories: json['skippedCategories'] ?? 0,
      insertedTags: json['insertedTags'] ?? 0,
      updatedTags: json['updatedTags'] ?? 0,
      skippedTags: json['skippedTags'] ?? 0,
      mediaCopied: json['mediaCopied'] ?? 0,
      mediaOverwritten: json['mediaOverwritten'] ?? 0,
      mediaSkipped: json['mediaSkipped'] ?? 0,
      sameTimestampConflicts: json['sameTimestampConflicts'] ?? 0,
      timestampParseErrors: json['timestampParseErrors'] ?? 0,
      missingDependencies: json['missingDependencies'] ?? 0,
      processingTime: Duration(milliseconds: json['processingTimeMs'] ?? 0),
      totalProcessedItems: json['totalProcessedItems'] ?? 0,
      clockSkewDetected: json['clockSkewDetected'] ?? false,
      estimatedClockSkew: json['estimatedClockSkewMs'] != null 
          ? Duration(milliseconds: json['estimatedClockSkewMs']) 
          : null,
      warnings: List<String>.from(json['warnings'] ?? []),
      errors: List<String>.from(json['errors'] ?? []),
      conflicts: (json['conflicts'] as List<dynamic>?)
          ?.map((c) => ConflictInfo.fromJson(c))
          .toList() ?? [],
    );
  }

  @override
  String toString() => summary;
}

/// 冲突信息记录
class ConflictInfo {
  final String id;
  final String type; // 'quote', 'category', 'tag', 'media'
  final String description;
  final String? localTimestamp;
  final String? remoteTimestamp;
  final String resolution; // 'local_kept', 'remote_used', 'manual_required'

  const ConflictInfo({
    required this.id,
    required this.type,
    required this.description,
    this.localTimestamp,
    this.remoteTimestamp,
    required this.resolution,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'localTimestamp': localTimestamp,
      'remoteTimestamp': remoteTimestamp,
      'resolution': resolution,
    };
  }

  factory ConflictInfo.fromJson(Map<String, dynamic> json) {
    return ConflictInfo(
      id: json['id'],
      type: json['type'],
      description: json['description'],
      localTimestamp: json['localTimestamp'],
      remoteTimestamp: json['remoteTimestamp'],
      resolution: json['resolution'],
    );
  }
}

/// 可变的合并报告构建器，用于在合并过程中累积统计信息
class MergeReportBuilder {
  int _insertedQuotes = 0;
  int _updatedQuotes = 0;
  int _skippedQuotes = 0;
  int _insertedCategories = 0;
  int _updatedCategories = 0;
  int _skippedCategories = 0;
  int _insertedTags = 0;
  int _updatedTags = 0;
  int _skippedTags = 0;
  int _mediaCopied = 0;
  int _mediaOverwritten = 0;
  int _mediaSkipped = 0;
  int _sameTimestampConflicts = 0;
  int _timestampParseErrors = 0;
  int _missingDependencies = 0;
  int _totalProcessedItems = 0;
  
  bool _clockSkewDetected = false;
  Duration? _estimatedClockSkew;
  final List<String> _warnings = [];
  final List<String> _errors = [];
  final List<ConflictInfo> _conflicts = [];
  
  late final DateTime _startTime;
  
  MergeReportBuilder() {
    _startTime = DateTime.now();
  }

  // 笔记操作统计
  void incrementInsertedQuotes() => _insertedQuotes++;
  void incrementUpdatedQuotes() => _updatedQuotes++;
  void incrementSkippedQuotes() => _skippedQuotes++;
  
  // 分类操作统计
  void incrementInsertedCategories() => _insertedCategories++;
  void incrementUpdatedCategories() => _updatedCategories++;
  void incrementSkippedCategories() => _skippedCategories++;
  
  // 标签操作统计
  void incrementInsertedTags() => _insertedTags++;
  void incrementUpdatedTags() => _updatedTags++;
  void incrementSkippedTags() => _skippedTags++;
  
  // 媒体文件操作统计
  void incrementMediaCopied() => _mediaCopied++;
  void incrementMediaOverwritten() => _mediaOverwritten++;
  void incrementMediaSkipped() => _mediaSkipped++;
  
  // 特殊情况统计
  void incrementSameTimestampConflicts() => _sameTimestampConflicts++;
  void incrementTimestampParseErrors() => _timestampParseErrors++;
  void incrementMissingDependencies() => _missingDependencies++;
  void incrementTotalProcessedItems() => _totalProcessedItems++;
  
  // 时钟偏移检测
  void setClockSkewDetected(Duration? skew) {
    _clockSkewDetected = true;
    _estimatedClockSkew = skew;
  }
  
  // 添加警告和错误
  void addWarning(String warning) => _warnings.add(warning);
  void addError(String error) => _errors.add(error);
  void addConflict(ConflictInfo conflict) => _conflicts.add(conflict);

  /// 构建最终报告
  MergeReport build() {
    final endTime = DateTime.now();
    final processingTime = endTime.difference(_startTime);
    
    return MergeReport(
      insertedQuotes: _insertedQuotes,
      updatedQuotes: _updatedQuotes,
      skippedQuotes: _skippedQuotes,
      insertedCategories: _insertedCategories,
      updatedCategories: _updatedCategories,
      skippedCategories: _skippedCategories,
      insertedTags: _insertedTags,
      updatedTags: _updatedTags,
      skippedTags: _skippedTags,
      mediaCopied: _mediaCopied,
      mediaOverwritten: _mediaOverwritten,
      mediaSkipped: _mediaSkipped,
      sameTimestampConflicts: _sameTimestampConflicts,
      timestampParseErrors: _timestampParseErrors,
      missingDependencies: _missingDependencies,
      processingTime: processingTime,
      totalProcessedItems: _totalProcessedItems,
      clockSkewDetected: _clockSkewDetected,
      estimatedClockSkew: _estimatedClockSkew,
      warnings: List.unmodifiable(_warnings),
      errors: List.unmodifiable(_errors),
      conflicts: List.unmodifiable(_conflicts),
    );
  }
}
