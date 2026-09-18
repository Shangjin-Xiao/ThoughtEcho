import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/import_cleanup_stats.dart';

void main() {
  group('ImportCleanupStats', () {
    test('default constructor sets default values to zero', () {
      const stats = ImportCleanupStats();
      expect(stats.sanitizedFields, 0);
      expect(stats.skippedEmptyQuotes, 0);
      expect(stats.isClean, isTrue);
    });

    test('custom constructor sets fields correctly', () {
      const stats = ImportCleanupStats(
        sanitizedFields: 3,
        skippedEmptyQuotes: 5,
      );
      expect(stats.sanitizedFields, 3);
      expect(stats.skippedEmptyQuotes, 5);
      expect(stats.isClean, isFalse);
    });

    group('isClean', () {
      test('returns true when sanitizedFields and skippedEmptyQuotes are zero',
          () {
        const stats = ImportCleanupStats(
          sanitizedFields: 0,
          skippedEmptyQuotes: 0,
        );
        expect(stats.isClean, isTrue);
      });

      test('returns false when sanitizedFields is greater than zero', () {
        const stats = ImportCleanupStats(
          sanitizedFields: 1,
          skippedEmptyQuotes: 0,
        );
        expect(stats.isClean, isFalse);
      });

      test('returns false when skippedEmptyQuotes is greater than zero', () {
        const stats = ImportCleanupStats(
          sanitizedFields: 0,
          skippedEmptyQuotes: 2,
        );
        expect(stats.isClean, isFalse);
      });

      test('returns false when both fields are greater than zero', () {
        const stats = ImportCleanupStats(
          sanitizedFields: 2,
          skippedEmptyQuotes: 4,
        );
        expect(stats.isClean, isFalse);
      });
    });
  });
}
