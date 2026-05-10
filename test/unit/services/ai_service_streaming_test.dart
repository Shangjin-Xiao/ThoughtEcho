import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';

/// Tests for AIService streaming migration verification
///
/// These tests verify the OpenAIStreamService infrastructure that AIService
/// now delegates to, ensuring:
/// 1. URL construction handles all provider formats (VAL-NONSTREAM-001, VAL-NONSTREAM-003)
/// 2. Stream conversion from ChatStreamEvent to String works (VAL-STREAM-003)
/// 3. Thinking callbacks work (VAL-THINK-001, VAL-THINK-002)
/// 4. Error handling works (VAL-ERR-001, VAL-ERR-002, VAL-ERR-003, VAL-ERR-004)
/// 5. Non-streaming requests work (VAL-NONSTREAM-002)
///
/// Note: The pre-existing test file openai_stream_service_test.dart
/// covers the core OpenAIStreamService unit tests.
/// This file specifically validates the migration contract.
void main() {
  group('AIService Streaming Migration', () {
    group(
        'URL normalization — all provider formats '
        '(VAL-NONSTREAM-001, VAL-NONSTREAM-003, VAL-ERR-001)', () {
      test('bare host URL gets /v1 appended', () {
        const url = 'http://192.168.1.100:8080';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://192.168.1.100:8080/v1');
      });

      test('URL with /v1 path is preserved without doubling', () {
        const url = 'http://192.168.1.100:8080/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://192.168.1.100:8080/v1');
        expect(result, isNot('http://192.168.1.100:8080/v1/v1'));
      });

      test(
          'URL with /v1/chat/completions strips endpoint suffix '
          '(no 405 error)', () {
        const url = 'http://192.168.1.100:8080/v1/chat/completions';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://192.168.1.100:8080/v1');
      });

      test('Ollama localhost:11434/v1 is preserved', () {
        const url = 'http://localhost:11434/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'http://localhost:11434/v1');
      });

      test('DeepSeek URL with /v1/chat/completions is normalized', () {
        const url = 'https://api.deepseek.com/v1/chat/completions';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.deepseek.com/v1');
      });

      test('OpenRouter /api/v1 path is preserved', () {
        const url = 'https://openrouter.ai/api/v1';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://openrouter.ai/api/v1');
      });

      test('bare host DeepSeek gets /v1 appended', () {
        const url = 'https://api.deepseek.com';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.deepseek.com/v1');
      });

      test('trailing slash after /v1 is stripped', () {
        const url = 'https://api.openai.com/v1/';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.openai.com/v1');
      });

      test('OpenAI full endpoint URL is normalized', () {
        const url = 'https://api.openai.com/v1/chat/completions';
        final result = OpenAIStreamService.normalizeOpenAIBaseUrl(url);
        expect(result, 'https://api.openai.com/v1');
      });

      test('throws FormatException for empty URL', () {
        expect(
          () => OpenAIStreamService.normalizeOpenAIBaseUrl(''),
          throwsFormatException,
        );
      });

      test('throws FormatException for invalid URL', () {
        expect(
          () => OpenAIStreamService.normalizeOpenAIBaseUrl('not a url'),
          throwsFormatException,
        );
      });
    });

    group('Config construction (VAL-STREAM-003)', () {
      test('preserves API key for OpenAI', () {
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);
        expect(config.baseUrl, 'https://api.openai.com/v1');
        expect(config.authProvider, isNotNull);
      });

      test('no auth for Ollama (empty API key)', () {
        const provider = AIProviderSettings(
          id: 'ollama',
          name: 'Ollama',
          apiKey: '',
          apiUrl: 'http://localhost:11434/v1',
          model: 'llama3',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);
        expect(config.baseUrl, 'http://localhost:11434/v1');
        expect(config.authProvider, isNull);
      });

      test('adds custom headers for OpenRouter', () {
        const provider = AIProviderSettings(
          id: 'openrouter',
          name: 'OpenRouter',
          apiKey: 'or-key',
          apiUrl: 'https://openrouter.ai/api/v1',
          model: 'meta-llama/llama-3.1-8b-instruct:free',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);
        expect(config.baseUrl, 'https://openrouter.ai/api/v1');
        expect(config.defaultHeaders.containsKey('HTTP-Referer'), isTrue);
        expect(config.defaultHeaders.containsKey('X-Title'), isTrue);
      });

      test('removes Content-Type from headers (openai_dart handles it)', () {
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
        );

        final config = OpenAIStreamService.buildOpenAIConfig(provider);
        expect(config.defaultHeaders.containsKey('Content-Type'), isFalse);
        expect(config.defaultHeaders.containsKey('content-type'), isFalse);
      });
    });

    group('Chat request building (VAL-STREAM-003)', () {
      test('builds request with messages and parameters', () {
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
          temperature: 0.7,
          maxTokens: 2000,
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
        expect(request.temperature, 0.7);
      });

      test('custom temperature overrides provider default', () {
        const provider = AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiKey: 'sk-test',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
          temperature: 0.7,
        );

        final request = OpenAIStreamService.buildChatRequest(
          provider: provider,
          messages: [openai.ChatMessage.user('Hello!')],
          temperature: 0.3,
        );

        expect(request.temperature, 0.3);
      });
    });

    group('Stream processing (VAL-STREAM-003, VAL-THINK-001)', () {
      test('converts text deltas to Stream<String>', () async {
        final events = [
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
        ];

        final result = await OpenAIStreamService.processStreamToText(
          Stream.fromIterable(events),
        ).toList();
        expect(result, ['Hello', ' world']);
      });

      test(
          'invokes onThinking for reasoning_content '
          '(VAL-THINK-001, passive detection)', () async {
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(
                  reasoningContent: 'Let me think...',
                ),
              ),
            ],
          ),
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: 'Answer.'),
              ),
            ],
          ),
        ];

        final thinkingChunks = <String>[];
        final textChunks = <String>[];

        await for (final chunk in OpenAIStreamService.processStreamToText(
          Stream.fromIterable(events),
          onThinking: (thinking) {
            thinkingChunks.add(thinking);
          },
        )) {
          textChunks.add(chunk);
        }

        expect(thinkingChunks, ['Let me think...']);
        expect(textChunks, ['Answer.']);
      });

      test('invokes onThinking for reasoning field (alternate format)',
          () async {
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(reasoning: 'Reasoning...'),
              ),
            ],
          ),
        ];

        final thinkingChunks = <String>[];

        await OpenAIStreamService.processStreamToText(
          Stream.fromIterable(events),
          onThinking: (thinking) {
            thinkingChunks.add(thinking);
          },
        ).toList();

        expect(thinkingChunks, ['Reasoning...']);
      });

      test('handles empty content gracefully (VAL-ERR-003)', () async {
        final events = [
          const openai.ChatStreamEvent(
            id: 'chatcmpl-1',
            choices: [
              openai.ChatStreamChoice(
                index: 0,
                delta: openai.ChatDelta(content: ''),
              ),
            ],
          ),
        ];

        final result = await OpenAIStreamService.processStreamToText(
          Stream.fromIterable(events),
        ).toList();
        expect(result, isEmpty);
      });

      test('handles null choices gracefully', () async {
        const event = openai.ChatStreamEvent(id: 'chatcmpl-1');
        final result = await OpenAIStreamService.processStreamToText(
          Stream.fromIterable([event]),
        ).toList();
        expect(result, isEmpty);
      });

      test('propagates stream errors (VAL-ERR-004)', () async {
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

    group('ChatCompletion (VAL-NONSTREAM-001, VAL-NONSTREAM-002)', () {
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

      test('returns empty string for no choices', () {
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

      test('returns empty string for null content', () {
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
  });
}
