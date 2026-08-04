import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/deferred_error_buffer.dart';

void main() {
  setUp(() {
    // 确保每次测试前清空状态
    getAndClearDeferredErrors();
  });

  group('DeferredErrorBuffer Tests', () {
    test('初始状态应为空', () {
      final errors = getAndClearDeferredErrors();
      expect(errors, isEmpty);
    });

    test('可以添加单个错误并获取', () {
      final error = {'error': 'Test error 1', 'stackTrace': 'stack 1'};
      addDeferredError(error);

      final errors = getAndClearDeferredErrors();
      expect(errors.length, 1);
      expect(errors.first, equals(error));
    });

    test('获取错误后应清空缓冲区', () {
      addDeferredError({'error': 'Test error 2'});

      // 第一次获取应该有数据
      expect(getAndClearDeferredErrors().length, 1);

      // 第二次获取应该为空
      expect(getAndClearDeferredErrors(), isEmpty);
    });

    test('最多保留 100 条记录，超出会移除最老的记录', () {
      // 插入 105 条错误记录
      for (var i = 0; i < 105; i++) {
        addDeferredError({'index': i});
      }

      final errors = getAndClearDeferredErrors();

      // 应该只有最后 100 条
      expect(errors.length, 100);
      // 第一条应该是 index = 5 (最老的 0-4 被移除了)
      expect(errors.first['index'], 5);
      // 最后一条应该是 index = 104
      expect(errors.last['index'], 104);
    });
  });
}
