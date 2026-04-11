import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/app_settings.dart';

import '../../test_setup.dart';

void main() {
  setUpAll(() async {
    await TestSetup.setupUnitTest();
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
  });
}
