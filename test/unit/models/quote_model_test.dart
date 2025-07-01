/// Unit tests for Quote model
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

void main() {
  group('Quote Model Tests', () {
    test('should create quote with required fields', () {
      final quote = Quote(
        content: '测试内容',
        date: DateTime.now().toIso8601String(),
      );

      expect(quote.content, equals('测试内容'));
      expect(quote.date, isNotEmpty);
      expect(quote.tagIds, isEmpty);
    });

    test('should create quote with all fields', () {
      final quote = Quote(
        id: 'test-id',
        content: '测试内容带所有字段',
        date: DateTime.now().toIso8601String(),
        categoryId: 'test-category',
        tagIds: ['tag1', 'tag2'],
        location: '北京市',
        weather: '晴天',
        temperature: '25°C',
      );

      expect(quote.id, equals('test-id'));
      expect(quote.content, equals('测试内容带所有字段'));
      expect(quote.categoryId, equals('test-category'));
      expect(quote.tagIds, hasLength(2));
      expect(quote.location, equals('北京市'));
      expect(quote.weather, equals('晴天'));
      expect(quote.temperature, equals('25°C'));
    });

    test('should convert to JSON correctly', () {
      const quote = Quote(
        id: 'test-id',
        content: '测试内容',
        date: '2024-01-01T00:00:00.000Z',
        categoryId: 'test-category',
        tagIds: ['tag1'],
      );

      final json = quote.toJson();
      expect(json['id'], equals('test-id'));
      expect(json['content'], equals('测试内容'));
      expect(json['date'], equals('2024-01-01T00:00:00.000Z'));
      expect(json['category_id'], equals('test-category'));
      expect(json['tag_ids'], equals('tag1'));
    });

    test('should create from JSON correctly', () {
      final json = {
        'id': 'test-id',
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'category_id': 'test-category',
        'tag_ids': 'tag1,tag2',
      };

      final quote = Quote.fromJson(json);
      expect(quote.id, equals('test-id'));
      expect(quote.content, equals('测试内容'));
      expect(quote.date, equals('2024-01-01T00:00:00.000Z'));
      expect(quote.categoryId, equals('test-category'));
      expect(quote.tagIds, equals(['tag1', 'tag2']));
    });
  });
}