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

    test('AppSettings should default note edit time toggle to false', () {
      expect(AppSettings.defaultSettings().showNoteEditTime, isFalse);
      expect(AppSettings.fromJson(const {}).showNoteEditTime, isFalse);
    });

    test('AppSettings should default daily quote provider to hitokoto', () {
      expect(AppSettings.defaultSettings().dailyQuoteProvider, 'hitokoto');
      expect(AppSettings.fromJson(const {}).dailyQuoteProvider, 'hitokoto');
    });

    test('AppSettings should default API Ninjas categories to empty', () {
      expect(AppSettings.defaultSettings().apiNinjasCategories, isEmpty);
      expect(AppSettings.fromJson(const {}).apiNinjasCategories, isEmpty);
    });

    test('should persist excerpt intake toggle changes', () async {
      expect(settingsService.excerptIntentEnabled, isTrue);

      await settingsService.setExcerptIntentEnabled(false);

      expect(settingsService.excerptIntentEnabled, isFalse);
      expect(settingsService.appSettings.excerptIntentEnabled, isFalse);
    });

    test('should persist direct fullscreen editor toggle changes', () async {
      expect(settingsService.skipNonFullscreenEditor, isFalse);

      await settingsService.setSkipNonFullscreenEditor(true);

      expect(settingsService.skipNonFullscreenEditor, isTrue);
      expect(settingsService.appSettings.skipNonFullscreenEditor, isTrue);
    });

    test('should persist note edit time toggle changes', () async {
      expect(settingsService.showNoteEditTime, isFalse);

      await settingsService.setShowNoteEditTime(true);

      expect(settingsService.showNoteEditTime, isTrue);
      expect(settingsService.appSettings.showNoteEditTime, isTrue);
    });

    test('should persist daily quote provider changes', () async {
      expect(settingsService.dailyQuoteProvider, 'hitokoto');

      await settingsService.setDailyQuoteProvider('zenquotes');

      expect(settingsService.dailyQuoteProvider, 'zenquotes');
      expect(settingsService.appSettings.dailyQuoteProvider, 'zenquotes');
    });

    test('should persist API Ninjas categories changes', () async {
      expect(settingsService.apiNinjasCategories, isEmpty);

      await settingsService.setApiNinjasCategories(
        const ['wisdom', 'success'],
      );

      expect(settingsService.apiNinjasCategories, ['wisdom', 'success']);
      expect(
        settingsService.appSettings.apiNinjasCategories,
        ['wisdom', 'success'],
      );
    });
  });
}
