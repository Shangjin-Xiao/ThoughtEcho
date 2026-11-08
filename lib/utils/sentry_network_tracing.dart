import 'package:dio/dio.dart';
import 'package:sentry_dio/sentry_dio.dart';
// ignore: implementation_imports
import 'package:sentry_dio/src/failed_request_interceptor.dart';
// ignore: implementation_imports
import 'package:sentry_dio/src/sentry_dio_client_adapter.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 根据用户明确授权，为普通网络请求启用 Sentry 性能追踪。
class SentryNetworkTracing {
  SentryNetworkTracing._();

  static bool _enabled = false;
  static final Map<Dio, HttpClientAdapter> _originalAdapters = {};
  static final Map<Dio, Transformer> _originalTransformers = {};

  static bool get isEnabled => _enabled;

  static void configure({required bool enabled}) {
    _enabled = enabled;
  }

  /// AI 请求不得调用此方法。
  static void addToGeneralDioIfEnabled(Dio dio) {
    if (_enabled) {
      mount(dio);
    }
  }

  /// 为指定的 Dio 实例装载 Sentry 监控组件。
  static void mount(Dio dio) {
    HttpClientAdapter? adapter;
    Transformer? transformer;
    try {
      if (dio.httpClientAdapter is SentryDioClientAdapter) {
        return;
      }
      adapter = dio.httpClientAdapter;
      transformer = dio.transformer;
    } catch (_) {
      return;
    }
    // ignore: unnecessary_null_comparison
    if (adapter == null || transformer == null) {
      return;
    }
    _originalAdapters[dio] = adapter;
    _originalTransformers[dio] = transformer;
    dio.addSentry();
  }

  /// 卸载指定 Dio 实例上的 Sentry 拦截器、适配器与转换器并还原为原始对象。
  /// 返回是否全部成功还原。
  static bool unmount(Dio dio) {
    var success = true;
    try {
      dio.interceptors.removeWhere((i) => i is FailedRequestInterceptor);
    } catch (e) {
      success = false;
      logWarning(
        'Failed to remove FailedRequestInterceptor: $e',
        source: 'SentryNetworkTracing',
      );
    }
    final originalAdapter = _originalAdapters.remove(dio);
    if (originalAdapter != null) {
      try {
        dio.httpClientAdapter = originalAdapter;
      } catch (e) {
        success = false;
        logWarning(
          'Failed to restore httpClientAdapter: $e',
          source: 'SentryNetworkTracing',
        );
      }
    }
    final originalTransformer = _originalTransformers.remove(dio);
    if (originalTransformer != null) {
      try {
        dio.transformer = originalTransformer;
      } catch (e) {
        success = false;
        logWarning(
          'Failed to restore transformer: $e',
          source: 'SentryNetworkTracing',
        );
      }
    }
    return success;
  }
}
