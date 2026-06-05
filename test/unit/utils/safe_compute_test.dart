import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/safe_compute.dart';

String _testComputeFunc(String message) {
  return message.toUpperCase();
}

String _timeoutComputeFunc(String message) {
  sleep(const Duration(seconds: 2));
  return message;
}

void _testIsolateEntryPoint(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    sendPort.send(message);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SafeCompute Tests', () {
    test('run returns expected result', () async {
      final result = await SafeCompute.run<String, String>(
        _testComputeFunc,
        'hello',
      );
      expect(result, 'HELLO');
    });

    test('run handles timeout and returns fallback', () async {
      final result = await SafeCompute.run<String, String>(
        _timeoutComputeFunc,
        'hello',
        timeout: const Duration(milliseconds: 100),
        fallbackValue: 'TIMEOUT_FALLBACK',
      );
      expect(result, 'TIMEOUT_FALLBACK');
    });

    test('runMultiple executes correctly', () async {
      final ops = [
        const ComputeOperation<String, String>(
          callback: _testComputeFunc,
          message: 'a',
        ),
        const ComputeOperation<String, String>(
          callback: _testComputeFunc,
          message: 'b',
        ),
      ];

      final results = await SafeCompute.runMultiple<String, String>(ops);
      expect(results.length, 2);
      expect(results, ['A', 'B']);
    });

    test('createIsolate lifecycle: send, messages, kill, isKilled', () async {
      final isolate = await SafeCompute.createIsolate(_testIsolateEntryPoint);
      expect(isolate, isNotNull);

      final completer = Completer<String>();
      SendPort? childSendPort;

      final sub = isolate!.messages.listen((msg) {
        if (msg is SendPort) {
          childSendPort = msg;
          childSendPort?.send('Test send');
        } else if (msg == 'Test send') {
          if (!completer.isCompleted) {
            completer.complete(msg as String);
          }
        }
      });

      final response = await completer.future;
      expect(response, 'Test send');

      expect(isolate.isKilled, isFalse);
      isolate.kill();
      expect(isolate.isKilled, isTrue);

      await sub.cancel();
    });
  });

  group('CommonSafeCompute Tests', () {
    test('encodeJson correctly serializes simple Map', () async {
      final data = {'key': 'value', 'num': 1};
      final result = await CommonSafeCompute.encodeJson(data);
      expect(result, '{"key":"value","num":1}');
    });

    test('decodeJson correctly deserializes simple JSON string', () async {
      final jsonStr = '{"key":"value","num":1}';
      final result = await CommonSafeCompute.decodeJson(jsonStr);
      expect(result, {'key': 'value', 'num': 1});
    });

    test('processLargeFile returns without throwing error', () async {
      final result = await CommonSafeCompute.processLargeFile('dummy_path.txt');
      expect(result, isNotNull);
      expect(result, isA<List<int>>());
    }, skip: '待实现真实文件读取与处理逻辑，避免虚假覆盖率');
  });
}
