import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart' as logging;
import 'package:thoughtecho/services/log_service.dart';

/// 全局日志工具类，用于替换 debugPrint
class AppLogger {
  static LogService? _logService;
  static logging.Logger? _logger;

  /// 初始化日志服务
  static void initialize() {
    // 启用分层日志记录
    logging.hierarchicalLoggingEnabled = true;

    // 设置全局日志级别
    logging.Logger.root.level = logging.Level.ALL;

    // 创建应用专用的 logger
    _logger = logging.Logger('ThoughtEcho');

    // 添加控制台输出处理器
    logging.Logger.root.onRecord.listen((record) {
      // 只在调试模式下输出到控制台
      if (kDebugMode) {
        final time = record.time.toIso8601String();
        final level = record.level.name;
        final loggerName = record.loggerName;
        final message = record.message;

        String logOutput = '[$time] [$level] [$loggerName] $message';

        if (record.error != null) {
          logOutput += '\nError: ${record.error}';
        }

        if (record.stackTrace != null) {
          logOutput += '\nStackTrace: ${record.stackTrace}';
        }

        // 使用原始 print 输出，避免递归
        print(logOutput);
      }
    });
  }

  /// 获取日志服务实例
  static LogService get _service {
    _logService ??= LogService.instance;
    return _logService!;
  }

  /// 获取 logging.Logger 实例
  static logging.Logger get _log {
    _logger ??= logging.Logger('ThoughtEcho');
    return _logger!;
  }

  /// 记录详细日志 (verbose)
  static void v(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _log.finest(message, error, stackTrace);
    _service.verbose(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录调试日志 (debug)
  static void d(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _log.fine(message, error, stackTrace);
    _service.debug(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录信息日志 (info)
  static void i(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _log.info(message, error, stackTrace);
    _service.info(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录警告日志 (warning)
  static void w(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _log.warning(message, error, stackTrace);
    _service.warning(message, source: source, error: error, stackTrace: stackTrace);
  }

  /// 记录错误日志 (error)
  static void e(String message, {String? source, Object? error, StackTrace? stackTrace}) {
    _log.severe(message, error, stackTrace);
    _service.error(message, source: source, error: error, stackTrace: stackTrace);
  }
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
