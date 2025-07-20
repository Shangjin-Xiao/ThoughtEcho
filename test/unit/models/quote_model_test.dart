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
      // tag_ids字段在toJson中被移除，因为使用关联表管理
      expect(json.containsKey('tag_ids'), isFalse);
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

    test('should validate data correctly', () {
      // 测试有效数据
      expect(Quote.isValidContent('有效内容'), isTrue);
      expect(Quote.isValidDate('2024-01-01T00:00:00.000Z'), isTrue);
      expect(Quote.isValidColorHex('#FF0000'), isTrue);
      expect(Quote.isValidColorHex(null), isTrue);

      // 测试无效数据
      expect(Quote.isValidContent(''), isFalse);
      expect(Quote.isValidContent('a' * 10001), isFalse);
      expect(Quote.isValidDate('invalid-date'), isFalse);
      expect(Quote.isValidColorHex('invalid-color'), isFalse);
      expect(Quote.isValidColorHex('#ZZ0000'), isFalse);
    });

    test('should handle edge cases in fromJson', () {
      // 测试空tag_ids
      final json1 = {
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'tag_ids': '',
      };
      final quote1 = Quote.fromJson(json1);
      expect(quote1.tagIds, isEmpty);

      // 测试null keywords
      final json2 = {
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'keywords': null,
      };
      final quote2 = Quote.fromJson(json2);
      expect(quote2.keywords, isNull);

      // 测试数组格式的tag_ids
      final json3 = {
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'tag_ids': ['tag1', 'tag2'],
      };
      final quote3 = Quote.fromJson(json3);
      expect(quote3.tagIds, equals(['tag1', 'tag2']));
    });

    test('should throw error for invalid JSON', () {
      // 测试缺少必填字段
      expect(() => Quote.fromJson({}), throwsA(isA<ArgumentError>()));
      expect(() => Quote.fromJson({'content': ''}), throwsA(isA<ArgumentError>()));
      expect(() => Quote.fromJson({'content': '测试', 'date': ''}), throwsA(isA<ArgumentError>()));

      // 测试无效日期格式
      expect(() => Quote.fromJson({
        'content': '测试内容',
        'date': 'invalid-date',
      }), throwsA(isA<ArgumentError>()));

      // 测试无效颜色格式
      expect(() => Quote.fromJson({
        'content': '测试内容',
        'date': '2024-01-01T00:00:00.000Z',
        'color_hex': 'invalid-color',
      }), throwsA(isA<ArgumentError>()));
    });
  });
}
