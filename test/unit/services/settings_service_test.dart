/// Basic unit tests for SettingsService
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/settings_service.dart';

void main() {
  group('SettingsService Tests', () {
    late SettingsService settingsService;

    setUp(() async {
      // Initialize mock SharedPreferences
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsService = SettingsService(prefs);
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
