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
}
