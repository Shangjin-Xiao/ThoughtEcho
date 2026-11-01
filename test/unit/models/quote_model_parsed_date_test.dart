import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

void main() {
  group('Quote parsedDate & parsedLastModified tests', () {
    test('parsedDate parses ISO date and caches the DateTime instance', () {
      final quote = Quote(
        id: 'quote-1',
        content: 'Test content',
        date: '2026-05-20T10:30:00.000Z',
      );

      final firstCall = quote.parsedDate;
      final secondCall = quote.parsedDate;

      expect(firstCall, DateTime.parse('2026-05-20T10:30:00.000Z'));
      expect(identical(firstCall, secondCall), isTrue,
          reason: 'parsedDate must return the cached instance');
    });

    test('parsedLastModified returns null when lastModified is null', () {
      final quote = Quote(
        id: 'quote-2',
        content: 'Test content',
        date: '2026-05-20T10:30:00.000Z',
        lastModified: null,
      );

      expect(quote.parsedLastModified, isNull);
    });

    test('parsedLastModified parses date and caches the DateTime instance', () {
      final quote = Quote(
        id: 'quote-3',
        content: 'Test content',
        date: '2026-05-20T10:30:00.000Z',
        lastModified: '2026-05-21T15:45:00.000Z',
      );

      final firstCall = quote.parsedLastModified;
      final secondCall = quote.parsedLastModified;

      expect(firstCall, isNotNull);
      expect(firstCall, DateTime.parse('2026-05-21T15:45:00.000Z'));
      expect(identical(firstCall, secondCall), isTrue,
          reason: 'parsedLastModified must return the cached instance');
    });

    test('parsedLastModified returns null for invalid date strings', () {
      final quote = Quote(
        id: 'quote-4',
        content: 'Test content',
        date: '2026-05-20T10:30:00.000Z',
        lastModified: 'invalid-date-string',
      );

      expect(quote.parsedLastModified, isNull);
    });
  });
}
