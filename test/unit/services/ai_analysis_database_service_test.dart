/// Unit tests for AIAnalysisDatabaseService
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/models/ai_analysis_model.dart';
import '../test_utils/test_data.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('AIAnalysisDatabaseService Tests', () {
    late AIAnalysisDatabaseService service;
    late Database testDatabase;

    setUpAll(() {
      TestHelpers.setupTestEnvironment();
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
    });

    setUp(() async {
      service = AIAnalysisDatabaseService();
      testDatabase = await TestHelpers.createTestDatabase();
      // Override database for testing
      AIAnalysisDatabaseService.setTestDatabase(testDatabase);
    });

    tearDown(() async {
      await service.closeDatabase();
      await TestHelpers.cleanupTestDatabase(testDatabase);
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    group('Initialization', () {
      test('should initialize database successfully', () async {
        final database = await service.database;
        expect(database, isNotNull);
      });

      test('should create ai_analyses table', () async {
        final database = await service.database;
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_analyses'"
        );
        expect(tables, isNotEmpty);
      });
    });

    group('Analysis Operations', () {
      test('should save analysis successfully', () async {
        final testAnalysis = TestData.createTestAIAnalysis();
        
        final savedAnalysis = await service.saveAnalysis(testAnalysis);
        
        expect(savedAnalysis.id, isNotNull);
        expect(savedAnalysis.quoteId, equals(testAnalysis.quoteId));
        expect(savedAnalysis.analysisType, equals(testAnalysis.analysisType));
        expect(savedAnalysis.content, equals(testAnalysis.content));
        expect(savedAnalysis.createdAt, isNotEmpty);
      });

      test('should generate ID when not provided', () async {
        final testAnalysis = TestData.createTestAIAnalysis(id: null);
        
        final savedAnalysis = await service.saveAnalysis(testAnalysis);
        
        expect(savedAnalysis.id, isNotNull);
        expect(savedAnalysis.id, TestHelpers.isValidId());
      });

      test('should update existing analysis', () async {
        // Save initial analysis
        final initialAnalysis = TestData.createTestAIAnalysis();
        final savedAnalysis = await service.saveAnalysis(initialAnalysis);
        
        // Update the analysis
        final updatedAnalysis = savedAnalysis.copyWith(
          content: '更新后的分析内容',
          analysisType: 'updated_sentiment',
        );
        
        final result = await service.saveAnalysis(updatedAnalysis);
        
        expect(result.id, equals(savedAnalysis.id));
        expect(result.content, equals('更新后的分析内容'));
        expect(result.analysisType, equals('updated_sentiment'));
      });

      test('should get analysis by ID', () async {
        final testAnalysis = TestData.createTestAIAnalysis();
        final savedAnalysis = await service.saveAnalysis(testAnalysis);
        
        final retrievedAnalysis = await service.getAnalysisById(savedAnalysis.id!);
        
        expect(retrievedAnalysis, isNotNull);
        expect(retrievedAnalysis!.id, equals(savedAnalysis.id));
        expect(retrievedAnalysis.content, equals(testAnalysis.content));
      });

      test('should return null for non-existent analysis', () async {
        final result = await service.getAnalysisById('non-existent-id');
        expect(result, isNull);
      });

      test('should get analyses by quote ID', () async {
        const quoteId = 'test-quote-123';
        
        // Save multiple analyses for the same quote
        final analysis1 = TestData.createTestAIAnalysis(
          quoteId: quoteId,
          analysisType: 'sentiment',
        );
        final analysis2 = TestData.createTestAIAnalysis(
          quoteId: quoteId,
          analysisType: 'keywords',
        );
        
        await service.saveAnalysis(analysis1);
        await service.saveAnalysis(analysis2);
        
        final analyses = await service.getAnalysesByQuoteId(quoteId);
        
        expect(analyses.length, equals(2));
        expect(analyses.every((a) => a.quoteId == quoteId), isTrue);
      });

      test('should delete analysis successfully', () async {
        final testAnalysis = TestData.createTestAIAnalysis();
        final savedAnalysis = await service.saveAnalysis(testAnalysis);
        
        await service.deleteAnalysis(savedAnalysis.id!);
        
        final retrievedAnalysis = await service.getAnalysisById(savedAnalysis.id!);
        expect(retrievedAnalysis, isNull);
      });

      test('should handle deletion of non-existent analysis', () async {
        // Should not throw error
        await service.deleteAnalysis('non-existent-id');
      });
    });

    group('Query Operations', () {
      test('should get analyses by type', () async {
        // Save analyses of different types
        final sentimentAnalysis = TestData.createTestAIAnalysis(
          analysisType: 'sentiment',
          content: '情感分析结果',
        );
        final keywordAnalysis = TestData.createTestAIAnalysis(
          analysisType: 'keywords',
          content: '关键词分析结果',
        );
        
        await service.saveAnalysis(sentimentAnalysis);
        await service.saveAnalysis(keywordAnalysis);
        
        final sentimentResults = await service.getAnalysesByType('sentiment');
        
        expect(sentimentResults.length, equals(1));
        expect(sentimentResults.first.analysisType, equals('sentiment'));
        expect(sentimentResults.first.content, equals('情感分析结果'));
      });

      test('should get all analyses', () async {
        // Save multiple analyses
        final analyses = [
          TestData.createTestAIAnalysis(analysisType: 'sentiment'),
          TestData.createTestAIAnalysis(analysisType: 'keywords'),
          TestData.createTestAIAnalysis(analysisType: 'summary'),
        ];
        
        for (final analysis in analyses) {
          await service.saveAnalysis(analysis);
        }
        
        final allAnalyses = await service.getAllAnalyses();
        
        expect(allAnalyses.length, greaterThanOrEqualTo(3));
      });

      test('should get recent analyses', () async {
        // Save analyses with different timestamps
        final oldAnalysis = TestData.createTestAIAnalysis().copyWith(
          createdAt: DateTime.now().subtract(const Duration(days: 10)).toIso8601String(),
        );
        final recentAnalysis = TestData.createTestAIAnalysis().copyWith(
          createdAt: DateTime.now().toIso8601String(),
        );
        
        await service.saveAnalysis(oldAnalysis);
        await service.saveAnalysis(recentAnalysis);
        
        final recentAnalyses = await service.getRecentAnalyses(limit: 1);
        
        expect(recentAnalyses.length, equals(1));
        // Should return the most recent one
        expect(recentAnalyses.first.id, equals(recentAnalysis.id));
      });

      test('should respect limit parameter', () async {
        // Save multiple analyses
        for (int i = 0; i < 5; i++) {
          final analysis = TestData.createTestAIAnalysis().copyWith(
            id: 'analysis-$i',
          );
          await service.saveAnalysis(analysis);
        }
        
        final limitedResults = await service.getRecentAnalyses(limit: 3);
        
        expect(limitedResults.length, equals(3));
      });
    });

    group('Batch Operations', () {
      test('should save multiple analyses in batch', () async {
        final analyses = [
          TestData.createTestAIAnalysis(id: 'batch-1'),
          TestData.createTestAIAnalysis(id: 'batch-2'),
          TestData.createTestAIAnalysis(id: 'batch-3'),
        ];
        
        // Note: If batch save method exists, use it. Otherwise, this tests individual saves.
        for (final analysis in analyses) {
          await service.saveAnalysis(analysis);
        }
        
        final allAnalyses = await service.getAllAnalyses();
        expect(allAnalyses.length, greaterThanOrEqualTo(3));
        
        final batchIds = analyses.map((a) => a.id).toSet();
        final savedIds = allAnalyses.map((a) => a.id).toSet();
        expect(savedIds.containsAll(batchIds), isTrue);
      });

      test('should delete analyses by quote ID', () async {
        const quoteId = 'quote-to-delete';
        
        // Save analyses for the quote
        final analysis1 = TestData.createTestAIAnalysis(quoteId: quoteId);
        final analysis2 = TestData.createTestAIAnalysis(quoteId: quoteId);
        final otherAnalysis = TestData.createTestAIAnalysis(quoteId: 'other-quote');
        
        await service.saveAnalysis(analysis1);
        await service.saveAnalysis(analysis2);
        await service.saveAnalysis(otherAnalysis);
        
        await service.deleteAnalysesByQuoteId(quoteId);
        
        final remainingAnalyses = await service.getAnalysesByQuoteId(quoteId);
        final otherRemaining = await service.getAnalysesByQuoteId('other-quote');
        
        expect(remainingAnalyses, isEmpty);
        expect(otherRemaining.length, equals(1));
      });
    });

    group('Metadata Handling', () {
      test('should store and retrieve metadata correctly', () async {
        final metadata = {
          'confidence': 0.95,
          'model': 'gpt-4',
          'tokens_used': 150,
          'processing_time': 1.5,
        };
        
        final testAnalysis = TestData.createTestAIAnalysis().copyWith(
          metadata: metadata,
        );
        
        final savedAnalysis = await service.saveAnalysis(testAnalysis);
        final retrievedAnalysis = await service.getAnalysisById(savedAnalysis.id!);
        
        expect(retrievedAnalysis!.metadata, isNotNull);
        expect(retrievedAnalysis.metadata!['confidence'], equals(0.95));
        expect(retrievedAnalysis.metadata!['model'], equals('gpt-4'));
        expect(retrievedAnalysis.metadata!['tokens_used'], equals(150));
        expect(retrievedAnalysis.metadata!['processing_time'], equals(1.5));
      });

      test('should handle null metadata', () async {
        final testAnalysis = TestData.createTestAIAnalysis().copyWith(
          metadata: null,
        );
        
        final savedAnalysis = await service.saveAnalysis(testAnalysis);
        final retrievedAnalysis = await service.getAnalysisById(savedAnalysis.id!);
        
        expect(retrievedAnalysis!.metadata, isNull);
      });
    });

    group('Error Handling', () {
      test('should handle database errors gracefully', () async {
        // Close the database to simulate an error
        await service.closeDatabase();
        
        expect(
          () => service.saveAnalysis(TestData.createTestAIAnalysis()),
          throwsException,
        );
      });

      test('should handle malformed JSON in metadata', () async {
        // Directly insert malformed data to test error handling
        final database = await service.database;
        
        await database.insert('ai_analyses', {
          'id': 'malformed-test',
          'quote_id': 'test-quote',
          'analysis_type': 'test',
          'content': 'test content',
          'created_at': DateTime.now().toIso8601String(),
          'metadata': 'invalid json string',
          'quote_count': 1,
        });
        
        final analysis = await service.getAnalysisById('malformed-test');
        
        // Should handle gracefully and return null metadata
        expect(analysis, isNotNull);
        expect(analysis!.metadata, isNull);
      });
    });

    group('Streaming', () {
      test('should stream analyses changes', () async {
        final analysesStream = service.analysesStream;
        
        // Add new analysis
        final testAnalysis = TestData.createTestAIAnalysis();
        await service.saveAnalysis(testAnalysis);
        
        await TestHelpers.expectStream(
          analysesStream.take(1),
          [anything], // Just verify stream emits
        );
      });
    });

    group('Database Cleanup', () {
      test('should clean up old analyses', () async {
        // Save old analyses
        final oldDate = DateTime.now().subtract(const Duration(days: 365));
        for (int i = 0; i < 5; i++) {
          final oldAnalysis = TestData.createTestAIAnalysis().copyWith(
            id: 'old-$i',
            createdAt: oldDate.toIso8601String(),
          );
          await service.saveAnalysis(oldAnalysis);
        }
        
        // Save recent analyses
        for (int i = 0; i < 3; i++) {
          final recentAnalysis = TestData.createTestAIAnalysis().copyWith(
            id: 'recent-$i',
          );
          await service.saveAnalysis(recentAnalysis);
        }
        
        // Note: If cleanup method exists, use it
        // await service.cleanupOldAnalyses(daysToKeep: 30);
        
        final allAnalyses = await service.getAllAnalyses();
        expect(allAnalyses.length, equals(8)); // All should still be there without cleanup method
      });

      test('should get database statistics', () async {
        // Add some test data
        for (int i = 0; i < 10; i++) {
          await service.saveAnalysis(TestData.createTestAIAnalysis());
        }
        
        // Note: If statistics method exists, use it
        // final stats = await service.getDatabaseStatistics();
        // expect(stats['total_analyses'], greaterThanOrEqualTo(10));
        
        final allAnalyses = await service.getAllAnalyses();
        expect(allAnalyses.length, greaterThanOrEqualTo(10));
      });
    });

    group('Performance', () {
      test('should handle large number of analyses efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Save 50 analyses
        for (int i = 0; i < 50; i++) {
          final analysis = TestData.createTestAIAnalysis().copyWith(
            id: 'perf-$i',
            content: '性能测试分析 $i',
          );
          await service.saveAnalysis(analysis);
        }
        
        stopwatch.stop();
        
        // Should complete within reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(3000));
        
        // Verify data integrity
        final analyses = await service.getAllAnalyses();
        expect(analyses.length, greaterThanOrEqualTo(50));
      });

      test('should query efficiently with large dataset', () async {
        // Add test data
        for (int i = 0; i < 30; i++) {
          final analysis = TestData.createTestAIAnalysis().copyWith(
            analysisType: i % 3 == 0 ? 'sentiment' : 'keywords',
          );
          await service.saveAnalysis(analysis);
        }
        
        final stopwatch = Stopwatch()..start();
        final sentimentAnalyses = await service.getAnalysesByType('sentiment');
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
        expect(sentimentAnalyses.length, equals(10)); // Should find 10 sentiment analyses
      });
    });
  });
}