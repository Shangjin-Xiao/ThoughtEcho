import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/ai_task.dart';
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
      expect(settings.providers.first.apiKey, isEmpty);
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
      expect(restored.providers.first.name, settings.providers.first.name);
      expect(restored.providers.first.apiUrl, settings.providers.first.apiUrl);
      expect(restored.providers.first.model, settings.providers.first.model);
      expect(restored.providers.first.apiKey, isEmpty);
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
        enableFailover: false,
      );

      final copy1 = initial.copyWith(providers: [provider1, provider2]);
      expect(copy1.providers.length, 2);
      expect(copy1.currentProviderId, 'p1');
      expect(copy1.enableFailover, isFalse);

      final copy2 = initial.copyWith(currentProviderId: 'p2');
      expect(copy2.providers.length, 1);
      expect(copy2.currentProviderId, 'p2');
      expect(copy2.enableFailover, isFalse);

      final copy3 = initial.copyWith(enableFailover: true);
      expect(copy3.providers.length, 1);
      expect(copy3.currentProviderId, 'p1');
      expect(copy3.enableFailover, isTrue);

      final copyNullId = initial.copyWith(currentProviderId: null);
      expect(copyNullId.providers.length, 1);
      expect(copyNullId.currentProviderId, isNull);
      expect(copyNullId.enableFailover, isFalse);

      final copyNone = initial.copyWith();
      expect(copyNone.providers.length, 1);
      expect(copyNone.currentProviderId, 'p1');
      expect(copyNone.enableFailover, isFalse);
    });
  });

  group('MultiAISettings stateless per-task routing', () {
    const defaultProvider = AIProviderSettings(
      id: 'default_p',
      name: 'Default Provider',
      apiUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
    );
    const fastProvider = AIProviderSettings(
      id: 'fast_p',
      name: 'Fast Provider',
      apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-4-flash',
    );
    const reasoningProvider = AIProviderSettings(
      id: 'reason_p',
      name: 'Reasoning Provider',
      apiUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-reasoner',
    );
    const disabledProvider = AIProviderSettings(
      id: 'disabled_p',
      name: 'Disabled Provider',
      apiUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      isEnabled: false,
    );

    test(
        'resolves explicit provider per task and falls back to currentProvider without mutating default',
        () {
      final settings = MultiAISettings(
        providers: const [
          defaultProvider,
          fastProvider,
          reasoningProvider,
          disabledProvider,
        ],
        currentProviderId: 'default_p',
        taskProviderIds: const {
          AITask.dailyInsight: 'fast_p',
          AITask.dreaming: 'reason_p',
        },
      );

      expect(
          settings.resolveProviderForTask(AITask.dailyInsight)?.id, 'fast_p');
      expect(settings.resolveProviderForTask(AITask.dreaming)?.id, 'reason_p');
      expect(
        settings.resolveProviderForTask(AITask.periodicInsight)?.id,
        'default_p',
      );
      expect(settings.resolveProviderForTask(AITask.agent)?.id, 'default_p');
      expect(settings.resolveProviderForTask(null)?.id, 'default_p');
      expect(settings.currentProviderId, 'default_p');
    });

    test(
        'falls back to currentProvider when assigned provider is disabled or missing',
        () {
      final settings = MultiAISettings(
        providers: const [defaultProvider, disabledProvider],
        currentProviderId: 'default_p',
        taskProviderIds: const {
          AITask.dailyInsight: 'disabled_p',
          AITask.dreaming: 'deleted_provider_id',
        },
      );

      expect(settings.explicitProviderForTask(AITask.dailyInsight), isNull);
      expect(settings.explicitProviderForTask(AITask.dreaming), isNull);
      expect(
        settings.resolveProviderForTask(AITask.dailyInsight)?.id,
        'default_p',
      );
      expect(
        settings.resolveProviderForTask(AITask.dreaming)?.id,
        'default_p',
      );
      expect(settings.tasksAssignedTo('disabled_p'), isEmpty);
    });

    test('withTaskProvider and withoutProvider keep taskProviderIds clean', () {
      var settings = const MultiAISettings(
        providers: [defaultProvider, fastProvider, reasoningProvider],
        currentProviderId: 'default_p',
      );

      settings = settings
          .withTaskProvider(AITask.dailyInsight, 'fast_p')
          .withTaskProvider(AITask.periodicInsight, 'fast_p')
          .withTaskProvider(AITask.dreaming, 'reason_p');

      expect(settings.currentProviderId, 'default_p');
      expect(
        settings.tasksAssignedTo('fast_p'),
        [AITask.dailyInsight, AITask.periodicInsight],
      );

      // Reset dailyInsight back to following default
      settings = settings.withTaskProvider(AITask.dailyInsight, null);
      expect(settings.explicitProviderForTask(AITask.dailyInsight), isNull);
      expect(
        settings.resolveProviderForTask(AITask.dailyInsight)?.id,
        'default_p',
      );

      // Delete fast_p -> cleans periodicInsight binding and preserves dreaming
      final afterDelete = settings.withoutProvider('fast_p');
      expect(afterDelete.taskProviderIds.containsKey(AITask.periodicInsight),
          isFalse);
      expect(afterDelete.taskProviderIds[AITask.dreaming], 'reason_p');
      expect(afterDelete.currentProviderId, 'default_p');
    });

    test('serializes taskProviderIds and tolerates legacy or malformed maps',
        () {
      final original = MultiAISettings(
        providers: const [defaultProvider, reasoningProvider],
        currentProviderId: 'default_p',
        taskProviderIds: const {
          AITask.dreaming: 'reason_p',
          AITask.agent: 'reason_p',
        },
      );

      final json = original.toJson();
      expect(json['taskProviderIds'], {
        'dreaming': 'reason_p',
        'agent': 'reason_p',
      });

      final restored = MultiAISettings.fromJson(json);
      expect(restored.taskProviderIds, {
        AITask.dreaming: 'reason_p',
        AITask.agent: 'reason_p',
      });

      final malformed = MultiAISettings.fromJson({
        'providers': [defaultProvider.toJson()],
        'currentProviderId': 'default_p',
        'taskProviderIds': {
          'unknownTask': 'default_p',
          'agent': 12345,
          'dailyInsight': '   ',
          'dreaming': 'default_p',
        },
      });
      expect(malformed.taskProviderIds, {AITask.dreaming: 'default_p'});
    });

    test('AITask parses cardGeneration and sessionTitle and exposes tier sets',
        () {
      expect(AITask.tryParse('cardGeneration'), AITask.cardGeneration);
      expect(AITask.tryParse('sessionTitle'), AITask.sessionTitle);
      expect(AITask.tryParse('unknown_future_task'), isNull);
      expect(AITask.customDisplayOrder, [
        AITask.agent,
        AITask.dailyInsight,
        AITask.periodicInsight,
        AITask.cardGeneration,
        AITask.sessionTitle,
        AITask.dreaming,
      ]);
      expect(AITask.agent.usesLightTier, isFalse);
      expect(AITask.dreaming.usesLightTier, isFalse);
      expect(AITask.cardGeneration.usesLightTier, isFalse);
      expect(AITask.dailyInsight.usesLightTier, isTrue);
      expect(AITask.periodicInsight.usesLightTier, isTrue);
      expect(AITask.sessionTitle.usesLightTier, isTrue);
    });

    test(
        'tiered mode routes primary vs light tasks and falls back to primary when light is unset, disabled, or deleted',
        () {
      const tieredWithLight = MultiAISettings(
        providers: [
          defaultProvider,
          fastProvider,
          reasoningProvider,
          disabledProvider,
        ],
        currentProviderId: 'reason_p',
        routingMode: AIRoutingMode.tiered,
        lightProviderId: 'fast_p',
      );

      expect(tieredWithLight.routingMode, AIRoutingMode.tiered);
      // Primary tasks -> reason_p
      expect(
          tieredWithLight.resolveProviderForTask(AITask.agent)?.id, 'reason_p');
      expect(
        tieredWithLight.resolveProviderForTask(AITask.dreaming)?.id,
        'reason_p',
      );
      expect(
        tieredWithLight.resolveProviderForTask(AITask.cardGeneration)?.id,
        'reason_p',
      );
      // Light tasks -> fast_p
      expect(
        tieredWithLight.resolveProviderForTask(AITask.dailyInsight)?.id,
        'fast_p',
      );
      expect(
        tieredWithLight.resolveProviderForTask(AITask.periodicInsight)?.id,
        'fast_p',
      );
      expect(
        tieredWithLight.resolveProviderForTask(AITask.sessionTitle)?.id,
        'fast_p',
      );

      // Disabled light provider -> falls back to primary
      final disabledLight = tieredWithLight.withLightProvider('disabled_p');
      expect(disabledLight.lightProvider, isNull);
      expect(
        disabledLight.resolveProviderForTask(AITask.dailyInsight)?.id,
        'reason_p',
      );

      // Deleting light provider cleans lightProviderId and falls back to primary
      final afterDelete = tieredWithLight.withoutProvider('fast_p');
      expect(afterDelete.lightProviderId, isNull);
      expect(
        afterDelete.resolveProviderForTask(AITask.sessionTitle)?.id,
        'reason_p',
      );
    });

    test(
        'switching from tiered to custom pre-fills light tasks when taskProviderIds is empty, and infers routingMode on legacy JSON',
        () {
      const tiered = MultiAISettings(
        providers: [defaultProvider, fastProvider],
        currentProviderId: 'default_p',
        routingMode: AIRoutingMode.tiered,
        lightProviderId: 'fast_p',
      );

      final switchedCustom = tiered.withRoutingMode(AIRoutingMode.custom);
      expect(switchedCustom.routingMode, AIRoutingMode.custom);
      expect(switchedCustom.taskProviderIds, {
        AITask.dailyInsight: 'fast_p',
        AITask.periodicInsight: 'fast_p',
        AITask.sessionTitle: 'fast_p',
      });
      expect(
        switchedCustom.resolveProviderForTask(AITask.agent)?.id,
        'default_p',
      );
      expect(
        switchedCustom.resolveProviderForTask(AITask.dreaming)?.id,
        'default_p',
      );
      expect(
        switchedCustom.resolveProviderForTask(AITask.periodicInsight)?.id,
        'fast_p',
      );
      expect(
        switchedCustom.resolveProviderForTask(AITask.sessionTitle)?.id,
        'fast_p',
      );

      // Legacy JSON with non-empty taskProviderIds and no routingMode -> custom
      final legacyCustom = MultiAISettings.fromJson({
        'providers': [defaultProvider.toJson(), fastProvider.toJson()],
        'currentProviderId': 'default_p',
        'taskProviderIds': {'cardGeneration': 'fast_p'},
      });
      expect(legacyCustom.routingMode, AIRoutingMode.custom);
      expect(
        legacyCustom.resolveProviderForTask(AITask.cardGeneration)?.id,
        'fast_p',
      );

      // Legacy JSON with empty taskProviderIds and no routingMode -> tiered
      final legacyTiered = MultiAISettings.fromJson({
        'providers': [defaultProvider.toJson()],
        'currentProviderId': 'default_p',
      });
      expect(legacyTiered.routingMode, AIRoutingMode.tiered);

      // Legacy JSON with dedicated agent provider migrates sessionTitle to preserve privacy
      final legacyAgentOnly = MultiAISettings.fromJson({
        'providers': [defaultProvider.toJson(), reasoningProvider.toJson()],
        'currentProviderId': 'default_p',
        'taskProviderIds': {'agent': 'reason_p'},
      });
      expect(legacyAgentOnly.routingMode, AIRoutingMode.custom);
      expect(
        legacyAgentOnly.resolveProviderForTask(AITask.sessionTitle)?.id,
        'reason_p',
      );

      // Clearing all custom assignments to Follow Default persists across tiered -> custom switches and JSON reloads
      final clearedCustom = switchedCustom
          .withTaskProvider(AITask.dailyInsight, null)
          .withTaskProvider(AITask.periodicInsight, null)
          .withTaskProvider(AITask.sessionTitle, null);
      expect(clearedCustom.taskProviderIds, isEmpty);
      expect(clearedCustom.customRoutingInitialized, isTrue);

      final reloadedCleared = MultiAISettings.fromJson(clearedCustom.toJson());
      final backToTiered =
          reloadedCleared.withRoutingMode(AIRoutingMode.tiered);
      final backToCustom = backToTiered.withRoutingMode(AIRoutingMode.custom);
      expect(backToCustom.taskProviderIds, isEmpty);
    });
  });
}
