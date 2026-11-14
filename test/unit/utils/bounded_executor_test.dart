import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/bounded_executor.dart';

void main() {
  group('BoundedExecutor', () {
    test('空列表立即返回空结果', () async {
      final executor = BoundedExecutor(maxConcurrency: 4);
      final results =
          await executor.map<int, int>([], (item) async => item * 2);
      expect(results, isEmpty);
    });

    test('元素少于最大并发数时正确执行', () async {
      final executor = BoundedExecutor(maxConcurrency: 4);
      final results = await executor.map<int, int>([1, 2], (item) async {
        await Future.delayed(const Duration(milliseconds: 10));
        return item * 10;
      });
      expect(results, equals([10, 20]));
    });

    test('并发执行严格限制在 maxConcurrency 上限以内', () async {
      final executor = BoundedExecutor(maxConcurrency: 4);
      const totalItems = 20;
      var activeCount = 0;
      var peakConcurrency = 0;

      final results = await executor.map<int, int>(
        List.generate(totalItems, (i) => i),
        (item) async {
          activeCount++;
          if (activeCount > peakConcurrency) {
            peakConcurrency = activeCount;
          }
          await Future.delayed(const Duration(milliseconds: 15));
          activeCount--;
          return item * 2;
        },
      );

      expect(results.length, equals(totalItems));
      for (var i = 0; i < totalItems; i++) {
        expect(results[i], equals(i * 2));
      }
      expect(peakConcurrency, equals(4));
    });

    test('单个任务发生异常时隔离错误且不阻断同批次任务完成', () async {
      final executor = BoundedExecutor(maxConcurrency: 4);
      const totalItems = 10;
      final completed = <int>[];

      final results = await executor.map<int, String>(
        List.generate(totalItems, (i) => i),
        (item) async {
          if (item == 3) {
            throw Exception('Item 3 failed');
          }
          await Future.delayed(const Duration(milliseconds: 10));
          completed.add(item);
          return 'item_$item';
        }.catchExceptionSafe,
      );

      expect(results[3], equals('failed'));
      expect(completed.length, equals(9));
      expect(completed.contains(3), isFalse);
    });
  });
}

extension on Future<String> Function(int) {
  Future<String> Function(int) get catchExceptionSafe => (item) async {
        try {
          return await this(item);
        } catch (_) {
          return 'failed';
        }
      };
}
