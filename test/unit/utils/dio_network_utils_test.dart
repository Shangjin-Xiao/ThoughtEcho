import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:thoughtecho/utils/dio_network_utils.dart";

class FakeErrorInterceptorHandler extends ErrorInterceptorHandler {
  final List<DioException> nextCalled = [];
  final List<Response> resolveCalled = [];
  final List<DioException> rejectCalled = [];

  @override
  void next(DioException err) {
    nextCalled.add(err);
  }

  @override
  void resolve(Response response) {
    resolveCalled.add(response);
  }

  @override
  void reject(DioException error) {
    rejectCalled.add(error);
  }
}

class FakeDio extends Fake implements Dio {
  final Response? fetchResponse;
  final DioException? fetchError;

  FakeDio({this.fetchResponse, this.fetchError});

  @override
  Future<Response<T>> fetch<T>(RequestOptions requestOptions) async {
    if (fetchError != null) {
      throw fetchError!;
    }
    if (fetchResponse != null) {
      return fetchResponse as Response<T>;
    }
    return Response<T>(requestOptions: requestOptions);
  }
}

void main() {
  group("RetryInterceptor", () {
    test(
        "shouldRetry evaluates true for 502 and next is NOT called immediately (triggers retry)",
        () async {
      final dio = FakeDio(
          fetchResponse: Response(requestOptions: RequestOptions(path: "/")));
      final interceptor = RetryInterceptor(
        dio: dio,
        retries: 1,
        retryDelays: [const Duration(milliseconds: 1)],
      );

      final handler = FakeErrorInterceptorHandler();
      final options = RequestOptions(path: "/", extra: {});
      final error = DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 502),
      );

      interceptor.onError(error, handler);

      // Verify that next was not called immediately, meaning a retry is scheduled
      expect(handler.nextCalled, isEmpty);

      // wait for the delay and fetch
      await Future.delayed(const Duration(milliseconds: 10));
      expect(handler.resolveCalled.length, 1);
    });

    test("shouldRetry evaluates false for 400 and next is called", () async {
      final dio = FakeDio();
      final interceptor = RetryInterceptor(dio: dio, retries: 1);
      final handler = FakeErrorInterceptorHandler();
      final options = RequestOptions(path: "/", extra: {});
      final error = DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 400),
      );

      interceptor.onError(error, handler);

      expect(handler.nextCalled.length, 1);
    });

    test(
        "shouldRetry evaluates false for 500 with 'model not found' and next is called",
        () async {
      final dio = FakeDio();
      final interceptor = RetryInterceptor(dio: dio, retries: 1);
      final handler = FakeErrorInterceptorHandler();
      final options = RequestOptions(path: "/", extra: {});
      final error = DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 500,
          data: '{"error": "model not found"}',
        ),
      );

      interceptor.onError(error, handler);

      expect(handler.nextCalled.length, 1);
    });
  });
}
