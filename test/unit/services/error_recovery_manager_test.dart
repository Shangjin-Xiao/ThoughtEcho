import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/error_recovery_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

void main() {
  group('ErrorRecoveryManager Tests', () {
    late ErrorRecoveryManager errorRecoveryManager;

    setUp(() {
      AppLogger.initialize();
      errorRecoveryManager = ErrorRecoveryManager();
      errorRecoveryManager.clearErrorHistory();
    });

    test('executeWithRecovery successful operation', () async {
      errorRecoveryManager.initialize();
      final result = await errorRecoveryManager.executeWithRecovery(
        'success_test',
        () async => 'success',
      );
      expect(result, equals('success'));
      expect(errorRecoveryManager.getErrorHistory().length, equals(0));
    });

    test('executeWithRecovery fails and retries', () async {
      errorRecoveryManager.initialize();
      int attemptCount = 0;

      await expectLater(
        () => errorRecoveryManager.executeWithRecovery(
          'fail_test',
          () async {
            attemptCount++;
            throw Exception('Test failure');
          },
          maxRetries: 2,
          retryDelay: const Duration(milliseconds: 10),
        ),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('Test failure'))),
      );
      expect(attemptCount, equals(3)); // 1 initial + 2 retries

      final history = errorRecoveryManager.getErrorHistory();
      expect(history.length, equals(3));
      expect(history.first.operationName, equals('fail_test'));
    });

    test('executeWithRecovery succeeds after retry', () async {
      errorRecoveryManager.initialize();
      int attemptCount = 0;

      final result = await errorRecoveryManager.executeWithRecovery(
        'retry_success_test',
        () async {
          attemptCount++;
          if (attemptCount < 2) {
            throw Exception('Temporary failure');
          }
          return 'success_after_retry';
        },
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(result, equals('success_after_retry'));
      expect(attemptCount, equals(2));
      expect(errorRecoveryManager.getErrorHistory().length, equals(1));
    });

    test('getErrorStatistics returns correct counts', () async {
      errorRecoveryManager.initialize();

      try {
        await errorRecoveryManager.executeWithRecovery(
          'stats_test_1',
          () async => throw const FormatException('Format Error'),
          maxRetries: 0,
        );
      } catch (_) {}

      try {
        await errorRecoveryManager.executeWithRecovery(
          'stats_test_2',
          () async => throw const FormatException('Format Error 2'),
          maxRetries: 0,
        );
      } catch (_) {}

      try {
        await errorRecoveryManager.executeWithRecovery(
          'stats_test_3',
          () async => throw TimeoutException('Timeout'),
          maxRetries: 0,
        );
      } catch (_) {}

      final stats = errorRecoveryManager.getErrorStatistics();
      expect(
          stats['FormatException'],
          equals(
              2)); // FormatException is likely caught as Exception or its runtime type
      expect(stats['TimeoutException'], equals(1));
    });
  });
}
