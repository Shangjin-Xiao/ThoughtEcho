import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/sentry_network_tracing.dart';

void main() {
  group('Sentry network tracing', () {
    setUp(() {
      SentryNetworkTracing.configure(enabled: false);
    });

    test('does not wrap ordinary network clients by default', () {
      final dio = Dio();
      final originalAdapter = dio.httpClientAdapter;

      SentryNetworkTracing.addToGeneralDioIfEnabled(dio);

      expect(dio.httpClientAdapter, same(originalAdapter));
    });

    test('wraps ordinary network clients only after explicit opt-in', () {
      final dio = Dio();
      final originalAdapter = dio.httpClientAdapter;
      SentryNetworkTracing.configure(enabled: true);

      SentryNetworkTracing.addToGeneralDioIfEnabled(dio);

      expect(dio.httpClientAdapter, isNot(same(originalAdapter)));
    });

    test(
        'unmount removes FailedRequestInterceptor and restores adapter & transformer',
        () {
      final dio = Dio();
      final originalAdapter = dio.httpClientAdapter;
      final originalTransformer = dio.transformer;

      SentryNetworkTracing.mount(dio);

      expect(dio.httpClientAdapter, isNot(same(originalAdapter)));
      expect(dio.transformer, isNot(same(originalTransformer)));
      expect(
        dio.interceptors
            .any((i) => i.runtimeType.toString() == 'FailedRequestInterceptor'),
        isTrue,
      );

      SentryNetworkTracing.unmount(dio);

      expect(dio.httpClientAdapter, same(originalAdapter));
      expect(dio.transformer, same(originalTransformer));
      expect(
        dio.interceptors
            .any((i) => i.runtimeType.toString() == 'FailedRequestInterceptor'),
        isFalse,
      );
    });

    test('mount and unmount are idempotent under rapid repeated calls', () {
      final dio = Dio();
      final originalAdapter = dio.httpClientAdapter;
      final originalTransformer = dio.transformer;

      // Repeated mount calls should keep same wrapper and not throw or nest
      SentryNetworkTracing.mount(dio);
      final firstWrappedAdapter = dio.httpClientAdapter;
      SentryNetworkTracing.mount(dio);
      expect(dio.httpClientAdapter, same(firstWrappedAdapter));

      // Repeated unmount calls should restore originals cleanly and not throw
      SentryNetworkTracing.unmount(dio);
      expect(dio.httpClientAdapter, same(originalAdapter));
      expect(dio.transformer, same(originalTransformer));

      expect(() => SentryNetworkTracing.unmount(dio), returnsNormally);
      expect(dio.httpClientAdapter, same(originalAdapter));
      expect(dio.transformer, same(originalTransformer));
    });
  });
}
