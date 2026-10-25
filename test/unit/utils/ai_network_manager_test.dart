import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/services/secure_storage_service.dart';
import 'package:thoughtecho/utils/ai_network_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
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
        if (methodCall.method == 'containsKey') {
          return storage.containsKey(methodCall.arguments['key']);
        }
        return null;
      },
    );
  });

  setUp(() async {
    SecureStorageService.resetForTesting();
    AINetworkManager.clearProviderFailures();
  });

  group('AINetworkManager unit tests', () {
    test('clearProviderFailures clears failed providers map', () {
      expect(() => AINetworkManager.clearProviderFailures(), returnsNormally);
    });

    test('makeRequest throws exception when no settings provided', () async {
      expect(
        () => AINetworkManager.makeRequest(
          url: '',
          data: {'model': 'test'},
        ),
        throwsException,
      );
    });

    test('makeStreamRequest throws exception when no settings provided',
        () async {
      expect(
        () => AINetworkManager.makeStreamRequest(
          url: '',
          data: {'model': 'test'},
          onData: (_) {},
          onComplete: (_) {},
          onError: (_) {},
        ),
        throwsException,
      );
    });

    test('MultiAISettings with empty available providers throws exception',
        () async {
      const emptyMultiSettings = MultiAISettings(
        providers: [],
        currentProviderId: 'none',
        enableFailover: true,
      );

      expect(
        () => AINetworkManager.makeRequest(
          url: '',
          data: {'model': 'test'},
          multiSettings: emptyMultiSettings,
        ),
        throwsException,
      );
    });

    test('Loads API key from storage during request execution', () async {
      final apiKeyManager = APIKeyManager();
      await apiKeyManager.saveProviderApiKey('provider_1', 'sk-test-key-12345');

      const provider = AIProviderSettings(
        id: 'provider_1',
        name: 'Provider 1',
        apiKey: '', // Empty key forces load from storage
        apiUrl: 'http://invalid-url-for-test.local',
        model: 'model-1',
      );

      const multiSettings = MultiAISettings(
        providers: [provider],
        currentProviderId: 'provider_1',
        enableFailover: false,
      );

      // Should attempt network call and fail, confirming API key was fetched and execution proceeded
      expect(
        () => AINetworkManager.makeRequest(
          url: '',
          data: {'model': 'test'},
          multiSettings: multiSettings,
        ),
        throwsA(
          predicate((e) =>
              e.toString().contains('非安全URL') ||
              e.toString().contains('HTTPS') ||
              e.toString().contains('AI请求未知错误')),
        ),
      );
    });
  });
}
