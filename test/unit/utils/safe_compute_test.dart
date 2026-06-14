import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/safe_compute.dart';

// 简单的测试函数，模拟正常计算
String _normalCompute(String message) {
  return 'Processed: $message';
}

// 模拟抛出异常
String _throwExceptionCompute(String message) {
  throw Exception('Test Exception: $message');
}

// 模拟长时间运行（可能导致超时）
Future<String> _timeoutCompute(String message) async {
  // 注意：在实际的 compute 中可能不支持异步函数，但由于 SafeCompute
  // 接受 ComputeCallback<Q, R>（typedef R ComputeCallback<Q, R>(Q message)）
  // 它的类型签名通常是同步的。但为了测试，我们可以提供一个长循环或者延迟。
  // 因为隔离区代码必须是顶层函数，我们这里做简单的循环模拟耗时（但在 Flutter Test 环境里 compute 会直接运行同步或真实 isolate）。
  int sum = 0;
  for (int i = 0; i < 100000000; i++) {
    sum += i;
  }
  return 'Done $sum';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SafeCompute', () {
    test('run should complete successfully', () async {
      final result = await SafeCompute.run<String, String>(
        _normalCompute,
        'hello',
      );
      expect(result, 'Processed: hello');
    });

    test('run should fallback on exception', () async {
      final result = await SafeCompute.run<String, String>(
        _throwExceptionCompute,
        'error',
        fallbackValue: 'fallback',
      );
      expect(result, 'fallback');
    });

    // Timeout 测试在真实 compute 环境下比较难通过时间准确触发，但可以提供较短超时来验证
    test('run should fallback on timeout', () async {
      final result = await SafeCompute.run<String, String>(
        _timeoutCompute,
        'timeout_test',
        timeout: const Duration(microseconds: 1), // 极短超时
        fallbackValue: 'fallback_timeout',
      );

      // 测试需要明确地保证触发了回退以覆盖超时逻辑路径。
      // 必须严格检查我们仅收到了后备值。
      expect(result, equals('fallback_timeout'));
    });

    test('runMultiple should execute and handle mixed results', () async {
      final operations = [
        ComputeOperation<String, String>(
            callback: _normalCompute, message: 'op1'),
        ComputeOperation<String, String>(
            callback: _throwExceptionCompute,
            message: 'op2',
            fallbackValue: 'fallback_op2'),
        ComputeOperation<String, String>(
            callback: _normalCompute, message: 'op3'),
      ];

      final results = await SafeCompute.runMultiple(operations);

      expect(results.length, 3);
      expect(results[0], 'Processed: op1');
      expect(results[1], 'fallback_op2');
      expect(results[2], 'Processed: op3');
    });
  });

  group('CommonSafeCompute', () {
    test('encodeJson should encode data correctly', () async {
      final data = {'key': 'value', 'num': 123};
      final result = await CommonSafeCompute.encodeJson(data);

      expect(result, isNotNull);
      expect(result!.contains('"key":"value"'), isTrue);
      expect(result.contains('"num":123'), isTrue);
    });

    test('decodeJson should decode json string correctly', () async {
      const jsonString = '{"key":"value","num":123}';
      final result = await CommonSafeCompute.decodeJson(jsonString);

      expect(result, isNotNull);
      expect(result!['key'], 'value');
      expect(result['num'], 123);
    });

    test('decodeJson should return null on invalid string (fallback)',
        () async {
      const invalidJsonString = '{invalid_json}';
      final result = await CommonSafeCompute.decodeJson(invalidJsonString);

      expect(result, isNull);
    });
  });
}
