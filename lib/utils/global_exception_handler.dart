import 'dart:async';
import 'dart:isolate';
import 'package:thoughtecho/utils/app_logger.dart';
import '../main.dart' show getAndClearDeferredErrors;

/// 全局异常处理器
/// 负责捕获和记录应用中的各种异常
class GlobalExceptionHandler {
  static bool _isInitialized = false;
  static final List<Map<String, dynamic>> _deferredErrors = [];
  static RawReceivePort? _isolateErrorPort;

  /// 初始化全局异常处理
  static void initialize() {
    if (_isInitialized) return;

    // FlutterError / PlatformDispatcher 由 main.dart 统一接管，避免重复覆盖。
    // 这里只负责补充 isolate 捕获，并明确记录当前没有通用的平台通道全局捕获钩子。

    // 1. 捕获Isolate异常
    _setupIsolateErrorHandler();

    // 2. 明确记录平台通道全局捕获当前未启用，避免误导
    _reportPlatformChannelCaptureLimitation();

    _isInitialized = true;
    AppLogger.i('全局异常处理器已初始化', source: 'GlobalExceptionHandler');
  }

  static void _storeDeferredError(Map<String, dynamic> error) {
    _deferredErrors.add(error);
  }

  /// 设置Isolate异常处理
  static void _setupIsolateErrorHandler() {
    try {
      _isolateErrorPort?.close();
      _isolateErrorPort = RawReceivePort((pair) {
        final List<dynamic> errorAndStacktrace = pair;
        final error = errorAndStacktrace.first;
        final stackTrace = errorAndStacktrace.length > 1
            ? StackTrace.fromString(errorAndStacktrace.last.toString())
            : null;

        AppLogger.e(
          'Isolate异常: $error',
          error: error,
          stackTrace: stackTrace,
          source: 'Isolate',
        );

        // 保存到延迟处理队列
        _storeDeferredError({
          'type': 'Isolate',
          'message': 'Isolate异常: $error',
          'error': error,
          'stackTrace': stackTrace,
          'source': 'Isolate',
          'timestamp': DateTime.now(),
        });
      });
      Isolate.current.addErrorListener(_isolateErrorPort!.sendPort);
    } catch (e) {
      AppLogger.w('设置Isolate异常处理失败: $e', source: 'GlobalExceptionHandler');
    }
  }

  /// 记录平台通道全局捕获限制。
  ///
  /// Flutter 当前没有稳定的通用入口可以在这里拦截所有 platform channel 异常，
  /// 因此这里只声明限制，不伪装成已经安装了全局捕获器。
  static void _reportPlatformChannelCaptureLimitation() {
    AppLogger.d(
      '未安装平台通道全局异常捕获：当前仅由调用侧或上层错误处理链路负责记录',
      source: 'PlatformChannel',
    );
  }

  /// 手动记录异常
  static void recordException(
    dynamic error, {
    StackTrace? stackTrace,
    String? source,
    String? context,
    Map<String, dynamic>? additionalData,
  }) {
    final errorMessage =
        context != null ? '$context: $error' : error.toString();

    AppLogger.e(
      errorMessage,
      error: error,
      stackTrace: stackTrace,
      source: source ?? 'Manual',
    );

    // 保存到延迟处理队列
    _storeDeferredError({
      'type': 'Manual',
      'message': errorMessage,
      'error': error,
      'stackTrace': stackTrace,
      'source': source ?? 'Manual',
      'context': context,
      'additionalData': additionalData,
      'timestamp': DateTime.now(),
    });
  }

  /// 安全执行异步操作
  static Future<T?> safeExecute<T>(
    Future<T> Function() operation, {
    String? operationName,
    T? fallbackValue,
    bool logErrors = true,
  }) async {
    try {
      return await operation();
    } catch (e, s) {
      if (logErrors) {
        recordException(
          e,
          stackTrace: s,
          source: 'SafeExecute',
          context: operationName ?? '未知操作',
        );
      }
      return fallbackValue;
    }
  }

  /// 安全执行同步操作
  static T? safeExecuteSync<T>(
    T Function() operation, {
    String? operationName,
    T? fallbackValue,
    bool logErrors = true,
  }) {
    try {
      return operation();
    } catch (e, s) {
      if (logErrors) {
        recordException(
          e,
          stackTrace: s,
          source: 'SafeExecuteSync',
          context: operationName ?? '未知操作',
        );
      }
      return fallbackValue;
    }
  }

  /// 获取延迟处理的错误
  static List<Map<String, dynamic>> getDeferredErrors() {
    final merged = <Map<String, dynamic>>[];
    merged.addAll(getAndClearDeferredErrors());
    merged.addAll(_deferredErrors);
    _deferredErrors
      ..clear()
      ..addAll(merged);
    return List.unmodifiable(_deferredErrors);
  }

  /// 清除延迟处理的错误
  static void clearDeferredErrors() {
    _deferredErrors.clear();
    AppLogger.d('已清除延迟处理的错误', source: 'GlobalExceptionHandler');
  }

  /// 处理延迟的错误（通常在应用完全初始化后调用）
  static void processDeferredErrors() {
    if (_deferredErrors.isEmpty) return;

    AppLogger.i(
      '开始处理 ${_deferredErrors.length} 个延迟错误',
      source: 'GlobalExceptionHandler',
    );

    for (final error in _deferredErrors) {
      // 这里可以添加更复杂的错误处理逻辑
      // 比如发送到错误报告服务、显示用户通知等
      AppLogger.d(
        '处理延迟错误: ${error['type']} - ${error['message']}',
        source: 'GlobalExceptionHandler',
      );
    }

    clearDeferredErrors();
  }

  /// 获取异常统计信息
  static Map<String, dynamic> getExceptionStats() {
    final stats = <String, int>{};
    for (final error in _deferredErrors) {
      final type = error['type'] as String;
      stats[type] = (stats[type] ?? 0) + 1;
    }

    return {
      'totalErrors': _deferredErrors.length,
      'errorsByType': stats,
      'isInitialized': _isInitialized,
      'platformChannelGlobalCaptureSupported': false,
    };
  }
}
