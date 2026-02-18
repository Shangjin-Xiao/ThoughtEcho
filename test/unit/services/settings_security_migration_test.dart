import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/secure_storage_service.dart';
import 'package:thoughtecho/models/ai_settings.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    SecureStorageService.resetForTesting();
    final safeMMKV = SafeMMKV();
    await safeMMKV.initialize();
    await safeMMKV.clear();

    // Mock FlutterSecureStorage
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          (methodCall) async => null,
        );
  });

  test(
    'SettingsService should clear sensitive data from SharedPreferences after migration',
    () async {
      final aiSettings = AISettings(apiKey: 'sk-legacy-key', model: 'gpt-4');
      final aiSettingsJson = jsonEncode(aiSettings.toJson());

      SharedPreferences.setMockInitialValues({
        'ai_settings': aiSettingsJson,
        'mmkv_migration_complete': false,
      });

      final prefs = await SharedPreferences.getInstance();
      // Verify initial state
      expect(prefs.getString('ai_settings'), aiSettingsJson);

      // This triggers _migrateDataIfNeeded
      await SettingsService.create();

      // Check if it was migrated to MMKV (SafeMMKV)
      final safeMMKV = SafeMMKV();
      expect(safeMMKV.getString('ai_settings'), isNotNull);

      // Check if it was cleared from SharedPreferences
      expect(prefs.getString('ai_settings'), isNull);
    },
  );

  test(
    '_secureLegacyApiKey should clear key from MMKV and SP even if no provider selected',
    () async {
      final aiSettings = AISettings(apiKey: 'sk-legacy-key', model: 'gpt-4');
      final aiSettingsJson = jsonEncode(aiSettings.toJson());

      // Mock SafeMMKV state
      final safeMMKV = SafeMMKV();
      await safeMMKV.initialize();
      await safeMMKV.setString('ai_settings', aiSettingsJson);
      await safeMMKV.setBool('mmkv_migration_complete', true);

      // Mock legacy key in SP
      SharedPreferences.setMockInitialValues({'ai_settings': aiSettingsJson});
      final prefs = await SharedPreferences.getInstance();

      // Create service (this triggers _secureLegacyApiKey)
      await SettingsService.create();

      // Plaintext key should be cleared from MMKV
      final updatedAiSettingsJson = safeMMKV.getString('ai_settings');
      final updatedAiSettings = jsonDecode(updatedAiSettingsJson!);
      expect(updatedAiSettings['apiKey'], '');

      // Plaintext key should be cleared from SP
      final updatedSpJson = prefs.getString('ai_settings');
      final updatedSp = jsonDecode(updatedSpJson!);
      expect(updatedSp['apiKey'], '');
    },
  );
}
