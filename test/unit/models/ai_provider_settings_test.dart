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

    test('preserves prefixed OpenAI-compatible v1 base URL', () {
      const provider = AIProviderSettings(
        id: 'openrouter',
        name: 'OpenRouter',
        apiUrl: 'https://openrouter.ai/api/v1',
        model: 'anthropic/claude-3.7-sonnet',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://openrouter.ai/api/v1/chat/completions',
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

    test('completes Ollama Cloud base URL as documented on ollama.com', () {
      const provider = AIProviderSettings(
        id: 'provider_1',
        name: 'Ollama 云端',
        apiUrl: 'https://ollama.com/v1',
        model: 'gpt-oss:120b',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://ollama.com/v1/chat/completions',
      );
    });

    test('completes vendor base URLs that are not plain /v1', () {
      const zhipu = AIProviderSettings(
        id: 'provider_2',
        name: '智谱 GLM',
        apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4-flash',
      );
      const dashscope = AIProviderSettings(
        id: 'provider_3',
        name: '阿里云百炼',
        apiUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        model: 'qwen-plus',
      );
      const gemini = AIProviderSettings(
        id: 'provider_4',
        name: 'Google Gemini',
        apiUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
        model: 'gemini-2.5-flash',
      );

      expect(
        zhipu.resolveRequestUrl(zhipu.apiUrl),
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
      expect(
        dashscope.resolveRequestUrl(dashscope.apiUrl),
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      );
      expect(
        gemini.resolveRequestUrl(gemini.apiUrl),
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      );
    });

    test('completes bare host to the OpenAI default layout', () {
      const provider = AIProviderSettings(
        id: 'provider_5',
        name: 'Custom',
        apiUrl: 'https://example.com',
        model: 'foo',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://example.com/v1/chat/completions',
      );
    });

    test('strips trailing slash before completing', () {
      const provider = AIProviderSettings(
        id: 'provider_6',
        name: 'Ollama 云端',
        apiUrl: 'https://ollama.com/v1/',
        model: 'gpt-oss:120b',
      );

      expect(
        provider.resolveRequestUrl(provider.apiUrl),
        'https://ollama.com/v1/chat/completions',
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

    // 这个白名单曾经冻结在 2024 年的型号上：`claude-3` 的子串匹配对
    // `claude-sonnet-4-5` 完全失效，GPT-5 / Gemini 2.5 也整代漏掉，
    // 结果是绝大多数用户根本看不到「深度思考」开关。
    test('supportsThinking covers current reasoning model families', () {
      AIProviderSettings withModel(String model) => AIProviderSettings(
            id: 'p',
            name: 'P',
            apiUrl: 'https://example.com/v1/chat/completions',
            model: model,
          );

      for (final model in const [
        'claude-sonnet-4-5-20250929',
        'claude-opus-4-1',
        'anthropic/claude-3.7-sonnet',
        'gpt-5.1',
        'openai/o3-mini',
        'gemini-2.5-pro',
        'gemini-3-pro-preview',
        'deepseek-chat-v3.1',
        'kimi-k2-thinking',
        'glm-4.6',
        'MiniMax-M2',
      ]) {
        expect(
          withModel(model).supportsThinking,
          isTrue,
          reason: '$model 应被识别为支持思考',
        );
      }

      for (final model in const [
        'claude-3-5-sonnet-20241022',
        'claude-3-haiku-20240307',
        'gpt-4o-mini',
        'gemini-1.5-flash',
        'gemini-2.0-flash',
        'llama-3.3-70b',
      ]) {
        expect(
          withModel(model).supportsThinking,
          isFalse,
          reason: '$model 不支持思考，不应显示开关',
        );
      }
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
