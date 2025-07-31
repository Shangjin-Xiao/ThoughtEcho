import 'package:test/test.dart';
import 'package:common/util/sleep.dart';
import 'package:common/util/task_runner.dart';

void main() {
  group('TaskRunner', () {
    test('should run all tasks in parallel', () async {
      final results = TaskRunner<String?>(
        concurrency: 10,
        initialTasks: [
          for (final data in [
            [10, null],
            [30, 'a'],
            [20, 'b'],
            [40, 'c']
          ])
            () async {
              final delay = data[0] as int;
              final result = data[1] as String?;
              await sleepAsync(delay);
              return result;
            },
        ],
      ).stream;

      String? finalResult;

      await results.forEach((result) {
        if (finalResult == null && result != null) {
          finalResult = result;
        }
      });

      expect(finalResult, 'b');
    });

    test('should handle empty initial tasks', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 5,
        initialTasks: [],
      );

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, isEmpty);
    });

    test('should handle single task', () async {
      final taskRunner = TaskRunner<String>(
        concurrency: 1,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 'single_result';
          }
        ],
      );

      final results = <String>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, equals(['single_result']));
    });

    test('should respect concurrency limit', () async {
      final concurrency = 2;
      var concurrentCount = 0;
      var maxConcurrentCount = 0;
      final taskRunner = TaskRunner<int>(
        concurrency: concurrency,
        initialTasks: [
          for (int i = 0; i < 5; i++)
            () async {
              concurrentCount++;
              maxConcurrentCount = maxConcurrentCount > concurrentCount 
                  ? maxConcurrentCount 
                  : concurrentCount;
              await sleepAsync(50);
              concurrentCount--;
              return i;
            }
        ],
      );

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(maxConcurrentCount, lessThanOrEqualTo(concurrency));
      expect(results.length, equals(5));
    });

    test('should handle null initial tasks', () async {
      final taskRunner = TaskRunner<String>(
        concurrency: 2,
        initialTasks: null,
      );

      final results = <String>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, isEmpty);
    });

    test('should handle tasks that throw exceptions', () async {
      final taskRunner = TaskRunner<String>(
        concurrency: 3,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 'success1';
          },
          () async {
            await sleepAsync(5);
            throw Exception('Test error');
          },
          () async {
            await sleepAsync(15);
            return 'success2';
          },
        ],
      );

      final results = <String>[];
      bool exceptionCaught = false;

      try {
        await taskRunner.stream.forEach((result) {
          results.add(result);
        });
      } catch (e) {
        exceptionCaught = true;
      }

      // TaskRunner should propagate exceptions
      expect(exceptionCaught, isTrue);
    });

    test('should handle addAll method with new tasks', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 2,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 1;
          },
        ],
      );

      // Add more tasks after creation
      taskRunner.addAll([
        () async {
          await sleepAsync(5);
          return 2;
        },
        () async {
          await sleepAsync(15);
          return 3;
        },
      ]);

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(3));
      expect(results, containsAll([1, 2, 3]));
    });

    test('should handle stop method', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 1,
        initialTasks: [
          () async {
            await sleepAsync(50);
            return 1;
          },
          () async {
            await sleepAsync(50);
            return 2;
          },
        ],
      );

      final results = <int>[];
      
      // Start processing and stop immediately
      final streamSubscription = taskRunner.stream.listen((result) {
        results.add(result);
      });

      await sleepAsync(25); // Let first task start
      taskRunner.stop();
      
      await streamSubscription.asFuture();

      // Should have processed at least the first task but stopped before completing all
      expect(results, isNotEmpty);
    });

    test('should handle stayAlive parameter when true', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 1,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 1;
          },
        ],
        stayAlive: true,
      );

      final results = <int>[];
      final streamSubscription = taskRunner.stream.listen((result) {
        results.add(result);
      });

      await sleepAsync(50); // Wait for initial task to complete
      
      // Add more tasks after initial ones are done
      taskRunner.addAll([
        () async {
          await sleepAsync(10);
          return 2;
        },
      ]);

      await sleepAsync(50); // Wait for new task to complete
      
      await streamSubscription.cancel();

      expect(results, containsAll([1, 2]));
    });

    test('should handle onFinish callback', () async {
      bool onFinishCalled = false;
      
      final taskRunner = TaskRunner<int>(
        concurrency: 2,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 1;
          },
          () async {
            await sleepAsync(5);
            return 2;
          },
        ],
        onFinish: () {
          onFinishCalled = true;
        },
      );

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(2));
      expect(onFinishCalled, isTrue);
    });

    test('should handle zero concurrency', () async {
      final taskRunner = TaskRunner<String>(
        concurrency: 0,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 'test';
          }
        ],
      );

      final results = <String>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      // With zero concurrency, no tasks should execute
      expect(results, isEmpty);
    });

    test('should handle negative concurrency', () async {
      final taskRunner = TaskRunner<String>(
        concurrency: -1,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 'test';
          }
        ],
      );

      final results = <String>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      // With negative concurrency, no tasks should execute
      expect(results, isEmpty);
    });

    test('should handle immediate return tasks', () async {
      final taskRunner = TaskRunner<String>(
        concurrency: 3,
        initialTasks: [
          () async => 'immediate1',
          () async => 'immediate2',
          () async => 'immediate3',
        ],
      );

      final results = <String>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(3));
      expect(results, containsAll(['immediate1', 'immediate2', 'immediate3']));
    });

    test('should maintain parallel execution timing', () async {
      final stopwatch = Stopwatch()..start();
      
      final taskRunner = TaskRunner<int>(
        concurrency: 3,
        initialTasks: [
          () async {
            await sleepAsync(100);
            return 1;
          },
          () async {
            await sleepAsync(100);
            return 2;
          },
          () async {
            await sleepAsync(100);
            return 3;
          },
        ],
      );

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      stopwatch.stop();
      
      // If running in parallel, should take ~100ms, not ~300ms
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
      expect(results, hasLength(3));
    });

    test('should handle complex object types', () async {
      final complexObjects = [
        {'id': 1, 'name': 'Object 1'},
        {'id': 2, 'name': 'Object 2'},
        {'id': 3, 'name': 'Object 3'},
      ];

      final taskRunner = TaskRunner<Map<String, dynamic>>(
        concurrency: 2,
        initialTasks: [
          for (final obj in complexObjects)
            () async {
              await sleepAsync(10);
              return Map<String, dynamic>.from(obj);
            }
        ],
      );

      final results = <Map<String, dynamic>>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(3));
      expect(results.any((r) => r['name'] == 'Object 1'), isTrue);
      expect(results.any((r) => r['name'] == 'Object 2'), isTrue);
      expect(results.any((r) => r['name'] == 'Object 3'), isTrue);
    });

    test('should handle large number of tasks efficiently', () async {
      final numberOfTasks = 100;
      final taskRunner = TaskRunner<int>(
        concurrency: 10,
        initialTasks: [
          for (int i = 0; i < numberOfTasks; i++)
            () async {
              await sleepAsync(1);
              return i;
            }
        ],
      );

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(numberOfTasks));
      expect(results.toSet(), equals(Set.from(List.generate(numberOfTasks, (i) => i))));
    });

    test('should handle high concurrency limit', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 1000, // Very high concurrency
        initialTasks: [
          for (int i = 0; i < 10; i++)
            () async {
              await sleepAsync(10);
              return i;
            }
        ],
      );

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(10));
      expect(results.toSet(), equals(Set.from(List.generate(10, (i) => i))));
    });

    test('should handle boolean results correctly', () async {
      final taskRunner = TaskRunner<bool>(
        concurrency: 2,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return true;
          },
          () async {
            await sleepAsync(5);
            return false;
          },
        ],
      );

      final results = <bool>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(2));
      expect(results, contains(true));
      expect(results, contains(false));
    });

    test('should handle nullable types correctly', () async {
      final taskRunner = TaskRunner<String?>(
        concurrency: 2,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return null;
          },
          () async {
            await sleepAsync(5);
            return 'not_null';
          },
          () async {
            await sleepAsync(15);
            return null;
          },
        ],
      );

      final results = <String?>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(3));
      expect(results.where((r) => r == null), hasLength(2));
      expect(results, contains('not_null'));
    });

    test('should handle numeric types correctly', () async {
      final taskRunner = TaskRunner<num>(
        concurrency: 3,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 42;
          },
          () async {
            await sleepAsync(5);
            return 3.14;
          },
          () async {
            await sleepAsync(15);
            return -7.5;
          },
        ],
      );

      final results = <num>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(3));
      expect(results, containsAll([42, 3.14, -7.5]));
    });

    test('should handle empty addAll calls', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 2,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 1;
          },
        ],
      );

      // Add empty list
      taskRunner.addAll([]);

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, equals([1]));
    });

    test('should handle multiple addAll calls', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 2,
        initialTasks: [
          () async {
            await sleepAsync(10);
            return 1;
          },
        ],
      );

      // Add tasks in multiple batches
      taskRunner.addAll([
        () async {
          await sleepAsync(5);
          return 2;
        },
      ]);

      taskRunner.addAll([
        () async {
          await sleepAsync(15);
          return 3;
        },
        () async {
          await sleepAsync(20);
          return 4;
        },
      ]);

      final results = <int>[];
      await taskRunner.stream.forEach((result) {
        results.add(result);
      });

      expect(results, hasLength(4));
      expect(results, containsAll([1, 2, 3, 4]));
    });

    test('should handle stream cancellation gracefully', () async {
      final taskRunner = TaskRunner<int>(
        concurrency: 1,
        initialTasks: [
          () async {
            await sleepAsync(100);
            return 1;
          },
          () async {
            await sleepAsync(100);
            return 2;
          },
        ],
      );

      final results = <int>[];
      final subscription = taskRunner.stream.listen((result) {
        results.add(result);
      });

      await sleepAsync(50); // Let first task start
      await subscription.cancel(); // Cancel subscription

      // Results should be limited due to cancellation
      expect(results, hasLength(lessThanOrEqualTo(1)));
    });
  });
}
