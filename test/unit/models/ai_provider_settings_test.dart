import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_model_metadata.dart';
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
        // gemma4 会思考，只是不主动吐 reasoning，要在请求里明确要。
        // 认不出来的话 agent 不会带上 reasoning_effort，用户就看不到思考过程。
        'gemma4:31b-cloud',
        'gemma-4-27b',
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
        'gemma2:9b',
        'gemma-3-12b',
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

    test(
        'supportsThinking prioritizes enableThinking==true, then modelMetadata.reasoning, then regex fallback',
        () {
      // Unknown model name with modelMetadata.reasoning == true -> true
      const customReasoning = AIProviderSettings(
        id: 'p_meta_true',
        name: 'Custom Reasoning',
        apiUrl: 'https://example.com/v1',
        model: 'acme-thinker-v1',
        modelMetadata: AIModelMetadata(reasoning: true),
      );
      expect(customReasoning.supportsThinking, isTrue);

      // Regex-matched model name (qwen3) but modelMetadata.reasoning == false -> false
      const nonReasoningOverride = AIProviderSettings(
        id: 'p_meta_false',
        name: 'Qwen Non-Reasoning Variant',
        apiUrl: 'https://example.com/v1',
        model: 'qwen3-instruct-fast',
        modelMetadata: AIModelMetadata(reasoning: false),
      );
      expect(nonReasoningOverride.supportsThinking, isFalse);

      // Explicit user enableThinking == true still wins even when metadata says false
      expect(
        nonReasoningOverride.copyWith(enableThinking: true).supportsThinking,
        isTrue,
      );
    });
  });

  group('AIProviderSettings models.dev protocol & slug compatibility', () {
    test(
        'serializes and deserializes providerSlug, protocol, and modelMetadata',
        () {
      const original = AIProviderSettings(
        id: 'provider_1700000001',
        name: 'OpenRouter Claude',
        apiUrl: 'https://my-gateway.example.com/v1',
        model: 'anthropic/claude-sonnet-4-5',
        providerSlug: 'openrouter',
        protocol: AIProtocolType.openAICompatible,
        modelMetadata: AIModelMetadata(
          contextWindow: 200000,
          maxOutputTokens: 64000,
          reasoning: true,
          toolCall: true,
          supportsVision: true,
        ),
      );

      final json = original.toJson();
      expect(json['providerSlug'], 'openrouter');
      expect(json['protocol'], 'openAICompatible');
      expect(json['modelMetadata'], isA<Map<String, dynamic>>());

      final restored = AIProviderSettings.fromJson(json);
      expect(restored.providerSlug, 'openrouter');
      expect(restored.protocol, AIProtocolType.openAICompatible);
      expect(restored.modelMetadata, equals(original.modelMetadata));
    });

    test(
        'buildHeaders injects OpenRouter headers when providerSlug is openrouter even with provider_<ts> id and proxy URL',
        () {
      const openRouterProxy = AIProviderSettings(
        id: 'provider_1712345678',
        name: 'My OpenRouter Proxy',
        apiKey: 'sk-or-test',
        apiUrl: 'https://gateway.example.com/v1/chat/completions',
        model: 'deepseek/deepseek-r1',
        providerSlug: 'openrouter',
      );

      final headers = openRouterProxy.buildHeaders();
      expect(headers['Authorization'], 'Bearer sk-or-test');
      expect(headers['HTTP-Referer'], 'https://thoughtecho.app');
      expect(headers['X-Title'], 'ThoughtEcho App');
    });

    test(
        'protocol anthropicMessages activates Anthropic headers and avoids /chat/completions suffix on custom gateway URL',
        () {
      const anthropicGateway = AIProviderSettings(
        id: 'provider_1712349999',
        name: 'Anthropic Enterprise Gateway',
        apiKey: 'sk-ant-test',
        apiUrl: 'https://llm-gateway.corp.example.com/anthropic',
        model: 'claude-sonnet-4-5',
        providerSlug: 'anthropic',
        protocol: AIProtocolType.anthropicMessages,
      );

      expect(anthropicGateway.isAnthropicMessagesApi, isTrue);
      final headers = anthropicGateway.buildHeaders();
      expect(headers['x-api-key'], 'sk-ant-test');
      expect(headers['anthropic-version'], '2023-06-01');
      expect(headers.containsKey('Authorization'), isFalse);
      expect(
        anthropicGateway.resolveRequestUrl(anthropicGateway.apiUrl),
        'https://llm-gateway.corp.example.com/anthropic/v1/messages',
      );
    });

    test(
        'distinguishes literal /v1/messages endpoint from shared OpenAI-compatible /v1 base URL and /v1/chat/completions',
        () {
      const nativeAnthropic = AIProviderSettings(
        id: 'provider_custom_ant',
        name: 'Anthropic Native',
        apiKey: 'sk-ant-native',
        apiUrl: 'https://api.anthropic.com/v1/messages',
        model: 'claude-sonnet-4-5',
      );
      expect(nativeAnthropic.isAnthropicMessagesApi, isTrue);
      expect(
        nativeAnthropic.resolveRequestUrl(nativeAnthropic.apiUrl),
        'https://api.anthropic.com/v1/messages',
      );
      expect(nativeAnthropic.buildHeaders()['x-api-key'], 'sk-ant-native');

      const sharedBaseAnthropic = AIProviderSettings(
        id: 'provider_shared_ant',
        name: 'Anthropic Shared Base',
        apiKey: 'sk-ant-shared',
        apiUrl: 'https://api.anthropic.com/v1',
        model: 'claude-sonnet-4-5',
        providerSlug: 'anthropic',
      );
      expect(sharedBaseAnthropic.isAnthropicMessagesApi, isFalse);
      expect(
        sharedBaseAnthropic.resolveRequestUrl(sharedBaseAnthropic.apiUrl),
        'https://api.anthropic.com/v1/chat/completions',
      );
      expect(
        sharedBaseAnthropic.buildHeaders()['Authorization'],
        'Bearer sk-ant-shared',
      );

      const compatAnthropic = AIProviderSettings(
        id: 'provider_compat_ant',
        name: 'Anthropic OpenAI Compat',
        apiKey: 'sk-ant-compat',
        apiUrl: 'https://api.anthropic.com/v1/chat/completions',
        model: 'claude-sonnet-4-5',
      );
      expect(compatAnthropic.isAnthropicMessagesApi, isFalse);
      expect(
        compatAnthropic.resolveRequestUrl(compatAnthropic.apiUrl),
        'https://api.anthropic.com/v1/chat/completions',
      );
      expect(
        compatAnthropic.buildHeaders()['Authorization'],
        'Bearer sk-ant-compat',
      );
    });

    test(
        'fromJson migrates host-inferred anthropic.com /v1 records to openAICompatible while keeping /v1/messages native',
        () {
      final migrated = AIProviderSettings.fromJson({
        'id': 'provider_legacy_ant',
        'name': 'Anthropic Compat Base',
        'apiUrl': 'https://api.anthropic.com/v1',
        'model': 'claude-sonnet-4-5',
        'providerSlug': 'anthropic',
        'protocol': 'anthropic_messages',
      });
      expect(migrated.protocol, AIProtocolType.openAICompatible);
      expect(migrated.isAnthropicMessagesApi, isFalse);

      final explicitNative = AIProviderSettings.fromJson({
        'id': 'provider_native_ant',
        'name': 'Anthropic Messages',
        'apiUrl': 'https://api.anthropic.com/v1/messages',
        'model': 'claude-sonnet-4-5',
        'providerSlug': 'anthropic',
        'protocol': 'anthropic_messages',
      });
      expect(explicitNative.protocol, AIProtocolType.anthropicMessages);
      expect(explicitNative.isAnthropicMessagesApi, isTrue);
    });

    test(
        'preserves OpenAI-compatible protocol on custom gateway bases ending in /messages while keeping literal /v1/messages native when unset',
        () {
      const compatGatewayPrefix = AIProviderSettings(
        id: 'provider_inbox_gw',
        name: 'Inbox Gateway',
        apiKey: 'sk-gw-inbox',
        apiUrl: 'https://gateway.example/v1/inbox/messages',
        model: 'gpt-4o-mini',
        protocol: AIProtocolType.openAICompatible,
      );
      expect(compatGatewayPrefix.isAnthropicMessagesApi, isFalse);
      expect(
        compatGatewayPrefix.resolveRequestUrl(compatGatewayPrefix.apiUrl),
        'https://gateway.example/v1/inbox/messages',
      );
      expect(
        compatGatewayPrefix.buildHeaders()['Authorization'],
        'Bearer sk-gw-inbox',
      );

      const unsetInboxGateway = AIProviderSettings(
        id: 'provider_inbox_unset',
        name: 'Inbox Unset',
        apiKey: 'sk-gw-unset',
        apiUrl: 'https://gateway.example/v1/inbox/messages',
        model: 'gpt-4o-mini',
      );
      expect(unsetInboxGateway.isAnthropicMessagesApi, isFalse);

      const explicitCompatOnV1MessagesPrefix = AIProviderSettings(
        id: 'provider_v1_msg_compat',
        name: 'Explicit Compat Prefix',
        apiKey: 'sk-gw-compat',
        apiUrl: 'https://gateway.example/v1/messages',
        model: 'gpt-4o-mini',
        protocol: AIProtocolType.openAICompatible,
      );
      expect(explicitCompatOnV1MessagesPrefix.isAnthropicMessagesApi, isFalse);

      const unsetLiteralV1Messages = AIProviderSettings(
        id: 'provider_v1_msg_native',
        name: 'Custom Native Anthropic',
        apiKey: 'sk-ant-proxy',
        apiUrl: 'https://gateway.example/v1/messages',
        model: 'claude-sonnet-4-5',
      );
      expect(unsetLiteralV1Messages.isAnthropicMessagesApi, isTrue);
      expect(
        unsetLiteralV1Messages.resolveRequestUrl(unsetLiteralV1Messages.apiUrl),
        'https://gateway.example/v1/messages',
      );
    });

    test(
        'identifies restored non-official Anthropic gateways via providerSlug or legacy id when protocol is null',
        () {
      const restoredBySlug = AIProviderSettings(
        id: 'provider_1712399999',
        name: 'Restored Anthropic Proxy',
        apiKey: 'sk-ant-restored',
        apiUrl: 'https://gateway.example/v1',
        model: 'claude-sonnet-4-5',
        providerSlug: 'anthropic',
      );
      expect(restoredBySlug.isAnthropicMessagesApi, isTrue);
      expect(
        restoredBySlug.resolveRequestUrl(restoredBySlug.apiUrl),
        'https://gateway.example/v1/messages',
      );
      expect(restoredBySlug.buildHeaders()['x-api-key'], 'sk-ant-restored');

      const legacyById = AIProviderSettings(
        id: 'anthropic',
        name: 'Legacy Anthropic Gateway',
        apiKey: 'sk-ant-legacy',
        apiUrl: 'https://gateway.example/v1',
        model: 'claude-sonnet-4-5',
      );
      expect(legacyById.isAnthropicMessagesApi, isTrue);
      expect(
        legacyById.resolveRequestUrl(legacyById.apiUrl),
        'https://gateway.example/v1/messages',
      );
    });
  });
}
