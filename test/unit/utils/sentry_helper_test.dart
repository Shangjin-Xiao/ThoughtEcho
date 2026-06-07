import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:thoughtecho/utils/sentry_helper.dart';

void main() {
  group('Sentry database privacy', () {
    test('removes local paths from database descriptions', () {
      const privatePath = '/Users/private/Documents/ThoughtEcho/quotes.db';

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
        'SELECT * FROM quotes',
      );
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
  });
}
