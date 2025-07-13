/// Basic unit tests for DatabaseService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/note_category.dart';

void main() {
  group('DatabaseService Tests', () {
    late DatabaseService databaseService;

    setUp(() {
      databaseService = DatabaseService();
    });

    test('should create DatabaseService instance', () {
      expect(databaseService, isNotNull);
    });

    test('should create Quote model correctly', () {
      final quote = Quote(
        content: '测试内容',
        date: DateTime.now().toIso8601String(),
      );

      expect(quote.content, equals('测试内容'));
      expect(quote.date, isNotEmpty);
    });

    test('should create NoteCategory model correctly', () {
      final category = NoteCategory(id: 'test-id', name: '测试分类');

      expect(category.id, equals('test-id'));
      expect(category.name, equals('测试分类'));
    });
  });
}
