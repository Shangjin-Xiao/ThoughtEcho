/// Unit tests for DatabaseService
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

import '../../lib/services/database_service.dart';
import '../../lib/models/quote_model.dart';
import '../../lib/models/note_category.dart';
import '../test_utils/test_data.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('DatabaseService Tests', () {
    late DatabaseService databaseService;
    late Database testDatabase;

    setUpAll(() {
      TestHelpers.setupTestEnvironment();
      // Initialize FFI for desktop platforms in tests
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
    });

    setUp(() async {
      // Create a fresh database for each test
      testDatabase = await TestHelpers.createTestDatabase();
      databaseService = DatabaseService();
      
      // Override the database instance for testing
      DatabaseService.setTestDatabase(testDatabase);
      await databaseService.initialize();
    });

    tearDown(() async {
      await TestHelpers.cleanupTestDatabase(testDatabase);
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        expect(databaseService.isInitialized, isTrue);
      });

      test('should create required tables', () async {
        final tables = await testDatabase.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"
        );
        
        final tableNames = tables.map((table) => table['name']).toSet();
        expect(tableNames, contains('quotes'));
        expect(tableNames, contains('categories'));
      });

      test('should create default categories', () async {
        final categories = await databaseService.getAllCategories();
        expect(categories, isNotEmpty);
        
        // Check for some default categories
        final categoryNames = categories.map((c) => c.name).toSet();
        expect(categoryNames, contains('动画'));
        expect(categoryNames, contains('漫画'));
        expect(categoryNames, contains('游戏'));
      });
    });

    group('Quote Operations', () {
      test('should add quote successfully', () async {
        final testQuote = TestData.createTestQuote();
        
        final addedQuote = await databaseService.addQuote(testQuote);
        
        expect(addedQuote.id, isNotNull);
        expect(addedQuote.content, equals(testQuote.content));
        expect(addedQuote.date, equals(testQuote.date));
      });

      test('should update quote successfully', () async {
        // Add a quote first
        final originalQuote = TestData.createTestQuote();
        final addedQuote = await databaseService.addQuote(originalQuote);
        
        // Update the quote
        final updatedQuote = addedQuote.copyWith(
          content: '更新后的内容',
          aiAnalysis: '更新后的AI分析',
        );
        
        await databaseService.updateQuote(updatedQuote);
        
        // Verify the update
        final retrievedQuote = await databaseService.getQuoteById(addedQuote.id!);
        expect(retrievedQuote?.content, equals('更新后的内容'));
        expect(retrievedQuote?.aiAnalysis, equals('更新后的AI分析'));
      });

      test('should delete quote successfully', () async {
        // Add a quote first
        final testQuote = TestData.createTestQuote();
        final addedQuote = await databaseService.addQuote(testQuote);
        
        // Delete the quote
        await databaseService.deleteQuote(addedQuote.id!);
        
        // Verify deletion
        final retrievedQuote = await databaseService.getQuoteById(addedQuote.id!);
        expect(retrievedQuote, isNull);
      });

      test('should get quote by ID', () async {
        final testQuote = TestData.createTestQuote();
        final addedQuote = await databaseService.addQuote(testQuote);
        
        final retrievedQuote = await databaseService.getQuoteById(addedQuote.id!);
        
        expect(retrievedQuote, isNotNull);
        expect(retrievedQuote!.id, equals(addedQuote.id));
        expect(retrievedQuote.content, equals(testQuote.content));
      });

      test('should get all user quotes', () async {
        // Add multiple quotes
        final quotes = TestData.createTestQuoteList(3);
        for (final quote in quotes) {
          await databaseService.addQuote(quote);
        }
        
        final userQuotes = await databaseService.getUserQuotes();
        
        expect(userQuotes.length, greaterThanOrEqualTo(3));
      });

      test('should filter quotes by category', () async {
        final category = TestData.createTestCategory(id: 'test-category');
        await databaseService.addCategory(category);
        
        // Add quotes with different categories
        final quote1 = TestData.createTestQuote(categoryId: 'test-category');
        final quote2 = TestData.createTestQuote(categoryId: 'other-category');
        
        await databaseService.addQuote(quote1);
        await databaseService.addQuote(quote2);
        
        final filteredQuotes = await databaseService.getUserQuotes(
          categoryId: 'test-category',
        );
        
        expect(filteredQuotes.length, equals(1));
        expect(filteredQuotes.first.categoryId, equals('test-category'));
      });

      test('should search quotes by content', () async {
        // Add test quotes
        final quote1 = TestData.createTestQuote(content: '这是关于Flutter的笔记');
        final quote2 = TestData.createTestQuote(content: '这是关于Dart的笔记');
        final quote3 = TestData.createTestQuote(content: '这是关于其他的笔记');
        
        await databaseService.addQuote(quote1);
        await databaseService.addQuote(quote2);
        await databaseService.addQuote(quote3);
        
        final searchResults = await databaseService.searchQuotes('Flutter');
        
        expect(searchResults.length, equals(1));
        expect(searchResults.first.content, contains('Flutter'));
      });

      test('should handle pagination correctly', () async {
        // Add multiple quotes
        final quotes = TestData.createTestQuoteList(10);
        for (final quote in quotes) {
          await databaseService.addQuote(quote);
        }
        
        // Test pagination
        final firstPage = await databaseService.getUserQuotes(
          limit: 5,
          offset: 0,
        );
        final secondPage = await databaseService.getUserQuotes(
          limit: 5,
          offset: 5,
        );
        
        expect(firstPage.length, equals(5));
        expect(secondPage.length, equals(5));
        
        // Ensure no overlap
        final firstPageIds = firstPage.map((q) => q.id).toSet();
        final secondPageIds = secondPage.map((q) => q.id).toSet();
        expect(firstPageIds.intersection(secondPageIds), isEmpty);
      });
    });

    group('Category Operations', () {
      test('should add category successfully', () async {
        final testCategory = TestData.createTestCategory();
        
        final addedCategory = await databaseService.addCategory(testCategory);
        
        expect(addedCategory.id, isNotNull);
        expect(addedCategory.name, equals(testCategory.name));
        expect(addedCategory.iconName, equals(testCategory.iconName));
      });

      test('should update category successfully', () async {
        final originalCategory = TestData.createTestCategory();
        final addedCategory = await databaseService.addCategory(originalCategory);
        
        final updatedCategory = addedCategory.copyWith(
          name: '更新后的分类',
          iconName: 'new-icon',
        );
        
        await databaseService.updateCategory(updatedCategory);
        
        final categories = await databaseService.getAllCategories();
        final retrieved = categories.firstWhere((c) => c.id == addedCategory.id);
        
        expect(retrieved.name, equals('更新后的分类'));
        expect(retrieved.iconName, equals('new-icon'));
      });

      test('should delete category successfully', () async {
        final testCategory = TestData.createTestCategory();
        final addedCategory = await databaseService.addCategory(testCategory);
        
        await databaseService.deleteCategory(addedCategory.id!);
        
        final categories = await databaseService.getAllCategories();
        expect(categories.any((c) => c.id == addedCategory.id), isFalse);
      });

      test('should get all categories', () async {
        final initialCount = (await databaseService.getAllCategories()).length;
        
        // Add test categories
        final categories = TestData.createTestCategoryList();
        for (final category in categories) {
          await databaseService.addCategory(category);
        }
        
        final allCategories = await databaseService.getAllCategories();
        expect(allCategories.length, equals(initialCount + categories.length));
      });
    });

    group('Data Export/Import', () {
      test('should export data successfully', () async {
        // Add test data
        final testQuote = TestData.createTestQuote();
        final testCategory = TestData.createTestCategory();
        
        await databaseService.addQuote(testQuote);
        await databaseService.addCategory(testCategory);
        
        final exportedData = await databaseService.exportData();
        
        expect(exportedData, containsPair('app_info', anything));
        expect(exportedData, containsPair('quotes', anything));
        expect(exportedData, containsPair('categories', anything));
        
        final quotes = exportedData['quotes'] as List;
        final categories = exportedData['categories'] as List;
        
        expect(quotes, isNotEmpty);
        expect(categories, isNotEmpty);
      });

      test('should import data successfully', () async {
        final importData = TestData.sampleBackupData;
        
        await databaseService.importData(importData);
        
        final quotes = await databaseService.getUserQuotes();
        final categories = await databaseService.getAllCategories();
        
        expect(quotes.any((q) => q.id == 'test-quote-json'), isTrue);
        expect(categories.any((c) => c.id == 'test-category'), isTrue);
      });

      test('should handle import with overwrite', () async {
        // Add initial data
        final initialQuote = TestData.createTestQuote();
        await databaseService.addQuote(initialQuote);
        
        final initialCount = (await databaseService.getUserQuotes()).length;
        
        // Import with overwrite
        final importData = TestData.sampleBackupData;
        await databaseService.importData(importData, overwrite: true);
        
        final finalQuotes = await databaseService.getUserQuotes();
        
        // Should only have imported data
        expect(finalQuotes.length, equals(1));
        expect(finalQuotes.first.id, equals('test-quote-json'));
      });
    });

    group('Error Handling', () {
      test('should handle invalid quote ID gracefully', () async {
        final result = await databaseService.getQuoteById('non-existent-id');
        expect(result, isNull);
      });

      test('should throw error when updating non-existent quote', () async {
        final nonExistentQuote = TestData.createTestQuote(id: 'non-existent');
        
        expect(
          () => databaseService.updateQuote(nonExistentQuote),
          throwsException,
        );
      });

      test('should throw error when deleting non-existent quote', () async {
        expect(
          () => databaseService.deleteQuote('non-existent-id'),
          throwsException,
        );
      });

      test('should handle malformed import data', () async {
        final malformedData = {'invalid': 'data'};
        
        // Should not throw but also not corrupt existing data
        await databaseService.importData(malformedData);
        
        // Verify service is still functional
        final quotes = await databaseService.getUserQuotes();
        expect(quotes, isNotNull);
      });
    });

    group('Streaming', () {
      test('should stream quotes changes', () async {
        final quotesStream = databaseService.quotesStream;
        final initialQuotes = await databaseService.getUserQuotes();
        
        // Add a new quote
        final testQuote = TestData.createTestQuote();
        await databaseService.addQuote(testQuote);
        
        await TestHelpers.expectStream(
          quotesStream.take(1),
          [anything], // Just verify stream emits
        );
      });

      test('should stream categories changes', () async {
        final categoriesStream = databaseService.categoriesStream;
        
        // Add a new category
        final testCategory = TestData.createTestCategory();
        await databaseService.addCategory(testCategory);
        
        await TestHelpers.expectStream(
          categoriesStream.take(1),
          [anything], // Just verify stream emits
        );
      });
    });

    group('Performance', () {
      test('should handle large number of quotes efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Add 100 quotes
        for (int i = 0; i < 100; i++) {
          final quote = TestData.createTestQuote(
            id: 'perf-test-$i',
            content: '性能测试笔记 $i',
          );
          await databaseService.addQuote(quote);
        }
        
        stopwatch.stop();
        
        // Should complete within reasonable time (adjust threshold as needed)
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        
        // Verify data integrity
        final quotes = await databaseService.getUserQuotes();
        expect(quotes.length, greaterThanOrEqualTo(100));
      });

      test('should search efficiently with large dataset', () async {
        // Add test data with various content
        for (int i = 0; i < 50; i++) {
          final quote = TestData.createTestQuote(
            content: i % 10 == 0 ? '特殊搜索目标 $i' : '普通内容 $i',
          );
          await databaseService.addQuote(quote);
        }
        
        final stopwatch = Stopwatch()..start();
        final searchResults = await databaseService.searchQuotes('特殊搜索目标');
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(searchResults.length, equals(5)); // Should find 5 matches
      });
    });
  });
}