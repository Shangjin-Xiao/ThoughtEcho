import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

enum _RequestMode { completion, streaming, ollamaThinking, agent }

const _apiKey = 'synthetic-endpoint-test-key';
const _message = 'Synthetic private message';

void main() {
  late SettingsService settings;
  late List<http.Request> requests;

  setUp(() async {
    await TestHarness.initialize();
    settings = await SettingsService.create();
    await APIKeyManager().saveProviderApiKey('ollama', _apiKey);
    requests = [];
    addTearDown(settings.dispose);
  });

  Future<String> sendRestoredRequest(_RequestMode mode, String url) async {
    // Restore a URL without a key, reusing the device's existing secure key.
    // This bypasses the editor validator just as it does in production.
    await settings.restoreAllSettingsFromBackup({
      'multi_ai_settings': {
        'currentProviderId': 'ollama',
        'providers': [
          {
            'id': 'ollama',
            'name': 'Synthetic provider',
            'apiUrl': url,
            'apiKey': _apiKey,
            'model': 'test-model',
          },
        ],
      },
    });
    final restored = settings.multiAISettings.currentProvider!;
    final provider = restored.copyWith(
      apiKey: await APIKeyManager().getProviderApiKey(restored.id),
    );
    expect(provider.apiKey, _apiKey);

    final client = MockClient((request) async {
      requests.add(request);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final streaming = body['stream'] == true;
      final response = jsonEncode({
        'id': 'synthetic-completion',
        'object': 'chat.completion',
        'created': 0,
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            if (streaming)
              'delta': {'content': 'Synthetic response'}
            else
              'message': {'role': 'assistant', 'content': 'Synthetic response'},
            'finish_reason': 'stop',
          },
        ],
      });
      return http.Response(
        streaming ? 'data: $response\n\ndata: [DONE]\n\n' : response,
        200,
        headers: {
          'content-type': streaming ? 'text/event-stream' : 'application/json',
        },
      );
    });
    addTearDown(client.close);

    return http.runWithClient(() async {
      if (mode == _RequestMode.agent) {
        final agent = AgentService(settingsService: settings, tools: []);
        addTearDown(agent.dispose);
        return (await agent.runAgent(userMessage: _message)).content;
      }
      final service = OpenAIStreamService();
      addTearDown(service.dispose);
      final messages = [openai.ChatMessage.user(_message)];
      return switch (mode) {
        _RequestMode.completion => service.chatCompletion(
          provider: provider,
          messages: messages,
        ),
        _RequestMode.streaming =>
          service.streamChat(provider: provider, messages: messages).join(),
        _RequestMode.ollamaThinking =>
          service
              .streamChatWithThinking(
                provider: provider,
                messages: messages,
                enableThinking: true,
              )
              .join(),
        _RequestMode.agent => throw StateError('Handled above'),
      };
    }, () => client);
  }

  for (final mode in _RequestMode.values) {
    test('${mode.name} blocks restored public HTTP before transport', () async {
      Object? failure;
      try {
        await sendRestoredRequest(
          mode,
          'http://public.example/v1/chat/completions',
        );
      } catch (error) {
        failure = error;
      }

      expect(
        requests,
        isEmpty,
        reason: 'Credentials and private messages must not reach transport',
      );
      expect(failure, isA<FormatException>());
    });

    for (final baseUrl in [
      'https://public.example/v1',
      'http://127.0.0.1:11434/v1',
      'http://192.168.1.10:11434/v1',
    ]) {
      test('${mode.name} sends to allowed endpoint $baseUrl', () async {
        expect(
          await sendRestoredRequest(mode, '$baseUrl/chat/completions'),
          'Synthetic response',
        );
        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.url.toString(), '$baseUrl/chat/completions');
        expect(request.headers['authorization'], 'Bearer $_apiKey');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(
          body['messages'],
          contains(equals({'role': 'user', 'content': _message})),
        );
        if (mode == _RequestMode.ollamaThinking) {
          expect(body['think'], isTrue);
        }
      });
    }
  }
}
