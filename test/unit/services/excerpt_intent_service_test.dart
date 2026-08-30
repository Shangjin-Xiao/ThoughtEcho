import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/excerpt_intent_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

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
    late _RecordingLogService logService;

    setUp(() {
      logService = _RecordingLogService();
      AppLogger.serviceForTesting = logService;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    tearDown(() {
      AppLogger.initialize();
    });

    test('两个方法都吞掉 MissingPluginException 并记录 debug 而不向 error 记录', () async {
      // 平台判断之后还撞上，说明是 Android 侧注册时机的问题（例如引擎重建）。
      // 仍然要能安全降级：调用方不该因此崩，且只记 debug，不当作 error 上报 Sentry。
      expect(await service.consumePendingExcerptText(), isNull);
      await expectLater(service.syncEntryPointEnabled(true), completes);

      final debugLogs = logService.records
          .where((r) => r.level == UnifiedLogLevel.debug)
          .toList();
      final errorLogs = logService.records
          .where((r) => r.level == UnifiedLogLevel.error)
          .toList();

      expect(errorLogs, isEmpty);
      expect(debugLogs.length, 2);
      expect(
        debugLogs[0].message,
        contains('ExcerptIntentService.consumePendingExcerptText 未找到原生实现'),
      );
      expect(
        debugLogs[1].message,
        contains('ExcerptIntentService.syncEntryPointEnabled 未找到原生实现'),
      );
    });
  });
}

class _RecordingLogService implements UnifiedLogService {
  final List<
      ({
        UnifiedLogLevel level,
        String message,
        String? source,
        Object? error
      })> records = [];

  @override
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.verbose,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.debug,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.info,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.warning,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.error,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void log(
    UnifiedLogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    records.add((level: level, message: message, source: source, error: error));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
