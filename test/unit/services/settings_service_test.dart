/// Basic unit tests for SettingsService
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/ai_assistant_entry.dart';
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

    test('should persist direct fullscreen editor toggle changes', () async {
      expect(settingsService.skipNonFullscreenEditor, isFalse);

      await settingsService.setSkipNonFullscreenEditor(true);

      expect(settingsService.skipNonFullscreenEditor, isTrue);
      expect(settingsService.appSettings.skipNonFullscreenEditor, isTrue);
    });

    test('should persist split AI assistant mode preferences', () async {
      expect(
        settingsService.exploreAiAssistantMode,
        AIAssistantPageMode.chat,
      );
      expect(
        settingsService.noteAiAssistantMode,
        AIAssistantPageMode.noteChat,
      );

      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );
      await settingsService.setNoteAiAssistantMode(
        AIAssistantPageMode.agent,
      );

      expect(
        settingsService.exploreAiAssistantMode,
        AIAssistantPageMode.agent,
      );
      expect(
        settingsService.noteAiAssistantMode,
        AIAssistantPageMode.agent,
      );
    });
  });
}
