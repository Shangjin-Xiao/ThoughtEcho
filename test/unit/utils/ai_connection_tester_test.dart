import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thoughtecho/utils/ai_connection_tester.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/services/api_key_manager.dart';

import '../../test_harness.dart';

void main() {
  group('AIConnectionTester', () {
    tearDown(() {
      AIConnectionTester.testOverrideForTesting = null;
    });

    for (final draftKey in ['', 'synthetic-draft-key']) {
      test(
          'changed destination uses the ${draftKey.isEmpty ? 'empty' : 'entered'} '
          'draft key without loading the saved key', () async {
        await TestHarness.initialize();
        const storedKey = 'synthetic-stored-key';
        const saved = AIProviderSettings(
          id: 'saved-provider',
          name: 'Saved provider',
          apiUrl: 'https://original.example/v1',
          model: 'test-model',
        );
        await APIKeyManager().saveProviderApiKey(saved.id, storedKey);
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'id': 'test-completion',
              'object': 'chat.completion',
              'created': 0,
              'model': 'test-model',
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': 'pong'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final result = await http.runWithClient(
          () => AIConnectionTester.test(
            provider: saved.copyWith(
              apiUrl: 'https://replacement.example/v1',
              apiKey: draftKey,
            ),
            systemPrompt: 'System',
            userMessage: 'User',
          ),
          () => client,
        );

        expect(result, 'pong');
        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.url,
            Uri.parse('https://replacement.example/v1/chat/completions'));
        expect(request.headers.values, isNot(contains(contains(storedKey))));
        if (draftKey.isNotEmpty) {
          expect(request.headers['authorization'], 'Bearer $draftKey');
        }
        expect(await APIKeyManager().getProviderApiKey(saved.id), storedKey);
      });
    }

    test('testOverrideForTesting allows mocking the test connection', () async {
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration? timeout,
      }) async {
        return 'Mocked response';
      };

      const provider = AIProviderSettings(
        id: 'test_provider',
        name: 'Test',
        apiKey: 'sk-test',
        apiUrl: 'https://api.test.com/v1',
        model: 'test-model',
      );

      final result = await AIConnectionTester.test(
        provider: provider,
        systemPrompt: 'System',
        userMessage: 'User',
      );

      expect(result, 'Mocked response');

      AIConnectionTester.testOverrideForTesting = null;
    });
  });
}
