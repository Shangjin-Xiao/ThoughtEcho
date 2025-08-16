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

    test('should convert to and from map correctly', () {
      final category = NoteCategory(
        id: 'test-id',
        name: '测试分类',
        isDefault: true,
        iconName: 'test_icon',
      );

      final map = category.toMap();
      expect(map['id'], equals('test-id'));
      expect(map['name'], equals('测试分类'));
      expect(map['is_default'], equals(1));
      expect(map['icon_name'], equals('test_icon'));

      final categoryFromMap = NoteCategory.fromMap(map);
      expect(categoryFromMap.id, equals('test-id'));
      expect(categoryFromMap.name, equals('测试分类'));
      expect(categoryFromMap.isDefault, isTrue);
      expect(categoryFromMap.iconName, equals('test_icon'));
    });

    test('should validate data correctly', () {
      // 测试有效数据
      expect(NoteCategory.isValidId('valid-id'), isTrue);
      expect(NoteCategory.isValidName('有效名称'), isTrue);
      expect(NoteCategory.isValidName('a' * 50), isTrue);

      // 测试无效数据
      expect(NoteCategory.isValidId(''), isFalse);
      expect(NoteCategory.isValidId('   '), isFalse);
      expect(NoteCategory.isValidName(''), isFalse);
      expect(NoteCategory.isValidName('   '), isFalse);
      expect(NoteCategory.isValidName('a' * 51), isFalse);
    });

    test('should create validated instance', () {
      // 测试有效数据
      final category = NoteCategory.validated(
        id: 'test-id',
        name: '测试分类',
        isDefault: true,
        iconName: 'test_icon',
      );
      expect(category.id, equals('test-id'));
      expect(category.name, equals('测试分类'));

      // 测试无效数据
      expect(() => NoteCategory.validated(id: '', name: '测试'),
          throwsA(isA<ArgumentError>()));
      expect(() => NoteCategory.validated(id: 'test', name: ''),
          throwsA(isA<ArgumentError>()));
      expect(() => NoteCategory.validated(id: 'test', name: 'a' * 51),
          throwsA(isA<ArgumentError>()));
    });

    test('should handle edge cases in fromMap', () {
      // 测试缺少必填字段
      expect(() => NoteCategory.fromMap({}), throwsA(isA<ArgumentError>()));
      expect(() => NoteCategory.fromMap({'id': ''}),
          throwsA(isA<ArgumentError>()));
      expect(() => NoteCategory.fromMap({'id': 'test', 'name': ''}),
          throwsA(isA<ArgumentError>()));

      // 测试不同的is_default值
      final map1 = {'id': 'test', 'name': '测试', 'is_default': 1};
      final category1 = NoteCategory.fromMap(map1);
      expect(category1.isDefault, isTrue);

      final map2 = {'id': 'test', 'name': '测试', 'is_default': true};
      final category2 = NoteCategory.fromMap(map2);
      expect(category2.isDefault, isTrue);

      final map3 = {'id': 'test', 'name': '测试', 'is_default': 0};
      final category3 = NoteCategory.fromMap(map3);
      expect(category3.isDefault, isFalse);
    });

    test('should support copyWith', () {
      final original = NoteCategory(
        id: 'test-id',
        name: '原始名称',
        isDefault: false,
        iconName: 'original_icon',
      );

      final copied = original.copyWith(name: '新名称', isDefault: true);
      expect(copied.id, equals('test-id'));
      expect(copied.name, equals('新名称'));
      expect(copied.isDefault, isTrue);
      expect(copied.iconName, equals('original_icon'));
    });
  });
}
