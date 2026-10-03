import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
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

    test(
        'executeWithRecovery rethrows the original error when the recovery strategy fails',
        () async {
      errorRecoveryManager.initialize();
      final failingStrategy = FailingCustomStrategy();

      int attemptCount = 0;
      // The strategy's own exception is swallowed; the operation error must surface
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
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(
            contains('Operation error'),
            isNot(contains('策略恢复失败')),
          ),
        )),
      );

      expect(attemptCount, equals(2));
    });

    test('getErrorHistory limit returns the most recent errors', () async {
      errorRecoveryManager.initialize();
      errorRecoveryManager.clearErrorHistory();

      for (int i = 0; i < 3; i++) {
        try {
          await errorRecoveryManager.executeWithRecovery(
            'history_op_$i',
            () async => throw Exception('Err $i'),
            maxRetries: 0,
          );
        } catch (_) {}
      }

      expect(
        errorRecoveryManager
            .getErrorHistory()
            .map((r) => r.operationName)
            .toList(),
        equals(['history_op_0', 'history_op_1', 'history_op_2']),
      );
      expect(
        errorRecoveryManager
            .getErrorHistory(limit: 2)
            .map((r) => r.operationName)
            .toList(),
        equals(['history_op_1', 'history_op_2']),
      );
    });

    test('enforces maximum error history capacity limit of 100 entries',
        () async {
      errorRecoveryManager.initialize();
      errorRecoveryManager.clearErrorHistory();

      // Trigger 105 errors
      for (int i = 0; i < 105; i++) {
        try {
          await errorRecoveryManager.executeWithRecovery(
            'op_$i',
            () async => throw Exception('error_$i'),
            maxRetries: 0,
          );
        } catch (_) {}
      }

      final history = errorRecoveryManager.getErrorHistory();
      expect(history.length, equals(100));
      // First 5 (op_0 .. op_4) should have been evicted; earliest remaining is op_5
      expect(history.first.operationName, equals('op_5'));
      expect(history.last.operationName, equals('op_104'));
    });

    test('ErrorRecord properties and getters expose expected metadata', () {
      final now = DateTime.now();
      final record = ErrorRecord(
        operationName: 'test_op',
        error: const FormatException('Invalid JSON payload'),
        stackTrace: StackTrace.current,
        timestamp: now,
        attemptCount: 2,
        context: {'key': 'val'},
      );

      expect(record.operationName, equals('test_op'));
      expect(record.error, isA<FormatException>());
      expect(record.errorType, equals('FormatException'));
      expect(record.errorMessage, contains('Invalid JSON payload'));
      expect(record.attemptCount, equals(2));
      expect(record.context['key'], equals('val'));
      expect(record.timestamp, equals(now));
    });

    test('RecoveryAttempt calculates duration and tracks state', () {
      final start = DateTime(2026, 1, 1, 12, 0, 0);
      final end = DateTime(2026, 1, 1, 12, 0, 5);
      final record = ErrorRecord(
        operationName: 'op',
        error: Exception('err'),
        stackTrace: StackTrace.current,
        timestamp: start,
        attemptCount: 1,
        context: {},
      );
      final attempt = RecoveryAttempt(
        id: 'attempt_1',
        operationId: 'op_id_1',
        errorRecord: record,
        strategy: TestCustomStrategy(),
        startTime: start,
      );

      expect(attempt.duration, isNull);
      expect(attempt.isSuccessful, isFalse);

      attempt.endTime = end;
      attempt.isSuccessful = true;

      expect(attempt.duration, equals(const Duration(seconds: 5)));
      expect(attempt.isSuccessful, isTrue);
    });

    test(
        'default recovery strategy classes execute directly and report correct names',
        () {
      fakeAsync((async) {
        final dummyRecord = ErrorRecord(
          operationName: 'test',
          error: Exception('test'),
          stackTrace: StackTrace.current,
          timestamp: DateTime.now(),
          attemptCount: 1,
          context: {},
        );

        final memory = MemoryRecoveryStrategy();
        expect(memory.name, equals('内存恢复策略'));
        memory.recover(dummyRecord);
        async.elapse(const Duration(milliseconds: 1500));

        final fileSystem = FileSystemRecoveryStrategy();
        expect(fileSystem.name, equals('文件系统恢复策略'));
        fileSystem.recover(dummyRecord);
        async.elapse(const Duration(milliseconds: 100));

        final timeout = TimeoutRecoveryStrategy();
        expect(timeout.name, equals('超时恢复策略'));
        timeout.recover(dummyRecord);
        async.elapse(const Duration(seconds: 3));

        final network = NetworkRecoveryStrategy();
        expect(network.name, equals('网络恢复策略'));
        network.recover(dummyRecord);
        async.elapse(const Duration(seconds: 4));

        final generic = GenericRecoveryStrategy();
        expect(generic.name, equals('通用恢复策略'));
        generic.recover(dummyRecord);
        async.elapse(const Duration(milliseconds: 600));
      });
    });
  });
}
