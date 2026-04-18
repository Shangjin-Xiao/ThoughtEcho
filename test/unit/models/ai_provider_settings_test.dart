import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';

void main() {
  group('AIProviderSettings endpoint helpers', () {
    test('appends chat completions suffix for OpenAI-compatible v1 base URL',
        () {
      const provider = AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1',
        model: 'gpt-4.1',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://api.openai.com/v1/chat/completions',
      );
    });

    test('keeps explicit chat completions endpoint unchanged', () {
      const provider = AIProviderSettings(
        id: 'deepseek',
        name: 'DeepSeek',
        apiUrl: 'https://api.deepseek.com/v1/chat/completions',
        model: 'deepseek-chat',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://api.deepseek.com/v1/chat/completions',
      );
    });

    test('keeps anthropic messages endpoint unchanged', () {
      const provider = AIProviderSettings(
        id: 'anthropic',
        name: 'Anthropic Claude',
        apiUrl: 'https://api.anthropic.com/v1/messages',
        model: 'claude-3-5-sonnet',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('keeps custom non-compatible endpoint unchanged', () {
      const provider = AIProviderSettings(
        id: 'custom',
        name: 'Custom',
        apiUrl: 'https://example.com/my-api/chat',
        model: 'foo',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://example.com/my-api/chat',
      );
    });
  });

  group('AIProviderSettings thinking fields', () {
    test('serializes and deserializes enableThinking=true', () {
      const provider = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiUrl: 'http://localhost:11434/v1/chat/completions',
        model: 'qwen3:8b',
        enableThinking: true,
      );

      final json = provider.toJson();
      expect(json['enableThinking'], isTrue);

      final restored = AIProviderSettings.fromJson(json);
      expect(restored.enableThinking, isTrue);
    });

    test('serializes and deserializes enableThinking=false', () {
      const provider = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiUrl: 'http://localhost:11434/v1/chat/completions',
        model: 'qwen3:8b',
        enableThinking: false,
      );

      final json = provider.toJson();
      expect(json['enableThinking'], isFalse);

      final restored = AIProviderSettings.fromJson(json);
      expect(restored.enableThinking, isFalse);
    });

    test('serializes and deserializes enableThinking=null', () {
      const provider = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiUrl: 'http://localhost:11434/v1/chat/completions',
        model: 'qwen3:8b',
      );

      final json = provider.toJson();
      expect(json['enableThinking'], isNull);

      final restored = AIProviderSettings.fromJson(json);
      expect(restored.enableThinking, isNull);
    });

    test('copyWith can update enableThinking', () {
      const provider = AIProviderSettings(
        id: 'openrouter',
        name: 'OpenRouter',
        apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
        model: 'anthropic/claude-3.7-sonnet',
      );

      final updated = provider.copyWith(enableThinking: false);
      expect(updated.enableThinking, isFalse);
    });

    test('copyWith can clear enableThinking back to auto(null)', () {
      const provider = AIProviderSettings(
        id: 'openrouter',
        name: 'OpenRouter',
        apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
        model: 'anthropic/claude-3.7-sonnet',
        enableThinking: true,
      );

      final updated = provider.copyWith(enableThinking: null);
      expect(updated.enableThinking, isNull);
    });

    test('supportsThinking matches qwen3/deepseek-r1 and openrouter prefixes',
        () {
      const qwenProvider = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiUrl: 'http://localhost:11434/v1/chat/completions',
        model: 'qwen3:8b',
      );
      const r1Provider = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiUrl: 'http://localhost:11434/v1/chat/completions',
        model: 'deepseek-r1:14b',
      );
      const qwqProvider = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiUrl: 'http://localhost:11434/v1/chat/completions',
        model: 'QwQ-32B',
      );
      const openRouterAnthropicProvider = AIProviderSettings(
        id: 'openrouter',
        name: 'OpenRouter',
        apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
        model: 'anthropic/claude-3.7-sonnet',
      );

      expect(qwenProvider.supportsThinking, isTrue);
      expect(r1Provider.supportsThinking, isTrue);
      expect(qwqProvider.supportsThinking, isTrue);
      expect(openRouterAnthropicProvider.supportsThinking, isTrue);
    });

    test('supportsThinking falls back to enableThinking=true', () {
      const provider = AIProviderSettings(
        id: 'custom',
        name: 'Custom',
        apiUrl: 'https://example.com/v1/chat/completions',
        model: 'my-unknown-model',
        enableThinking: true,
      );

      expect(provider.supportsThinking, isTrue);
    });

    test(
        'supportsThinking stays false for unknown model when enableThinking=false',
        () {
      const provider = AIProviderSettings(
        id: 'custom',
        name: 'Custom',
        apiUrl: 'https://example.com/v1/chat/completions',
        model: 'my-unknown-model',
        enableThinking: false,
      );

      expect(provider.supportsThinking, isFalse);
    });
  });
}
