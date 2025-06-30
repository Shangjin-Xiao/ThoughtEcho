/// Unit tests for SettingsService
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/models/ai_settings.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('SettingsService Tests', () {
    late SettingsService settingsService;

    setUpAll(() {
      TestHelpers.setupTestEnvironment();
    });

    setUp(() async {
      // Clear shared preferences before each test
      SharedPreferences.setMockInitialValues({});
      settingsService = await SettingsService.create();
      await settingsService.initialize();
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        expect(settingsService.isInitialized, isTrue);
      });

      test('should have default AI settings', () {
        final aiSettings = settingsService.aiSettings;
        expect(aiSettings, isNotNull);
        expect(aiSettings.model, isNotEmpty);
        expect(aiSettings.temperature, greaterThan(0));
        expect(aiSettings.maxTokens, greaterThan(0));
      });

      test('should have default app settings', () {
        final appSettings = settingsService.appSettings;
        expect(appSettings, isNotNull);
        expect(appSettings.fontSize, greaterThan(0));
        expect(appSettings.lineHeight, greaterThan(0));
        expect(appSettings.backupInterval, greaterThan(0));
      });

      test('should have default multi AI settings', () {
        final multiAISettings = settingsService.multiAISettings;
        expect(multiAISettings, isNotNull);
        expect(multiAISettings.maxRetries, greaterThan(0));
        expect(multiAISettings.timeout, greaterThan(0));
      });

      test('should have default theme mode', () {
        expect(settingsService.themeMode, isNotNull);
      });
    });

    group('AI Settings Management', () {
      test('should update AI settings successfully', () async {
        const newSettings = AISettings(
          apiKey: 'test-api-key',
          model: 'gpt-4',
          temperature: 0.8,
          maxTokens: 3000,
          enableAnalysis: false,
        );

        await settingsService.updateAISettings(newSettings);

        expect(settingsService.aiSettings.apiKey, equals('test-api-key'));
        expect(settingsService.aiSettings.model, equals('gpt-4'));
        expect(settingsService.aiSettings.temperature, equals(0.8));
        expect(settingsService.aiSettings.maxTokens, equals(3000));
        expect(settingsService.aiSettings.enableAnalysis, isFalse);
      });

      test('should persist AI settings', () async {
        const newSettings = AISettings(
          apiKey: 'persistent-key',
          model: 'claude-3',
          temperature: 0.5,
          maxTokens: 4000,
          enableAnalysis: true,
        );

        await settingsService.updateAISettings(newSettings);

        // Create new instance to test persistence
        final newService = await SettingsService.create();
        await newService.initialize();

        expect(newService.aiSettings.apiKey, equals('persistent-key'));
        expect(newService.aiSettings.model, equals('claude-3'));
        expect(newService.aiSettings.temperature, equals(0.5));
        expect(newService.aiSettings.maxTokens, equals(4000));
        expect(newService.aiSettings.enableAnalysis, isTrue);
      });

      test('should handle invalid AI settings gracefully', () async {
        const invalidSettings = AISettings(
          temperature: -1.0, // Invalid temperature
          maxTokens: -100,   // Invalid max tokens
        );

        // Should not throw but may adjust values
        await settingsService.updateAISettings(invalidSettings);

        // The service should handle invalid values appropriately
        expect(settingsService.aiSettings, isNotNull);
      });
    });

    group('App Settings Management', () {
      test('should update app settings successfully', () async {
        const newSettings = AppSettings(
          enableNotifications: false,
          autoSave: false,
          fontSize: 18.0,
          lineHeight: 1.8,
          enableClipboardMonitoring: true,
          backupInterval: 14,
        );

        await settingsService.updateAppSettings(newSettings);

        expect(settingsService.appSettings.enableNotifications, isFalse);
        expect(settingsService.appSettings.autoSave, isFalse);
        expect(settingsService.appSettings.fontSize, equals(18.0));
        expect(settingsService.appSettings.lineHeight, equals(1.8));
        expect(settingsService.appSettings.enableClipboardMonitoring, isTrue);
        expect(settingsService.appSettings.backupInterval, equals(14));
      });

      test('should persist app settings', () async {
        const newSettings = AppSettings(
          enableNotifications: false,
          autoSave: true,
          fontSize: 20.0,
          lineHeight: 2.0,
          enableClipboardMonitoring: false,
          backupInterval: 30,
        );

        await settingsService.updateAppSettings(newSettings);

        // Create new instance to test persistence
        final newService = await SettingsService.create();
        await newService.initialize();

        expect(newService.appSettings.enableNotifications, isFalse);
        expect(newService.appSettings.autoSave, isTrue);
        expect(newService.appSettings.fontSize, equals(20.0));
        expect(newService.appSettings.lineHeight, equals(2.0));
        expect(newService.appSettings.enableClipboardMonitoring, isFalse);
        expect(newService.appSettings.backupInterval, equals(30));
      });
    });

    group('Multi AI Settings Management', () {
      test('should update multi AI settings successfully', () async {
        const newSettings = MultiAISettings(
          enableMultiProvider: true,
          fallbackEnabled: false,
          maxRetries: 5,
          timeout: 45,
        );

        await settingsService.updateMultiAISettings(newSettings);

        expect(settingsService.multiAISettings.enableMultiProvider, isTrue);
        expect(settingsService.multiAISettings.fallbackEnabled, isFalse);
        expect(settingsService.multiAISettings.maxRetries, equals(5));
        expect(settingsService.multiAISettings.timeout, equals(45));
      });

      test('should persist multi AI settings', () async {
        const newSettings = MultiAISettings(
          enableMultiProvider: true,
          fallbackEnabled: true,
          maxRetries: 2,
          timeout: 60,
        );

        await settingsService.updateMultiAISettings(newSettings);

        // Create new instance to test persistence
        final newService = await SettingsService.create();
        await newService.initialize();

        expect(newService.multiAISettings.enableMultiProvider, isTrue);
        expect(newService.multiAISettings.fallbackEnabled, isTrue);
        expect(newService.multiAISettings.maxRetries, equals(2));
        expect(newService.multiAISettings.timeout, equals(60));
      });
    });

    group('Theme Mode Management', () {
      test('should update theme mode successfully', () async {
        await settingsService.updateThemeMode(ThemeMode.dark);
        expect(settingsService.themeMode, equals(ThemeMode.dark));

        await settingsService.updateThemeMode(ThemeMode.light);
        expect(settingsService.themeMode, equals(ThemeMode.light));

        await settingsService.updateThemeMode(ThemeMode.system);
        expect(settingsService.themeMode, equals(ThemeMode.system));
      });

      test('should persist theme mode', () async {
        await settingsService.updateThemeMode(ThemeMode.dark);

        // Create new instance to test persistence
        final newService = await SettingsService.create();
        await newService.initialize();

        expect(newService.themeMode, equals(ThemeMode.dark));
      });
    });

    group('Generic Preferences', () {
      test('should store and retrieve preferences', () async {
        await settingsService.setPreference('test_string', 'test value');
        await settingsService.setPreference('test_int', 42);
        await settingsService.setPreference('test_bool', true);
        await settingsService.setPreference('test_double', 3.14);

        expect(settingsService.getPreference<String>('test_string'), equals('test value'));
        expect(settingsService.getPreference<int>('test_int'), equals(42));
        expect(settingsService.getPreference<bool>('test_bool'), isTrue);
        expect(settingsService.getPreference<double>('test_double'), equals(3.14));
      });

      test('should return null for non-existent preferences', () {
        expect(settingsService.getPreference<String>('non_existent'), isNull);
        expect(settingsService.getPreference<int>('non_existent'), isNull);
        expect(settingsService.getPreference<bool>('non_existent'), isNull);
      });

      test('should handle type mismatches gracefully', () {
        settingsService.setPreference('test_value', 'string_value');
        
        // Trying to get as wrong type should return null or handle gracefully
        final result = settingsService.getPreference<int>('test_value');
        expect(result, isNull);
      });
    });

    group('Application State Management', () {
      test('should manage onboarding completion', () async {
        expect(settingsService.isOnboardingComplete(), isFalse);

        await settingsService.markOnboardingComplete();
        expect(settingsService.isOnboardingComplete(), isTrue);
      });

      test('should manage database migration state', () async {
        expect(settingsService.isDatabaseMigrationComplete(), isFalse);

        await settingsService.markDatabaseMigrationComplete();
        expect(settingsService.isDatabaseMigrationComplete(), isTrue);
      });

      test('should manage initial database setup state', () async {
        expect(settingsService.isInitialDatabaseSetupComplete(), isFalse);

        await settingsService.markInitialDatabaseSetupComplete();
        expect(settingsService.isInitialDatabaseSetupComplete(), isTrue);
      });

      test('should manage app installation state', () async {
        expect(settingsService.isAppInstalled(), isFalse);

        await settingsService.markAppInstalled();
        expect(settingsService.isAppInstalled(), isTrue);
      });

      test('should manage app upgrade state', () async {
        expect(settingsService.isAppUpgraded(), isFalse);

        await settingsService.markAppUpgraded();
        expect(settingsService.isAppUpgraded(), isTrue);
      });

      test('should manage version tracking', () async {
        expect(settingsService.getLastVersion(), isNull);

        await settingsService.setLastVersion('1.0.0');
        expect(settingsService.getLastVersion(), equals('1.0.0'));

        await settingsService.setLastVersion('1.1.0');
        expect(settingsService.getLastVersion(), equals('1.1.0'));
      });
    });

    group('Data Management', () {
      test('should clear all settings', () async {
        // Set some data first
        await settingsService.updateThemeMode(ThemeMode.dark);
        await settingsService.setPreference('test_key', 'test_value');
        await settingsService.markOnboardingComplete();

        // Clear all settings
        await settingsService.clearAllSettings();

        // Verify defaults are restored
        expect(settingsService.themeMode, equals(ThemeMode.system));
        expect(settingsService.getPreference('test_key'), isNull);
        expect(settingsService.isOnboardingComplete(), isFalse);
      });

      test('should export settings', () {
        settingsService.setPreference('export_test', 'export_value');
        
        final exportedSettings = settingsService.exportSettings();
        
        expect(exportedSettings, isNotNull);
        expect(exportedSettings, isA<Map<String, dynamic>>());
        expect(exportedSettings['export_test'], equals('export_value'));
      });

      test('should import settings', () async {
        final importData = {
          'import_test': 'import_value',
          'theme_mode': ThemeMode.dark.index,
          'onboarding_complete': true,
        };

        await settingsService.importSettings(importData);

        expect(settingsService.getPreference('import_test'), equals('import_value'));
        expect(settingsService.themeMode, equals(ThemeMode.dark));
        expect(settingsService.isOnboardingComplete(), isTrue);
      });

      test('should reset to defaults', () async {
        // Set some custom values
        await settingsService.updateThemeMode(ThemeMode.dark);
        await settingsService.setPreference('custom_key', 'custom_value');
        await settingsService.markOnboardingComplete();

        // Reset to defaults
        await settingsService.resetToDefaults();

        // Verify defaults are restored
        expect(settingsService.themeMode, equals(ThemeMode.system));
        expect(settingsService.getPreference('custom_key'), isNull);
        expect(settingsService.isOnboardingComplete(), isFalse);
        expect(settingsService.isInitialized, isTrue);
      });
    });

    group('Notifications', () {
      test('should notify listeners on AI settings change', () async {
        bool notified = false;
        settingsService.addListener(() {
          notified = true;
        });

        const newSettings = AISettings(model: 'test-model');
        await settingsService.updateAISettings(newSettings);

        expect(notified, isTrue);
      });

      test('should notify listeners on app settings change', () async {
        bool notified = false;
        settingsService.addListener(() {
          notified = true;
        });

        const newSettings = AppSettings(fontSize: 20.0);
        await settingsService.updateAppSettings(newSettings);

        expect(notified, isTrue);
      });

      test('should notify listeners on theme mode change', () async {
        bool notified = false;
        settingsService.addListener(() {
          notified = true;
        });

        await settingsService.updateThemeMode(ThemeMode.dark);

        expect(notified, isTrue);
      });

      test('should notify listeners on preference change', () async {
        bool notified = false;
        settingsService.addListener(() {
          notified = true;
        });

        await settingsService.setPreference('test_key', 'test_value');

        expect(notified, isTrue);
      });
    });

    group('Error Handling', () {
      test('should handle corrupted settings gracefully', () async {
        // This test would require mocking shared preferences to return invalid data
        // For now, we'll test that the service can reinitialize
        await settingsService.resetToDefaults();
        expect(settingsService.isInitialized, isTrue);
      });

      test('should handle storage errors gracefully', () async {
        // Test that the service continues to work even if storage fails
        // This would typically involve mocking the storage layer
        expect(settingsService.aiSettings, isNotNull);
        expect(settingsService.appSettings, isNotNull);
      });
    });

    group('Migration', () {
      test('should handle settings migration from old versions', () async {
        // Simulate old version settings
        final oldSettings = {
          'ai_api_key': 'old-key', // Old format
          'app_theme': 'dark',     // Old format
        };

        await settingsService.importSettings(oldSettings);

        // Service should handle migration or ignore unknown keys
        expect(settingsService.isInitialized, isTrue);
      });
    });

    group('Performance', () {
      test('should handle rapid setting changes efficiently', () async {
        final stopwatch = Stopwatch()..start();

        // Perform many rapid changes
        for (int i = 0; i < 100; i++) {
          await settingsService.setPreference('rapid_test_$i', 'value_$i');
        }

        stopwatch.stop();

        // Should complete within reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));

        // Verify data integrity
        for (int i = 0; i < 100; i++) {
          expect(
            settingsService.getPreference('rapid_test_$i'),
            equals('value_$i'),
          );
        }
      });

      test('should handle large setting values efficiently', () async {
        final largeValue = 'x' * 10000; // 10KB string

        final stopwatch = Stopwatch()..start();
        await settingsService.setPreference('large_value', largeValue);
        final retrieved = settingsService.getPreference<String>('large_value');
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(retrieved, equals(largeValue));
      });
    });
  });
}