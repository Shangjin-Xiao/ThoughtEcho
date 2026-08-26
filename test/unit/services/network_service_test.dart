import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/ai_settings.dart';

class MockErrorInterceptorHandler extends ErrorInterceptorHandler {
  DioException? passedError;

  @override
  void next(DioException err) {
    passedError = err;
  }
}

void main() {
  group('RetryInterceptor Tests', () {
    test(
        'should handle null or missing retryCount safely without throwing TypeError',
        () async {
      final dio = Dio();
      final interceptor = RetryInterceptor(dio: dio, retries: 0);

      final requestOptions = RequestOptions(path: 'https://example.com');
      // extra['retryCount'] is null / omitted intentionally
      final err = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );
      final handler = MockErrorInterceptorHandler();

      interceptor.onError(err, handler);

      expect(requestOptions.extra['retryCount'], 0);
      expect(handler.passedError, equals(err));
    });

    test('should handle non-int numeric retryCount safely', () async {
      final dio = Dio();
      final interceptor = RetryInterceptor(dio: dio, retries: 0);

      final requestOptions = RequestOptions(
        path: 'https://example.com',
        extra: {'retryCount': 1.0},
      );
      final err = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );
      final handler = MockErrorInterceptorHandler();

      interceptor.onError(err, handler);

      expect(requestOptions.extra['retryCount'], 1);
      expect(handler.passedError, equals(err));
    });

    test('should handle unexpected type in retryCount safely as 0', () async {
      final dio = Dio();
      final interceptor = RetryInterceptor(dio: dio, retries: 0);

      final requestOptions = RequestOptions(
        path: 'https://example.com',
        extra: {'retryCount': 'invalid_string'},
      );
      final err = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );
      final handler = MockErrorInterceptorHandler();

      interceptor.onError(err, handler);

      expect(requestOptions.extra['retryCount'], 0);
      expect(handler.passedError, equals(err));
    });
  });

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
  });

  group('NetworkService Security Validation Tests', () {
    late NetworkService networkService;

    setUp(() async {
      networkService = NetworkService.instance;
      await networkService.init();
    });

    test('aiRequest should throw exception when URL is not HTTPS', () async {
      expect(
        () => networkService.aiRequest(
          url: 'http://api.openai.com/v1/chat/completions',
          data: {},
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'description',
          contains('非安全URL: 所有请求必须使用HTTPS'),
        )),
      );
    });

    test('aiRequest should allow uppercase HTTPS URL scheme', () async {
      try {
        await networkService.aiRequest(
          url: 'HTTPS://api.openai.com/v1/chat/completions',
          data: {},
        );
      } catch (e) {
        expect(e.toString(), isNot(contains('非安全URL: 所有请求必须使用HTTPS')));
      }
    });

    test('aiStreamRequest should call onError when URL is not HTTPS', () async {
      Exception? capturedError;
      await networkService.aiStreamRequest(
        url: 'http://api.openai.com/v1/chat/completions',
        data: {},
        onData: (_) {},
        onComplete: (_) {},
        onError: (err) {
          capturedError = err;
        },
      );

      expect(capturedError, isNotNull);
      expect(
        capturedError.toString(),
        contains('非安全URL: 所有请求必须使用HTTPS'),
      );
    });
  });
}
