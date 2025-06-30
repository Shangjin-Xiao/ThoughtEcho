/// Integration tests for app startup and initialization
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test_utils/test_helpers.dart';
import '../mocks/mock_database_service.dart';
import '../mocks/mock_settings_service.dart';
import '../mocks/mock_location_service.dart';
import '../mocks/mock_weather_service.dart';
import '../mocks/mock_ai_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Startup Integration Tests', () {
    setUpAll(() {
      TestHelpers.setupTestEnvironment();
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    testWidgets('should complete app startup sequence', (tester) async {
      // Create mock services
      final databaseService = MockDatabaseService();
      final settingsService = MockSettingsService();
      final locationService = MockLocationService();
      final weatherService = MockWeatherService();
      final aiService = MockAIService();

      // Test app initialization sequence
      await databaseService.initialize();
      await settingsService.initialize();
      await locationService.initialize();
      await weatherService.initialize();
      await aiService.initialize();

      expect(databaseService.isInitialized, isTrue);
      expect(settingsService.isInitialized, isTrue);
      expect(locationService.hasLocationPermission, isTrue);
      expect(weatherService.isInitialized, isTrue);
      expect(aiService.isInitialized, isTrue);
    });

    testWidgets('should handle service dependencies correctly', (tester) async {
      final databaseService = MockDatabaseService();
      final settingsService = MockSettingsService();

      // Settings should initialize before database operations
      await settingsService.initialize();
      await databaseService.initialize();

      // Add test data
      databaseService.addTestData();
      final quotes = await databaseService.getUserQuotes();
      
      expect(quotes, isNotEmpty);
      expect(quotes.length, greaterThan(0));
    });

    testWidgets('should recover from initialization failures', (tester) async {
      final databaseService = MockDatabaseService();
      
      // Simulate initialization error
      databaseService.simulateError('初始化失败');
      
      // Service should handle error gracefully
      expect(databaseService.lastError, isNotNull);
      
      // Recovery should be possible
      await databaseService.initialize();
      expect(databaseService.isInitialized, isTrue);
    });

    testWidgets('should maintain data integrity during startup', (tester) async {
      final databaseService = MockDatabaseService();
      await databaseService.initialize();

      // Add initial data
      databaseService.addTestData();
      final initialCount = (await databaseService.getUserQuotes()).length;

      // Simulate app restart by reinitializing
      await databaseService.initialize();
      final finalCount = (await databaseService.getUserQuotes()).length;

      // Data should be preserved
      expect(finalCount, equals(initialCount));
    });

    testWidgets('should handle concurrent service operations', (tester) async {
      final databaseService = MockDatabaseService();
      final weatherService = MockWeatherService();
      final locationService = MockLocationService();

      // Initialize services concurrently
      final futures = [
        databaseService.initialize(),
        weatherService.initialize(),
        locationService.initialize(),
      ];

      await Future.wait(futures);

      expect(databaseService.isInitialized, isTrue);
      expect(weatherService.isInitialized, isTrue);
      expect(locationService.hasLocationPermission, isTrue);
    });

    testWidgets('should validate service configuration', (tester) async {
      final settingsService = MockSettingsService();
      await settingsService.initialize();

      // Check default configurations
      expect(settingsService.aiSettings, isNotNull);
      expect(settingsService.appSettings, isNotNull);
      expect(settingsService.multiAISettings, isNotNull);
      expect(settingsService.themeMode, isNotNull);
    });

    testWidgets('should handle first-time app launch', (tester) async {
      final settingsService = MockSettingsService();
      await settingsService.initialize();

      // Should detect first-time launch
      expect(settingsService.isOnboardingComplete(), isFalse);
      expect(settingsService.isAppInstalled(), isFalse);

      // Mark as installed
      await settingsService.markAppInstalled();
      await settingsService.markOnboardingComplete();

      expect(settingsService.isAppInstalled(), isTrue);
      expect(settingsService.isOnboardingComplete(), isTrue);
    });

    testWidgets('should handle app upgrade scenarios', (tester) async {
      final settingsService = MockSettingsService();
      await settingsService.initialize();

      // Simulate existing installation
      await settingsService.markAppInstalled();
      await settingsService.setLastVersion('1.0.0');

      // Simulate upgrade
      await settingsService.setLastVersion('1.1.0');
      await settingsService.markAppUpgraded();

      expect(settingsService.getLastVersion(), equals('1.1.0'));
      expect(settingsService.isAppUpgraded(), isTrue);
    });
  });

  group('Note Creation to Analysis Flow Integration Tests', () {
    testWidgets('should complete full note creation and analysis flow', (tester) async {
      final databaseService = MockDatabaseService();
      final aiService = MockAIService();
      final locationService = MockLocationService();
      final weatherService = MockWeatherService();

      // Initialize services
      await databaseService.initialize();
      await aiService.initialize();
      await locationService.initialize();
      await weatherService.initialize();

      // Setup AI service
      aiService.setApiKeyValid(true);

      // Create a note
      final testQuote = Quote(
        content: '这是一个测试笔记内容',
        date: DateTime.now().toIso8601String(),
      );

      // Add note to database
      final savedQuote = await databaseService.addQuote(testQuote);
      expect(savedQuote.id, isNotNull);

      // Get location and weather data
      final position = await locationService.getCurrentLocation();
      final weather = await weatherService.getWeatherByCoordinates(
        position!.latitude,
        position.longitude,
      );

      expect(position, isNotNull);
      expect(weather.isValid, isTrue);

      // Update note with location and weather
      final updatedQuote = savedQuote.copyWith(
        location: locationService.getFormattedAddress(),
        weather: weather.description,
        temperature: weather.temperatureText,
      );

      await databaseService.updateQuote(updatedQuote);

      // Analyze note with AI
      final analysis = await aiService.summarizeNoteWithMultiProvider(updatedQuote);
      expect(analysis, isNotEmpty);

      // Update note with AI analysis
      final finalQuote = updatedQuote.copyWith(aiAnalysis: analysis);
      await databaseService.updateQuote(finalQuote);

      // Verify final note
      final retrievedQuote = await databaseService.getQuoteById(finalQuote.id!);
      expect(retrievedQuote, isNotNull);
      expect(retrievedQuote!.content, equals(testQuote.content));
      expect(retrievedQuote.location, isNotNull);
      expect(retrievedQuote.weather, isNotNull);
      expect(retrievedQuote.aiAnalysis, isNotNull);
    });

    testWidgets('should handle AI analysis errors gracefully', (tester) async {
      final databaseService = MockDatabaseService();
      final aiService = MockAIService();

      await databaseService.initialize();
      await aiService.initialize();

      // Simulate AI service error
      aiService.setApiKeyValid(false);

      final testQuote = Quote(
        content: '测试内容',
        date: DateTime.now().toIso8601String(),
      );

      final savedQuote = await databaseService.addQuote(testQuote);

      // AI analysis should fail gracefully
      expect(
        () => aiService.summarizeNoteWithMultiProvider(savedQuote),
        throwsException,
      );

      // Note should still exist without analysis
      final retrievedQuote = await databaseService.getQuoteById(savedQuote.id!);
      expect(retrievedQuote, isNotNull);
      expect(retrievedQuote!.aiAnalysis, isNull);
    });

    testWidgets('should handle streaming AI responses', (tester) async {
      final aiService = MockAIService();
      await aiService.initialize();
      aiService.setApiKeyValid(true);

      final testQuote = Quote(
        content: '流式分析测试内容',
        date: DateTime.now().toIso8601String(),
      );

      // Test streaming analysis
      final responseStream = aiService.streamQAWithNote(testQuote, '这个笔记的主题是什么？');
      
      final responses = <String>[];
      await for (final chunk in responseStream) {
        responses.add(chunk);
      }

      expect(responses, isNotEmpty);
      expect(responses.join(), isNotEmpty);
    });
  });

  group('Backup and Restore Integration Tests', () {
    testWidgets('should complete backup and restore cycle', (tester) async {
      final databaseService = MockDatabaseService();
      await databaseService.initialize();

      // Add test data
      databaseService.addTestData();
      final originalQuotes = await databaseService.getUserQuotes();
      final originalCategories = await databaseService.getAllCategories();

      expect(originalQuotes, isNotEmpty);
      expect(originalCategories, isNotEmpty);

      // Export data
      final exportedData = await databaseService.exportData();
      expect(exportedData, isNotNull);
      expect(exportedData['quotes'], isNotEmpty);
      expect(exportedData['categories'], isNotEmpty);

      // Clear database
      await databaseService.clearAllData();
      final clearedQuotes = await databaseService.getUserQuotes();
      expect(clearedQuotes, isEmpty);

      // Restore data
      await databaseService.importData(exportedData);
      final restoredQuotes = await databaseService.getUserQuotes();
      final restoredCategories = await databaseService.getAllCategories();

      // Verify restoration
      expect(restoredQuotes.length, equals(originalQuotes.length));
      expect(restoredCategories.length, greaterThanOrEqualTo(originalCategories.length));

      // Verify data integrity
      for (final originalQuote in originalQuotes) {
        final restored = restoredQuotes.firstWhere(
          (q) => q.id == originalQuote.id,
          orElse: () => throw Exception('Quote not found: ${originalQuote.id}'),
        );
        expect(restored.content, equals(originalQuote.content));
      }
    });

    testWidgets('should handle incremental backup and restore', (tester) async {
      final databaseService = MockDatabaseService();
      await databaseService.initialize();

      // Add initial data
      databaseService.addTestData();
      final initialCount = (await databaseService.getUserQuotes()).length;

      // Export data
      final initialExport = await databaseService.exportData();

      // Add more data
      final newQuote = Quote(
        content: '新增笔记',
        date: DateTime.now().toIso8601String(),
      );
      await databaseService.addQuote(newQuote);

      // Export again
      final incrementalExport = await databaseService.exportData();
      final incrementalQuotes = incrementalExport['quotes'] as List;

      expect(incrementalQuotes.length, equals(initialCount + 1));

      // Restore incremental data (without overwrite)
      await databaseService.clearAllData();
      await databaseService.importData(incrementalExport, overwrite: false);

      final finalQuotes = await databaseService.getUserQuotes();
      expect(finalQuotes.length, equals(initialCount + 1));
    });

    testWidgets('should handle corrupted backup data', (tester) async {
      final databaseService = MockDatabaseService();
      await databaseService.initialize();

      // Test with corrupted data
      final corruptedData = {
        'invalid': 'structure',
        'quotes': 'not_a_list',
        'categories': null,
      };

      // Should handle gracefully without crashing
      await databaseService.importData(corruptedData);

      // Database should remain functional
      final quotes = await databaseService.getUserQuotes();
      expect(quotes, isNotNull);
    });
  });

  group('Performance Integration Tests', () {
    testWidgets('should handle large datasets efficiently', (tester) async {
      final databaseService = MockDatabaseService();
      await databaseService.initialize();

      final stopwatch = Stopwatch()..start();

      // Add large number of quotes
      for (int i = 0; i < 100; i++) {
        final quote = Quote(
          content: '性能测试笔记 $i',
          date: DateTime.now().subtract(Duration(days: i)).toIso8601String(),
        );
        await databaseService.addQuote(quote);
      }

      stopwatch.stop();

      // Should complete within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      // Verify data integrity
      final quotes = await databaseService.getUserQuotes();
      expect(quotes.length, greaterThanOrEqualTo(100));

      // Test query performance
      final queryStopwatch = Stopwatch()..start();
      final searchResults = await databaseService.searchQuotes('性能');
      queryStopwatch.stop();

      expect(queryStopwatch.elapsedMilliseconds, lessThan(1000));
      expect(searchResults, isNotEmpty);
    });

    testWidgets('should handle concurrent operations efficiently', (tester) async {
      final databaseService = MockDatabaseService();
      final aiService = MockAIService();
      final weatherService = MockWeatherService();

      // Initialize services
      await Future.wait([
        databaseService.initialize(),
        aiService.initialize(),
        weatherService.initialize(),
      ]);

      // Perform concurrent operations
      final futures = <Future>[];
      
      for (int i = 0; i < 10; i++) {
        futures.add(databaseService.addQuote(Quote(
          content: '并发测试 $i',
          date: DateTime.now().toIso8601String(),
        )));
        
        futures.add(weatherService.getWeatherByCity('测试城市$i'));
      }

      final stopwatch = Stopwatch()..start();
      await Future.wait(futures);
      stopwatch.stop();

      // Should handle concurrent operations efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));

      // Verify data integrity
      final quotes = await databaseService.getUserQuotes();
      expect(quotes.length, greaterThanOrEqualTo(10));
    });
  });
}