import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/excerpt_intent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.shangjin.thoughtecho/excerpt_intent');
  final calls = <String>[];
  String? pendingText;

  setUp(() {
    calls.clear();
    pendingText = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          if (methodCall.method == 'setExcerptEntryEnabled') {
            calls.add('${methodCall.method}:${methodCall.arguments}');
            return null;
          }

          calls.add(methodCall.method);
          if (methodCall.method == 'consumePendingExcerptText') {
            final value = pendingText;
            pendingText = null;
            return value;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ExcerptIntentService', () {
    const service = ExcerptIntentService();

    test('returns pending excerpt text and drains native queue', () async {
      pendingText = '摘录内容';

      final first = await service.consumePendingExcerptText();
      final second = await service.consumePendingExcerptText();

      expect(first, '摘录内容');
      expect(second, isNull);
      expect(calls, ['consumePendingExcerptText', 'consumePendingExcerptText']);
    });

    test('trims pending excerpt text', () async {
      pendingText = '  一段来自浏览器的文字  ';

      final result = await service.consumePendingExcerptText();

      expect(result, '一段来自浏览器的文字');
    });

    test('ignores blank excerpt text', () async {
      pendingText = '   ';

      final result = await service.consumePendingExcerptText();

      expect(result, isNull);
    });

    test('syncs Android excerpt entry point enabled state', () async {
      await service.syncEntryPointEnabled(true);
      await service.syncEntryPointEnabled(false);

      expect(
        calls,
        containsAll([
          'setExcerptEntryEnabled:true',
          'setExcerptEntryEnabled:false',
        ]),
      );
    });
  });
}
