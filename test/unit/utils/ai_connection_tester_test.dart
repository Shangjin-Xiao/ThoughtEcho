import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/ai_connection_tester.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';

void main() {
  group('AIConnectionTester', () {
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
