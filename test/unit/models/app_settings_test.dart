import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/app_settings.dart';

import '../../test_setup.dart';

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });

  group('AppSettings Tests', () {
    test('should default trash retention to 30 days', () {
      final settings = AppSettings.defaultSettings();

      expect(settings.trashRetentionDays, equals(30));
      expect(settings.trashRetentionLastModified, isNull);
    });

    test('fromJson should normalize invalid trash retention values', () {
      final settings = AppSettings.fromJson({
        'trashRetentionDays': 15,
      });

      expect(settings.trashRetentionDays, equals(30));
    });

    test('copyWith should update trash retention fields', () {
      final settings = AppSettings.defaultSettings();

      final updated = settings.copyWith(
        trashRetentionDays: 90,
        trashRetentionLastModified: '2026-03-28T10:00:00.000Z',
      );

      expect(updated.trashRetentionDays, equals(90));
      expect(
        updated.trashRetentionLastModified,
        equals('2026-03-28T10:00:00.000Z'),
      );
    });
  });

  group('AppSettings.fromJson list deserialization', () {
    test('filters non-string items from persisted list fields', () {
      final settings = AppSettings.fromJson({
        'apiNinjasCategories': ['wisdom', 1, null, 'success'],
        'defaultTagIds': ['tag-1', 2, null, 'tag-2'],
      });

      expect(settings.apiNinjasCategories, ['wisdom', 'success']);
      expect(settings.defaultTagIds, ['tag-1', 'tag-2']);
    });

    test('handles non-list persisted values as empty list', () {
      final settings = AppSettings.fromJson({
        'apiNinjasCategories': 'wisdom,success',
        'defaultTagIds': {'a': 1},
      });

      expect(settings.apiNinjasCategories, isEmpty);
      expect(settings.defaultTagIds, isEmpty);
    });

    test('falls back to default provider when persisted provider is non-string',
        () {
      final settings = AppSettings.fromJson({
        'dailyQuoteProvider': 42,
      });

      expect(settings.dailyQuoteProvider, 'hitokoto');
    });

    test(
        'falls back to default provider when persisted provider is unsupported',
        () {
      final settings = AppSettings.fromJson({
        'dailyQuoteProvider': 'unknown_provider',
      });

      expect(settings.dailyQuoteProvider, 'hitokoto');
    });

    test('filters unsupported api ninjas categories in persisted settings', () {
      final settings = AppSettings.fromJson({
        'apiNinjasCategories': ['wisdom', 'retired', 'success', 'invalid'],
      });

      expect(settings.apiNinjasCategories, ['wisdom', 'success']);
    });
  });
}
