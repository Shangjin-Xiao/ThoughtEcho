import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/ai_settings.dart';

void main() {
  group('NetworkService AI Headers Tests', () {
    late NetworkService networkService;

    setUp(() {
      networkService = NetworkService.instance;
    });

    test(
        'should build default headers when both provider and legacy settings are null',
        () {
      final headers = networkService.buildAIHeadersForTesting(null, null);

      expect(headers, isA<Map<String, String>>());
      expect(headers.length, 1);
      expect(headers['Content-Type'], 'application/json');
    });

    test('should build headers for Anthropic provider', () {
      final provider = AIProviderSettings(
        id: 'test_anthropic',
        name: 'Anthropic',
        apiUrl: 'https://api.anthropic.com/v1/messages',
        apiKey: 'test-anthropic-key',
        model: 'claude-3-haiku-20240307',
      );

      final headers = networkService.buildAIHeadersForTesting(provider, null);

      expect(headers.length, 3);
      expect(headers['Content-Type'], 'application/json');
      expect(headers['anthropic-version'], '2023-06-01');
      expect(headers['x-api-key'], 'test-anthropic-key');
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('should build headers for OpenRouter provider', () {
      final provider = AIProviderSettings(
        id: 'test_openrouter',
        name: 'OpenRouter',
        apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
        apiKey: 'test-openrouter-key',
        model: 'openai/gpt-3.5-turbo',
      );

      final headers = networkService.buildAIHeadersForTesting(provider, null);

      expect(headers.length, 4);
      expect(headers['Content-Type'], 'application/json');
      expect(headers['Authorization'], 'Bearer test-openrouter-key');
      expect(headers['HTTP-Referer'], 'https://thoughtecho.app');
      expect(headers['X-Title'], 'ThoughtEcho App');
    });

    test('should build headers for standard provider (like OpenAI)', () {
      final provider = AIProviderSettings(
        id: 'test_openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        apiKey: 'test-openai-key',
        model: 'gpt-3.5-turbo',
      );

      final headers = networkService.buildAIHeadersForTesting(provider, null);

      expect(headers.length, 2);
      expect(headers['Content-Type'], 'application/json');
      expect(headers['Authorization'], 'Bearer test-openai-key');
    });

    test('should build headers using legacy settings if provider is null', () {
      final legacySettings = AISettings(
        apiUrl: 'https://legacy.api.com',
        apiKey: 'test-legacy-key',
        model: 'legacy-model',
      );

      final headers =
          networkService.buildAIHeadersForTesting(null, legacySettings);

      expect(headers.length, 2);
      expect(headers['Content-Type'], 'application/json');
      expect(headers['Authorization'], 'Bearer test-legacy-key');
    });

    test('should prioritize provider settings over legacy settings', () {
      final provider = AIProviderSettings(
        id: 'test_openai2',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        apiKey: 'test-openai-key',
        model: 'gpt-3.5-turbo',
      );

      final legacySettings = AISettings(
        apiUrl: 'https://legacy.api.com',
        apiKey: 'test-legacy-key',
        model: 'legacy-model',
      );

      final headers =
          networkService.buildAIHeadersForTesting(provider, legacySettings);

      expect(headers.length, 2);
      expect(headers['Content-Type'], 'application/json');
      expect(headers['Authorization'],
          'Bearer test-openai-key'); // Uses provider key
    });
    test('should sanitize DioException headers and payload', () {
      final requestOptions = RequestOptions(
        path: '/test',
        headers: {
          'Authorization': 'Bearer test-token',
          'x-api-key': 'test-api-key',
          'Content-Type': 'application/json',
        },
        data: {'secret': 'request data'},
      );

      final response = Response(
        requestOptions: requestOptions,
        data: {'sensitive': 'response data'},
        statusCode: 400,
      );

      final dioException = DioException(
        requestOptions: requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Test error',
      );

      final sanitizedError =
          networkService.sanitizeErrorForTesting(dioException);

      expect(sanitizedError, isA<DioException>());
      final sanitizedDioException = sanitizedError as DioException;

      expect(
          sanitizedDioException.requestOptions.headers['Authorization'], '***');
      expect(sanitizedDioException.requestOptions.headers['x-api-key'], '***');
      expect(sanitizedDioException.requestOptions.headers['Content-Type'],
          'application/json');

      expect(sanitizedDioException.requestOptions.data,
          '***[Masked Request Data]***');
      expect(
          sanitizedDioException.response?.data, '***[Masked Response Data]***');

      expect(sanitizedDioException.response?.statusCode, 400);
      expect(sanitizedDioException.message, 'Test error');
      expect(sanitizedDioException.type, DioExceptionType.badResponse);
    });
  });
}
