import 'package:dio/dio.dart';
import 'package:sentry_dio/sentry_dio.dart';

/// 根据用户明确授权，为普通网络请求启用 Sentry 性能追踪。
class SentryNetworkTracing {
  SentryNetworkTracing._();

  static bool _enabled = false;

  static void configure({required bool enabled}) {
    _enabled = enabled;
  }

  /// AI 请求不得调用此方法。
  static void addToGeneralDioIfEnabled(Dio dio) {
    if (_enabled) {
      dio.addSentry();
    }
  }
}
