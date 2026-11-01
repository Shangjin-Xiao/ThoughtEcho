import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/background_push_handler.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MMKVService mmkvService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() async {
    mmkvService = MMKVService();
    await mmkvService.clear();
    AppLogger.initialize();
  });

  group('initBackgroundMonitoring', () {
    test(
        'initializes Sentry, Aptabase, and error handlers when telemetry & sentry enabled',
        () async {
      await mmkvService.setString(
        'app_settings',
        jsonEncode({
          'sentryEnabled': true,
          'telemetryEnabled': true,
        }),
      );

      expect(
        () => initBackgroundMonitoring(mmkvService),
        returnsNormally,
      );

      expect(PlatformDispatcher.instance.onError, isNotNull);

      // Verify PlatformDispatcher.instance.onError handles error
      final handler = PlatformDispatcher.instance.onError!;
      final handled =
          handler(Exception('Test async exception'), StackTrace.current);
      expect(handled, isTrue);
    });

    test('handles sentryEnabled and telemetryEnabled being false', () async {
      await mmkvService.setString(
        'app_settings',
        jsonEncode({
          'sentryEnabled': false,
          'telemetryEnabled': false,
        }),
      );

      expect(
        () => initBackgroundMonitoring(mmkvService),
        returnsNormally,
      );

      expect(PlatformDispatcher.instance.onError, isNotNull);
    });

    test('gracefully falls back to false when app_settings JSON is corrupted',
        () async {
      await mmkvService.setString('app_settings', 'invalid_json_{{{');

      expect(
        () => initBackgroundMonitoring(mmkvService),
        returnsNormally,
      );

      expect(PlatformDispatcher.instance.onError, isNotNull);
    });

    test('gracefully handles missing telemetryEnabled field in app_settings',
        () async {
      await mmkvService.setString(
        'app_settings',
        jsonEncode({
          'sentryEnabled': true,
        }),
      );

      expect(
        () => initBackgroundMonitoring(mmkvService),
        returnsNormally,
      );

      expect(PlatformDispatcher.instance.onError, isNotNull);
    });

    test('gracefully handles null app_settings string in MMKV', () async {
      // mmkvService is empty
      expect(
        () => initBackgroundMonitoring(mmkvService),
        returnsNormally,
      );

      expect(PlatformDispatcher.instance.onError, isNotNull);
    });

    test('PlatformDispatcher.instance.onError logs error and returns true', () {
      initBackgroundMonitoring(mmkvService);

      final onError = PlatformDispatcher.instance.onError;
      expect(onError, isNotNull);

      final testError = StateError('Background async error');
      final testStackTrace = StackTrace.current;

      final result = onError!(testError, testStackTrace);
      expect(result, isTrue);
    });
  });
}
