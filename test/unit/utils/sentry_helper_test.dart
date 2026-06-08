// ignore_for_file: depend_on_referenced_packages, experimental_member_use, implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry/src/sentry_tracer.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:thoughtecho/utils/sentry_helper.dart';

void main() {
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
    });

    test('removes sensitive and bulky transaction span data', () async {
      final tracer = SentryTracer(
        SentryTransactionContext(
          'root /',
          'ui.load',
          samplingDecision: SentryTracesSamplingDecision(true),
          transactionNameSource: SentryTransactionNameSource.component,
        ),
        Hub(SentryOptions(dsn: 'https://public@example.com/1')),
      );
      final httpSpan = tracer.startChild(
        'http.client',
        description: 'GET https://example.com/path?api_key=secret#private',
      ) as SentrySpan;
      httpSpan
        ..setData('url', 'https://example.com/path?api_key=secret#private')
        ..setData('http.query', 'api_key=secret')
        ..setData('http.fragment', 'private');
      await httpSpan.finish();
      final sqlSpan = tracer.startChild(
        'db.sql.query',
        description: 'SELECT * FROM quotes WHERE content LIKE ?',
      ) as SentrySpan;
      await sqlSpan.finish();
      final logSpan = tracer.startChild(
        'db',
        description: '''
INSERT OR REPLACE INTO app_logs (timestamp, level, message, source, error, stack_trace) VALUES (?, ?, ?, ?, NULL, NULL)
INSERT OR REPLACE INTO app_logs (timestamp, level, message, source, error, stack_trace) VALUES (?, ?, ?, ?, NULL, NULL)
''',
      ) as SentrySpan;
      await logSpan.finish();
      await tracer.finish();

      final transaction = SentryTransaction(tracer);

      final sanitized = sanitizeSentryTransaction(transaction, Hint());

      expect(sanitized, same(transaction));
      expect(httpSpan.context.description, 'GET https://example.com/path');
      expect(httpSpan.data['url'], 'https://example.com/path');
      expect(httpSpan.data, isNot(contains('http.query')));
      expect(httpSpan.data, isNot(contains('http.fragment')));
      expect(sqlSpan.context.description, 'SQL query');
      expect(logSpan.context.description, 'Log database write');
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
