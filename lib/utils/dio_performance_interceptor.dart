import 'package:dio/dio.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

/// 零开销的 API 请求耗时统计拦截器
class DioPerformanceInterceptor extends Interceptor {
  static const String _startTimeKey = 'request_start_time';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 将时间戳直接存入 RequestOptions 的 extra 中，避免高并发请求时的 Map 状态污染
    options.extra[_startTimeKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logNetwork(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logNetwork(err.requestOptions, err.response?.statusCode,
        error: err.message);
    handler.next(err);
  }

  void _logNetwork(RequestOptions options, int? statusCode, {String? error}) {
    final startTime = options.extra[_startTimeKey] as int?;
    if (startTime != null) {
      final duration = DateTime.now().millisecondsSinceEpoch - startTime;

      final method = options.method;
      final path = options.uri.path;
      // 截断过长的 URL 防止日志污染数据库
      final displayPath =
          path.length > 80 ? '${path.substring(0, 77)}...' : path;

      final message =
          '[API耗时] $method $displayPath -> 状态:$statusCode, 耗时:${duration}ms${error != null ? " (错误: $error)" : ""}';

      if (duration > 3000 || error != null) {
        // 如果 AI 请求超过 3 秒，或者发生报错，记录为警告
        UnifiedLogService.instance.warning(message, source: 'NetworkPerf');
      } else {
        UnifiedLogService.instance.info(message, source: 'NetworkPerf');
      }
    }
  }
}
