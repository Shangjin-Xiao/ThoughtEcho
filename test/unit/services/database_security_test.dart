import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_service.dart';

void main() {
  group('Database Security Tests - sanitizeOrderBy', () {
    late DatabaseService databaseService;

    setUp(() {
      databaseService = DatabaseService();
    });

    test('should allow valid columns and directions', () {
      expect(databaseService.sanitizeOrderBy('date DESC'), equals('date DESC'));
      expect(databaseService.sanitizeOrderBy('favorite_count ASC'),
          equals('favorite_count ASC'));
      expect(
          databaseService.sanitizeOrderBy('content'), equals('content DESC'));
      expect(databaseService.sanitizeOrderBy('last_modified DESC'),
          equals('last_modified DESC'));
    test('should allow valid columns and directions', () {
      expect(databaseService.sanitizeOrderBy('date DESC'), equals('date DESC'));
      expect(databaseService.sanitizeOrderBy('favorite_count ASC'), equals('favorite_count ASC'));
      expect(databaseService.sanitizeOrderBy('content'), equals('content DESC'));
      expect(databaseService.sanitizeOrderBy('last_modified DESC'), equals('last_modified DESC'));
    });

    test('should handle valid prefixes and remove them for validation', () {
      expect(databaseService.sanitizeOrderBy('q.date DESC'), equals('date DESC'));
      expect(databaseService.sanitizeOrderBy('qt.favorite_count ASC'), equals('favorite_count ASC'));
    });

    test('should fallback to default for invalid columns', () {
      expect(databaseService.sanitizeOrderBy('DROP TABLE quotes; --'), equals('date DESC'));
      expect(databaseService.sanitizeOrderBy('1; SELECT * FROM users'), equals('date DESC'));
      expect(databaseService.sanitizeOrderBy('invalid_column'), equals('date DESC'));
    });

    test('should fallback to DESC if direction is invalid', () {
      expect(databaseService.sanitizeOrderBy('date DROP'), equals('date DESC'));
      expect(databaseService.sanitizeOrderBy('date 1=1'), equals('date DESC'));
    });

    test('should keep valid multi-column order by', () {
      expect(
        databaseService.sanitizeOrderBy('favorite_count DESC, date DESC'),
        equals('favorite_count DESC, date DESC'),
      );
    });
  });
}
