library;

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
}
