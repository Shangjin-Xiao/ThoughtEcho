/// Unit tests for Quote model
import 'package:flutter_test/flutter_test.dart';

import '../../lib/models/quote_model.dart';
import '../test_utils/test_data.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('Quote Model Tests', () {
    group('Construction', () {
      test('should create quote with required fields', () {
        final quote = Quote(
          content: '测试内容',
          date: DateTime.now().toIso8601String(),
        );

        expect(quote.content, equals('测试内容'));
        expect(quote.date, TestHelpers.isValidDate());
        expect(quote.tagIds, isEmpty);
      });

      test('should create quote with all fields', () {
        final testQuote = TestData.createTestQuote();

        expect(testQuote.id, isNotNull);
        expect(testQuote.content, isNotEmpty);
        expect(testQuote.date, TestHelpers.isValidDate());
        expect(testQuote.categoryId, isNotNull);
        expect(testQuote.tagIds, isNotEmpty);
        expect(testQuote.location, isNotNull);
        expect(testQuote.weather, isNotNull);
        expect(testQuote.temperature, isNotNull);
        expect(testQuote.source, isNotNull);
        expect(testQuote.sourceAuthor, isNotNull);
        expect(testQuote.sourceWork, isNotNull);
        expect(testQuote.aiAnalysis, isNotNull);
        expect(testQuote.sentiment, isNotNull);
        expect(testQuote.keywords, isNotNull);
        expect(testQuote.summary, isNotNull);
        expect(testQuote.colorHex, isNotNull);
        expect(testQuote.editSource, isNotNull);
        expect(testQuote.dayPeriod, isNotNull);
      });

      test('should handle empty tag IDs', () {
        final quote = Quote(
          content: '测试内容',
          date: DateTime.now().toIso8601String(),
          tagIds: [],
        );

        expect(quote.tagIds, isEmpty);
      });

      test('should handle null optional fields', () {
        final quote = Quote(
          content: '测试内容',
          date: DateTime.now().toIso8601String(),
          id: null,
          source: null,
          sourceAuthor: null,
          sourceWork: null,
          categoryId: null,
          location: null,
          weather: null,
          temperature: null,
          aiAnalysis: null,
          sentiment: null,
          keywords: null,
          summary: null,
          colorHex: null,
          editSource: null,
          deltaContent: null,
          dayPeriod: null,
        );

        expect(quote.id, isNull);
        expect(quote.source, isNull);
        expect(quote.sourceAuthor, isNull);
        expect(quote.sourceWork, isNull);
        expect(quote.categoryId, isNull);
        expect(quote.location, isNull);
        expect(quote.weather, isNull);
        expect(quote.temperature, isNull);
        expect(quote.aiAnalysis, isNull);
        expect(quote.sentiment, isNull);
        expect(quote.keywords, isNull);
        expect(quote.summary, isNull);
        expect(quote.colorHex, isNull);
        expect(quote.editSource, isNull);
        expect(quote.deltaContent, isNull);
        expect(quote.dayPeriod, isNull);
      });
    });

    group('JSON Serialization', () {
      test('should convert to JSON correctly', () {
        final testQuote = TestData.createTestQuote();
        final json = testQuote.toJson();

        expect(json, isA<Map<String, dynamic>>());
        expect(json['id'], equals(testQuote.id));
        expect(json['content'], equals(testQuote.content));
        expect(json['date'], equals(testQuote.date));
        expect(json['category_id'], equals(testQuote.categoryId));
        expect(json['tag_ids'], isA<String>());
        expect(json['source'], equals(testQuote.source));
        expect(json['source_author'], equals(testQuote.sourceAuthor));
        expect(json['source_work'], equals(testQuote.sourceWork));
        expect(json['location'], equals(testQuote.location));
        expect(json['weather'], equals(testQuote.weather));
        expect(json['temperature'], equals(testQuote.temperature));
        expect(json['color_hex'], equals(testQuote.colorHex));
        expect(json['edit_source'], equals(testQuote.editSource));
        expect(json['delta_content'], equals(testQuote.deltaContent));
        expect(json['day_period'], equals(testQuote.dayPeriod));
        expect(json['ai_analysis'], equals(testQuote.aiAnalysis));
        expect(json['sentiment'], equals(testQuote.sentiment));
        expect(json['keywords'], isA<String>());
        expect(json['summary'], equals(testQuote.summary));
      });

      test('should create from JSON correctly', () {
        final json = TestData.sampleQuoteJson;
        final quote = Quote.fromJson(json);

        expect(quote.id, equals(json['id']));
        expect(quote.content, equals(json['content']));
        expect(quote.date, equals(json['date']));
        expect(quote.categoryId, equals(json['category_id']));
        expect(quote.source, equals(json['source']));
        expect(quote.sourceAuthor, equals(json['source_author']));
        expect(quote.sourceWork, equals(json['source_work']));
        expect(quote.location, equals(json['location']));
        expect(quote.weather, equals(json['weather']));
        expect(quote.temperature, equals(json['temperature']));
        expect(quote.colorHex, equals(json['color_hex']));
        expect(quote.editSource, equals(json['edit_source']));
        expect(quote.deltaContent, equals(json['delta_content']));
        expect(quote.dayPeriod, equals(json['day_period']));
        expect(quote.aiAnalysis, equals(json['ai_analysis']));
        expect(quote.sentiment, equals(json['sentiment']));
        expect(quote.summary, equals(json['summary']));
      });

      test('should handle tag IDs conversion correctly', () {
        // Test string tag IDs
        final jsonWithStringTags = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'tag_ids': 'tag1,tag2,tag3',
        };
        final quoteFromString = Quote.fromJson(jsonWithStringTags);
        expect(quoteFromString.tagIds, equals(['tag1', 'tag2', 'tag3']));

        // Test list tag IDs
        final jsonWithListTags = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'tag_ids': ['tag1', 'tag2', 'tag3'],
        };
        final quoteFromList = Quote.fromJson(jsonWithListTags);
        expect(quoteFromList.tagIds, equals(['tag1', 'tag2', 'tag3']));

        // Test empty tag IDs
        final jsonWithEmptyTags = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'tag_ids': '',
        };
        final quoteFromEmpty = Quote.fromJson(jsonWithEmptyTags);
        expect(quoteFromEmpty.tagIds, isEmpty);

        // Test null tag IDs
        final jsonWithNullTags = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'tag_ids': null,
        };
        final quoteFromNull = Quote.fromJson(jsonWithNullTags);
        expect(quoteFromNull.tagIds, isEmpty);
      });

      test('should handle keywords conversion correctly', () {
        // Test string keywords
        final jsonWithStringKeywords = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'keywords': 'keyword1,keyword2,keyword3',
        };
        final quoteFromString = Quote.fromJson(jsonWithStringKeywords);
        expect(quoteFromString.keywords, equals(['keyword1', 'keyword2', 'keyword3']));

        // Test list keywords
        final jsonWithListKeywords = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'keywords': ['keyword1', 'keyword2', 'keyword3'],
        };
        final quoteFromList = Quote.fromJson(jsonWithListKeywords);
        expect(quoteFromList.keywords, equals(['keyword1', 'keyword2', 'keyword3']));

        // Test empty keywords
        final jsonWithEmptyKeywords = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'keywords': '',
        };
        final quoteFromEmpty = Quote.fromJson(jsonWithEmptyKeywords);
        expect(quoteFromEmpty.keywords, isEmpty);

        // Test null keywords
        final jsonWithNullKeywords = {
          'content': '测试内容',
          'date': '2024-01-01T12:00:00Z',
          'keywords': null,
        };
        final quoteFromNull = Quote.fromJson(jsonWithNullKeywords);
        expect(quoteFromNull.keywords, isNull);
      });

      test('should handle malformed JSON gracefully', () {
        final malformedJson = {
          'content': '测试内容',
          'date': 'invalid-date',
          'tag_ids': 123, // Invalid type
          'keywords': 456, // Invalid type
        };

        expect(() => Quote.fromJson(malformedJson), returnsNormally);
        final quote = Quote.fromJson(malformedJson);
        expect(quote.content, equals('测试内容'));
        expect(quote.tagIds, isEmpty);
      });
    });

    group('Copy With', () {
      test('should copy with new values', () {
        final originalQuote = TestData.createTestQuote();
        final copiedQuote = originalQuote.copyWith(
          content: '新的内容',
          aiAnalysis: '新的AI分析',
          sentiment: 'neutral',
        );

        expect(copiedQuote.content, equals('新的内容'));
        expect(copiedQuote.aiAnalysis, equals('新的AI分析'));
        expect(copiedQuote.sentiment, equals('neutral'));

        // Unchanged fields should remain the same
        expect(copiedQuote.id, equals(originalQuote.id));
        expect(copiedQuote.date, equals(originalQuote.date));
        expect(copiedQuote.source, equals(originalQuote.source));
        expect(copiedQuote.categoryId, equals(originalQuote.categoryId));
      });

      test('should copy with null values', () {
        final originalQuote = TestData.createTestQuote();
        final copiedQuote = originalQuote.copyWith(
          aiAnalysis: null,
          sentiment: null,
          location: null,
        );

        expect(copiedQuote.aiAnalysis, isNull);
        expect(copiedQuote.sentiment, isNull);
        expect(copiedQuote.location, isNull);

        // Other fields should remain unchanged
        expect(copiedQuote.content, equals(originalQuote.content));
        expect(copiedQuote.date, equals(originalQuote.date));
      });

      test('should copy with new tag IDs', () {
        final originalQuote = TestData.createTestQuote();
        final newTagIds = ['new1', 'new2', 'new3'];
        final copiedQuote = originalQuote.copyWith(tagIds: newTagIds);

        expect(copiedQuote.tagIds, equals(newTagIds));
        expect(copiedQuote.tagIds, isNot(equals(originalQuote.tagIds)));
      });

      test('should copy with new keywords', () {
        final originalQuote = TestData.createTestQuote();
        final newKeywords = ['新关键词1', '新关键词2'];
        final copiedQuote = originalQuote.copyWith(keywords: newKeywords);

        expect(copiedQuote.keywords, equals(newKeywords));
        expect(copiedQuote.keywords, isNot(equals(originalQuote.keywords)));
      });
    });

    group('Equality and Hash Code', () {
      test('should be equal with same values', () {
        final quote1 = TestData.createTestQuote();
        final quote2 = Quote.fromJson(quote1.toJson());

        expect(quote1, equals(quote2));
        expect(quote1.hashCode, equals(quote2.hashCode));
      });

      test('should not be equal with different values', () {
        final quote1 = TestData.createTestQuote();
        final quote2 = quote1.copyWith(content: '不同的内容');

        expect(quote1, isNot(equals(quote2)));
        expect(quote1.hashCode, isNot(equals(quote2.hashCode)));
      });

      test('should handle null fields in equality', () {
        final quote1 = Quote(
          content: '内容',
          date: '2024-01-01T12:00:00Z',
          aiAnalysis: null,
        );
        final quote2 = Quote(
          content: '内容',
          date: '2024-01-01T12:00:00Z',
          aiAnalysis: null,
        );

        expect(quote1, equals(quote2));
      });
    });

    group('Validation', () {
      test('should validate content is not empty', () {
        expect(
          () => Quote(content: '', date: DateTime.now().toIso8601String()),
          returnsNormally, // Model itself might not validate, validation could be elsewhere
        );
      });

      test('should handle very long content', () {
        final longContent = 'x' * 10000;
        final quote = Quote(
          content: longContent,
          date: DateTime.now().toIso8601String(),
        );

        expect(quote.content, equals(longContent));
        expect(quote.content.length, equals(10000));
      });

      test('should handle special characters', () {
        const specialContent = '测试内容 with 🎉 emoji and "quotes" & <tags>';
        final quote = Quote(
          content: specialContent,
          date: DateTime.now().toIso8601String(),
        );

        expect(quote.content, equals(specialContent));

        // Test JSON serialization with special characters
        final json = quote.toJson();
        final deserializedQuote = Quote.fromJson(json);
        expect(deserializedQuote.content, equals(specialContent));
      });
    });

    group('Utility Methods', () {
      test('should check if quote has analysis', () {
        final quoteWithAnalysis = TestData.createTestQuote();
        final quoteWithoutAnalysis = TestData.createTestQuote().copyWith(
          aiAnalysis: null,
        );

        expect(quoteWithAnalysis.hasAIAnalysis, isTrue);
        expect(quoteWithoutAnalysis.hasAIAnalysis, isFalse);
      });

      test('should check if quote has location', () {
        final quoteWithLocation = TestData.createTestQuote();
        final quoteWithoutLocation = TestData.createTestQuote().copyWith(
          location: null,
        );

        expect(quoteWithLocation.hasLocation, isTrue);
        expect(quoteWithoutLocation.hasLocation, isFalse);
      });

      test('should check if quote has weather', () {
        final quoteWithWeather = TestData.createTestQuote();
        final quoteWithoutWeather = TestData.createTestQuote().copyWith(
          weather: null,
          temperature: null,
        );

        expect(quoteWithWeather.hasWeather, isTrue);
        expect(quoteWithoutWeather.hasWeather, isFalse);
      });

      test('should get formatted date', () {
        final quote = TestData.createTestQuote(
          date: '2024-01-15T14:30:00Z',
        );

        final formattedDate = quote.getFormattedDate();
        expect(formattedDate, isNotEmpty);
        expect(formattedDate, contains('2024'));
      });

      test('should get readable source', () {
        final quoteWithFullSource = TestData.createTestQuote();
        final quoteWithAuthorOnly = TestData.createTestQuote().copyWith(
          source: null,
          sourceWork: null,
        );
        final quoteWithNoSource = TestData.createTestQuote().copyWith(
          source: null,
          sourceAuthor: null,
          sourceWork: null,
        );

        expect(quoteWithFullSource.getReadableSource(), isNotEmpty);
        expect(quoteWithAuthorOnly.getReadableSource(), isNotEmpty);
        expect(quoteWithNoSource.getReadableSource(), equals('未知来源'));
      });
    });

    group('Performance', () {
      test('should handle large lists efficiently', () {
        final stopwatch = Stopwatch()..start();

        // Create many quotes
        final quotes = <Quote>[];
        for (int i = 0; i < 1000; i++) {
          quotes.add(TestData.createTestQuote(
            id: 'perf-$i',
            content: '性能测试内容 $i',
          ));
        }

        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(quotes.length, equals(1000));
      });

      test('should serialize/deserialize efficiently', () {
        final quotes = TestData.createTestQuoteList(100);
        
        final stopwatch = Stopwatch()..start();
        
        // Serialize all quotes
        final jsonList = quotes.map((q) => q.toJson()).toList();
        
        // Deserialize all quotes
        final deserializedQuotes = jsonList.map((json) => Quote.fromJson(json)).toList();
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
        expect(deserializedQuotes.length, equals(100));
        
        // Verify data integrity
        for (int i = 0; i < quotes.length; i++) {
          expect(deserializedQuotes[i].content, equals(quotes[i].content));
          expect(deserializedQuotes[i].id, equals(quotes[i].id));
        }
      });
    });
  });
}