import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/global_exception_handler.dart';

/// 安全的compute函数包装器
/// 提供更好的异常处理和日志记录
class SafeCompute {
  /// 安全执行compute操作
  ///
  /// [callback] - 要在isolate中执行的函数
  /// [message] - 传递给函数的参数
  /// [debugLabel] - 调试标签，用于日志记录
  /// [timeout] - 超时时间，默认30秒
  /// [fallbackValue] - 失败时的回退值
  static Future<R?> run<Q, R>(
    ComputeCallback<Q, R> callback,
    Q message, {
    String? debugLabel,
    Duration timeout = const Duration(seconds: 30),
    R? fallbackValue,
  }) async {
    final operationName = debugLabel ?? 'SafeCompute';

    try {
      AppLogger.d('开始执行Isolate操作: $operationName', source: 'SafeCompute');

      // 使用超时包装compute操作
      final result = await compute(callback, message).timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('Isolate操作超时', timeout);
        },
      );

      AppLogger.d('Isolate操作完成: $operationName', source: 'SafeCompute');
      return result;
    } on TimeoutException catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'SafeCompute',
        context: '$operationName - 超时',
      );
      return fallbackValue;
    } catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'SafeCompute',
        context: '$operationName - 执行失败',
      );
      return fallbackValue;
    }
  }

  /// 安全执行多个并发compute操作
  ///
  /// [operations] - 操作列表，每个操作包含callback、message和debugLabel
  /// [timeout] - 单个操作的超时时间
  /// [maxConcurrency] - 最大并发数，默认为CPU核心数
  static Future<List<R?>> runMultiple<Q, R>(
    List<ComputeOperation<Q, R>> operations, {
    Duration timeout = const Duration(seconds: 30),
    int? maxConcurrency,
  }) async {
    final concurrency = maxConcurrency ?? (kDebugMode ? 2 : 4); // 调试模式使用较少并发数

    AppLogger.d(
      '开始执行${operations.length}个并发Isolate操作，并发数: $concurrency',
      source: 'SafeCompute',
    );

    final results = <R?>[];

    // 分批处理操作
    for (int i = 0; i < operations.length; i += concurrency) {
      final batch = operations.skip(i).take(concurrency).toList();

      final batchFutures = batch.map(
        (op) => run(
          op.callback,
          op.message,
          debugLabel: op.debugLabel,
          timeout: timeout,
          fallbackValue: op.fallbackValue,
        ),
      );

      final batchResults = await Future.wait(batchFutures);
      results.addAll(batchResults);

      // 在批次之间稍作延迟，避免过度占用资源
      if (i + concurrency < operations.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    AppLogger.d(
      '并发Isolate操作完成，成功: ${results.where((r) => r != null).length}/${operations.length}',
      source: 'SafeCompute',
    );

    return results;
  }

  /// 创建一个可重用的Isolate
  ///
  /// [entryPoint] - Isolate入口点
  /// [debugName] - 调试名称
  static Future<SafeIsolate?> createIsolate(
    void Function(SendPort) entryPoint, {
    String? debugName,
  }) async {
    try {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        entryPoint,
        receivePort.sendPort,
        debugName: debugName,
      );

      AppLogger.d(
        '创建Isolate成功: ${debugName ?? 'unnamed'}',
        source: 'SafeCompute',
      );

      return SafeIsolate._(isolate, receivePort, debugName);
    } catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'SafeCompute',
        context: '创建Isolate失败: ${debugName ?? 'unnamed'}',
      );
      return null;
    }
  }
}

/// Compute操作定义
class ComputeOperation<Q, R> {
  final ComputeCallback<Q, R> callback;
  final Q message;
  final String? debugLabel;
  final R? fallbackValue;

  const ComputeOperation({
    required this.callback,
    required this.message,
    this.debugLabel,
    this.fallbackValue,
  });
}

/// 安全的Isolate包装器
class SafeIsolate {
  final Isolate _isolate;
  final ReceivePort _receivePort;
  final String? _debugName;
  bool _isKilled = false;

  SafeIsolate._(this._isolate, this._receivePort, this._debugName);

  /// 发送消息到Isolate
  void send(dynamic message) {
    if (_isKilled) {
      AppLogger.w('尝试向已终止的Isolate发送消息: $_debugName', source: 'SafeIsolate');
      return;
    }

    try {
      _receivePort.sendPort.send(message);
    } catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'SafeIsolate',
        context: '发送消息失败: $_debugName',
      );
    }
  }

  /// 监听Isolate消息
  Stream<dynamic> get messages => _receivePort;

  /// 终止Isolate
  void kill({int priority = Isolate.beforeNextEvent}) {
    if (_isKilled) return;

    try {
      _isolate.kill(priority: priority);
      _receivePort.close();
      _isKilled = true;

      AppLogger.d('Isolate已终止: $_debugName', source: 'SafeIsolate');
    } catch (e, s) {
      GlobalExceptionHandler.recordException(
        e,
        stackTrace: s,
        source: 'SafeIsolate',
        context: '终止Isolate失败: $_debugName',
      );
    }
  }

  /// 检查Isolate是否已终止
  bool get isKilled => _isKilled;

  /// 获取调试名称
  String? get debugName => _debugName;
}

/// 常用的安全compute操作
class CommonSafeCompute {
  /// 安全的JSON编码
  static Future<String?> encodeJson(
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return await SafeCompute.run(
      _encodeJsonInIsolate,
      data,
      debugLabel: 'JSON编码',
      timeout: timeout,
      fallbackValue: null,
    );
  }

  /// 安全的JSON解码
  static Future<Map<String, dynamic>?> decodeJson(
    String jsonString, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return await SafeCompute.run(
      _decodeJsonInIsolate,
      jsonString,
      debugLabel: 'JSON解码',
      timeout: timeout,
      fallbackValue: null,
    );
  }

  /// 安全的大文件处理
  static Future<List<int>?> processLargeFile(
    String filePath, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    return await SafeCompute.run(
      _processLargeFileInIsolate,
      filePath,
      debugLabel: '大文件处理',
      timeout: timeout,
      fallbackValue: null,
    );
  }
}

// Isolate入口点函数
String _encodeJsonInIsolate(Map<String, dynamic> data) {
  try {
    return jsonEncode(data);
  } catch (e) {
    throw Exception('JSON编码失败: $e');
  }
}

Map<String, dynamic> _decodeJsonInIsolate(String jsonString) {
  try {
    final result = jsonDecode(jsonString);
    if (result is Map<String, dynamic>) {
      return result;
    } else {
      throw Exception('JSON解码结果不是Map类型');
    }
  } catch (e) {
    throw Exception('JSON解码失败: $e');
  }
}

List<int> _processLargeFileInIsolate(String filePath) {
  try {
    // 这里可以添加实际的文件处理逻辑
    // 目前只是一个示例
    return [];
  } catch (e) {
    throw Exception('大文件处理失败: $e');
  }
}
