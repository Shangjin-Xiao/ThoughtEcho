import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final Map<String, String> storage = {};

  setUp(() async {
    // Clear mock storage
    storage.clear();

    // Reset service state
    SecureStorageService.resetForTesting();

    // Ensure SharedPreferences is mocked (needed for AppPreferencesService init)
    SharedPreferences.setMockInitialValues({});

    // Reset AppPreferencesService and clear data
    final appPrefs = AppPreferencesService();
    appPrefs.resetForTesting();
    await appPrefs.initialize();
    await appPrefs.clear();

    // Mock FlutterSecureStorage
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return storage[methodCall.arguments['key']];
        }
        if (methodCall.method == 'write') {
          storage[methodCall.arguments['key']] = methodCall.arguments['value'];
          return null;
        }
        if (methodCall.method == 'delete') {
          storage.remove(methodCall.arguments['key']);
          return null;
        }
        if (methodCall.method == 'readAll') {
          return storage;
        }
        return null;
      },
    );
  });

  test('SecureStorageService should save, retrieve and remove keys', () async {
    final service = SecureStorageService();

    // Test Save
    await service.saveProviderApiKey('openai', 'sk-test-123');
    expect(storage.containsKey('provider_api_keys'), true);

    // Test Get
    final key = await service.getProviderApiKey('openai');
    expect(key, 'sk-test-123');

    // Test Remove
    await service.removeProviderApiKey('openai');
    final keyAfterRemove = await service.getProviderApiKey('openai');
    expect(keyAfterRemove, null);

    // Test Empty Save (should remove)
    await service.saveProviderApiKey('anthropic', 'sk-ant-123');
    expect(await service.getProviderApiKey('anthropic'), 'sk-ant-123');
    await service.saveProviderApiKey('anthropic', '');
    expect(await service.getProviderApiKey('anthropic'), null);
  });

  test(
      'should migrate legacy data from SharedPreferences to FlutterSecureStorage',
      () async {
    // 1. Setup legacy data using AppPreferencesService directly to ensure it persists in the singleton
    final legacyKeys = {'openai': 'sk-legacy-key'};
    final legacyJson = jsonEncode(legacyKeys);

    final appPrefs = AppPreferencesService();
    await appPrefs.setString('provider_api_keys', legacyJson);

    // 2. Initialize service
    final service = SecureStorageService();
    // Force initialization to trigger migration
    await service.ensureInitialized();

    // 3. Verify data moved to secure storage
    expect(storage.containsKey('provider_api_keys'), true);
    final secureData = storage['provider_api_keys'];
    expect(secureData, legacyJson);

    // 4. Verify data removed from legacy storage
    expect(appPrefs.containsKey('provider_api_keys'), false);
  });

  test('should not overwrite existing secure data during migration', () async {
    // 1. Setup legacy data AND existing secure data
    final legacyKeys = {'openai': 'sk-legacy-key'};
    final secureKeys = {'openai': 'sk-secure-key', 'anthropic': 'sk-ant-key'};

    final appPrefs = AppPreferencesService();
    await appPrefs.setString('provider_api_keys', jsonEncode(legacyKeys));

    storage['provider_api_keys'] = jsonEncode(secureKeys);

    // 2. Initialize service
    final service = SecureStorageService();
    await service.ensureInitialized();

    // 3. Verify secure data was NOT overwritten
    final currentSecureData = storage['provider_api_keys'];
    final decoded = jsonDecode(currentSecureData!);
    expect(decoded['openai'], 'sk-secure-key'); // Should keep secure one
    expect(decoded['anthropic'], 'sk-ant-key');

    // 4. Verify legacy data was still removed (cleanup)
    expect(appPrefs.containsKey('provider_api_keys'), false);
  });
}
