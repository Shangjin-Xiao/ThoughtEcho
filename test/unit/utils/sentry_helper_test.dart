// ignore_for_file: experimental_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:thoughtecho/utils/sentry_helper.dart';

import '../../test_setup.dart';

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });

  group('Sentry minimal collection options', () {
    test('disables sensitive and high-overhead collection', () {
      final options = SentryFlutterOptions();

      configureSentryOptions(options);

      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.attachViewHierarchy, isFalse);
      expect(options.profilesSampleRate, isNull);
      expect(options.enableAutoSessionTracking, isFalse);
      expect(options.enablePrintBreadcrumbs, isFalse);
      expect(options.enableUserInteractionBreadcrumbs, isFalse);
      expect(options.enableUserInteractionTracing, isFalse);
      expect(options.enableAutoPerformanceTracing, isTrue);
      expect(options.tracesSampleRate, equals(1.0));
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
        'SQL query',
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
        expect(sqlTransactionSpan.context.description, 'SQL query');
        expect(logTransactionSpan.context.description, 'Log database write');
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

class _MockSentryTransport implements Transport {
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return SentryId.newId();
  }
}
