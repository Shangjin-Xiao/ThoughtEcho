import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AINetworkManager provider key caching performance benchmark', () {
    test('Simulated failover key lookup repeatedly with and without cache', () {
      final p1 = AIProviderSettings(
        id: 'provider-1',
        name: 'Provider 1',
        apiUrl: 'https://api.p1.com/v1',
        model: 'gpt-4o',
      );
      final p2 = AIProviderSettings(
        id: 'provider-2',
        name: 'Provider 2',
        apiUrl: 'https://api.p2.com/v1',
        model: 'gpt-4o',
      );
      final p3 = AIProviderSettings(
        id: 'provider-3',
        name: 'Provider 3',
        apiUrl: 'https://api.p3.com/v1',
        model: 'gpt-4o',
      );

      final multiSettings = MultiAISettings(
        enableFailover: true,
        currentProviderId: 'provider-1',
        providers: [p1, p2, p3],
      );

      const iterations = 10000;

      // 模拟无 cache 的多次 key 读取与对象生成
      final swWithoutCache = Stopwatch()..start();
      int loadedCountWithoutCache = 0;
      for (int i = 0; i < iterations; i++) {
        for (final provider in multiSettings.availableProviders) {
          // 模拟从加密存储中重新加载与封装 provider
          final loadedProvider =
              provider.copyWith(apiKey: 'key-${provider.id}');
          if (loadedProvider.apiKey.isNotEmpty) {
            loadedCountWithoutCache++;
          }
        }
      }
      swWithoutCache.stop();

      // 模拟使用 execution-scope cache 的 key 读取
      final swWithCache = Stopwatch()..start();
      int loadedCountWithCache = 0;
      for (int i = 0; i < iterations; i++) {
        final cache = <String, AIProviderSettings>{};
        for (final provider in multiSettings.availableProviders) {
          AIProviderSettings loadedProvider;
          if (cache.containsKey(provider.id)) {
            loadedProvider = cache[provider.id]!;
          } else {
            loadedProvider = provider.copyWith(apiKey: 'key-${provider.id}');
            cache[provider.id] = loadedProvider;
          }
          if (loadedProvider.apiKey.isNotEmpty) {
            loadedCountWithCache++;
          }
        }
      }
      swWithCache.stop();

      expect(loadedCountWithoutCache,
          iterations * multiSettings.availableProviders.length);
      expect(loadedCountWithCache,
          iterations * multiSettings.availableProviders.length);
      expect(swWithoutCache.elapsedMicroseconds, isPositive);
      expect(swWithCache.elapsedMicroseconds, isPositive);
    });
  });
}
