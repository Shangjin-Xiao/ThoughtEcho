/// Basic unit tests for SettingsService
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
