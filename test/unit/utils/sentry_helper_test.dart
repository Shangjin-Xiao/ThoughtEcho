// ignore_for_file: experimental_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:thoughtecho/utils/app_tracer.dart';
import 'package:thoughtecho/utils/sentry_helper.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('Sentry minimal collection options', () {
    test('disables sensitive and high-overhead collection', () {
      final options = SentryFlutterOptions();

      configureSentryOptions(options);

      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.attachViewHierarchy, isFalse);
      expect(options.enableAutoSessionTracking, isFalse);
      expect(options.enablePrintBreadcrumbs, isFalse);
      expect(options.enableUserInteractionBreadcrumbs, isFalse);
      expect(options.enableUserInteractionTracing, isFalse);
      expect(options.enableAutoPerformanceTracing, isTrue);
      expect(options.tracesSampleRate, equals(1.0));
    });

    test('enables CPU profiling for sampled transactions', () {
      final options = SentryFlutterOptions();

      configureSentryOptions(options);

      // SDK 只在 iOS/macOS 真正启动 profiler，这里只保证采样率开着 ——
      // 关掉它记录页滚动就再也拿不到 CPU profile。
      expect(options.profilesSampleRate, equals(1.0));
    });
  });

  group('Sentry database privacy', () {
    test('removes local paths from database descriptions', () {
      const privatePath = '/Users/private/Documents/ThoughtEcho/quotes.db';
      const longSql = '''
INSERT OR REPLACE INTO app_logs (timestamp, level, message, source, error, stack_trace) VALUES (?, ?, ?, ?, NULL, NULL)
INSERT OR REPLACE INTO app_logs (timestamp, level, message, source, error, stack_trace) VALUES (?, ?, ?, ?, NULL, NULL)
''';

      expect(
        sanitizeSentryDatabaseDescription('Transaction DB: $privatePath'),
        'Transaction DB: main',
      );
      expect(
        sanitizeSentryDatabaseDescription('Close DB: $privatePath'),
        'Close DB: main',
      );
      expect(
        sanitizeSentryDatabaseDescription('SELECT * FROM quotes'),
        'SELECT FROM QUOTES',
      );
      expect(
        sanitizeSentryDatabaseDescription(longSql),
        'Log database write',
      );
      expect(
        sanitizeSentryDatabaseDescription('INSERT INTO APP_LOGS VALUES (?)'),
        'Log database write',
      );
      expect(
        sanitizeSentrySpanDescription(
          'GET\t https://example.com/path?api_key=secret#private',
        ),
        'GET https://example.com/path',
      );
    });

    test('removes sensitive and bulky transaction span data', () async {
      final mockTransport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://public@example.com/1';
        options.transport = mockTransport;
        options.tracesSampleRate = 1.0;
        options.beforeSendTransaction = sanitizeSentryTransaction;
      });

      try {
        final transaction = Sentry.startTransaction('root /', 'ui.load');
        final httpSpan = transaction.startChild(
          'http.client',
          description: 'GET https://example.com/path?api_key=secret#private',
        );
        httpSpan
          ..setData('url', 'https://example.com/path?api_key=secret#private')
          ..setData('http.query', 'api_key=secret')
          ..setData('http.fragment', 'private');
        await httpSpan.finish();
        final sqlSpan = transaction.startChild(
          'db.sql.query',
          description: 'SELECT * FROM quotes WHERE content LIKE ?',
        );
        await sqlSpan.finish();
        final logSpan = transaction.startChild(
          'db',
          description: '''
INSERT OR REPLACE INTO app_logs (timestamp, level, message, source, error, stack_trace) VALUES (?, ?, ?, ?, NULL, NULL)
INSERT OR REPLACE INTO app_logs (timestamp, level, message, source, error, stack_trace) VALUES (?, ?, ?, ?, NULL, NULL)
''',
        );
        await logSpan.finish();
        await transaction.finish();

        await Future<void>.delayed(const Duration(milliseconds: 200));

        final sentryTransaction = mockTransport.envelopes
            .expand((envelope) => envelope.items)
            .map((item) => item.originalObject)
            .whereType<SentryTransaction>()
            .single;
        final httpTransactionSpan = sentryTransaction.spans.singleWhere(
          (span) => span.context.operation == 'http.client',
        );
        final sqlTransactionSpan = sentryTransaction.spans.singleWhere(
          (span) => span.context.operation == 'db.sql.query',
        );
        final logTransactionSpan = sentryTransaction.spans.singleWhere(
          (span) => span.context.operation == 'db',
        );

        expect(
          httpTransactionSpan.context.description,
          'GET https://example.com/path',
        );
        expect(httpTransactionSpan.data['url'], 'https://example.com/path');
        expect(httpTransactionSpan.data, isNot(contains('http.query')));
        expect(httpTransactionSpan.data, isNot(contains('http.fragment')));
        expect(sqlTransactionSpan.context.description, 'SELECT FROM QUOTES');
        expect(logTransactionSpan.context.description, 'Log database write');
      } finally {
        await Sentry.close();
      }
    });

    test('drops smooth scroll sessions but keeps janky ones', () async {
      final mockTransport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://public@example.com/1';
        options.transport = mockTransport;
        options.tracesSampleRate = 1.0;
        options.beforeSendTransaction = sanitizeSentryTransaction;
      });

      try {
        await _finishScrollSession(frameJank: 0, worstFrameMs: 5.5);
        await _finishScrollSession(frameJank: 2, worstFrameMs: 35.8);
        // 只坏了一帧，但坏到两帧预算以上，同样要留。
        await _finishScrollSession(frameJank: 0, worstFrameMs: 24.1);

        await Future<void>.delayed(const Duration(milliseconds: 200));

        final worstFrames = mockTransport.envelopes
            .expand((envelope) => envelope.items)
            .map((item) => item.originalObject)
            .whereType<SentryTransaction>()
            .where((transaction) =>
                transaction.transaction == scrollSessionTraceName)
            .map((transaction) => transaction.spans
                .singleWhere((span) =>
                    span.context.description == scrollSessionFinalizeTraceName)
                .data['worstFrameMs'])
            .toList();

        expect(worstFrames, unorderedEquals(<Object?>[35.8, 24.1]));
      } finally {
        await Sentry.close();
      }
    });

    test('keeps a scroll session that never reached its finalize mark',
        () async {
      final mockTransport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://public@example.com/1';
        options.transport = mockTransport;
        options.tracesSampleRate = 1.0;
        options.beforeSendTransaction = sanitizeSentryTransaction;
      });

      try {
        // 没有收尾地标 = 会话被下一次滚动顶掉或页面被销毁，异常路径要看得见。
        final transaction =
            Sentry.startTransaction(scrollSessionTraceName, 'ui.scroll');
        await transaction.finish();

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          mockTransport.envelopes
              .expand((envelope) => envelope.items)
              .map((item) => item.originalObject)
              .whereType<SentryTransaction>()
              .where((t) => t.transaction == scrollSessionTraceName),
          hasLength(1),
        );
      } finally {
        await Sentry.close();
      }
    });

    test('scroll session stays a root transaction under an open route trace',
        () async {
      final mockTransport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://public@example.com/1';
        options.transport = mockTransport;
        options.tracesSampleRate = 1.0;
        options.beforeSendTransaction = sanitizeSentryTransaction;
      });

      try {
        // 冷启动进记录页时 SentryNavigatorObserver 的路由事务还开着并绑在作用域上。
        final route = Sentry.startTransaction(
          'route /notes',
          'ui.load',
          bindToScope: true,
        );

        final scroll = AppTracer.start(
          scrollSessionTraceName,
          operation: 'ui.scroll',
          forceRootTransaction: true,
        );
        scroll.instant(scrollSessionFinalizeTraceName, arguments: {
          'frameJank': 3,
          'budgetMs': 8.333,
          'worstFrameMs': 35.8,
        });
        scroll.finish();

        // 强开根事务不能把路由事务的作用域绑定顶掉，否则它剩下的子 span 挂不上去。
        expect(Sentry.getSpan(), same(route));
        final afterScroll = route.startChild('db', description: 'SELECT');
        await afterScroll.finish();
        await route.finish();

        await Future<void>.delayed(const Duration(milliseconds: 200));

        final transactions = mockTransport.envelopes
            .expand((envelope) => envelope.items)
            .map((item) => item.originalObject)
            .whereType<SentryTransaction>()
            .toList();

        // 滚动会话必须是**自己**的一条事务，否则 CPU profile 和卡顿筛选都拿不到它。
        expect(
          transactions.where((t) => t.transaction == scrollSessionTraceName),
          hasLength(1),
        );
        final routeTransaction =
            transactions.singleWhere((t) => t.transaction == 'route /notes');
        expect(
          routeTransaction.spans.map((span) => span.context.operation),
          contains('db'),
        );
      } finally {
        await Sentry.close();
      }
    });

    test('removes local paths from database breadcrumbs', () {
      const privatePath = '/Users/private/Documents/ThoughtEcho/quotes.db';
      final breadcrumb = Breadcrumb(
        message: 'Close DB: $privatePath',
        category: 'db',
      );

      final sanitized = sanitizeSentryBreadcrumb(breadcrumb, Hint());

      expect(sanitized?.message, 'Close DB: main');
      expect(sanitized?.message, isNot(contains(privatePath)));
    });

    test('removes HTTP query parameters and fragments from breadcrumbs', () {
      final breadcrumb = Breadcrumb.http(
        url: Uri.parse('https://example.com/path'),
        method: 'GET',
        httpQuery: 'api_key=secret',
        httpFragment: 'private',
      );

      final sanitized = sanitizeSentryBreadcrumb(breadcrumb, Hint());

      expect(sanitized?.data, isNot(contains('http.query')));
      expect(sanitized?.data, isNot(contains('http.fragment')));
    });

    test('removes sensitive HTTP request context from error events', () {
      final event = SentryEvent(
        request: SentryRequest(
          url: 'https://example.com/path?api_key=secret#private',
          method: 'GET',
          queryString: 'api_key=secret',
          cookies: 'session=secret',
          data: const {'note': 'private'},
          headers: const {'authorization': 'secret'},
        ),
      );

      final sanitized = sanitizeSentryEvent(event, Hint());

      expect(sanitized?.request?.url, 'https://example.com/path');
      expect(sanitized?.request?.queryString, isNull);
      expect(sanitized?.request?.fragment, isNull);
      expect(sanitized?.request?.cookies, isNull);
      expect(sanitized?.request?.data, isNull);
      expect(sanitized?.request?.headers, isEmpty);
    });
  });
}

/// 造一个和 `note_list_scroll.dart` 收尾时形状一致的滚动会话事务。
Future<void> _finishScrollSession({
  required int frameJank,
  required double worstFrameMs,
}) async {
  final transaction =
      Sentry.startTransaction(scrollSessionTraceName, 'ui.scroll');
  final mark = transaction.startChild(
    'mark',
    description: scrollSessionFinalizeTraceName,
  );
  mark
    ..setData('frameJank', frameJank)
    ..setData('budgetMs', 8.333)
    ..setData('worstFrameMs', worstFrameMs);
  await mark.finish();
  await transaction.finish();
}

class _MockSentryTransport implements Transport {
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return SentryId.newId();
  }
}
