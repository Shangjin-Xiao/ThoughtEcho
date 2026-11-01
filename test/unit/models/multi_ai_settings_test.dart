import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';

void main() {
  group('MultiAISettings initialization & getters', () {
    test('default constructor initializes with expected defaults', () {
      const settings = MultiAISettings();

      expect(settings.providers, isEmpty);
      expect(settings.availableProviders, isEmpty);
      expect(settings.currentProviderId, isNull);
      expect(settings.enableFailover, isTrue);
      expect(settings.currentProvider, isNull);
    });

    test('defaultSettings factory returns clean empty configuration', () {
      final settings = MultiAISettings.defaultSettings();

      expect(settings.providers, isEmpty);
      expect(settings.availableProviders, isEmpty);
      expect(settings.currentProviderId, isNull);
      expect(settings.enableFailover, isTrue);
      expect(settings.currentProvider, isNull);
    });

    test('currentProvider resolves correctly when ID matches provider', () {
      const provider1 = AIProviderSettings(
        id: 'p1',
        name: 'Provider 1',
        apiUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o',
      );
      const provider2 = AIProviderSettings(
        id: 'p2',
        name: 'Provider 2',
        apiUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-chat',
      );

      const settings = MultiAISettings(
        providers: [provider1, provider2],
        currentProviderId: 'p2',
        enableFailover: false,
      );

      expect(settings.currentProvider, isNotNull);
      expect(settings.currentProvider?.id, 'p2');
      expect(settings.currentProvider?.name, 'Provider 2');
      expect(settings.availableProviders, equals([provider1, provider2]));
      expect(settings.enableFailover, isFalse);
    });

    test('currentProvider returns null when ID is not found in providers', () {
      const provider1 = AIProviderSettings(
        id: 'p1',
        name: 'Provider 1',
        apiUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o',
      );

      const settings = MultiAISettings(
        providers: [provider1],
        currentProviderId: 'non_existent_id',
      );

      expect(settings.currentProvider, isNull);
    });

    test('currentProvider returns null when currentProviderId is null', () {
      const provider1 = AIProviderSettings(
        id: 'p1',
        name: 'Provider 1',
        apiUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o',
      );

      const settings = MultiAISettings(
        providers: [provider1],
        currentProviderId: null,
      );

      expect(settings.currentProvider, isNull);
    });
  });

  group('MultiAISettings fromJson & toJson', () {
    test('deserializes standard modern json format', () {
      final json = {
        'providers': [
          {
            'id': 'provider_test',
            'name': 'Test Provider',
            'apiUrl': 'https://example.com/v1',
            'model': 'test-model',
            'apiKey': 'secret-key',
          }
        ],
        'currentProviderId': 'provider_test',
        'enableFailover': false,
      };

      final settings = MultiAISettings.fromJson(json);

      expect(settings.providers.length, 1);
      expect(settings.providers.first.id, 'provider_test');
      expect(settings.currentProviderId, 'provider_test');
      expect(settings.enableFailover, isFalse);
      expect(settings.currentProvider?.id, 'provider_test');
    });

    test(
        'handles fallback when providers is null but availableProviders exists',
        () {
      final json = {
        'availableProviders': [
          {
            'id': 'legacy_provider',
            'name': 'Legacy Provider',
            'apiUrl': 'https://legacy.example.com',
            'model': 'legacy-model',
          }
        ],
        'currentProviderId': 'legacy_provider',
      };

      final settings = MultiAISettings.fromJson(json);

      expect(settings.providers.length, 1);
      expect(settings.providers.first.id, 'legacy_provider');
      expect(settings.currentProviderId, 'legacy_provider');
      expect(settings.enableFailover, isTrue); // default fallback
    });

    test(
        'handles legacy currentProvider object map when currentProviderId is missing',
        () {
      final json = {
        'providers': [
          {
            'id': 'p_old',
            'name': 'Old Provider',
            'apiUrl': 'https://example.com',
            'model': 'old-model',
          }
        ],
        'currentProvider': {
          'id': 'p_old',
          'name': 'Old Provider',
        },
      };

      final settings = MultiAISettings.fromJson(json);

      expect(settings.currentProviderId, 'p_old');
      expect(settings.currentProvider?.id, 'p_old');
    });

    test('handles empty or malformed legacy currentProvider gracefully', () {
      final json1 = {
        'providers': <dynamic>[],
        'currentProvider': 'not_a_map',
      };
      final settings1 = MultiAISettings.fromJson(json1);
      expect(settings1.currentProviderId, isNull);

      final json2 = {
        'providers': <dynamic>[],
        'currentProvider': <String, dynamic>{},
      };
      final settings2 = MultiAISettings.fromJson(json2);
      expect(settings2.currentProviderId, isNull);

      final json3 = <String, dynamic>{};
      final settings3 = MultiAISettings.fromJson(json3);
      expect(settings3.providers, isEmpty);
      expect(settings3.currentProviderId, isNull);
      expect(settings3.enableFailover, isTrue);
    });

    test('toJson serializes all fields including backward-compatibility fields',
        () {
      const provider = AIProviderSettings(
        id: 'p_roundtrip',
        name: 'RT Provider',
        apiUrl: 'https://example.com/v1',
        model: 'rt-model',
      );
      const settings = MultiAISettings(
        providers: [provider],
        currentProviderId: 'p_roundtrip',
        enableFailover: true,
      );

      final json = settings.toJson();

      expect(json['providers'], isA<List>());
      expect(json['availableProviders'], isA<List>());
      expect((json['providers'] as List).length, 1);
      expect((json['availableProviders'] as List).length, 1);
      expect(json['currentProviderId'], 'p_roundtrip');
      expect(json['currentProvider'], isA<Map<String, dynamic>>());
      expect(
        (json['currentProvider'] as Map<String, dynamic>)['id'],
        'p_roundtrip',
      );
      expect(json['enableFailover'], isTrue);

      final restored = MultiAISettings.fromJson(json);
      expect(restored.providers.length, settings.providers.length);
      expect(restored.providers.first.id, settings.providers.first.id);
      expect(restored.currentProviderId, settings.currentProviderId);
      expect(restored.enableFailover, settings.enableFailover);
      expect(restored.currentProvider?.id, settings.currentProvider?.id);
    });

    test(
        'toJson handles null currentProvider gracefully for compatibility field',
        () {
      const settings = MultiAISettings(
        providers: [],
        currentProviderId: null,
        enableFailover: false,
      );

      final json = settings.toJson();
      expect(json['currentProvider'], isNull);
      expect(json['currentProviderId'], isNull);
      expect(json['enableFailover'], isFalse);
    });
  });

  group('MultiAISettings copyWith', () {
    test('updates properties independently', () {
      const provider1 = AIProviderSettings(
        id: 'p1',
        name: 'P1',
        apiUrl: 'https://p1.com',
        model: 'm1',
      );
      const provider2 = AIProviderSettings(
        id: 'p2',
        name: 'P2',
        apiUrl: 'https://p2.com',
        model: 'm2',
      );

      const initial = MultiAISettings(
        providers: [provider1],
        currentProviderId: 'p1',
        enableFailover: true,
      );

      final copy1 = initial.copyWith(providers: [provider1, provider2]);
      expect(copy1.providers.length, 2);
      expect(copy1.currentProviderId, 'p1');
      expect(copy1.enableFailover, isTrue);

      final copy2 = initial.copyWith(currentProviderId: 'p2');
      expect(copy2.providers.length, 1);
      expect(copy2.currentProviderId, 'p2');
      expect(copy2.enableFailover, isTrue);

      final copy3 = initial.copyWith(enableFailover: false);
      expect(copy3.providers.length, 1);
      expect(copy3.currentProviderId, 'p1');
      expect(copy3.enableFailover, isFalse);

      final copyNone = initial.copyWith();
      expect(copyNone.providers.length, 1);
      expect(copyNone.currentProviderId, 'p1');
      expect(copyNone.enableFailover, isTrue);
    });
  });
}
