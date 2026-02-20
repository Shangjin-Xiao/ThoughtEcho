import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 全局异常处理器
/// 负责捕获和记录应用中的各种异常
class GlobalExceptionHandler {
  static bool _isInitialized = false;
  static final List<Map<String, dynamic>> _deferredErrors = [];

  /// 初始化全局异常处理
  static void initialize() {
    if (_isInitialized) return;

    // 1. 捕获Flutter框架异常
    _setupFlutterErrorHandler();

    // 2. 捕获平台分发器异常
    _setupPlatformDispatcherErrorHandler();

    // 3. 捕获Isolate异常
    _setupIsolateErrorHandler();

    // 4. 捕获平台通道异常
    _setupPlatformChannelErrorHandler();

    _isInitialized = true;
    AppLogger.i('全局异常处理器已初始化', source: 'GlobalExceptionHandler');
  }

  /// 设置Flutter框架异常处理
  static void _setupFlutterErrorHandler() {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }

      AppLogger.e(
        'Flutter框架异常: ${details.exceptionAsString()}',
        error: details.exception,
        stackTrace: details.stack,
        source: 'FlutterError',
      );

      // 保存到延迟处理队列
      _deferredErrors.add({
        'type': 'FlutterError',
        'message': 'Flutter框架异常: ${details.exceptionAsString()}',
        'error': details.exception,
        'stackTrace': details.stack,
        'source': 'FlutterError',
        'timestamp': DateTime.now(),
      });
    };
  }

  /// 设置平台分发器异常处理
  static void _setupPlatformDispatcherErrorHandler() {
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.e(
        '平台分发器异常: $error',
        error: error,
        stackTrace: stack,
        source: 'PlatformDispatcher',
      );

      // 保存到延迟处理队列
      _deferredErrors.add({
        'type': 'PlatformDispatcher',
        'message': '平台分发器异常: $error',
        'error': error,
        'stackTrace': stack,
        'source': 'PlatformDispatcher',
        'timestamp': DateTime.now(),
      });

      return true; // 表示错误已处理
    };
  }

  /// 设置Isolate异常处理
  static void _setupIsolateErrorHandler() {
    try {
      Isolate.current.addErrorListener(
        RawReceivePort((pair) {
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
          _deferredErrors.add({
            'type': 'Isolate',
            'message': 'Isolate异常: $error',
            'error': error,
            'stackTrace': stackTrace,
            'source': 'Isolate',
            'timestamp': DateTime.now(),
          });
        }).sendPort,
      );
    } catch (e) {
      AppLogger.w('设置Isolate异常处理失败: $e', source: 'GlobalExceptionHandler');
    }
  }

  /// 设置平台通道异常处理
  static void _setupPlatformChannelErrorHandler() {
    // 监听平台通道异常
    ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
      'flutter/platform_views',
      (data) async {
        try {
          // 这里可以添加平台视图相关的异常处理
          return null;
        } catch (e, s) {
          AppLogger.e(
            '平台通道异常: $e',
            error: e,
            stackTrace: s,
            source: 'PlatformChannel',
          );
          return null;
        }
      },
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
    final errorMessage = context != null
        ? '$context: $error'
        : error.toString();

    AppLogger.e(
      errorMessage,
      error: error,
      stackTrace: stackTrace,
      source: source ?? 'Manual',
    );

    // 保存到延迟处理队列
    _deferredErrors.add({
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
    };
  }
}
