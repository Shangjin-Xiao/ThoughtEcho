import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:thoughtecho/utils/dio_performance_interceptor.dart";
import "package:thoughtecho/services/unified_log_service.dart";
import "package:flutter/widgets.dart";

class FakeUnifiedLogService extends ChangeNotifier
    with WidgetsBindingObserver
    implements UnifiedLogService {
  final List<Map<String, dynamic>> logRecords = [];

  @override
  void warning(String message,
      {String? source, Object? error, StackTrace? stackTrace}) {
    logRecords.add({
      "level": UnifiedLogLevel.warning,
      "message": message,
      "source": source,
      "error": error,
      "stackTrace": stackTrace,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequestInterceptorHandler extends RequestInterceptorHandler {
  final List<RequestOptions> calledOptions = [];
  @override
  void next(RequestOptions options) {
    calledOptions.add(options);
  }
}

class FakeResponseInterceptorHandler extends ResponseInterceptorHandler {
  final List<Response> calledResponses = [];
  @override
  void next(Response response) {
    calledResponses.add(response);
  }
}

class FakeErrorInterceptorHandler extends ErrorInterceptorHandler {
  final List<DioException> calledErrors = [];
  @override
  void next(DioException err) {
    calledErrors.add(err);
  }
}

void main() {
  group("DioPerformanceInterceptor", () {
    late FakeUnifiedLogService fakeLogService;
    late DioPerformanceInterceptor interceptor;

    setUp(() {
      fakeLogService = FakeUnifiedLogService();
      UnifiedLogService.instanceForTesting = fakeLogService;
      interceptor = DioPerformanceInterceptor();
    });

    test("onRequest injects timestamp into extra", () {
      final options = RequestOptions(path: "/test");
      final handler = FakeRequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(handler.calledOptions.length, 1);
      final modifiedOptions = handler.calledOptions.first;
      expect(modifiedOptions.extra.containsKey("request_start_time"), isTrue);
      expect(modifiedOptions.extra["request_start_time"], isA<int>());
    });

    test("onResponse logs when request is slow", () async {
      final options = RequestOptions(path: "/slow");
      // Simulate request started 4000ms ago
      options.extra["request_start_time"] =
          DateTime.now().millisecondsSinceEpoch - 4000;
      final response = Response(requestOptions: options, statusCode: 200);
      final handler = FakeResponseInterceptorHandler();

      interceptor.onResponse(response, handler);

      expect(handler.calledResponses.length, 1);
      expect(fakeLogService.logRecords.length, 1);

      final logRecord = fakeLogService.logRecords.first;
      expect(logRecord["level"], UnifiedLogLevel.warning);
      expect(logRecord["source"], "NetworkPerf");
      expect(
          logRecord["message"], contains("[API耗时] GET /slow -> 状态:200, 耗时:"));
    });

    test("onResponse does not log when request is fast", () async {
      final options = RequestOptions(path: "/fast");
      // Simulate request started 100ms ago
      options.extra["request_start_time"] =
          DateTime.now().millisecondsSinceEpoch - 100;
      final response = Response(requestOptions: options, statusCode: 200);
      final handler = FakeResponseInterceptorHandler();

      interceptor.onResponse(response, handler);

      expect(handler.calledResponses.length, 1);
      expect(fakeLogService.logRecords.length, 0);
    });

    test("onError logs regardless of duration if there is an error", () async {
      final options = RequestOptions(path: "/error_path");
      // Simulate request started 100ms ago (fast request, but failed)
      options.extra["request_start_time"] =
          DateTime.now().millisecondsSinceEpoch - 100;
      final err = DioException(
          requestOptions: options,
          error: "Connection timeout",
          response: Response(requestOptions: options, statusCode: 500));
      final handler = FakeErrorInterceptorHandler();

      interceptor.onError(err, handler);

      expect(handler.calledErrors.length, 1);
      expect(fakeLogService.logRecords.length, 1);

      final logRecord = fakeLogService.logRecords.first;
      expect(logRecord["level"], UnifiedLogLevel.warning);
      expect(logRecord["source"], "NetworkPerf");
      expect(logRecord["message"],
          contains("[API耗时] GET /error_path -> 状态:500, 耗时:"));
      expect(logRecord["message"], contains("(错误: Connection timeout)"));
    });

    test("URL length is truncated if too long", () async {
      final longPath = "/" + "a" * 100;
      final options = RequestOptions(path: longPath);
      options.extra["request_start_time"] =
          DateTime.now().millisecondsSinceEpoch - 4000;
      final response = Response(requestOptions: options, statusCode: 200);
      final handler = FakeResponseInterceptorHandler();

      interceptor.onResponse(response, handler);

      expect(fakeLogService.logRecords.length, 1);
      final logMessage = fakeLogService.logRecords.first["message"] as String;

      // Expected length: 77 + 3 ("...") = 80 characters from the path
      final truncatedPath = longPath.substring(0, 77) + "...";
      expect(logMessage, contains(truncatedPath));
      expect(logMessage.contains(longPath), isFalse);
    });
  });
}
