import 'package:flutter_test/flutter_test.dart';
import '../../../lib/models/quote_model.dart';
import '../../../lib/models/note_category.dart';

void main() {
  group('Quote Model Tests', () {
    test('should create Quote with required fields', () {
      // Arrange & Act
      final quote = Quote(
        content: 'Test content',
        date: '2024-01-01T10:00:00.000Z',
      );

      // Assert
      expect(quote.content, equals('Test content'));
      expect(quote.date, equals('2024-01-01T10:00:00.000Z'));
      expect(quote.id, isNull);
      expect(quote.tagIds, isEmpty);
    });

    test('should create Quote with all fields', () {
      // Arrange & Act
      final quote = Quote(
        id: 'test-id',
        content: 'Test content',
        date: '2024-01-01T10:00:00.000Z',
        categoryId: 'category-1',
        tagIds: ['tag1', 'tag2'],
        source: 'Test Source',
        sourceAuthor: 'Test Author',
        sourceWork: 'Test Work',
        location: 'Test Location',
        weather: 'Sunny',
        temperature: '25°C',
        aiAnalysis: 'AI analysis',
        sentiment: 'positive',
        keywords: ['test', 'keyword'],
        summary: 'Test summary',
        colorHex: '#FF0000',
        editSource: 'manual',
        deltaContent: '{"ops":[{"insert":"test"}]}',
        dayPeriod: 'morning',
      );

      // Assert
      expect(quote.id, equals('test-id'));
      expect(quote.content, equals('Test content'));
      expect(quote.categoryId, equals('category-1'));
      expect(quote.tagIds, equals(['tag1', 'tag2']));
      expect(quote.source, equals('Test Source'));
      expect(quote.location, equals('Test Location'));
      expect(quote.weather, equals('Sunny'));
      expect(quote.aiAnalysis, equals('AI analysis'));
      expect(quote.colorHex, equals('#FF0000'));
      expect(quote.deltaContent, equals('{"ops":[{"insert":"test"}]}'));
    });

    test('should convert Quote to JSON correctly', () {
      // Arrange
      final quote = Quote(
        id: 'test-id',
        content: 'Test content',
        date: '2024-01-01T10:00:00.000Z',
        categoryId: 'category-1',
        tagIds: ['tag1', 'tag2'],
        source: 'Test Source',
        location: 'Test Location',
      );

      // Act
      final json = quote.toJson();

      // Assert
      expect(json['id'], equals('test-id'));
      expect(json['content'], equals('Test content'));
      expect(json['date'], equals('2024-01-01T10:00:00.000Z'));
      expect(json['category_id'], equals('category-1'));
      expect(json['tag_ids'], equals('tag1,tag2'));
      expect(json['source'], equals('Test Source'));
      expect(json['location'], equals('Test Location'));
    });

    test('should create Quote from JSON correctly', () {
      // Arrange
      final json = {
        'id': 'test-id',
        'content': 'Test content',
        'date': '2024-01-01T10:00:00.000Z',
        'category_id': 'category-1',
        'tag_ids': 'tag1,tag2',
        'source': 'Test Source',
        'location': 'Test Location',
        'weather': 'Sunny',
        'ai_analysis': 'AI analysis',
        'sentiment': 'positive',
        'keywords': 'test,keyword',
        'summary': 'Test summary',
      };

      // Act
      final quote = Quote.fromJson(json);

      // Assert
      expect(quote.id, equals('test-id'));
      expect(quote.content, equals('Test content'));
      expect(quote.date, equals('2024-01-01T10:00:00.000Z'));
      expect(quote.categoryId, equals('category-1'));
      expect(quote.tagIds, equals(['tag1', 'tag2']));
      expect(quote.source, equals('Test Source'));
      expect(quote.location, equals('Test Location'));
      expect(quote.weather, equals('Sunny'));
      expect(quote.aiAnalysis, equals('AI analysis'));
      expect(quote.sentiment, equals('positive'));
      expect(quote.keywords, equals(['test', 'keyword']));
      expect(quote.summary, equals('Test summary'));
    });

    test('should handle empty tag_ids in JSON', () {
      // Arrange
      final json = {
        'id': 'test-id',
        'content': 'Test content',
        'date': '2024-01-01T10:00:00.000Z',
        'tag_ids': '',
      };

      // Act
      final quote = Quote.fromJson(json);

      // Assert
      expect(quote.tagIds, isEmpty);
    });

    test('should handle null tag_ids in JSON', () {
      // Arrange
      final json = {
        'id': 'test-id',
        'content': 'Test content',
        'date': '2024-01-01T10:00:00.000Z',
        'tag_ids': null,
      };

      // Act
      final quote = Quote.fromJson(json);

      // Assert
      expect(quote.tagIds, isEmpty);
    });

    test('should handle copyWith method', () {
      // Arrange
      final originalQuote = Quote(
        id: 'original-id',
        content: 'Original content',
        date: '2024-01-01T10:00:00.000Z',
        categoryId: 'original-category',
      );

      // Act
      final updatedQuote = originalQuote.copyWith(
        content: 'Updated content',
        categoryId: 'updated-category',
      );

      // Assert
      expect(updatedQuote.id, equals('original-id')); // Unchanged
      expect(updatedQuote.content, equals('Updated content')); // Changed
      expect(updatedQuote.date, equals('2024-01-01T10:00:00.000Z')); // Unchanged
      expect(updatedQuote.categoryId, equals('updated-category')); // Changed
    });

    test('should compare quotes for equality', () {
      // Arrange
      final quote1 = Quote(
        id: 'test-id',
        content: 'Test content',
        date: '2024-01-01T10:00:00.000Z',
      );

      final quote2 = Quote(
        id: 'test-id',
        content: 'Test content',
        date: '2024-01-01T10:00:00.000Z',
      );

      final quote3 = Quote(
        id: 'different-id',
        content: 'Test content',
        date: '2024-01-01T10:00:00.000Z',
      );

      // Act & Assert
      expect(quote1, equals(quote2));
      expect(quote1, isNot(equals(quote3)));
      expect(quote1.hashCode, equals(quote2.hashCode));
      expect(quote1.hashCode, isNot(equals(quote3.hashCode)));
    });
  });

  group('NoteCategory Model Tests', () {
    test('should create NoteCategory with required fields', () {
      // Arrange & Act
      final category = NoteCategory(
        id: 'test-id',
        name: 'Test Category',
        isDefault: false,
      );

      // Assert
      expect(category.id, equals('test-id'));
      expect(category.name, equals('Test Category'));
      expect(category.isDefault, isFalse);
      expect(category.iconName, isNull);
    });

    test('should create NoteCategory with all fields', () {
      // Arrange & Act
      final category = NoteCategory(
        id: 'test-id',
        name: 'Test Category',
        isDefault: true,
        iconName: 'bookmark',
      );

      // Assert
      expect(category.id, equals('test-id'));
      expect(category.name, equals('Test Category'));
      expect(category.isDefault, isTrue);
      expect(category.iconName, equals('bookmark'));
    });

    test('should convert NoteCategory to JSON correctly', () {
      // Arrange
      final category = NoteCategory(
        id: 'test-id',
        name: 'Test Category',
        isDefault: true,
        iconName: 'bookmark',
      );

      // Act
      final json = category.toJson();

      // Assert
      expect(json['id'], equals('test-id'));
      expect(json['name'], equals('Test Category'));
      expect(json['is_default'], equals(1)); // SQLite stores boolean as int
      expect(json['icon_name'], equals('bookmark'));
    });

    test('should create NoteCategory from JSON correctly', () {
      // Arrange
      final json = {
        'id': 'test-id',
        'name': 'Test Category',
        'is_default': 1, // SQLite boolean as int
        'icon_name': 'bookmark',
      };

      // Act
      final category = NoteCategory.fromJson(json);

      // Assert
      expect(category.id, equals('test-id'));
      expect(category.name, equals('Test Category'));
      expect(category.isDefault, isTrue);
      expect(category.iconName, equals('bookmark'));
    });

    test('should handle copyWith method', () {
      // Arrange
      final originalCategory = NoteCategory(
        id: 'original-id',
        name: 'Original Name',
        isDefault: false,
        iconName: 'original-icon',
      );

      // Act
      final updatedCategory = originalCategory.copyWith(
        name: 'Updated Name',
        isDefault: true,
      );

      // Assert
      expect(updatedCategory.id, equals('original-id')); // Unchanged
      expect(updatedCategory.name, equals('Updated Name')); // Changed
      expect(updatedCategory.isDefault, isTrue); // Changed
      expect(updatedCategory.iconName, equals('original-icon')); // Unchanged
    });

    test('should compare categories for equality', () {
      // Arrange
      final category1 = NoteCategory(
        id: 'test-id',
        name: 'Test Category',
        isDefault: false,
      );

      final category2 = NoteCategory(
        id: 'test-id',
        name: 'Test Category',
        isDefault: false,
      );

      final category3 = NoteCategory(
        id: 'different-id',
        name: 'Test Category',
        isDefault: false,
      );

      // Act & Assert
      expect(category1, equals(category2));
      expect(category1, isNot(equals(category3)));
      expect(category1.hashCode, equals(category2.hashCode));
      expect(category1.hashCode, isNot(equals(category3.hashCode)));
    });
  });
}