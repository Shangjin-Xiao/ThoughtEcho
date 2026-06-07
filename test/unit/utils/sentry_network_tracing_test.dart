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
  });
}
