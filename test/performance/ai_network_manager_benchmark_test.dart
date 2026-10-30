import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
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

  test('Benchmark API Key loading in provider resolution', () async {
    final apiKeyManager = APIKeyManager();
    const providerCount = 10;
    final providers = <AIProviderSettings>[];

    for (int i = 0; i < providerCount; i++) {
      final id = 'provider_$i';
      await apiKeyManager.saveProviderApiKey(id, 'sk-test-key-$i-123456');
      providers.add(
        AIProviderSettings(
          id: id,
          name: 'Provider $i',
          apiKey: '', // Empty key forces loading from secure storage
          apiUrl: 'https://api.test$i.com/v1',
          model: 'model-$i',
        ),
      );
    }

    // Benchmark loading keys for all providers in loop (simulating failover resolution scope)
    const iterations = 50;
    final stopwatch = Stopwatch()..start();

    for (int it = 0; it < iterations; it++) {
      // Execution scope map caching simulation
      final Map<String, AIProviderSettings> apiKeyCache = {};
      for (final provider in providers) {
        if (apiKeyCache.containsKey(provider.id)) {
          // ignore: unused_local_variable
          final cached = apiKeyCache[provider.id]!;
        } else {
          final loadedKey = await apiKeyManager.getProviderApiKey(provider.id);
          final loaded = provider.copyWith(apiKey: loadedKey);
          apiKeyCache[provider.id] = loaded;
        }
      }
    }

    stopwatch.stop();

    // ignore: avoid_print
    print(
      'Cached API key loading for $providerCount providers x $iterations iterations: ${stopwatch.elapsedMilliseconds} ms',
    );
  });
}
