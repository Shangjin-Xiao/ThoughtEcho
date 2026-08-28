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
    // 显式声明「这是支持的平台」：默认判据是 Platform.isAndroid，而测试跑在
    // 宿主机上，不注入的话下面每条都会走提前返回、一个 channel 调用都发不出去。
    const service = ExcerptIntentService(supported: true);

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

  group('不支持的平台一个 channel 调用都不发', () {
    // 「摘录到心迹」的原生实现只在 MainActivity.kt 里，iOS 的 AppDelegate.swift
    // 没有注册这个 channel。不判平台的话，iOS 每次进主页都会撞一次
    // MissingPluginException 并按 ERROR 记进日志、上报到 Sentry ——
    // 2026-08-28 的 iPad 日志里一条 trace 就带了 6 条。
    const service = ExcerptIntentService(supported: false);

    test('consumePendingExcerptText 直接返回 null', () async {
      pendingText = '不该被读到';

      expect(await service.consumePendingExcerptText(), isNull);
      expect(calls, isEmpty);
    });

    test('syncEntryPointEnabled 静默跳过', () async {
      await service.syncEntryPointEnabled(true);

      expect(calls, isEmpty);
    });
  });

  group('原生实现缺失时不当成错误', () {
    const service = ExcerptIntentService(supported: true);

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('两个方法都吞掉 MissingPluginException 而不是抛出去', () async {
      // 平台判断之后还撞上，说明是 Android 侧注册时机的问题（例如引擎重建）。
      // 仍然要能安全降级：调用方不该因此崩，也不该被当成错误上报。
      expect(await service.consumePendingExcerptText(), isNull);
      await expectLater(service.syncEntryPointEnabled(true), completes);
    });
  });
}
