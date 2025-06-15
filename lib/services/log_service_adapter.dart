import 'package:flutter/widgets.dart';
import 'package:thoughtecho/services/log_service.dart' as old_log;
import 'package:thoughtecho/services/unified_log_service.dart';

/// 适配器类，使 UnifiedLogService 能够作为 LogService 使用
/// 这样现有的日志页面就可以无缝使用新的统一日志服务
class LogServiceAdapter extends old_log.LogService {
  final UnifiedLogService _unifiedService;

  LogServiceAdapter(this._unifiedService);

  /// 创建适配器实例
  static LogServiceAdapter fromUnified(UnifiedLogService unifiedService) {
    return LogServiceAdapter(unifiedService);
  }

  @override
  List<old_log.LogEntry> get logs => _unifiedService.oldLogs;

  @override
  old_log.LogLevel get currentLevel => _unifiedService.oldCurrentLevel;

  @override
  Future<void> setLogLevel(old_log.LogLevel newLevel) async {
    await _unifiedService.setOldLogLevel(newLevel);
  }

  @override
  void log(
    old_log.LogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _unifiedService.log(
      level.toUnifiedLogLevel,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _unifiedService.verbose(
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _unifiedService.debug(
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _unifiedService.info(
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _unifiedService.warning(
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _unifiedService.error(
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void clearMemoryLogs() {
    _unifiedService.clearMemoryLogs();
  }

  @override
  Future<void> clearAllLogs() async {
    await _unifiedService.clearAllLogs();
  }

  @override
  Future<List<old_log.LogEntry>> queryLogs({
    old_log.LogLevel? level,
    String? searchText,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    return await _unifiedService.queryOldLogs(
      level: level,
      searchText: searchText,
      source: source,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      offset: offset,
    );
  }

  @override
  void addListener(VoidCallback listener) {
    _unifiedService.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _unifiedService.removeListener(listener);
  }

  @override
  bool get hasListeners => _unifiedService.hasListeners;

  @override
  void notifyListeners() {
    _unifiedService.notifyListeners();
  }

  @override
  void dispose() {
    _unifiedService.dispose();
    super.dispose();
  }
}
