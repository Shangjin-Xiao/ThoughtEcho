import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/global_exception_handler.dart';

/// 日志查看和管理工具
class LogViewer {
  /// 获取所有日志的统计信息
  static Map<String, dynamic> getLogStatistics() {
    final logService = UnifiedLogService.instance;
    final stats = logService.logStats;
    final exceptionStats = GlobalExceptionHandler.getExceptionStats();

    return {
      'totalLogs': logService.logs.length,
      'logsByLevel': stats.map((level, count) => MapEntry(level.name, count)),
      'lastLogTime': logService.lastLogTime?.toIso8601String(),
      'performanceStats': logService.getPerformanceStats(),
      'exceptionStats': exceptionStats,
      'memoryUsage': _getMemoryUsage(),
      'systemInfo': _getSystemInfo(),
    };
  }

  /// 搜索日志
  static Future<List<LogEntry>> searchLogs({
    String? searchText,
    UnifiedLogLevel? level,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final logService = UnifiedLogService.instance;
      return await logService.queryLogs(
        searchText: searchText,
        level: level,
        source: source,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
        offset: offset,
      );
    } catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'LogViewer',
        context: '搜索日志失败',
      );
      return [];
    }
  }

  /// 导出日志
  static Future<String?> exportLogs({
    UnifiedLogLevel? minLevel,
    DateTime? startDate,
    DateTime? endDate,
    String? filePath,
  }) async {
    try {
      final logService = UnifiedLogService.instance;
      final content = logService.exportLogsAsText(
        minLevel: minLevel,
        startDate: startDate,
        endDate: endDate,
      );

      if (filePath != null) {
        final file = File(filePath);
        await file.writeAsString(content);
        AppLogger.i('日志已导出到: $filePath', source: 'LogViewer');
        return filePath;
      }

      return content;
    } catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'LogViewer',
        context: '导出日志失败',
      );
      return null;
    }
  }

  /// 清理旧日志
  static Future<bool> cleanupOldLogs({
    Duration? olderThan,
    int? keepCount,
  }) async {
    try {
      if (olderThan != null) {
        final cutoffDate = DateTime.now().subtract(olderThan);
        // 这里需要在UnifiedLogService中添加按日期清理的方法
        AppLogger.i('清理${cutoffDate.toIso8601String()}之前的日志',
            source: 'LogViewer');
      }

      if (keepCount != null) {
        // 这里需要在UnifiedLogService中添加按数量清理的方法
        AppLogger.i('保留最新的$keepCount条日志', source: 'LogViewer');
      }

      return true;
    } catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'LogViewer',
        context: '清理日志失败',
      );
      return false;
    }
  }

  /// 获取日志来源列表
  static List<String> getLogSources() {
    final logService = UnifiedLogService.instance;
    final sources = <String>{};

    for (final log in logService.logs) {
      if (log.source != null && log.source!.isNotEmpty) {
        sources.add(log.source!);
      }
    }

    return sources.toList()..sort();
  }

  /// 获取日志级别统计
  static Map<UnifiedLogLevel, int> getLogLevelStats() {
    final logService = UnifiedLogService.instance;
    return Map.from(logService.logStats);
  }

  /// 获取最近的错误日志
  static List<LogEntry> getRecentErrors({int limit = 10}) {
    final logService = UnifiedLogService.instance;
    return logService.logs
        .where((log) => log.level == UnifiedLogLevel.error)
        .take(limit)
        .toList();
  }

  /// 获取最近的警告日志
  static List<LogEntry> getRecentWarnings({int limit = 10}) {
    final logService = UnifiedLogService.instance;
    return logService.logs
        .where((log) => log.level == UnifiedLogLevel.warning)
        .take(limit)
        .toList();
  }

  /// 分析日志模式
  static Map<String, dynamic> analyzeLogPatterns() {
    final logService = UnifiedLogService.instance;
    final logs = logService.logs;

    // 分析错误模式
    final errorPatterns = <String, int>{};
    final warningPatterns = <String, int>{};
    final sourceActivity = <String, int>{};

    for (final log in logs) {
      // 统计来源活动
      if (log.source != null) {
        sourceActivity[log.source!] = (sourceActivity[log.source!] ?? 0) + 1;
      }

      // 分析错误模式
      if (log.level == UnifiedLogLevel.error && log.error != null) {
        final errorType = _extractErrorType(log.error!);
        errorPatterns[errorType] = (errorPatterns[errorType] ?? 0) + 1;
      }

      // 分析警告模式
      if (log.level == UnifiedLogLevel.warning) {
        final warningType = _extractWarningType(log.message);
        warningPatterns[warningType] = (warningPatterns[warningType] ?? 0) + 1;
      }
    }

    return {
      'errorPatterns': errorPatterns,
      'warningPatterns': warningPatterns,
      'sourceActivity': sourceActivity,
      'totalLogs': logs.length,
      'analysisTime': DateTime.now().toIso8601String(),
    };
  }

  /// 生成日志报告
  static String generateLogReport({
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final stats = getLogStatistics();
    final recentErrors = getRecentErrors();
    final recentWarnings = getRecentWarnings();

    final buffer = StringBuffer();
    buffer.writeln('# 心迹应用日志报告');
    buffer.writeln('生成时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    // 基本统计
    buffer.writeln('## 基本统计');
    buffer.writeln('总日志数: ${stats['totalLogs']}');
    buffer.writeln('最后日志时间: ${stats['lastLogTime'] ?? '无'}');
    buffer.writeln();

    // 日志级别分布
    buffer.writeln('## 日志级别分布');
    final logsByLevel = stats['logsByLevel'] as Map<String, dynamic>;
    for (final entry in logsByLevel.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    // 异常统计
    buffer.writeln('## 异常统计');
    final exceptionStats = stats['exceptionStats'] as Map<String, dynamic>;
    buffer.writeln('总异常数: ${exceptionStats['totalErrors']}');
    final errorsByType = exceptionStats['errorsByType'] as Map<String, dynamic>;
    for (final entry in errorsByType.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    // 最近错误
    buffer.writeln('## 最近错误 (最多10条)');
    for (final error in recentErrors) {
      buffer.writeln(
          '- [${error.timestamp.toIso8601String()}] ${error.source}: ${error.message}');
    }
    buffer.writeln();

    // 最近警告
    buffer.writeln('## 最近警告 (最多10条)');
    for (final warning in recentWarnings) {
      buffer.writeln(
          '- [${warning.timestamp.toIso8601String()}] ${warning.source}: ${warning.message}');
    }
    buffer.writeln();

    // 性能统计
    buffer.writeln('## 性能统计');
    final perfStats = stats['performanceStats'] as Map<String, dynamic>;
    for (final entry in perfStats.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }

    return buffer.toString();
  }

  /// 提取错误类型
  static String _extractErrorType(String error) {
    if (error.contains('Exception')) return 'Exception';
    if (error.contains('Error')) return 'Error';
    if (error.contains('Timeout')) return 'Timeout';
    if (error.contains('Network')) return 'Network';
    if (error.contains('Database')) return 'Database';
    if (error.contains('File')) return 'File';
    return 'Other';
  }

  /// 提取警告类型
  static String _extractWarningType(String message) {
    if (message.contains('内存')) return 'Memory';
    if (message.contains('性能')) return 'Performance';
    if (message.contains('网络')) return 'Network';
    if (message.contains('权限')) return 'Permission';
    if (message.contains('配置')) return 'Configuration';
    return 'Other';
  }

  /// 获取内存使用情况
  static Map<String, dynamic> _getMemoryUsage() {
    // 这里可以添加更详细的内存使用统计
    return {
      'platform': Platform.operatingSystem,
      'isDebugMode': kDebugMode,
    };
  }

  /// 获取系统信息
  static Map<String, dynamic> _getSystemInfo() {
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'isDebugMode': kDebugMode,
      'isProfileMode': kProfileMode,
      'isReleaseMode': kReleaseMode,
    };
  }
}
