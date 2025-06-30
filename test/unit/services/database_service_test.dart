import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import '../../../lib/models/quote_model.dart';
import '../../../lib/models/note_category.dart';
import '../../mocks/mock_database_service.dart';

void main() {
  group('DatabaseService Tests', () {
    late MockDatabaseService mockDb;

    setUp(() {
      mockDb = MockDatabaseService();
      MockDatabaseService.resetTestData();
    });

    tearDown(() {
      reset(mockDb);
    });

    group('Quote Operations', () {
      test('should return user quotes', () async {
        // Act
        final result = await mockDb.getUserQuotes();

        // Assert
        expect(result, isNotEmpty);
        expect(result.length, equals(2));
        expect(result.first.content, equals('Test quote 1'));
        expect(result.last.content, equals('Test quote 2'));
      });

      test('should filter quotes by category', () async {
        // Act
        final result = await mockDb.getUserQuotes(categoryId: 'test-category-1');

        // Assert
        expect(result.length, equals(1));
        expect(result.first.categoryId, equals('test-category-1'));
      });

      test('should add new quote', () async {
        // Arrange
        final newQuote = Quote(
          id: '3',
          content: 'New test quote',
          date: DateTime.now().toIso8601String(),
          categoryId: 'test-category-1',
        );

        // Act
        await mockDb.addQuote(newQuote);
        final result = await mockDb.getUserQuotes();

        // Assert
        expect(result.length, equals(3));
        expect(result.any((q) => q.content == 'New test quote'), isTrue);
      });

      test('should update existing quote', () async {
        // Arrange
        const updatedContent = 'Updated test quote';
        final updatedQuote = Quote(
          id: '1',
          content: updatedContent,
          date: '2024-01-01T10:00:00.000Z',
          categoryId: 'test-category-1',
        );

        // Act
        await mockDb.updateQuote(updatedQuote);
        final result = await mockDb.getQuoteById('1');

        // Assert
        expect(result, isNotNull);
        expect(result!.content, equals(updatedContent));
      });

      test('should delete quote', () async {
        // Act
        await mockDb.deleteQuote('1');
        final result = await mockDb.getUserQuotes();

        // Assert
        expect(result.length, equals(1));
        expect(result.any((q) => q.id == '1'), isFalse);
      });

      test('should get quote by id', () async {
        // Act
        final result = await mockDb.getQuoteById('1');

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals('1'));
        expect(result.content, equals('Test quote 1'));
      });

      test('should return null for non-existent quote id', () async {
        // Act
        final result = await mockDb.getQuoteById('999');

        // Assert
        expect(result, isNull);
      });

      test('should count quotes correctly', () async {
        // Act
        final totalCount = await mockDb.getQuoteCount();
        final categoryCount = await mockDb.getQuoteCount(categoryId: 'test-category-1');

        // Assert
        expect(totalCount, equals(2));
        expect(categoryCount, equals(1));
      });

      test('should apply limit to results', () async {
        // Act
        final result = await mockDb.getUserQuotes(limit: 1);

        // Assert
        expect(result.length, equals(1));
      });
    });

    group('Category Operations', () {
      test('should return categories', () async {
        // Act
        final result = await mockDb.getCategories();

        // Assert
        expect(result, isNotEmpty);
        expect(result.length, equals(3));
        expect(result.any((c) => c.name == 'Test Category 1'), isTrue);
        expect(result.any((c) => c.name == '一言'), isTrue);
      });

      test('should add new category', () async {
        // Arrange
        final newCategory = NoteCategory(
          id: 'new-category',
          name: 'New Category',
          isDefault: false,
          iconName: 'new_icon',
        );

        // Act
        await mockDb.addCategory(newCategory);
        final result = await mockDb.getCategories();

        // Assert
        expect(result.length, equals(4));
        expect(result.any((c) => c.name == 'New Category'), isTrue);
      });

      test('should update existing category', () async {
        // Arrange
        const updatedName = 'Updated Category';
        final updatedCategory = NoteCategory(
          id: 'test-category-1',
          name: updatedName,
          isDefault: false,
          iconName: 'updated_icon',
        );

        // Act
        await mockDb.updateCategory(updatedCategory);
        final result = await mockDb.getCategoryById('test-category-1');

        // Assert
        expect(result, isNotNull);
        expect(result!.name, equals(updatedName));
        expect(result.iconName, equals('updated_icon'));
      });

      test('should delete category', () async {
        // Act
        await mockDb.deleteCategory('test-category-1');
        final result = await mockDb.getCategories();

        // Assert
        expect(result.length, equals(2));
        expect(result.any((c) => c.id == 'test-category-1'), isFalse);
      });

      test('should get category by id', () async {
        // Act
        final result = await mockDb.getCategoryById('test-category-1');

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals('test-category-1'));
        expect(result.name, equals('Test Category 1'));
      });

      test('should return null for non-existent category id', () async {
        // Act
        final result = await mockDb.getCategoryById('999');

        // Assert
        expect(result, isNull);
      });
    });

    group('Data Import/Export', () {
      test('should export data correctly', () async {
        // Act
        final exportedData = await mockDb.exportData();

        // Assert
        expect(exportedData['quotes'], isNotNull);
        expect(exportedData['categories'], isNotNull);
        expect(exportedData['exportTime'], isNotNull);
        expect(exportedData['version'], isNotNull);

        final quotes = exportedData['quotes'] as List;
        final categories = exportedData['categories'] as List;
        expect(quotes.length, equals(2));
        expect(categories.length, equals(3));
      });

      test('should import data without override', () async {
        // Arrange
        final importData = {
          'quotes': [
            {
              'id': '10',
              'content': 'Imported quote',
              'date': '2024-01-10T10:00:00.000Z',
              'category_id': 'imported-category',
              'tag_ids': [],
            }
          ],
          'categories': [
            {
              'id': 'imported-category',
              'name': 'Imported Category',
              'is_default': false,
              'icon_name': 'import',
            }
          ],
        };

        // Act
        await mockDb.importData(importData, override: false);
        final quotes = await mockDb.getUserQuotes();
        final categories = await mockDb.getCategories();

        // Assert
        expect(quotes.length, equals(3)); // Original 2 + 1 imported
        expect(categories.length, equals(4)); // Original 3 + 1 imported
        expect(quotes.any((q) => q.content == 'Imported quote'), isTrue);
        expect(categories.any((c) => c.name == 'Imported Category'), isTrue);
      });

      test('should import data with override', () async {
        // Arrange
        final importData = {
          'quotes': [
            {
              'id': '20',
              'content': 'Override quote',
              'date': '2024-01-20T10:00:00.000Z',
              'category_id': 'override-category',
              'tag_ids': [],
            }
          ],
          'categories': [
            {
              'id': 'override-category',
              'name': 'Override Category',
              'is_default': false,
              'icon_name': 'override',
            }
          ],
        };

        // Act
        await mockDb.importData(importData, override: true);
        final quotes = await mockDb.getUserQuotes();
        final categories = await mockDb.getCategories();

        // Assert
        expect(quotes.length, equals(1)); // Only imported data
        expect(categories.length, equals(1)); // Only imported data
        expect(quotes.first.content, equals('Override quote'));
        expect(categories.first.name, equals('Override Category'));
      });
    });

    group('Edge Cases', () {
      test('should handle empty results gracefully', () async {
        // Arrange - Delete all quotes
        await mockDb.deleteQuote('1');
        await mockDb.deleteQuote('2');

        // Act
        final quotes = await mockDb.getUserQuotes();
        final count = await mockDb.getQuoteCount();

        // Assert
        expect(quotes, isEmpty);
        expect(count, equals(0));
      });

      test('should handle non-existent filter categories', () async {
        // Act
        final result = await mockDb.getUserQuotes(categoryId: 'non-existent');

        // Assert
        expect(result, isEmpty);
      });

      test('should handle empty tag filter', () async {
        // Act
        final result = await mockDb.getUserQuotes(tagIds: []);

        // Assert
        expect(result.length, equals(2)); // Should return all quotes
      });
    });
  });
}