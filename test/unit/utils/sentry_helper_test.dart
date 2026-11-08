// ignore_for_file: experimental_member_use, deprecated_member_use

import 'dart:collection';
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

    test('redacts local file paths in non-SQL breadcrumb messages', () {
      final cases = <String, String>{
        'User opened /Users/developer/mock_path/notes.txt':
            'User opened [path]',
        r'Saved export to C:\Users\developer\mock_docs\backup.json':
            'Saved export to [path]',
        'Android db ready at /data/user/0/com.thoughtecho/databases/app.db':
            'Android db ready at [path]',
        'Linux config in /home/developer/.config/app.conf':
            'Linux config in [path]',
        'Container file at /private/var/mobile/Containers/Data/notes.db':
            'Container file at [path]',
        'Mounted external storage at /mnt/developer/private-notes.txt':
            'Mounted external storage at [path]',
        'Volumes path /Volumes/ExternalDrive/notes.txt': 'Volumes path [path]',
        'Server storage in /srv/data/backup.json': 'Server storage in [path]',
        'Quoted: "/Users/developer/My Documents/note.txt"': 'Quoted: "[path]"',
        'Quoted mount: "/mnt/developer/My Documents/note.txt"':
            'Quoted mount: "[path]"',
        'Saved to /Users/developer/file.txt.': 'Saved to [path].',
        'Saved to /mnt/developer/file.txt.': 'Saved to [path].',
        'Failed (/Users/developer/file.txt)': 'Failed ([path])',
        'Failed (/mnt/developer/file.txt)': 'Failed ([path])',
        'User opened file:///Users/developer/Documents/private.txt':
            'User opened [path]',
        'User opened file:///mnt/developer/private-notes.txt':
            'User opened [path]',
        'Windows file URI: file:///C:/Users/developer/notes.txt':
            'Windows file URI: [path]',
        'Quoted file URI: "file:///Users/developer/My Documents/note.txt"':
            'Quoted file URI: "[path]"',
        'Saved to file:///Users/developer/file.txt.': 'Saved to [path].',
        'Failed (file:///Users/developer/file.txt)': 'Failed ([path])',
      };

      for (final entry in cases.entries) {
        final breadcrumb = Breadcrumb(
          message: entry.key,
          category: 'ui.click',
        );
        final sanitized = sanitizeSentryBreadcrumb(breadcrumb, Hint());
        expect(
          sanitized?.message,
          entry.value,
          reason: 'Failed to sanitize "${entry.key}"',
        );
      }
    });

    test('sanitizes URLs in non-SQL breadcrumb messages while keeping base URL',
        () {
      final breadcrumb = Breadcrumb(
        message:
            'Navigated to https://example.com/notes?secret_key=12345#overview',
        category: 'navigation',
      );

      final sanitized = sanitizeSentryBreadcrumb(breadcrumb, Hint());

      expect(sanitized?.message, 'Navigated to https://example.com/notes');
      expect(sanitized?.message, isNot(contains('secret_key')));
      expect(sanitized?.message, isNot(contains('overview')));

      final networkBreadcrumb = Breadcrumb(
        message:
            'Fetched https://example.com/mnt/storage/data?token=secret123#overview',
        category: 'network',
      );
      final sanitizedNetwork =
          sanitizeSentryBreadcrumb(networkBreadcrumb, Hint());
      expect(
        sanitizedNetwork?.message,
        'Fetched https://example.com/mnt/storage/data',
      );
      expect(sanitizedNetwork?.message, isNot(contains('secret123')));
      expect(sanitizedNetwork?.message, isNot(contains('[path]')));

      final portBreadcrumb = Breadcrumb(
        message: 'Calling http://localhost:8080/mnt/files?auth=secret',
        category: 'network',
      );
      final sanitizedPort = sanitizeSentryBreadcrumb(portBreadcrumb, Hint());
      expect(
        sanitizedPort?.message,
        'Calling http://localhost:8080/mnt/files',
      );
      expect(sanitizedPort?.message, isNot(contains('secret')));
      expect(sanitizedPort?.message, isNot(contains('[path]')));
    });

    test('removes sensitive blacklist keys from breadcrumb data', () {
      final breadcrumb = Breadcrumb(
        category: 'user_action',
        data: <String, dynamic>{
          'query': 'user search keyword',
          'search': 'find quote',
          'search_term': 'important',
          'file_path': '/Users/developer/secret.txt',
          'filePath': r'C:\Users\developer\secret.txt',
          'path': '/home/developer/app',
          'text': 'private user note text',
          'button_text': 'submit',
          'content': 'confidential content',
          'prompt': 'summarize this text',
          'system_prompt': 'you are an assistant',
          'token': 'secret-token-value',
          'access_token': 'xyz789',
          'secret': 'client-secret-val',
          'auth': 'Basic secretcredentials',
          'action': 'tap_button',
          'status_code': 200,
          'count': 5,
        },
      );

      final sanitized = sanitizeSentryBreadcrumb(breadcrumb, Hint());
      final data = sanitized?.data;

      expect(data, isNotNull);
      expect(data, isNot(contains('query')));
      expect(data, isNot(contains('search')));
      expect(data, isNot(contains('search_term')));
      expect(data, isNot(contains('file_path')));
      expect(data, isNot(contains('filePath')));
      expect(data, isNot(contains('path')));
      expect(data, isNot(contains('text')));
      expect(data, isNot(contains('button_text')));
      expect(data, isNot(contains('content')));
      expect(data, isNot(contains('prompt')));
      expect(data, isNot(contains('system_prompt')));
      expect(data, isNot(contains('token')));
      expect(data, isNot(contains('access_token')));
      expect(data, isNot(contains('secret')));
      expect(data, isNot(contains('auth')));

      expect(data?['action'], 'tap_button');
      expect(data?['status_code'], 200);
      expect(data?['count'], 5);
    });

    test(
        'sanitizes local paths and URLs with query parameters in data String values',
        () {
      final breadcrumb = Breadcrumb(
        category: 'custom',
        data: <String, dynamic>{
          'target_url':
              'https://example.com/api/v1/resource?token=secret123&user=admin#section',
          'destination_dir': '/Users/developer/Documents/backups',
          'win_dir': r'C:\Users\developer\AppData\Local',
          'android_dir': '/data/user/0/com.thoughtecho/files',
          'mnt_dir': '/mnt/developer/storage/notes',
          'file_uri': 'file:///Users/developer/Documents/private.txt',
          'mnt_file_uri': 'file:///mnt/developer/private.txt',
          'network_url_with_mnt':
              'https://example.com/mnt/storage?key=secret123',
          'summary':
              'Exported https://example.com/item?api=val to /home/developer/out.json',
          'file_summary':
              'Synced file:///Users/developer/file.txt to /mnt/developer/backup.txt',
          'is_valid': true,
          'item_count': 10,
        },
      );

      final sanitized = sanitizeSentryBreadcrumb(breadcrumb, Hint());
      final data = sanitized?.data;

      expect(data?['target_url'], 'https://example.com/api/v1/resource');
      expect(data?['target_url'], isNot(contains('token')));
      expect(data?['target_url'], isNot(contains('admin')));
      expect(data?['destination_dir'], '[path]');
      expect(data?['win_dir'], '[path]');
      expect(data?['android_dir'], '[path]');
      expect(data?['mnt_dir'], '[path]');
      expect(data?['file_uri'], '[path]');
      expect(data?['mnt_file_uri'], '[path]');
      expect(
        data?['network_url_with_mnt'],
        'https://example.com/mnt/storage',
      );
      expect(data?['network_url_with_mnt'], isNot(contains('secret123')));
      expect(data?['network_url_with_mnt'], isNot(contains('[path]')));
      expect(
        data?['summary'],
        'Exported https://example.com/item to [path]',
      );
      expect(
        data?['file_summary'],
        'Synced [path] to [path]',
      );
      expect(data?['is_valid'], isTrue);
      expect(data?['item_count'], 10);
    });

    test('handles null, empty, or unmodifiable breadcrumb data gracefully', () {
      // Null breadcrumb
      expect(sanitizeSentryBreadcrumb(null, Hint()), isNull);

      // Null data
      final breadcrumbNullData = Breadcrumb(message: 'Plain message');
      final sanitizedNull =
          sanitizeSentryBreadcrumb(breadcrumbNullData, Hint());
      expect(sanitizedNull?.message, 'Plain message');
      expect(sanitizedNull?.data, isNull);

      // Unmodifiable map in data
      final unmodifiableBreadcrumb = Breadcrumb(
        message: 'Loaded file at /Users/developer/data.txt',
        data: Map.unmodifiable(<String, dynamic>{
          'http.query': 'secret=1',
          'custom_note': 'Loaded from /home/developer/doc.pdf',
          'is_cached': true,
        }),
      );

      expect(
        () => sanitizeSentryBreadcrumb(unmodifiableBreadcrumb, Hint()),
        returnsNormally,
      );

      final sanitizedUnmodifiable =
          sanitizeSentryBreadcrumb(unmodifiableBreadcrumb, Hint());
      expect(sanitizedUnmodifiable?.message, 'Loaded file at [path]');
      expect(sanitizedUnmodifiable?.data, isNot(contains('http.query')));
      expect(sanitizedUnmodifiable?.data?['custom_note'], 'Loaded from [path]');
      expect(sanitizedUnmodifiable?.data?['is_cached'], isTrue);
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

    test(
        'sanitizes multi-platform absolute local file paths in exception values and event message',
        () {
      final exceptions = [
        SentryException(
          type: 'PathNotFoundException',
          value:
              r'Cannot open C:\Users\developer\AppData\Local\ThoughtEcho\quotes.db: file not found',
        ),
        SentryException(
          type: 'FileSystemException',
          value:
              'Failed reading /Users/developer/Documents/ThoughtEcho/notes.db: Permission denied',
        ),
        SentryException(
          type: 'StorageException',
          value:
              'Android DB unavailable at /data/user/0/com.thoughtecho/databases/app.db',
        ),
        SentryException(
          type: 'StorageException',
          value:
              'Linux config missing at /home/developer/.config/thoughtecho/app.conf',
        ),
        SentryException(
          type: 'StorageException',
          value:
              'iOS container missing at /private/var/mobile/Containers/Data/notes.db',
        ),
        SentryException(
          type: 'StorageException',
          value: 'Mounted path missing at /mnt/developer/storage/notes.db',
        ),
        SentryException(
          type: 'UriException',
          value:
              'Failed loading file:///Users/developer/data.txt and file:///C:/Users/developer/notes.txt',
        ),
      ];

      final event = SentryEvent(
        exceptions: exceptions,
        message: SentryMessage(
          'Export error writing to /Users/developer/backup.json',
          template: 'Export error writing to /Users/developer/backup.json',
          params: ['/home/developer/out.txt'],
        ),
      );

      final sanitized = sanitizeSentryEvent(event, Hint());

      expect(
        sanitized?.exceptions?[0].value,
        'Cannot open [path]: file not found',
      );
      expect(sanitized?.exceptions?[0].type, 'PathNotFoundException');
      expect(
        sanitized?.exceptions?[1].value,
        'Failed reading [path]: Permission denied',
      );
      expect(sanitized?.exceptions?[1].type, 'FileSystemException');
      expect(
        sanitized?.exceptions?[2].value,
        'Android DB unavailable at [path]',
      );
      expect(
        sanitized?.exceptions?[3].value,
        'Linux config missing at [path]',
      );
      expect(
        sanitized?.exceptions?[4].value,
        'iOS container missing at [path]',
      );
      expect(
        sanitized?.exceptions?[5].value,
        'Mounted path missing at [path]',
      );
      expect(
        sanitized?.exceptions?[6].value,
        'Failed loading [path] and [path]',
      );
      expect(
        sanitized?.message?.formatted,
        'Export error writing to [path]',
      );
      expect(
        sanitized?.message?.template,
        'Export error writing to [path]',
      );
      expect(
        sanitized?.message?.params,
        ['[path]'],
      );
    });

    test(
        'sanitizes WebDAV Basic authentication credentials and URLs in error events',
        () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'DioException',
            value: 'DioException [bad response]: 401 Unauthorized for '
                'https://user:secret123@webdav.example.com:8443/remote.php/webdav/backup.json '
                'with Authorization: Basic dXNlcjpzZWNyZXQxMjM= and header "Basic dXNlcjpzZWNyZXQxMjM="',
          ),
          SentryException(
            type: 'HttpException',
            value:
                'Basic dXNlcjpzZWNyZXQxMjM= failed authentication at https://dav.example.com',
          ),
        ],
      );

      final sanitized = sanitizeSentryEvent(event, Hint());

      final ex0 = sanitized?.exceptions?[0];
      expect(ex0?.type, 'DioException');
      expect(ex0?.value, isNot(contains('secret123')));
      expect(ex0?.value, isNot(contains('user:')));
      expect(ex0?.value, isNot(contains('dXNlcjpzZWNyZXQxMjM=')));
      expect(
        ex0?.value,
        contains(
            'https://webdav.example.com:8443/remote.php/webdav/backup.json'),
      );
      expect(ex0?.value, contains('Authorization: Basic [redacted]'));
      expect(ex0?.value, contains('"Basic [redacted]"'));

      final ex1 = sanitized?.exceptions?[1];
      expect(ex1?.type, 'HttpException');
      expect(ex1?.value, isNot(contains('dXNlcjpzZWNyZXQxMjM=')));
      expect(
        ex1?.value,
        contains(
            'Basic [redacted] failed authentication at https://dav.example.com'),
      );
    });

    test(
        'reproduces and sanitizes THOUGHTECHO-5S HTTP Bearer authorization header leak',
        () {
      const sensitiveQuote = '对不起，风太大了，我听不清。——皇昴流《东京巴比伦》';
      final rawException = 'FormatException: Invalid HTTP header field value: '
          '"Bearer $sensitiveQuote" (at character 8)\n'
          'Bearer $sensitiveQuote\n'
          '       ^';

      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FormatException',
            value: rawException,
          ),
        ],
      );

      final sanitized = sanitizeSentryEvent(event, Hint());

      final ex = sanitized?.exceptions?.single;
      expect(ex?.type, 'FormatException');
      expect(ex?.value, isNot(contains(sensitiveQuote)));
      expect(
        ex?.value,
        'FormatException: Invalid HTTP header field value: "Bearer [redacted]" (at character 8)\n'
        'Bearer [redacted]\n'
        '       ^',
      );
    });

    test(
        'reproduces and sanitizes THOUGHTECHO-5Y third-party AI error and response body leak',
        () {
      final rawAiException =
          'ApiException: Add usage credits or subscribe and save up to 66%: '
          'https://ollama.com/plans?token=secret123#plans (ref: req_1793787470276_ce9a1100) '
          '(status: 402, type: api_error, request_id: req_1793787470276_ce9a1100)';

      final rawAiPayloadException = 'ApiException: OpenAI request failed: '
          '{"error": {"message": "Invalid API key provided: sk-proj-1234567890abcdefghijklmnopqrstuvwxyz", '
          '"type": "invalid_request_error"}, '
          '"prompt": "User private diary note content", '
          '"messages": [{"role": "user", "content": "Sensitive conversation"}], '
          '"content": "Secret note body content", '
          '"deltaContent": "[{\\"insert\\":\\"private\\"}]"}';

      final rawGeminiException =
          'ApiException: Request to Gemini failed with key AIzaSyD-1234567890abcdefghijklmnopqrstuv '
          'and header x-api-key: secret_api_key_456 and api_key="test_key_789"';

      final event = SentryEvent(
        exceptions: [
          SentryException(type: 'ApiException', value: rawAiException),
          SentryException(type: 'ApiException', value: rawAiPayloadException),
          SentryException(type: 'ApiException', value: rawGeminiException),
        ],
      );

      final sanitized = sanitizeSentryEvent(event, Hint());

      final ex0 = sanitized?.exceptions?[0];
      expect(ex0?.type, 'ApiException');
      expect(ex0?.value, isNot(contains('secret123')));
      expect(ex0?.value, isNot(contains('#plans')));
      expect(
        ex0?.value,
        'ApiException: Add usage credits or subscribe and save up to 66%: '
        'https://ollama.com/plans (ref: req_1793787470276_ce9a1100) '
        '(status: 402, type: api_error, request_id: req_1793787470276_ce9a1100)',
      );

      final ex1 = sanitized?.exceptions?[1];
      expect(ex1?.type, 'ApiException');
      expect(ex1?.value,
          isNot(contains('sk-proj-1234567890abcdefghijklmnopqrstuvwxyz')));
      expect(ex1?.value, isNot(contains('User private diary note content')));
      expect(ex1?.value, isNot(contains('Sensitive conversation')));
      expect(ex1?.value, isNot(contains('Secret note body content')));
      expect(ex1?.value, isNot(contains('private')));
      expect(ex1?.value,
          contains('"message": "Invalid API key provided: [redacted]"'));
      expect(ex1?.value, contains('"prompt": "[redacted]"'));
      expect(ex1?.value, contains('"messages": "[redacted]"'));
      expect(ex1?.value, contains('"content": "[redacted]"'));
      expect(ex1?.value, contains('"deltaContent": "[redacted]"'));

      final ex2 = sanitized?.exceptions?[2];
      expect(ex2?.type, 'ApiException');
      expect(ex2?.value,
          isNot(contains('AIzaSyD-1234567890abcdefghijklmnopqrstuv')));
      expect(ex2?.value, isNot(contains('secret_api_key_456')));
      expect(ex2?.value, isNot(contains('test_key_789')));
      expect(ex2?.value, contains('key [redacted]'));
      expect(ex2?.value, contains('x-api-key: [redacted]'));
      expect(ex2?.value, contains('api_key="[redacted]"'));
    });

    test(
        'sanitizes Hint context storage data and metadata extra/contexts recursively',
        () {
      final hint = Hint.withMap({
        'message':
            'UnifiedLogService: Failed sync at /data/user/0/com.thoughtecho/app.db '
                'with Authorization: Basic dXNlcjpwYXNz and apiKey="sk-secret123456789"',
        'source': 'UnifiedLogService',
        'token': 'private_hint_token',
        'prompt': 'secret prompt in hint',
        'details': {
          'destination_dir': '/Users/developer/notes.db',
          'secret_key': 'hint_secret_val',
          'metric': 42,
        },
      });

      final event = SentryEvent(
        extra: {
          'file_path': '/home/developer/app.json',
          'destination': '/data/user/0/com.thoughtecho/files',
          'api_key': 'super_secret_extra_key',
          'normal_count': 12,
          'nested_meta': {
            'content': 'private extra content',
            'url': 'https://api.example.com/v1?token=extra_secret#section',
            'safe_flag': true,
          },
        },
        contexts: Contexts(
          device: SentryDevice(name: 'Test Device'),
        ),
      );
      event.contexts['custom'] = {
        'path': r'C:\Users\developer\secret.txt',
        'password': 'my_password',
        'endpoint': 'https://dav.example.com/item?auth=yes',
        'status': 'error',
      };

      final sanitized = sanitizeSentryEvent(event, hint);

      // Hint assertions
      expect(hint.get('token'), isNull);
      expect(hint.get('prompt'), isNull);
      expect(hint.get('source'), 'UnifiedLogService');
      final hintMsg = hint.get('message') as String;
      expect(hintMsg, isNot(contains('/data/user/0')));
      expect(hintMsg, isNot(contains('dXNlcjpwYXNz')));
      expect(hintMsg, isNot(contains('sk-secret123456789')));
      expect(
        hintMsg,
        'UnifiedLogService: Failed sync at [path] '
        'with Authorization: Basic [redacted] and apiKey="[redacted]"',
      );
      final hintDetails = hint.get('details') as Map<String, dynamic>;
      expect(hintDetails['destination_dir'], '[path]');
      expect(hintDetails, isNot(contains('secret_key')));
      expect(hintDetails['metric'], 42);

      // Extra assertions
      final extra = sanitized?.extra;
      expect(extra, isNotNull);
      expect(extra, isNot(contains('file_path')));
      expect(extra, isNot(contains('api_key')));
      expect(extra?['destination'], '[path]');
      expect(extra?['normal_count'], 12);
      final nestedMeta = extra?['nested_meta'] as Map<String, dynamic>;
      expect(nestedMeta, isNot(contains('content')));
      expect(nestedMeta['url'], 'https://api.example.com/v1');
      expect(nestedMeta['safe_flag'], isTrue);

      // Contexts assertions
      final customContext =
          sanitized?.contexts['custom'] as Map<String, dynamic>;
      expect(customContext, isNot(contains('path')));
      expect(customContext, isNot(contains('password')));
      expect(customContext['endpoint'], 'https://dav.example.com/item');
      expect(customContext['status'], 'error');
    });

    test(
        'handles edge cases gracefully: null values, empty strings, and malformed inputs',
        () {
      final event = SentryEvent(
        exceptions: [
          SentryException(type: 'EmptyException', value: ''),
          SentryException(type: 'NullException', value: null),
          SentryException(
            type: 'MalformedException',
            value: 'Normal error with no secrets: {"incomplete json',
          ),
        ],
        message: SentryMessage(''),
      );

      final hint = Hint.withMap({
        'message': '',
        'non_string_val': 12345,
        'bool_val': false,
      });

      expect(() => sanitizeSentryEvent(event, hint), returnsNormally);

      final sanitized = sanitizeSentryEvent(event, hint);
      expect(sanitized?.exceptions?[0].value, '');
      expect(sanitized?.exceptions?[0].type, 'EmptyException');
      expect(sanitized?.exceptions?[1].value, isNull);
      expect(sanitized?.exceptions?[1].type, 'NullException');
      expect(
        sanitized?.exceptions?[2].value,
        'Normal error with no secrets: {"incomplete json',
      );
      expect(sanitized?.message?.formatted, '');
      expect(hint.get('message'), '');
      expect(hint.get('non_string_val'), 12345);
      expect(hint.get('bool_val'), false);
    });

    test(
        'redacts quoted JSON string values for credential keys including escaped characters',
        () {
      // 1. Quoted JSON credential keys (e.g. api_key, authToken)
      const jsonText =
          '{"api_key": "secret123", "authToken": "token456", "safe": "value"}';
      expect(
        sanitizeSentryNonSqlText(jsonText),
        '{"api_key": "[redacted]", "authToken": "[redacted]", "safe": "value"}',
      );

      // 2. Escaped characters inside quoted values
      const jsonWithEscapes =
          '{"api_key": "secret\\"with\\\\escapes\\nand\\"quotes", "authToken": "token\\"xyz"}';
      expect(
        sanitizeSentryNonSqlText(jsonWithEscapes),
        '{"api_key": "[redacted]", "authToken": "[redacted]"}',
      );

      // 3. Various credential key name formats in JSON
      const jsonVariousKeys =
          '{"access_token": "tok1", "secret_key": "sec2", "apiKey": "key3", "x-api-key": "xkey4", "private_key": "priv5"}';
      expect(
        sanitizeSentryNonSqlText(jsonVariousKeys),
        '{"access_token": "[redacted]", "secret_key": "[redacted]", "apiKey": "[redacted]", "x-api-key": "[redacted]", "private_key": "[redacted]"}',
      );

      // 4. Preserves unquoted / key-value format handling
      const plainKeyValue =
          'Error with api_key: secret_val, x-api-key: secret_x, api_key=secret_eq, and sk-ant-api03-1234567890123456';
      expect(
        sanitizeSentryNonSqlText(plainKeyValue),
        'Error with api_key: [redacted], x-api-key: [redacted], api_key=[redacted], and [redacted]',
      );

      // 5. End-to-end via sanitizeSentryEvent in exception value
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'ApiException',
            value:
                'Request failed with body: {"api_key": "my_secret_key", "authToken": "secret\\"with\\\\escapes"}',
          ),
        ],
      );
      final sanitized = sanitizeSentryEvent(event, Hint());
      expect(
        sanitized?.exceptions?.single.value,
        'Request failed with body: {"api_key": "[redacted]", "authToken": "[redacted]"}',
      );
    });

    test(
        'handles metadata sanitization failures by dropping affected entry without mutating unmodifiable maps',
        () {
      // 1. Unmodifiable map in extra is sanitized cleanly without mutating original map
      final unmodifiableExtra =
          Map<String, dynamic>.unmodifiable(<String, dynamic>{
        'token': 'sensitive_secret_token',
        'safe_key': 'safe_value',
        'destination': '/Users/developer/file.txt',
      });
      final eventWithUnmodifiable = SentryEvent();
      eventWithUnmodifiable.extra = unmodifiableExtra;
      final sanitizedUnmodifiable =
          sanitizeSentryEvent(eventWithUnmodifiable, Hint());
      expect(sanitizedUnmodifiable, isNotNull);
      expect(sanitizedUnmodifiable?.extra, isNotNull);
      expect(sanitizedUnmodifiable?.extra, isNot(contains('token')));
      expect(sanitizedUnmodifiable?.extra?['safe_key'], 'safe_value');
      expect(sanitizedUnmodifiable?.extra?['destination'], '[path]');
      // The original unmodifiable map must remain unchanged
      expect(unmodifiableExtra['token'], 'sensitive_secret_token');

      // 2. Failure in extra metadata sanitization drops the affected entry (event.extra becomes null)
      final throwingMap = _ThrowingMap(<String, dynamic>{'token': 'secret'});
      final eventWithThrowingExtra = SentryEvent(
        message: SentryMessage('Event message is preserved'),
      );
      eventWithThrowingExtra.extra = throwingMap;
      final sanitizedThrowingExtra =
          sanitizeSentryEvent(eventWithThrowingExtra, Hint());
      expect(sanitizedThrowingExtra, isNotNull);
      // The affected entry (extra) is dropped rather than returned unsanitized
      expect(sanitizedThrowingExtra?.extra, isNull);
      expect(
        sanitizedThrowingExtra?.message?.formatted,
        'Event message is preserved',
      );

      // 3. Failure in contexts entry drops only the affected context entry
      final eventWithThrowingContext = SentryEvent(
        contexts: Contexts(
          device: SentryDevice(name: 'Safe Device'),
        ),
      );
      eventWithThrowingContext.contexts['faulty'] = throwingMap;
      final sanitizedContext =
          sanitizeSentryEvent(eventWithThrowingContext, Hint());
      expect(sanitizedContext, isNotNull);
      expect(sanitizedContext?.contexts.containsKey('faulty'), isFalse);
      expect(sanitizedContext?.contexts.device?.name, 'Safe Device');
    });
    tearDown(() {
      SentryHelper.onCaptureExceptionForTesting = null;
    });

    test('invokes onCaptureExceptionForTesting when set including withScope',
        () async {
      dynamic capturedThrowable;
      dynamic capturedStackTrace;
      Hint? capturedHint;
      ScopeCallback? capturedWithScope;
      final expectedId = SentryId.newId();

      SentryHelper.onCaptureExceptionForTesting = (
        throwable, {
        stackTrace,
        hint,
        withScope,
      }) async {
        capturedThrowable = throwable;
        capturedStackTrace = stackTrace;
        capturedHint = hint;
        capturedWithScope = withScope;
        return expectedId;
      };

      final error = StateError('db_error');
      final stackTrace = StackTrace.current;
      final hint = Hint.withMap({'operation': 'test_op'});

      final sentryId = await SentryHelper.captureException(
        error,
        stackTrace: stackTrace,
        hint: hint,
        withScope: (scope) {
          scope.setTag('operation', 'test_op');
          scope.setTag('source', 'AgentMemoryService');
        },
      );

      expect(sentryId, equals(expectedId));
      expect(capturedThrowable, equals(error));
      expect(capturedStackTrace, equals(stackTrace));
      expect(capturedHint?.get('operation'), equals('test_op'));
      expect(capturedWithScope, isNotNull);

      final scope = Scope(SentryOptions(dsn: ''));
      capturedWithScope!(scope);
      expect(scope.tags['operation'], equals('test_op'));
      expect(scope.tags['source'], equals('AgentMemoryService'));
    });

    test('returns SentryId.empty() when not enabled and no handler set',
        () async {
      SentryHelper.onCaptureExceptionForTesting = null;
      final sentryId = await SentryHelper.captureException(
        Exception('some_error'),
        stackTrace: StackTrace.current,
      );
      expect(sentryId, equals(SentryId.empty()));
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

class _ThrowingMap extends MapView<String, dynamic> {
  _ThrowingMap(super.map);

  @override
  void forEach(void Function(String key, dynamic value) action) {
    throw StateError('Simulated traversal error');
  }

  @override
  Iterable<MapEntry<String, dynamic>> get entries {
    throw StateError('Simulated traversal error');
  }

  @override
  void clear() {
    throw UnsupportedError('Cannot modify unmodifiable map');
  }
}
