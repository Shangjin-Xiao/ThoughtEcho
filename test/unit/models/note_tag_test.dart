/// Unit tests for NoteTag model
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_tag.dart';

void main() {
  group('NoteTag Model Tests', () {
    test('should create tag with required fields', () {
      final tag = NoteTag(id: 'test-tag-id', name: '测试标签');

      expect(tag.id, equals('test-tag-id'));
      expect(tag.name, equals('测试标签'));
      expect(tag.isDefault, isFalse);
      expect(tag.iconName, isNull);
    });

    test('should create tag with all fields', () {
      final tag = NoteTag(
        id: 'test-tag-id',
        name: '测试标签',
        isDefault: true,
        iconName: 'tag_icon',
      );

      expect(tag.id, equals('test-tag-id'));
      expect(tag.name, equals('测试标签'));
      expect(tag.isDefault, isTrue);
      expect(tag.iconName, equals('tag_icon'));
    });

    test('should check equality correctly based on id', () {
      final tag1 = NoteTag(id: 'same-id', name: '标签1');
      final tag2 = NoteTag(id: 'same-id', name: '标签2');
      final tag3 = NoteTag(id: 'different-id', name: '标签1');

      expect(tag1 == tag2, isTrue);
      expect(tag1.hashCode, equals(tag2.hashCode));
      expect(tag1 == tag3, isFalse);
    });

    test('should convert to and from map correctly', () {
      final tag = NoteTag(
        id: 'test-id',
        name: '测试标签',
        isDefault: true,
        iconName: 'test_icon',
      );

      final map = tag.toMap();
      expect(map['id'], equals('test-id'));
      expect(map['name'], equals('测试标签'));
      expect(map['is_default'], equals(1));
      expect(map['icon_name'], equals('test_icon'));

      final tagFromMap = NoteTag.fromMap(map);
      expect(tagFromMap.id, equals('test-id'));
      expect(tagFromMap.name, equals('测试标签'));
      expect(tagFromMap.isDefault, isTrue);
      expect(tagFromMap.iconName, equals('test_icon'));
    });

    test('should handle boolean is_default in fromMap', () {
      final map = {
        'id': 'test-id',
        'name': '测试标签',
        'is_default': true,
      };
      final tag = NoteTag.fromMap(map);
      expect(tag.isDefault, isTrue);
    });

    test('should throw ArgumentError in fromMap when id or name is missing', () {
      expect(() => NoteTag.fromMap({'name': '测试'}), throwsA(isA<ArgumentError>()));
      expect(() => NoteTag.fromMap({'id': 'test'}), throwsA(isA<ArgumentError>()));
      expect(() => NoteTag.fromMap({'id': '', 'name': '测试'}), throwsA(isA<ArgumentError>()));
      expect(() => NoteTag.fromMap({'id': 'test', 'name': ''}), throwsA(isA<ArgumentError>()));
    });

    test('should support copyWith', () {
      final original = NoteTag(
        id: 'old-id',
        name: '旧名称',
        isDefault: false,
        iconName: 'old_icon',
      );

      final copied = original.copyWith(name: '新名称', isDefault: true);

      expect(copied.id, equals('old-id'));
      expect(copied.name, equals('新名称'));
      expect(copied.isDefault, isTrue);
      expect(copied.iconName, equals('old_icon'));
    });

    test('toString should contain key properties', () {
      final tag = NoteTag(id: 'test-id', name: '测试标签');
      final str = tag.toString();

      expect(str, contains('test-id'));
      expect(str, contains('测试标签'));
    });
  });
}
