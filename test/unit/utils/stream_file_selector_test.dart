import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/stream_file_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StreamFileSelector', () {
    const channel = MethodChannel('thoughtecho/file_selector');

    setUp(() {
      StreamFileSelector.disableNativeSelector();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      StreamFileSelector.disableNativeSelector();
    });

    test('enableNativeSelector should set _useNativeSelector to true',
        () async {
      StreamFileSelector.enableNativeSelector();
      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isTrue);
    });

    test('disableNativeSelector should set _useNativeSelector to false',
        () async {
      StreamFileSelector.enableNativeSelector();
      StreamFileSelector.disableNativeSelector();
      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });

    test(
        'isNativeFileSelectorAvailable should return false if useNativeSelector is false',
        () async {
      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });

    test('isNativeFileSelectorAvailable should handle timeout gracefully',
        () async {
      StreamFileSelector.enableNativeSelector();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          // 模拟超时
          await Future.delayed(const Duration(milliseconds: 2100));
          return true;
        }
        return null;
      });

      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });

    test('isNativeFileSelectorAvailable should handle exception gracefully',
        () async {
      StreamFileSelector.enableNativeSelector();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          throw Exception('Method call failed');
        }
        return null;
      });

      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });
  });
}
