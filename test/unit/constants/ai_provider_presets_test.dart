import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/ai_provider_presets.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';

void main() {
  group('AIProviderPresets catalog', () {
    test('preset ids are unique', () {
      final ids = AIProviderPresets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('exactly one preset is marked as recommended', () {
      final recommended =
          AIProviderPresets.all.where((p) => p.recommended).toList();
      expect(recommended, hasLength(1));
      expect(AIProviderPresets.recommended.id, 'ollama_cloud');
    });

    test('Ollama Cloud points at the documented endpoint', () {
      final preset = AIProviderPresets.byId('ollama_cloud')!;
      expect(preset.apiUrl, startsWith('https://ollama.com/v1'));
      expect(preset.consoleUrl, isNotNull);
      expect(preset.defaultModel, isNotEmpty);
    });

    test('every cloud preset requires a key and links to its console', () {
      for (final preset in AIProviderPresets.ofKind(AIPresetKind.cloud)) {
        expect(preset.requiresApiKey, isTrue, reason: preset.id);
        expect(preset.consoleUrl, isNotNull, reason: preset.id);
      }
    });

    test('local presets need no key', () {
      for (final preset in AIProviderPresets.ofKind(AIPresetKind.local)) {
        expect(preset.requiresApiKey, isFalse, reason: preset.id);
      }
    });

    test('every preset stores the vendor base URL, not the full endpoint', () {
      for (final preset in AIProviderPresets.all) {
        if (preset.apiUrl.isEmpty) continue;
        expect(
          preset.apiUrl,
          isNot(endsWith('/chat/completions')),
          reason: '${preset.id} 应当填服务商文档给的 base URL',
        );
      }
    });

    test('every preset base URL completes to a chat/completions endpoint', () {
      for (final preset in AIProviderPresets.all) {
        if (preset.apiUrl.isEmpty) continue;
        final provider = AIProviderSettings(
          id: 'probe',
          name: preset.id,
          apiUrl: preset.apiUrl,
          model: 'x',
        );
        expect(
          provider.resolveRequestUrl(preset.apiUrl),
          '${preset.apiUrl}/chat/completions',
          reason: '${preset.id} 的 base URL 应当能补全成完整 endpoint',
        );
      }
    });

    test('no preset uses the unsupported Anthropic messages protocol', () {
      for (final preset in AIProviderPresets.all) {
        expect(preset.apiUrl, isNot(contains('/v1/messages')),
            reason: preset.id);
      }
    });
  });

  group('AIProviderPresets.matchApiUrl', () {
    test('matches an exact template URL', () {
      final preset = AIProviderPresets.matchApiUrl(
        'https://api.deepseek.com/v1/chat/completions',
      );
      expect(preset?.id, 'deepseek');
    });

    test('matches a base URL of the same host', () {
      final preset = AIProviderPresets.matchApiUrl('https://ollama.com/v1');
      expect(preset?.id, 'ollama_cloud');
    });

    test('tells local Ollama and LM Studio apart by port', () {
      expect(
        AIProviderPresets.matchApiUrl('http://localhost:11434/v1')?.id,
        'ollama_local',
      );
      expect(
        AIProviderPresets.matchApiUrl('http://localhost:1234/v1')?.id,
        'lmstudio',
      );
    });

    test('returns null for an unknown host and for empty input', () {
      expect(AIProviderPresets.matchApiUrl('https://example.com/v1'), isNull);
      expect(AIProviderPresets.matchApiUrl('   '), isNull);
    });
  });
}
