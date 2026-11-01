import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    group('parseSseLine', () {
      test('correctly parses valid SSE data line into ChatStreamEvent',
          () async {
        final controller = StreamController<openai.ChatStreamEvent>();
        const line =
            'data: {"id": "chatcmpl-1", "choices": [{"index": 0, "delta": {"content": "Hello"}}]}';

        final eventsFuture = controller.stream.toList();
        OpenAIStreamService.parseSseLine(line, controller);
        await controller.close();

        final events = await eventsFuture;
        expect(events.length, 1);
        expect(events[0].id, 'chatcmpl-1');
        expect(events[0].choices?[0].delta.content, 'Hello');
      });

      test('ignores empty or whitespace-only lines', () async {
        final controller = StreamController<openai.ChatStreamEvent>();
        final eventsFuture = controller.stream.toList();

        OpenAIStreamService.parseSseLine('', controller);
        OpenAIStreamService.parseSseLine('   ', controller);
        OpenAIStreamService.parseSseLine('\t\n', controller);
        await controller.close();

        final events = await eventsFuture;
        expect(events, isEmpty);
      });

      test('ignores non-data SSE events and comments', () async {
        final controller = StreamController<openai.ChatStreamEvent>();
        final eventsFuture = controller.stream.toList();

        OpenAIStreamService.parseSseLine(': ping', controller);
        OpenAIStreamService.parseSseLine('event: completion', controller);
        OpenAIStreamService.parseSseLine('id: 42', controller);
        OpenAIStreamService.parseSseLine('retry: 1000', controller);
        await controller.close();

        final events = await eventsFuture;
        expect(events, isEmpty);
      });

      test('handles [DONE] termination marker without adding event', () async {
        final controller = StreamController<openai.ChatStreamEvent>();
        final eventsFuture = controller.stream.toList();

        OpenAIStreamService.parseSseLine('data: [DONE]', controller);
        OpenAIStreamService.parseSseLine('data:[DONE]', controller);
        OpenAIStreamService.parseSseLine('data:   [DONE]  ', controller);
        await controller.close();

        final events = await eventsFuture;
        expect(events, isEmpty);
      });

      test('handles empty data payload gracefully', () async {
        final controller = StreamController<openai.ChatStreamEvent>();
        final eventsFuture = controller.stream.toList();

        OpenAIStreamService.parseSseLine('data:', controller);
        OpenAIStreamService.parseSseLine('data:   ', controller);
        await controller.close();

        final events = await eventsFuture;
        expect(events, isEmpty);
      });

      test('catches malformed JSON without throwing or corrupting stream',
          () async {
        final controller = StreamController<openai.ChatStreamEvent>();
        final eventsFuture = controller.stream.toList();

        OpenAIStreamService.parseSseLine('data: {"id": "chatcmpl', controller);
        OpenAIStreamService.parseSseLine('data: not json at all', controller);
        await controller.close();

        final events = await eventsFuture;
        expect(events, isEmpty);
      });

      test('does not throw when controller is closed', () {
        final controller = StreamController<openai.ChatStreamEvent>();
        controller.close();

        expect(
          () => OpenAIStreamService.parseSseLine(
            'data: {"id": "1", "choices": [{"index": 0, "delta": {"content": "Closed"}}]}',
            controller,
          ),
          returnsNormally,
        );
      });
    });

    group('streamWithCustomBody & partialLine buffer', () {
      const ollamaProvider = AIProviderSettings(
        id: 'ollama',
        name: 'Ollama',
        apiKey: '',
        apiUrl: 'http://localhost:11434/v1',
        model: 'llama3',
      );
      final config = OpenAIStreamService.buildOpenAIConfig(ollamaProvider);
      final service = OpenAIStreamService();

      Future<List<openai.ChatStreamEvent>> executeStream(
        List<String> chunks,
      ) async {
        final client = MockClient.streaming((request, body) async {
          final stream = Stream.fromIterable(
            chunks.map((c) => utf8.encode(c)),
          );
          return http.StreamedResponse(stream, 200);
        });

        final controller = StreamController<openai.ChatStreamEvent>();
        final eventsFuture = controller.stream.toList();

        await service.streamWithCustomBody(
          config: config,
          requestBody: {'model': 'llama3'},
          controller: controller,
          httpClient: client,
        );
        await controller.close();

        return eventsFuture;
      }

      test(
          'reassembles SSE data line split across two chunks (TCP fragmentation)',
          () async {
        // Line split at arbitrary point: `data: {"id": "1",`
        final chunks = [
          'data: {"id": "1",',
          ' "choices": [{"index": 0, "delta": {"content": "reassembled"}}]}\n',
        ];

        final events = await executeStream(chunks);
        expect(events.length, 1);
        expect(events[0].id, '1');
        expect(events[0].choices?[0].delta.content, 'reassembled');
      });

      test('reassembles SSE data line split across three chunks', () async {
        final chunks = [
          'data: {"id": "2", ',
          '"choices": [{"index": 0, "delta": ',
          '{"content": "piece by piece"}}]}\n',
        ];

        final events = await executeStream(chunks);
        expect(events.length, 1);
        expect(events[0].id, '2');
        expect(events[0].choices?[0].delta.content, 'piece by piece');
      });

      test('handles single chunk containing multiple complete SSE lines',
          () async {
        final chunks = [
          'data: {"id": "1", "choices": [{"index": 0, "delta": {"content": "First"}}]}\n'
              'data: {"id": "2", "choices": [{"index": 0, "delta": {"content": "Second"}}]}\n'
              'data: {"id": "3", "choices": [{"index": 0, "delta": {"content": "Third"}}]}\n',
        ];

        final events = await executeStream(chunks);
        expect(events.length, 3);
        expect(events[0].choices?[0].delta.content, 'First');
        expect(events[1].choices?[0].delta.content, 'Second');
        expect(events[2].choices?[0].delta.content, 'Third');
      });

      test('processes chunks cleanly when each chunk ends with a newline',
          () async {
        final chunks = [
          'data: {"id": "1", "choices": [{"index": 0, "delta": {"content": "Line1"}}]}\n',
          'data: {"id": "2", "choices": [{"index": 0, "delta": {"content": "Line2"}}]}\n',
          'data: [DONE]\n',
        ];

        final events = await executeStream(chunks);
        expect(events.length, 2);
        expect(events[0].choices?[0].delta.content, 'Line1');
        expect(events[1].choices?[0].delta.content, 'Line2');
      });

      test(
          'flushes trailing partialLine when stream ends without newline (Requirement 4)',
          () async {
        final chunks = [
          'data: {"id": "1", "choices": [{"index": 0, "delta": {"content": "Line1"}}]}\n',
          'data: {"id": "final", "choices": [{"index": 0, "delta": {"content": "Tail"}}]}', // NO trailing \n
        ];

        final events = await executeStream(chunks);
        expect(events.length, 2);
        expect(events[0].choices?[0].delta.content, 'Line1');
        expect(events[1].choices?[0].delta.content, 'Tail');
      });

      test('handles mixed chunk fragmentation with multiple lines and [DONE]',
          () async {
        final chunks = [
          'data: {"id": "1", "choices": [{"index": 0, "delta": {"content": "A"}}]}\ndata: {"id": "2", "choi',
          'ces": [{"index": 0, "delta": {"content": "B"}}]}\ndata: [DO',
          'NE]\n',
        ];

        final events = await executeStream(chunks);
        expect(events.length, 2);
        expect(events[0].choices?[0].delta.content, 'A');
        expect(events[1].choices?[0].delta.content, 'B');
      });

      test('handles CRLF line endings split across chunks', () async {
        final chunks = [
          'data: {"id": "1", "choices": [{"index": 0, "delta": {"content": "crlf1"}}]}\r',
          '\ndata: {"id": "2", "choices": [{"index": 0, "delta": {"content": "crlf2"}}]}\r\n',
        ];

        final events = await executeStream(chunks);
        expect(events.length, 2);
        expect(events[0].choices?[0].delta.content, 'crlf1');
        expect(events[1].choices?[0].delta.content, 'crlf2');
      });

      test('skips malformed JSON line and preserves subsequent valid lines',
          () async {
        final chunks = [
          'data: {corrupt json}\n'
              'data: {"id": "valid", "choices": [{"index": 0, "delta": {"content": "ok"}}]}\n',
        ];

        final events = await executeStream(chunks);
        expect(events.length, 1);
        expect(events[0].choices?[0].delta.content, 'ok');
      });

      test('throws Exception when HTTP response status is not 200', () async {
        final client = MockClient(
          (request) async => http.Response('Server Error', 500),
        );
        final controller = StreamController<openai.ChatStreamEvent>();

        expect(
          () => service.streamWithCustomBody(
            config: config,
            requestBody: {'model': 'llama3'},
            controller: controller,
            httpClient: client,
          ),
          throwsA(
            predicate(
              (e) => e is Exception && e.toString().contains('500'),
            ),
          ),
        );
      });

      test(
          'throws Exception when single chunk exceeds maxSseLineLength without newline',
          () async {
        final hugeChunk = 'x' * (OpenAIStreamService.maxSseLineLength + 1);
        final client = MockClient.streaming((request, body) async {
          final stream = Stream.value(utf8.encode(hugeChunk));
          return http.StreamedResponse(stream, 200);
        });
        final controller = StreamController<openai.ChatStreamEvent>();

        expect(
          () => service.streamWithCustomBody(
            config: config,
            requestBody: {'model': 'llama3'},
            controller: controller,
            httpClient: client,
          ),
          throwsA(
            predicate(
              (e) =>
                  e is Exception &&
                  e.toString().contains('AI 响应单行超过') &&
                  e.toString().contains(
                        '${OpenAIStreamService.maxSseLineLength}',
                      ),
            ),
          ),
        );
      });

      test(
          'throws Exception when cumulative chunks without newline exceed maxSseLineLength',
          () async {
        final half = OpenAIStreamService.maxSseLineLength ~/ 2 + 10;
        final client = MockClient.streaming((request, body) async {
          final stream = Stream.fromIterable([
            utf8.encode('a' * half),
            utf8.encode('b' * half),
          ]);
          return http.StreamedResponse(stream, 200);
        });
        final controller = StreamController<openai.ChatStreamEvent>();

        expect(
          () => service.streamWithCustomBody(
            config: config,
            requestBody: {'model': 'llama3'},
            controller: controller,
            httpClient: client,
          ),
          throwsA(
            predicate(
              (e) =>
                  e is Exception &&
                  e.toString().contains('AI 响应单行超过') &&
                  e.toString().contains(
                        '${OpenAIStreamService.maxSseLineLength}',
                      ),
            ),
          ),
        );
      });
    });
  });
}
