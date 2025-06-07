import 'package:flutter/foundation.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

/// 全局日志工具类，用于替换 debugPrint
class AppLogger {
  static UnifiedLogService? _logService;

  /// 初始化日志服务
  static void initialize() {
    _logService = UnifiedLogService.instance;
  }

  /// 获取日志服务实例
  static UnifiedLogService get _service {
    _logService ??= UnifiedLogService.instance;
    return _logService!;
  }

  /// 记录详细日志 (verbose)
  static void v(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _service.verbose(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录调试日志 (debug)
  static void d(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _service.debug(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录信息日志 (info)
  static void i(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _service.info(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录警告日志 (warning)
  static void w(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _service.warning(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录错误日志 (error)
  static void e(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _service.error(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 通用日志记录方法
  static void log(UnifiedLogLevel level, String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _service.log(level, message, source: source, error: error, stackTrace: stackTrace);
  }
}

/// 全局日志函数，用于替换 debugPrint
void appLog(String message, {
  UnifiedLogLevel level = UnifiedLogLevel.debug,
  String? source,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger.log(level, message, source: source, error: error, stackTrace: stackTrace);
}

/// 简化的日志函数，直接替换 debugPrint 的使用
void logDebug(String? message, {String? source}) {
  if (message != null && message.isNotEmpty) {
    AppLogger.d(message, source: source ?? 'Debug');
  }
}

/// 错误日志函数
void logError(String message, {Object? error, StackTrace? stackTrace, String? source}) {
  AppLogger.e(message, error: error, stackTrace: stackTrace, source: source ?? 'Error');
}

/// 信息日志函数
void logInfo(String message, {String? source}) {
  AppLogger.i(message, source: source ?? 'Info');
}

/// 警告日志函数
void logWarning(String message, {String? source}) {
  AppLogger.w(message, source: source ?? 'Warning');
}

/// HTTP 请求日志函数
void logHttp(String message, {String? source}) {
  AppLogger.d(message, source: source ?? 'HTTP');
}

/// 网络重试日志函数
void logRetry(String message, {String? source}) {
  AppLogger.d(message, source: source ?? 'RETRY');
}

/// AI 相关日志函数
void logAI(String message, {String? source}) {
  AppLogger.d(message, source: source ?? 'AI');
}

/// DIO 网络日志函数
void logDio(String message, {String? source}) {
  AppLogger.d(message, source: source ?? 'DIO');
}
