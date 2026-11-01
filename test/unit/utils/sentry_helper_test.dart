// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_dio/sentry_dio.dart';
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

  group('sanitizeSentryDatabaseDescription', () {
    test('handles database lifecycle prefixes', () {
      expect(
        sanitizeSentryDatabaseDescription('Open DB: /path/to/db.sqlite'),
        'Open DB: main',
      );
      expect(
        sanitizeSentryDatabaseDescription('Close DB: /path/to/db.sqlite'),
        'Close DB: main',
      );
      expect(
        sanitizeSentryDatabaseDescription('Transaction DB: /path/to/db.sqlite'),
        'Transaction DB: main',
      );
    });

    test('sanitizes app logs and log database operations', () {
      expect(
        sanitizeSentryDatabaseDescription(
            'INSERT INTO app_logs (id) VALUES (1)'),
        'Log database write',
      );
      expect(
        sanitizeSentryDatabaseDescription('SELECT * FROM LOG_DATABASE'),
        'Log database write',
      );
    });

    test('sanitizes standard SQL query patterns with table names', () {
      expect(
        sanitizeSentryDatabaseDescription(
            'SELECT id, content FROM notes WHERE id = 1'),
        'SELECT FROM NOTES',
      );
      expect(
        sanitizeSentryDatabaseDescription(
            'INSERT INTO user_profile (name) VALUES (?)'),
        'INSERT INTO USER_PROFILE',
      );
      expect(
        sanitizeSentryDatabaseDescription('UPDATE settings SET theme = "dark"'),
        'UPDATE SETTINGS',
      );
      expect(
        sanitizeSentryDatabaseDescription('DELETE FROM trash_bin WHERE id = ?'),
        'DELETE FROM TRASH_BIN',
      );
      expect(
        sanitizeSentryDatabaseDescription('CREATE TABLE items (id INT)'),
        'CREATE TABLE ITEMS',
      );
    });

    test('falls back to generic query description when table name is missing',
        () {
      expect(
        sanitizeSentryDatabaseDescription('SELECT (1)'),
        'SELECT query',
      );
      expect(
        sanitizeSentryDatabaseDescription('INSERT (1)'),
        'INSERT query',
      );
      expect(
        sanitizeSentryDatabaseDescription('UPDATE (1)'),
        'UPDATE query',
      );
      expect(
        sanitizeSentryDatabaseDescription('DELETE (1)'),
        'DELETE query',
      );
      expect(
        sanitizeSentryDatabaseDescription('CREATE (1)'),
        'CREATE query',
      );
    });

    test('sanitizes schema and pragma queries', () {
      expect(
        sanitizeSentryDatabaseDescription(
            'ALTER TABLE users ADD COLUMN age INT'),
        'SQL schema/pragma query',
      );
      expect(
        sanitizeSentryDatabaseDescription('DROP TABLE obsolete_data'),
        'SQL schema/pragma query',
      );
      expect(
        sanitizeSentryDatabaseDescription('PRAGMA foreign_keys = ON'),
        'SQL schema/pragma query',
      );
    });

    test('handles leading whitespace, mixed case, and unmatched descriptions',
        () {
      expect(
        sanitizeSentryDatabaseDescription('   SeLeCt * FrOm NoTeS'),
        'SELECT FROM NOTES',
      );
      expect(
        sanitizeSentryDatabaseDescription('Custom Non-SQL Operation'),
        'Custom Non-SQL Operation',
      );
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

    test(
        'sanitizes sensitive span data keys and cleans URLs while preserving metrics',
        () {
      final spanData = <String, dynamic>{
        'content': 'sensitive note content',
        'rawContent': 'some raw text',
        'note_content': 'user thoughts',
        'text': 'quote text',
        'noteText': 'additional note details',
        'query': 'SELECT * FROM private_notes',
        'search_query': 'user search query',
        'http.query': 'api_key=secret',
        'http.fragment': 'private_section',
        'title': 'Secret Title',
        'note_title': 'My Diary',
        'password': 'user_password_123',
        'token': 'bearer_token_abc',
        'secret': 'app_secret_xyz',
        'authorization': 'Bearer auth_token_secret',
        'api_key': 'key_secret',
        'apiKey': 'key_secret_camel',
        'credential': 'user_credentials',
        'frameJank': 2,
        'worstFrameMs': 33.3,
        'budgetMs': 16.6,
        'droppedFrames': 1,
        'frames': 60,
        'avgFrameMs': 12.5,
        'worstVsyncMs': 2.1,
        'mode': 'edit',
        'inset': 240,
        'index': 3,
        'contentLength': 140,
        'textLength': 80,
        'tagCount': 5,
        'diagnostic': 'FormatException: bad input string',
        'error_info': 'Error: failed to connect to host',
        'url': 'https://example.com/api/v1/notes?secret_token=123#frag',
        'endpoint': 'https://service.internal/path?auth=yes',
        'nestedData': <String, dynamic>{
          'content': 'nested sensitive content',
          'innerMetric': 42,
          'nestedUrl': 'https://api.example.com/endpoint?param=secret',
          'nestedDiagnostic': 'FormatException: invalid integer',
        },
        'complexList': <dynamic>[
          'https://api.example.com/item?api_key=secret#section',
          'FormatException: not a url',
          <String, dynamic>{
            'query': 'nested search query',
            'safeField': 'retained',
          },
          123,
          true,
        ],
        'deepNestedList': <dynamic>[
          <dynamic>[
            <String, dynamic>{
              'token': 'deeply_nested_token',
              'count': 7,
            },
          ],
        ],
        'unmodifiableMap': Map.unmodifiable(<String, dynamic>{
          'secret': 'unmodifiable_secret',
          'validKey': 'preserved',
        }),
        'unmodifiableList': List.unmodifiable(<dynamic>[
          'https://example.com/item?token=abc',
          'FormatException: unmodifiable item',
        ]),
        'nonStringKeyMap': <dynamic, dynamic>{
          101: 'numeric_id_val',
          true: 'boolean_key_val',
          'password': 'nested_pass_secret',
        },
      };

      final sanitized = sanitizeSpanData(spanData);

      // Sensitive fields must be removed
      expect(sanitized, isNot(contains('content')));
      expect(sanitized, isNot(contains('rawContent')));
      expect(sanitized, isNot(contains('note_content')));
      expect(sanitized, isNot(contains('text')));
      expect(sanitized, isNot(contains('noteText')));
      expect(sanitized, isNot(contains('query')));
      expect(sanitized, isNot(contains('search_query')));
      expect(sanitized, isNot(contains('http.query')));
      expect(sanitized, isNot(contains('http.fragment')));
      expect(sanitized, isNot(contains('title')));
      expect(sanitized, isNot(contains('note_title')));
      expect(sanitized, isNot(contains('password')));
      expect(sanitized, isNot(contains('token')));
      expect(sanitized, isNot(contains('secret')));
      expect(sanitized, isNot(contains('authorization')));
      expect(sanitized, isNot(contains('api_key')));
      expect(sanitized, isNot(contains('apiKey')));
      expect(sanitized, isNot(contains('credential')));

      // Legitimate metrics and diagnostic keys must be preserved
      expect(sanitized['frameJank'], 2);
      expect(sanitized['worstFrameMs'], 33.3);
      expect(sanitized['budgetMs'], 16.6);
      expect(sanitized['droppedFrames'], 1);
      expect(sanitized['frames'], 60);
      expect(sanitized['avgFrameMs'], 12.5);
      expect(sanitized['worstVsyncMs'], 2.1);
      expect(sanitized['mode'], 'edit');
      expect(sanitized['inset'], 240);
      expect(sanitized['index'], 3);
      expect(sanitized['contentLength'], 140);
      expect(sanitized['textLength'], 80);
      expect(sanitized['tagCount'], 5);

      // Diagnostic text must NOT be misclassified or modified as URLs
      expect(sanitized['diagnostic'], 'FormatException: bad input string');
      expect(sanitized['error_info'], 'Error: failed to connect to host');

      // URLs must have queries and fragments sanitized
      expect(sanitized['url'], 'https://example.com/api/v1/notes');
      expect(sanitized['endpoint'], 'https://service.internal/path');

      // Complex nested map and list must be sanitized safely
      final nested = sanitized['nestedData'] as Map<dynamic, dynamic>;
      expect(nested, isNot(contains('content')));
      expect(nested['innerMetric'], 42);
      expect(nested['nestedUrl'], 'https://api.example.com/endpoint');
      expect(nested['nestedDiagnostic'], 'FormatException: invalid integer');

      final list = sanitized['complexList'] as List<dynamic>;
      expect(list[0], 'https://api.example.com/item');
      expect(list[1], 'FormatException: not a url');
      final listMap = list[2] as Map<dynamic, dynamic>;
      expect(listMap, isNot(contains('query')));
      expect(listMap['safeField'], 'retained');
      expect(list[3], 123);
      expect(list[4], true);

      // Deeply nested list traversal
      final deepList = sanitized['deepNestedList'] as List<dynamic>;
      final deepInnerList = deepList[0] as List<dynamic>;
      final deepMap = deepInnerList[0] as Map<dynamic, dynamic>;
      expect(deepMap, isNot(contains('token')));
      expect(deepMap['count'], 7);

      // Unmodifiable map & list are deep-copied safely without mutation
      final unmodifiableMapResult =
          sanitized['unmodifiableMap'] as Map<dynamic, dynamic>;
      expect(unmodifiableMapResult, isNot(contains('secret')));
      expect(unmodifiableMapResult['validKey'], 'preserved');

      final unmodifiableListResult =
          sanitized['unmodifiableList'] as List<dynamic>;
      expect(unmodifiableListResult[0], 'https://example.com/item');
      expect(unmodifiableListResult[1], 'FormatException: unmodifiable item');

      // Map keys that are not String are preserved
      final nonStringMap =
          sanitized['nonStringKeyMap'] as Map<dynamic, dynamic>;
      expect(nonStringMap[101], 'numeric_id_val');
      expect(nonStringMap[true], 'boolean_key_val');
      expect(nonStringMap, isNot(contains('password')));

      // Top-level unmodifiable map handling
      final topLevelUnmodifiable = Map.unmodifiable(<String, dynamic>{
        'token': 'top_token',
        'safeMetric': 99,
      });
      final sanitizedTop = sanitizeSpanData(topLevelUnmodifiable);
      expect(sanitizedTop, isNot(contains('token')));
      expect(sanitizedTop['safeMetric'], 99);
    });

    test('sanitizes AppTracer arguments directly in AppTracer before upload',
        () async {
      final mockTransport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://public@example.com/1';
        options.transport = mockTransport;
        options.tracesSampleRate = 1.0;
        // Do NOT set options.beforeSendTransaction so this tests AppTracer directly.
      });

      try {
        final tracer = AppTracer.start(
          'ThoughtEcho.TracerSanitizeTest',
          operation: 'ui.load',
          arguments: {
            'content': 'Sensitive note content from tracer start',
            'query': 'SELECT * FROM secret_table',
            'title': 'Confidential Title',
            'password': 'tracer_password',
            'token': 'tracer_token_value',
            'frameJank': 1,
            'worstFrameMs': 34.0,
            'budgetMs': 16.6,
            'mode': 'create',
            'contentLength': 50,
            'diagnostic': 'FormatException: bad number input',
            'url': 'https://example.com/test?token=tracer_secret#tag',
          },
        );

        tracer.instant(
          'ThoughtEcho.TracerSanitizeTest.landmark',
          arguments: {
            'noteText': 'Instant landmark sensitive note text',
            'secret': 'landmark_secret',
            'droppedFrames': 2,
            'inset': 150,
          },
        );

        tracer.finish(
          arguments: {
            'search_query': 'user search keywords in finish',
            'authorization': 'Bearer finish_auth_token',
            'avgFrameMs': 16.0,
          },
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        final sentryTransaction = mockTransport.envelopes
            .expand((envelope) => envelope.items)
            .map((item) => item.originalObject)
            .whereType<SentryTransaction>()
            .single;

        // Verify root trace context data populated directly by AppTracer
        final traceData = sentryTransaction.contexts.trace?.data;
        expect(traceData, isNotNull);
        expect(traceData!, isNot(contains('content')));
        expect(traceData, isNot(contains('query')));
        expect(traceData, isNot(contains('title')));
        expect(traceData, isNot(contains('password')));
        expect(traceData, isNot(contains('token')));
        expect(traceData, isNot(contains('secret')));
        expect(traceData, isNot(contains('authorization')));
        expect(traceData, isNot(contains('search_query')));
        expect(traceData['frameJank'], 1);
        expect(traceData['worstFrameMs'], 34.0);
        expect(traceData['budgetMs'], 16.6);
        expect(traceData['mode'], 'create');
        expect(traceData['contentLength'], 50);
        expect(traceData['avgFrameMs'], 16.0);
        expect(traceData['diagnostic'], 'FormatException: bad number input');
        expect(traceData['url'], 'https://example.com/test');

        // Verify instant child span data
        final landmarkSpan = sentryTransaction.spans.singleWhere(
          (span) =>
              span.context.description ==
              'ThoughtEcho.TracerSanitizeTest.landmark',
        );
        expect(landmarkSpan.data, isNot(contains('noteText')));
        expect(landmarkSpan.data, isNot(contains('secret')));
        expect(landmarkSpan.data['droppedFrames'], 2);
        expect(landmarkSpan.data['inset'], 150);

        // Verify across all spans in the transaction
        for (final span in sentryTransaction.spans) {
          expect(span.data, isNot(contains('content')));
          expect(span.data, isNot(contains('query')));
          expect(span.data, isNot(contains('title')));
          expect(span.data, isNot(contains('password')));
          expect(span.data, isNot(contains('token')));
          expect(span.data, isNot(contains('secret')));
          expect(span.data, isNot(contains('authorization')));
          expect(span.data, isNot(contains('noteText')));
          expect(span.data, isNot(contains('search_query')));
        }
      } finally {
        await Sentry.close();
      }
    });

    test(
        'end-to-end: sanitizeSentryTransaction hook scrubs span data and transaction trace data',
        () async {
      final mockTransport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://public@example.com/1';
        options.transport = mockTransport;
        options.tracesSampleRate = 1.0;
        options.beforeSendTransaction = sanitizeSentryTransaction;
      });

      try {
        final transaction = Sentry.startTransaction(
          'DirectTransaction',
          'task.direct',
          bindToScope: true,
        );
        transaction.setData('rawContent', 'direct note content');
        transaction.setData('frameJank', 4);
        transaction.setData('url', 'https://api.example.com/v1?token=xyz#hash');

        final childSpan = transaction.startChild(
          'subtask',
          description: 'GET https://api.example.com/data?user=secret',
        );
        childSpan.setData('query', 'SELECT password FROM accounts');
        childSpan.setData('inset', 20);
        childSpan.setData('nested', <String, dynamic>{
          'secret': 'child_secret',
          'innerMetric': 88,
        });
        await childSpan.finish();
        await transaction.finish();

        await Future<void>.delayed(const Duration(milliseconds: 200));

        final sentryTransaction = mockTransport.envelopes
            .expand((envelope) => envelope.items)
            .map((item) => item.originalObject)
            .whereType<SentryTransaction>()
            .single;

        final traceData = sentryTransaction.contexts.trace?.data;
        expect(traceData, isNotNull);
        expect(traceData!, isNot(contains('rawContent')));
        expect(traceData['frameJank'], 4);
        expect(traceData['url'], 'https://api.example.com/v1');

        final subtaskSpan = sentryTransaction.spans.singleWhere(
          (span) => span.context.operation == 'subtask',
        );
        expect(subtaskSpan.context.description,
            'GET https://api.example.com/data');
        expect(subtaskSpan.data, isNot(contains('query')));
        expect(subtaskSpan.data['inset'], 20);

        final childNested = subtaskSpan.data['nested'] as Map<dynamic, dynamic>;
        expect(childNested, isNot(contains('secret')));
        expect(childNested['innerMetric'], 88);
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

    test('scrubs URLs in every transmitted nested network exception', () async {
      final transport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://public@example.com/1';
        options.transport = transport;
        options.beforeSend = sanitizeSentryEvent;
      });
      final dio = Dio()..addSentry();

      try {
        final uri = Uri.parse(
          'https://user:private-pass@weather.example/forecast'
          '?latitude=12.345678&longitude=98.765432&api_key=private-key'
          '#private-fragment',
        );
        final stackTrace = StackTrace.current;
        final error = DioException(
          requestOptions: RequestOptions(path: uri.toString()),
          error: HttpException(
            'Connection closed before full header was received',
            uri: uri,
          ),
          message: 'Retry HTTP://fallback.example/forecast?token=private-token',
          stackTrace: stackTrace,
        );

        await Sentry.captureException(error, stackTrace: stackTrace);

        final event = transport.envelopes
            .expand((envelope) => envelope.items)
            .map((item) => item.originalObject)
            .whereType<SentryEvent>()
            .single;
        final exceptions = event.toJson()['exception']['values'] as List;
        expect(
          exceptions.map((dynamic exception) => exception['type']),
          containsAll(['DioException', 'HttpException']),
        );
        for (final exception in exceptions) {
          expect(
              exception['value'], contains('https://weather.example/forecast'));
          expect(exception['value'], contains('Connection closed'));
        }
        expect(
          exceptions.singleWhere(
            (dynamic exception) => exception['type'] == 'DioException',
          )['value'],
          contains('http://fallback.example/forecast'),
        );
        expect(event.exceptions!.any((e) => e.stackTrace != null), isTrue);
        final payload = jsonEncode(event.toJson());
        for (final sensitive in [
          '12.345678',
          '98.765432',
          'user:',
          'private-pass',
          'api_key',
          'private-key',
          'private-fragment',
          'private-token',
        ]) {
          expect(payload, isNot(contains(sensitive)));
        }
      } finally {
        dio.close();
        await Sentry.close();
      }
    });

    test('preserves non-URL values and redacts malformed exception URLs', () {
      final event = SentryEvent(exceptions: [
        SentryException(type: 'StateError', value: 'Cache unavailable'),
        SentryException(type: 'UnknownError', value: null),
        SentryException(
          type: 'NetworkError',
          value: 'Failed: https://[invalid?token=private-token',
        ),
      ]);

      final sanitized = sanitizeSentryEvent(event, Hint());

      expect(
        sanitized?.exceptions?.map((exception) => exception.value),
        ['Cache unavailable', null, 'Failed: [invalid URL]'],
      );
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
