import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';

void main() {
  group('OpenAIStreamService', () {
    group('normalizeOpenAIBaseUrl', () {
      test('strips /chat/completions suffix from URL', () {
        const url = 'https://api.openai.com/v1/chat/completions';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.openai.com/v1');
      });

      test('keeps /v1 path without trailing slash', () {
        const url = 'https://api.openai.com/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.openai.com/v1');
      });

      test('keeps /v1/ path and strips trailing slash', () {
        const url = 'https://api.openai.com/v1/';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.openai.com/v1');
      });

      test('adds /v1 to bare host URL', () {
        const url = 'http://localhost:11434';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://localhost:11434/v1');
      });

      test('handles Ollama URL with /v1 correctly', () {
        const url = 'http://localhost:11434/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://localhost:11434/v1');
      });

      test('handles DeepSeek URL correctly', () {
        const url = 'https://api.deepseek.com/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.deepseek.com/v1');
      });

      test('handles OpenRouter URL correctly', () {
        const url = 'https://openrouter.ai/api/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://openrouter.ai/api/v1');
      });

      test('strips /chat/completions from DeepSeek URL', () {
        const url = 'https://api.deepseek.com/v1/chat/completions';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.deepseek.com/v1');
      });

      test('does not double-add /v1 for URL already ending in /v1', () {
        const url = 'http://localhost:11434/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://localhost:11434/v1');
        expect(result, isNot('http://localhost:11434/v1/v1'));
      });

      test('handles URL with trailing slash after /v1', () {
        const url = 'http://localhost:11434/v1/';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://localhost:11434/v1');
      });

      test('strips query parameters from URL', () {
        const url = 'https://api.openai.com/v1?version=2024-01';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.openai.com/v1');
      });

      test('throws FormatException for invalid URL', () {
        const url = 'not a url';
        expect(() => OpenAIStreamService.normalizeOpenAIBaseUrl(url),
            throwsFormatException);
      });

      test('throws FormatException for empty string', () {
        const url = '';
        expect(() => OpenAIStreamService.normalizeOpenAIBaseUrl(url),
            throwsFormatException);
      });

      test('handles various localhost Ollama URLs', () {
        const cases = {
          'http://localhost:11434': 'http://localhost:11434/v1',
          'http://localhost:11434/v1': 'http://localhost:11434/v1',
          'http://localhost:11434/v1/': 'http://localhost:11434/v1',
          'http://localhost:11434/v1/chat/completions':
              'http://localhost:11434/v1',
        };
        cases.forEach((input, expected) {
          expect(OpenAIStreamService.normalizeOpenAIBaseUrl(input), expected);
        });
      });
    });

    group('buildOpenAIConfig', () {
      test('creates config for OpenAI provider', () {
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test-key',
          apiUrl: 'https://api.openai.com/v1/chat/completions',
          model: 'gpt-4o',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);

        expect(config.baseUrl, 'https://api.openai.com/v1');
        // ApiKeyProvider adds Authorization header
        // We verify it doesn't throw and produces expected baseUrl
      });

      test('creates config for Ollama provider without API key', () {
        const provider = AIProviderSettings(
          id: 'ollama',
          name: 'Ollama',
          apiKey: '',
          apiUrl: 'http://localhost:11434/v1',
          model: 'llama3',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);

        expect(config.baseUrl, 'http://localhost:11434/v1');
        // No auth provider for empty API key
        expect(config.authProvider, isNull);
      });

      test('creates config for OpenRouter with custom headers', () {
        const provider = AIProviderSettings(
          id: 'openrouter',
          name: 'OpenRouter',
          apiKey: 'or-key',
          apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
          model: 'meta-llama/llama-3.1-8b-instruct:free',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);

        expect(config.baseUrl, 'https://openrouter.ai/api/v1');
        // OpenRouter adds HTTP-Referer and X-Title headers
        expect(config.defaultHeaders.containsKey('HTTP-Referer'), isTrue);
        expect(config.defaultHeaders.containsKey('X-Title'), isTrue);
      });

      test('creates config for DeepSeek provider', () {
        const provider = AIProviderSettings(
          id: 'deepseek',
          name: 'DeepSeek',
          apiKey: 'ds-key',
          apiUrl: 'https://api.deepseek.com',
          model: 'deepseek-chat',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);

        // DeepSeek URLs may not have /v1 — should add it
        expect(config.baseUrl, 'https://api.deepseek.com/v1');
      });
    });

    group('buildChatRequest', () {
      test('creates basic chat completion request', () {
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
        );

        final request = OpenAIStreamService.buildChatRequest(
          provider: provider,
          messages: [
            openai.ChatMessage.system('You are a helpful assistant.'),
            openai.ChatMessage.user('Hello!'),
          ],
        );

        expect(request.model, 'gpt-4o');
        expect(request.messages.length, 2);
      });

      test('creates request with custom temperature', () {
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
          temperature: 0.5,
        );

        final request = OpenAIStreamService.buildChatRequest(
          provider: provider,
          messages: [openai.ChatMessage.user('Hello!')],
          temperature: 0.5,
        );

        expect(request.model, 'gpt-4o');
        expect(request.temperature, 0.5);
      });
    });

    // 内容生成（每日提示 / 周期洞察 / 空周期洞察）不该开思考：那是一次性的
    // 短文案，混合思考模型上开着只是拖慢、多花钱，推理内容还会被丢掉。
    // 这一组钉的是"必须显式传 false"——留 null 在 gemma4 这类模型上等于默认开着。
    group('thinking resolution for content generation', () {
      const gemmaOnOllama = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiKey: '',
        apiUrl: 'http://localhost:11434/v1',
        model: 'gemma4:31b',
      );

      test('gemma4 counts as a hybrid thinking model', () {
        expect(gemmaOnOllama.supportsThinking, isTrue);
      });

      test('leaving it unset falls back to supportsThinking (thinking ON)', () {
        expect(
          OpenAIStreamService.resolveThinkingEnabled(
            provider: gemmaOnOllama,
            enableThinking: null,
          ),
          isTrue,
        );
      });

      test('passing false actually turns it off', () {
        expect(
          OpenAIStreamService.resolveThinkingEnabled(
            provider: gemmaOnOllama,
            enableThinking: false,
          ),
          isFalse,
        );
      });

      test('OpenRouter gets reasoning excluded when thinking is off', () {
        const gemmaOnOpenRouter = AIProviderSettings(
          id: 'openrouter',
          name: 'OpenRouter',
          apiKey: 'sk-test',
          apiUrl: 'https://openrouter.ai/api/v1',
          model: 'google/gemma4-31b',
        );

        final off = OpenAIStreamService.buildChatRequest(
          provider: gemmaOnOpenRouter,
          messages: [openai.ChatMessage.user('Hello!')],
          enableThinking: false,
        );
        expect(off.openRouterReasoning?.effort, 'none');
        expect(off.openRouterReasoning?.exclude, isTrue);

        final on = OpenAIStreamService.buildChatRequest(
          provider: gemmaOnOpenRouter,
          messages: [openai.ChatMessage.user('Hello!')],
          enableThinking: true,
        );
        expect(on.openRouterReasoning?.effort, 'high');
      });
    });

    group('processStreamToText', () {
      test('receives text deltas from stream events', () async {
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(role: 'assistant'),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: 'Hello'),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: ' world'),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: '!'),
                finishReason: openai.FinishReason.stop,
              ),
            ],
          ),
        ];

        final stream = Stream.fromIterable(events);

        final result =
            await OpenAIStreamService.processStreamToText(stream).toList();

        expect(result, ['Hello', ' world', '!']);
      });

      test('推理模型先吐 reasoning 再吐正文时，思考过程不得混进正文', () async {
        // 回归：曾按单个 event 判断 content 是否为空，而推理模型的 reasoning
        // 总是先于 content 到达，导致思考过程被当成正文流出去——在洞察页里
        // 表现为洞察正文顶着一大段思考。
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(reasoning: '让我想想用户想要什么……'),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(reasoningContent: '再确认一下语气。'),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: '今天想写点什么？'),
                finishReason: openai.FinishReason.stop,
              ),
            ],
          ),
        ];

        final result = await OpenAIStreamService.processStreamToText(
          Stream.fromIterable(events),
        ).toList();

        expect(result, ['今天想写点什么？']);
      });

      test('整条流只有 reasoning 时仍兜底输出，避免结果全空', () async {
        // 某些模型（Ollama 上的 minimax 系列）把全部输出放在 reasoning 里，
        // 这时必须兜底，否则每日提示会退回默认模板。
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(reasoning: '今天'),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(reasoning: '想写点什么？'),
                finishReason: openai.FinishReason.stop,
              ),
            ],
          ),
        ];

        final result = await OpenAIStreamService.processStreamToText(
          Stream.fromIterable(events),
        ).toList();

        expect(result, ['今天想写点什么？']);
      });

      test('ignores empty content deltas', () async {
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(role: 'assistant'),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: ''),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: 'Hi'),
                finishReason: openai.FinishReason.stop,
              ),
            ],
          ),
        ];

        final stream = Stream.fromIterable(events);

        final result =
            await OpenAIStreamService.processStreamToText(stream).toList();

        // Empty content should be filtered out
        expect(result, ['Hi']);
      });

      test('extracts reasoning_content from stream events', () async {
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(
                  reasoningContent: 'Let me think about this...',
                ),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: 'The answer is 42.'),
              ),
            ],
          ),
        ];

        final reasoningChunks = <String>[];
        final textChunks = <String>[];

        await for (final chunk in OpenAIStreamService.processStreamToText(
          Stream.fromIterable(events),
          onThinking: (thinking) {
            reasoningChunks.add(thinking);
          },
        )) {
          textChunks.add(chunk);
        }

        expect(reasoningChunks, ['Let me think about this...']);
        expect(textChunks, ['The answer is 42.']);
      });

      test('handles stream with null choices gracefully', () async {
        const event = openai.ChatStreamEvent(id: 'chatcmpl-1');

        final stream = Stream.fromIterable([event]);

        final result =
            await OpenAIStreamService.processStreamToText(stream).toList();

        expect(result, isEmpty);
      });

      test('propagates stream errors', () async {
        final controller = StreamController<openai.ChatStreamEvent>();
        controller.addError(Exception('Connection refused'));
        controller.close();

        expect(
          () => OpenAIStreamService.processStreamToText(controller.stream)
              .toList(),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('chatCompletion (non-streaming)', () {
      test('extracts text from ChatCompletion response', () {
        final completion = openai.ChatCompletion(
          id: 'chatcmpl-1',
          object: 'chat.completion',
          created: 1234567890,
          model: 'gpt-4o',
          choices: [
            openai.ChatChoice(
              index: 0,
              message: openai.AssistantMessage(content: 'Hello, world!'),
              finishReason: openai.FinishReason.stop,
            ),
          ],
        );

        final result =
            OpenAIStreamService.extractTextFromCompletion(completion);
        expect(result, 'Hello, world!');
      });

      test('returns empty string when no choices', () {
        final completion = openai.ChatCompletion(
          id: 'chatcmpl-1',
          object: 'chat.completion',
          created: 1234567890,
          model: 'gpt-4o',
          choices: const [],
        );

        final result =
            OpenAIStreamService.extractTextFromCompletion(completion);
        expect(result, '');
      });

      test('returns empty string when message content is null', () {
        final completion = openai.ChatCompletion(
          id: 'chatcmpl-1',
          object: 'chat.completion',
          created: 1234567890,
          model: 'gpt-4o',
          choices: [
            openai.ChatChoice(
              index: 0,
              message: openai.AssistantMessage(),
              finishReason: openai.FinishReason.stop,
            ),
          ],
        );

        final result =
            OpenAIStreamService.extractTextFromCompletion(completion);
        expect(result, '');
      });
    });

    group(
        'URL normalization edge cases (VAL-NONSTREAM-001, VAL-NONSTREAM-003, VAL-ERR-001)',
        () {
      test('bare host without path gets /v1', () {
        // VERIFIES: No 405 errors for bare host URL configurations
        expect(
          OpenAIStreamService.normalizeOpenAIBaseUrl(
              'http://192.168.1.100:8080'),
          'http://192.168.1.100:8080/v1',
        );
      });

      test('host with /v1 path is preserved', () {
        // VERIFIES: No double /v1/v1 path
        expect(
          OpenAIStreamService.normalizeOpenAIBaseUrl(
              'http://192.168.1.100:8080/v1'),
          'http://192.168.1.100:8080/v1',
        );
      });

      test('host with /v1/chat/completions path strips endpoint', () {
        // VERIFIES: URL correctly appends /chat/completions (via openai_dart)
        // without double-path issues
        expect(
          OpenAIStreamService.normalizeOpenAIBaseUrl(
            'http://192.168.1.100:8080/v1/chat/completions',
          ),
          'http://192.168.1.100:8080/v1',
        );
      });

      test('OpenRouter /api/v1 path is preserved', () {
        // OpenRouter uses /api/v1 which should be preserved as-is
        expect(
          OpenAIStreamService.normalizeOpenAIBaseUrl(
              'https://openrouter.ai/api/v1'),
          'https://openrouter.ai/api/v1',
        );
        expect(
          OpenAIStreamService.normalizeOpenAIBaseUrl(
            'https://openrouter.ai/api/v1/chat/completions',
          ),
          'https://openrouter.ai/api/v1',
        );
      });

      test('URL without trailing slash after /v1', () {
        expect(
          OpenAIStreamService.normalizeOpenAIBaseUrl(
              'https://api.deepseek.com/v1'),
          'https://api.deepseek.com/v1',
        );
      });

      test('URL with trailing slash after /v1', () {
        expect(
          OpenAIStreamService.normalizeOpenAIBaseUrl(
              'https://api.deepseek.com/v1/'),
          'https://api.deepseek.com/v1',
        );
      });

      test('buildOpenAIConfig removes Content-Type header', () {
        // Content-Type should be removed because openai_dart sets it
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);

        // Content-Type should not be in defaultHeaders
        expect(config.defaultHeaders.containsKey('Content-Type'), isFalse);
        expect(config.defaultHeaders.containsKey('content-type'), isFalse);
      });
    });
  });
}
