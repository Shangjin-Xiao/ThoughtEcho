import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/error_recovery_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class TestCustomStrategy implements ErrorRecoveryStrategy {
  bool recovered = false;

  @override
  String get name => '测试自定义策略';

  @override
  Future<void> recover(ErrorRecord errorRecord) async {
    recovered = true;
  }
}

class FailingCustomStrategy implements ErrorRecoveryStrategy {
  @override
  String get name => '失败策略';

  @override
  Future<void> recover(ErrorRecord errorRecord) async {
    throw Exception('策略恢复失败');
  }
}

class CustomTestException implements Exception {
  final String message;
  CustomTestException(this.message);

  @override
  String toString() => 'CustomTestException: $message';
}

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
      expect(stats['FormatException'], equals(2));
      expect(stats['TimeoutException'], equals(1));
    });

    test('registerRecoveryStrategy and custom strategy usage', () async {
      errorRecoveryManager.initialize();
      final customStrategy = TestCustomStrategy();
      errorRecoveryManager.registerRecoveryStrategy(
        CustomTestException,
        customStrategy,
      );

      int attemptCount = 0;
      final result = await errorRecoveryManager.executeWithRecovery(
        'custom_strategy_test',
        () async {
          attemptCount++;
          if (attemptCount == 1) {
            throw CustomTestException('Custom Error');
          }
          return 'recovered';
        },
        maxRetries: 1,
        retryDelay: Duration.zero,
      );

      expect(result, equals('recovered'));
      expect(customStrategy.recovered, isTrue);
    });

    test('executeWithRecovery with customStrategy parameter', () async {
      errorRecoveryManager.initialize();
      final customStrategy = TestCustomStrategy();

      int attemptCount = 0;
      final result = await errorRecoveryManager.executeWithRecovery(
        'custom_param_test',
        () async {
          attemptCount++;
          if (attemptCount == 1) {
            throw Exception('Generic error with custom strategy param');
          }
          return 'recovered_param';
        },
        maxRetries: 1,
        retryDelay: Duration.zero,
        customStrategy: customStrategy,
      );

      expect(result, equals('recovered_param'));
      expect(customStrategy.recovered, isTrue);
    });

    test('executeWithRecovery handles strategy failure gracefully', () async {
      errorRecoveryManager.initialize();
      final failingStrategy = FailingCustomStrategy();

      int attemptCount = 0;
      await expectLater(
        () => errorRecoveryManager.executeWithRecovery(
          'failing_strategy_test',
          () async {
            attemptCount++;
            throw Exception('Operation error');
          },
          maxRetries: 1,
          retryDelay: Duration.zero,
          customStrategy: failingStrategy,
        ),
        throwsA(isA<Exception>()),
      );

      expect(attemptCount, equals(2));
    });

    test('getErrorHistory limit and maximum error history queue', () async {
      errorRecoveryManager.initialize();

      // Clear history first
      errorRecoveryManager.clearErrorHistory();

      // Add 105 errors to test max error history limit (100)
      for (int i = 0; i < 105; i++) {
        try {
          await errorRecoveryManager.executeWithRecovery(
            'overflow_op_$i',
            () async => throw Exception('Err $i'),
            maxRetries: 0,
          );
        } catch (_) {}
      }

      final fullHistory = errorRecoveryManager.getErrorHistory();
      expect(fullHistory.length, equals(100));
      expect(fullHistory.first.operationName, equals('overflow_op_5'));
      expect(fullHistory.last.operationName, equals('overflow_op_104'));

      final limitedHistory = errorRecoveryManager.getErrorHistory(limit: 10);
      expect(limitedHistory.length, equals(10));
      expect(limitedHistory.last.operationName, equals('overflow_op_104'));
    });

    test('ErrorRecord properties and methods', () {
      final record = ErrorRecord(
        operationName: 'test_op',
        error: const FormatException('Invalid format'),
        stackTrace: StackTrace.empty,
        timestamp: DateTime.now(),
        attemptCount: 1,
        context: {'key': 'value'},
      );

      expect(record.operationName, equals('test_op'));
      expect(record.errorType, equals('FormatException'));
      expect(record.errorMessage, contains('Invalid format'));
      expect(record.context['key'], equals('value'));
    });

    test('RecoveryAttempt duration calculation', () {
      final start = DateTime.now();
      final record = ErrorRecord(
        operationName: 'test_op',
        error: Exception('Test'),
        stackTrace: StackTrace.empty,
        timestamp: start,
        attemptCount: 1,
        context: {},
      );

      final attempt = RecoveryAttempt(
        id: 'rec_1',
        operationId: 'op_1',
        errorRecord: record,
        strategy: TestCustomStrategy(),
        startTime: start,
      );

      expect(attempt.duration, isNull);

      final end = start.add(const Duration(milliseconds: 250));
      attempt.endTime = end;
      expect(attempt.duration, equals(const Duration(milliseconds: 250)));
    });

    test('Default recovery strategies execution', () async {
      final record = ErrorRecord(
        operationName: 'test',
        error: Exception('test'),
        stackTrace: StackTrace.empty,
        timestamp: DateTime.now(),
        attemptCount: 1,
        context: {},
      );

      final memoryStrategy = MemoryRecoveryStrategy();
      expect(memoryStrategy.name, equals('内存恢复策略'));
      await memoryStrategy.recover(record);

      final fileSystemStrategy = FileSystemRecoveryStrategy();
      expect(fileSystemStrategy.name, equals('文件系统恢复策略'));
      await fileSystemStrategy.recover(record);

      final timeoutStrategy = TimeoutRecoveryStrategy();
      expect(timeoutStrategy.name, equals('超时恢复策略'));
      await timeoutStrategy.recover(record);

      final networkStrategy = NetworkRecoveryStrategy();
      expect(networkStrategy.name, equals('网络恢复策略'));
      await networkStrategy.recover(record);

      final genericStrategy = GenericRecoveryStrategy();
      expect(genericStrategy.name, equals('通用恢复策略'));
      await genericStrategy.recover(record);
    });
  });
}
