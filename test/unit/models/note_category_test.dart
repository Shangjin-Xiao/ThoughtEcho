/// Unit tests for NoteCategory model
import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtecho/models/note_category.dart';
import '../test_utils/test_data.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('NoteCategory Model Tests', () {
    group('Construction', () {
      test('should create category with required fields', () {
        final category = NoteCategory(
          id: 'test-id',
          name: '测试分类',
        );

        expect(category.id, equals('test-id'));
        expect(category.name, equals('测试分类'));
        expect(category.iconName, isNull);
        expect(category.isDefault, isFalse);
      });

      test('should create category with all fields', () {
        final category = TestData.createTestCategory();

        expect(category.id, isNotNull);
        expect(category.name, isNotEmpty);
        expect(category.iconName, isNotNull);
        expect(category.isDefault, isA<bool>());
      });

      test('should handle optional fields', () {
        final category = NoteCategory(
          id: 'test-id',
          name: '测试分类',
          iconName: 'test-icon',
          isDefault: true,
        );

        expect(category.iconName, equals('test-icon'));
        expect(category.isDefault, isTrue);
      });

      test('should handle null optional fields', () {
        final category = NoteCategory(
          id: 'test-id',
          name: '测试分类',
          iconName: null,
          isDefault: false,
        );

        expect(category.iconName, isNull);
        expect(category.isDefault, isFalse);
      });
    });

    group('JSON Serialization', () {
      test('should convert to JSON correctly', () {
        final category = TestData.createTestCategory();
        final json = category.toJson();

        expect(json, isA<Map<String, dynamic>>());
        expect(json['id'], equals(category.id));
        expect(json['name'], equals(category.name));
        expect(json['icon_name'], equals(category.iconName));
        expect(json['is_default'], equals(category.isDefault));
      });

      test('should create from JSON correctly', () {
        final json = {
          'id': 'json-test-id',
          'name': 'JSON测试分类',
          'icon_name': 'json_icon',
          'is_default': true,
        };

        final category = NoteCategory.fromJson(json);

        expect(category.id, equals('json-test-id'));
        expect(category.name, equals('JSON测试分类'));
        expect(category.iconName, equals('json_icon'));
        expect(category.isDefault, isTrue);
      });

      test('should handle missing optional fields in JSON', () {
        final json = {
          'id': 'minimal-id',
          'name': '最小分类',
        };

        final category = NoteCategory.fromJson(json);

        expect(category.id, equals('minimal-id'));
        expect(category.name, equals('最小分类'));
        expect(category.iconName, isNull);
        expect(category.isDefault, isFalse);
      });

      test('should handle null values in JSON', () {
        final json = {
          'id': 'null-test',
          'name': '空值测试',
          'icon_name': null,
          'is_default': null,
        };

        final category = NoteCategory.fromJson(json);

        expect(category.id, equals('null-test'));
        expect(category.name, equals('空值测试'));
        expect(category.iconName, isNull);
        expect(category.isDefault, isFalse); // Should default to false
      });

      test('should handle boolean conversion in JSON', () {
        final jsonWithStringBoolean = {
          'id': 'bool-test',
          'name': '布尔测试',
          'is_default': 'true', // String instead of boolean
        };

        final jsonWithIntBoolean = {
          'id': 'bool-test-2',
          'name': '布尔测试2',
          'is_default': 1, // Integer instead of boolean
        };

        final category1 = NoteCategory.fromJson(jsonWithStringBoolean);
        final category2 = NoteCategory.fromJson(jsonWithIntBoolean);

        // Should handle gracefully (might depend on implementation)
        expect(category1, isNotNull);
        expect(category2, isNotNull);
      });
    });

    group('Copy With', () {
      test('should copy with new values', () {
        final originalCategory = TestData.createTestCategory();
        final copiedCategory = originalCategory.copyWith(
          name: '新分类名',
          iconName: '新图标',
          isDefault: true,
        );

        expect(copiedCategory.name, equals('新分类名'));
        expect(copiedCategory.iconName, equals('新图标'));
        expect(copiedCategory.isDefault, isTrue);

        // Unchanged field should remain the same
        expect(copiedCategory.id, equals(originalCategory.id));
      });

      test('should copy with null values', () {
        final originalCategory = TestData.createTestCategory();
        final copiedCategory = originalCategory.copyWith(
          iconName: null,
          isDefault: false,
        );

        expect(copiedCategory.iconName, isNull);
        expect(copiedCategory.isDefault, isFalse);

        // Other fields should remain unchanged
        expect(copiedCategory.id, equals(originalCategory.id));
        expect(copiedCategory.name, equals(originalCategory.name));
      });

      test('should copy without changes', () {
        final originalCategory = TestData.createTestCategory();
        final copiedCategory = originalCategory.copyWith();

        expect(copiedCategory.id, equals(originalCategory.id));
        expect(copiedCategory.name, equals(originalCategory.name));
        expect(copiedCategory.iconName, equals(originalCategory.iconName));
        expect(copiedCategory.isDefault, equals(originalCategory.isDefault));
      });
    });

    group('Equality and Hash Code', () {
      test('should be equal with same values', () {
        final category1 = TestData.createTestCategory();
        final category2 = NoteCategory.fromJson(category1.toJson());

        expect(category1, equals(category2));
        expect(category1.hashCode, equals(category2.hashCode));
      });

      test('should not be equal with different values', () {
        final category1 = TestData.createTestCategory();
        final category2 = category1.copyWith(name: '不同的名称');

        expect(category1, isNot(equals(category2)));
        expect(category1.hashCode, isNot(equals(category2.hashCode)));
      });

      test('should handle equality with null fields', () {
        final category1 = NoteCategory(
          id: 'test',
          name: '测试',
          iconName: null,
        );
        final category2 = NoteCategory(
          id: 'test',
          name: '测试',
          iconName: null,
        );

        expect(category1, equals(category2));
        expect(category1.hashCode, equals(category2.hashCode));
      });

      test('should not be equal with different null status', () {
        final category1 = NoteCategory(
          id: 'test',
          name: '测试',
          iconName: null,
        );
        final category2 = NoteCategory(
          id: 'test',
          name: '测试',
          iconName: 'icon',
        );

        expect(category1, isNot(equals(category2)));
      });
    });

    group('Validation', () {
      test('should validate required fields', () {
        expect(
          () => NoteCategory(id: '', name: ''),
          returnsNormally, // Model itself might not validate
        );
      });

      test('should handle very long names', () {
        final longName = 'x' * 1000;
        final category = NoteCategory(
          id: 'long-name-test',
          name: longName,
        );

        expect(category.name, equals(longName));
        expect(category.name.length, equals(1000));
      });

      test('should handle special characters in name', () {
        const specialName = '特殊分类 🎉 with "quotes" & <tags>';
        final category = NoteCategory(
          id: 'special-test',
          name: specialName,
        );

        expect(category.name, equals(specialName));

        // Test JSON serialization with special characters
        final json = category.toJson();
        final deserializedCategory = NoteCategory.fromJson(json);
        expect(deserializedCategory.name, equals(specialName));
      });

      test('should handle special characters in icon name', () {
        const specialIcon = 'icon-with-special_chars.123';
        final category = NoteCategory(
          id: 'icon-test',
          name: '图标测试',
          iconName: specialIcon,
        );

        expect(category.iconName, equals(specialIcon));
      });
    });

    group('Utility Methods', () {
      test('should check if category is default', () {
        final defaultCategory = TestData.createTestCategory(isDefault: true);
        final normalCategory = TestData.createTestCategory(isDefault: false);

        expect(defaultCategory.isDefault, isTrue);
        expect(normalCategory.isDefault, isFalse);
      });

      test('should check if category has icon', () {
        final categoryWithIcon = TestData.createTestCategory(iconName: 'test_icon');
        final categoryWithoutIcon = TestData.createTestCategory(iconName: null);

        expect(categoryWithIcon.hasIcon, isTrue);
        expect(categoryWithoutIcon.hasIcon, isFalse);
      });

      test('should get display name', () {
        final category = TestData.createTestCategory(name: '测试分类');
        
        expect(category.getDisplayName(), equals('测试分类'));
      });

      test('should get icon or default', () {
        final categoryWithIcon = TestData.createTestCategory(iconName: 'custom_icon');
        final categoryWithoutIcon = TestData.createTestCategory(iconName: null);

        expect(categoryWithIcon.getIconOrDefault(), equals('custom_icon'));
        expect(categoryWithoutIcon.getIconOrDefault(), equals('folder')); // Default icon
      });
    });

    group('Default Categories', () {
      test('should create default categories correctly', () {
        final defaultCategories = [
          NoteCategory.createDefault('动画', 'animation', true),
          NoteCategory.createDefault('漫画', 'comic', false),
          NoteCategory.createDefault('游戏', 'game', false),
        ];

        for (final category in defaultCategories) {
          expect(category.id, TestHelpers.isValidId());
          expect(category.name, isNotEmpty);
          expect(category.iconName, isNotNull);
        }

        expect(defaultCategories.first.isDefault, isTrue);
        expect(defaultCategories[1].isDefault, isFalse);
      });

      test('should have consistent default category IDs', () {
        final category1 = NoteCategory.createDefault('测试', 'test', false);
        final category2 = NoteCategory.createDefault('测试', 'test', false);

        // Should generate different IDs for different instances
        expect(category1.id, isNot(equals(category2.id)));
      });
    });

    group('Comparison and Sorting', () {
      test('should sort categories alphabetically', () {
        final categories = [
          NoteCategory(id: '1', name: '游戏'),
          NoteCategory(id: '2', name: '动画'),
          NoteCategory(id: '3', name: '漫画'),
        ];

        categories.sort((a, b) => a.name.compareTo(b.name));

        expect(categories[0].name, equals('动画'));
        expect(categories[1].name, equals('漫画'));
        expect(categories[2].name, equals('游戏'));
      });

      test('should sort with default categories first', () {
        final categories = [
          NoteCategory(id: '1', name: '自定义1', isDefault: false),
          NoteCategory(id: '2', name: '默认1', isDefault: true),
          NoteCategory(id: '3', name: '自定义2', isDefault: false),
          NoteCategory(id: '4', name: '默认2', isDefault: true),
        ];

        categories.sort((a, b) {
          if (a.isDefault && !b.isDefault) return -1;
          if (!a.isDefault && b.isDefault) return 1;
          return a.name.compareTo(b.name);
        });

        expect(categories[0].isDefault, isTrue);
        expect(categories[1].isDefault, isTrue);
        expect(categories[2].isDefault, isFalse);
        expect(categories[3].isDefault, isFalse);
      });
    });

    group('Performance', () {
      test('should handle large numbers of categories efficiently', () {
        final stopwatch = Stopwatch()..start();

        final categories = <NoteCategory>[];
        for (int i = 0; i < 1000; i++) {
          categories.add(NoteCategory(
            id: 'perf-$i',
            name: '性能测试分类 $i',
            iconName: 'icon_$i',
            isDefault: i % 10 == 0,
          ));
        }

        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(categories.length, equals(1000));
      });

      test('should serialize/deserialize efficiently', () {
        final categories = TestData.createTestCategoryList();
        
        final stopwatch = Stopwatch()..start();
        
        // Serialize all categories
        final jsonList = categories.map((c) => c.toJson()).toList();
        
        // Deserialize all categories
        final deserializedCategories = jsonList.map((json) => NoteCategory.fromJson(json)).toList();
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
        expect(deserializedCategories.length, equals(categories.length));
        
        // Verify data integrity
        for (int i = 0; i < categories.length; i++) {
          expect(deserializedCategories[i].name, equals(categories[i].name));
          expect(deserializedCategories[i].id, equals(categories[i].id));
        }
      });
    });

    group('Edge Cases', () {
      test('should handle empty strings gracefully', () {
        final category = NoteCategory(
          id: '',
          name: '',
          iconName: '',
        );

        expect(category.id, isEmpty);
        expect(category.name, isEmpty);
        expect(category.iconName, isEmpty);

        // Should still serialize/deserialize
        final json = category.toJson();
        final deserialized = NoteCategory.fromJson(json);
        expect(deserialized.name, isEmpty);
      });

      test('should handle unicode characters', () {
        final category = NoteCategory(
          id: 'unicode-test',
          name: '测试分类 🎯 Категория тест',
          iconName: 'unicode_icon_🔥',
        );

        expect(category.name, contains('测试分类'));
        expect(category.name, contains('🎯'));
        expect(category.name, contains('Категория'));
        expect(category.iconName, contains('🔥'));

        // Test serialization with unicode
        final json = category.toJson();
        final deserialized = NoteCategory.fromJson(json);
        expect(deserialized.name, equals(category.name));
        expect(deserialized.iconName, equals(category.iconName));
      });

      test('should handle malformed JSON gracefully', () {
        final malformedJson = {
          'id': 123, // Wrong type
          'name': null, // Required field is null
          'icon_name': ['array', 'instead', 'of', 'string'], // Wrong type
          'is_default': 'maybe', // Invalid boolean
        };

        expect(() => NoteCategory.fromJson(malformedJson), returnsNormally);
        
        final category = NoteCategory.fromJson(malformedJson);
        expect(category, isNotNull);
      });
    });

    group('Integration with Test Data', () {
      test('should work with test data factory', () {
        final testCategory = TestData.createTestCategory();
        
        expect(testCategory.id, TestHelpers.isValidId());
        expect(testCategory.name, isNotEmpty);
        expect(testCategory.iconName, isNotNull);
        expect(testCategory.isDefault, isA<bool>());
      });

      test('should work with test category list', () {
        final categories = TestData.createTestCategoryList();
        
        expect(categories, isNotEmpty);
        expect(categories.every((c) => c.name.isNotEmpty), isTrue);
        expect(categories.every((c) => c.id.isNotEmpty), isTrue);
      });
    });
  });
}