/// Basic unit tests for SettingsService
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/settings_service.dart';

void main() {
  group('SettingsService Tests', () {
    late SettingsService settingsService;

    setUp(() {
      settingsService = SettingsService();
    });

    test('should create SettingsService instance', () {
      expect(settingsService, isNotNull);
    });

    test('should have default values', () {
      expect(settingsService.autoSave, isA<bool>());
      expect(settingsService.isDarkMode, isA<bool>());
    });
  });
}