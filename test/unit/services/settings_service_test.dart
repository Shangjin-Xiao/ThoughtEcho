/// Basic unit tests for SettingsService
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/services/settings_service.dart';
import '../../test_setup.dart';

void main() {
  group('SettingsService Tests', () {
    late SettingsService settingsService;

    setUp(() async {
      // Initialize test setup with all mocks
      await TestSetup.setupAll();

      // Use the create method to properly initialize the service
      settingsService = await SettingsService.create();
    });

    tearDown(() async {
      await TestSetup.teardown();
    });

    test('should create SettingsService instance', () {
      expect(settingsService, isNotNull);
    });

    test('should have default appSettings and themeMode', () {
      expect(settingsService.appSettings, isNotNull);
      expect(settingsService.appSettings, isA<Object>());
      expect(settingsService.themeMode, isA<ThemeMode>());
    });

    test('AppSettings should default excerpt intake to enabled', () {
      expect(AppSettings.defaultSettings().excerptIntentEnabled, isTrue);
      expect(AppSettings.fromJson(const {}).excerptIntentEnabled, isTrue);
    });

    test('AppSettings should default direct fullscreen editor toggle to false',
        () {
      expect(AppSettings.defaultSettings().skipNonFullscreenEditor, isFalse);
      expect(AppSettings.fromJson(const {}).skipNonFullscreenEditor, isFalse);
    });

    test('should persist excerpt intake toggle changes', () async {
      expect(settingsService.excerptIntentEnabled, isTrue);

      await settingsService.setExcerptIntentEnabled(false);

      expect(settingsService.excerptIntentEnabled, isFalse);
      expect(settingsService.appSettings.excerptIntentEnabled, isFalse);
    });

    test(
      'applyIncomingTrashSettings should ignore missing timestamp when local is newer',
      () async {
        await settingsService.setTrashRetentionDays(
          90,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'retention_days': 7,
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(90));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test(
      'applyIncomingTrashSettings should ignore payload without retention_days',
      () async {
        await settingsService.setTrashRetentionDays(
          90,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'last_modified': '2026-03-29T10:00:00.000Z',
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(90));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test('setTrashRetentionDays should persist modifiedAt as UTC timestamp',
        () async {
      final localTime = DateTime(2026, 3, 28, 10, 30, 0);

      await settingsService.setTrashRetentionDays(
        90,
        modifiedAt: localTime,
      );

      expect(
        settingsService.trashRetentionLastModified,
        equals(localTime.toUtc().toIso8601String()),
      );
    });

    test(
      'applyIncomingTrashSettings should ignore unparseable retention_days',
      () async {
        await settingsService.setTrashRetentionDays(
          30,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'retention_days': 'invalid',
          'last_modified': '2026-03-29T10:00:00.000Z',
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(30));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test('should persist direct fullscreen editor toggle changes', () async {
      expect(settingsService.skipNonFullscreenEditor, isFalse);

      await settingsService.setSkipNonFullscreenEditor(true);

      expect(settingsService.skipNonFullscreenEditor, isTrue);
      expect(settingsService.appSettings.skipNonFullscreenEditor, isTrue);
    });
  });
}
