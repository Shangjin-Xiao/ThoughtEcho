import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final Map<String, String> storage = {};

  setUp(() {
    // Clear mock storage
    storage.clear();

    // Mock FlutterSecureStorage
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
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

  // Note: SecureStorageService is a singleton. Once initialized, it stays initialized.
  // We can only test migration logic if we are the first to initialize it in this isolate.
  // Since we can't guarantee execution order or if it was accessed before,
  // we focus on functional testing of the current implementation.
  // However, we can try to inject initial data into SharedPreferences before accessing the service.

  test('SecureStorageService should save, retrieve and remove keys', () async {
    // Ensure SharedPreferences is mocked (needed for SafeMMKV init inside service)
    SharedPreferences.setMockInitialValues({});

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
}
