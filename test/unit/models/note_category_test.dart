/// Unit tests for NoteCategory model
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_category.dart';

void main() {
  group('NoteCategory Model Tests', () {
    test('should create category with required fields', () {
      final category = NoteCategory(id: 'test-id', name: '测试分类');

      expect(category.id, equals('test-id'));
      expect(category.name, equals('测试分类'));
      expect(category.isDefault, isFalse);
      expect(category.iconName, isNull);
    });

    test('should create category with all fields', () {
      final category = NoteCategory(
        id: 'test-id',
        name: '测试分类',
        isDefault: true,
        iconName: 'category_icon',
      );

      expect(category.id, equals('test-id'));
      expect(category.name, equals('测试分类'));
      expect(category.isDefault, isTrue);
      expect(category.iconName, equals('category_icon'));
    });

    test('should check equality correctly', () {
      final category1 = NoteCategory(id: 'test-id', name: '测试分类');

      final category2 = NoteCategory(id: 'test-id', name: '测试分类');

      expect(category1 == category2, isTrue);
      expect(category1.hashCode, equals(category2.hashCode));
    });

    test('should handle different categories', () {
      final category1 = NoteCategory(id: 'test-id-1', name: '分类1');

      final category2 = NoteCategory(id: 'test-id-2', name: '分类2');

      expect(category1 == category2, isFalse);
    });
  });
}
