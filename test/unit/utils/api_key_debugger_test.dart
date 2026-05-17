import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/api_key_debugger.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/services/secure_storage_service.dart';
import 'package:flutter/services.dart';

void main() {
  group('ApiKeyDebugger Tests', () {
    late APIKeyManager apiKeyManager;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();

      const MethodChannel channel =
          MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

      final Map<String, String> storage = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'read') {
            return storage[methodCall.arguments['key']];
          }
          if (methodCall.method == 'write') {
            storage[methodCall.arguments['key']] =
                methodCall.arguments['value'];
            return null;
          }
          if (methodCall.method == 'delete') {
            storage.remove(methodCall.arguments['key']);
            return null;
          }
          if (methodCall.method == 'readAll') {
            return storage;
          }
          if (methodCall.method == 'containsKey') {
            return storage.containsKey(methodCall.arguments['key']);
          }
          return null;
        },
      );
    });

    setUp(() async {
      SecureStorageService.resetForTesting();
      apiKeyManager = APIKeyManager();
    });

    test('debugApiKeyInRequest executes without error', () async {
      await ApiKeyDebugger.debugApiKeyInRequest(
        'test_provider',
        'Test Provider',
        'sk-test-stored-key-123456',
      );
      expect(true, isTrue);
    });

    test('debugApiKeyInRequest executes with empty passed key without error',
        () async {
      await apiKeyManager.saveProviderApiKey(
          'test_provider', 'sk-test-stored-key-123456');

      await ApiKeyDebugger.debugApiKeyInRequest(
        'test_provider',
        'Test Provider',
        '',
      );
      expect(true, isTrue);
    });

    test('debugApiKeyInRequest executes with empty stored key without error',
        () async {
      await ApiKeyDebugger.debugApiKeyInRequest(
        'test_provider',
        'Test Provider',
        'sk-test-passed-key-123456',
      );
      expect(true, isTrue);
    });

    test('debugApiKeyInRequest executes with mismatched keys without error',
        () async {
      await apiKeyManager.saveProviderApiKey(
          'test_provider', 'sk-test-stored-key-123456');

      await ApiKeyDebugger.debugApiKeyInRequest(
        'test_provider',
        'Test Provider',
        'sk-test-passed-key-123456',
      );
      expect(true, isTrue);
    });

    test('debugApiKeySave executes without error', () async {
      await ApiKeyDebugger.debugApiKeySave('test_provider', 'sk-test-123456');
      expect(true, isTrue);
    });

    test('debugApiKeySave executes with mismatching verification without error',
        () async {
      // Simulate save failure by just saving nothing
      await ApiKeyDebugger.debugApiKeySave('test_provider', '');
      expect(true, isTrue);
    });
  });
}
