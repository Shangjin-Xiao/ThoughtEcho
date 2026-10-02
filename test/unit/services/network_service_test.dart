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

class TestHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) fetchHandler;

  TestHttpClientAdapter(this.fetchHandler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return fetchHandler(options);
  }

  @override
  void close({bool force = false}) {}
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

  group('NetworkService Initialization and Lifecycle Tests', () {
    test('init() should initialize service and create Dio instances', () async {
      final service = NetworkService.instance;
      await service.init();

      expect(service.isInitializedForTesting, isTrue);
      expect(service.generalDioForTesting, isNotNull);
      expect(service.aiDioForTesting, isNotNull);

      // Re-initializing should be safe and idempotent
      await service.init();
      expect(service.isInitializedForTesting, isTrue);
    });

    test('calling get or post when uninitialized should throw StateError',
        () async {
      final service = NetworkService.instance;
      service.dispose();

      expect(service.isInitializedForTesting, isFalse);

      expect(
        () => service.get('https://example.com'),
        throwsStateError,
      );

      expect(
        () => service.post('https://example.com'),
        throwsStateError,
      );

      expect(
        () => service.aiRequest(
          url: 'https://api.openai.com/v1/chat/completions',
          data: {},
        ),
        throwsStateError,
      );

      // Re-initialize for subsequent tests
      await service.init();
    });

    test('dispose() should close Dio instances and reset initialization flag',
        () async {
      final service = NetworkService.instance;
      await service.init();
      expect(service.isInitializedForTesting, isTrue);

      service.dispose();
      expect(service.isInitializedForTesting, isFalse);

      // Re-initialize for subsequent tests
      await service.init();
    });
  });

  group('NetworkService GET and POST Tests', () {
    late NetworkService networkService;

    setUp(() async {
      networkService = NetworkService.instance;
      await networkService.init();
    });

    test('get() should make GET request and return HttpResponse', () async {
      networkService.generalDioForTesting.httpClientAdapter =
          TestHttpClientAdapter(
        (options) async {
          expect(options.method, 'GET');
          expect(options.uri.toString(), 'https://example.com/data');
          expect(options.headers['X-Test-Header'], 'test-value');

          return ResponseBody.fromString(
            'hello world',
            200,
            headers: {
              'content-type': ['text/plain'],
            },
          );
        },
      );

      final response = await networkService.get(
        'https://example.com/data',
        headers: {'X-Test-Header': 'test-value'},
      );

      expect(response.statusCode, 200);
      expect(response.body, 'hello world');
      expect(response.headers['content-type'], 'text/plain');
    });

    test('get() should properly handle Hitokoto API responses', () async {
      networkService.generalDioForTesting.httpClientAdapter =
          TestHttpClientAdapter(
        (options) async {
          expect(options.uri.toString(), contains('hitokoto.cn'));
          return ResponseBody.fromString(
            '{"hitokoto": "hello"}',
            200,
            headers: {
              'content-type': ['application/json'],
            },
          );
        },
      );

      final response = await networkService.get('https://v1.hitokoto.cn/');

      expect(response.statusCode, 200);
      expect(response.body, contains('hitokoto'));
    });

    test('get() should catch DioException and return error HttpResponse',
        () async {
      networkService.generalDioForTesting.httpClientAdapter =
          TestHttpClientAdapter(
        (options) async {
          throw DioException(
            requestOptions: options,
            message: 'Connection failed',
            response: Response(
              requestOptions: options,
              statusCode: 503,
            ),
          );
        },
      );

      final response = await networkService.get('https://example.com/fail');

      expect(response.statusCode, 503);
      expect(response.body, contains('Connection failed'));
    });

    test('post() should throw exception for non-HTTPS URLs', () async {
      expect(
        () => networkService
            .post('http://example.com/post', body: {'key': 'val'}),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('非安全URL'),
        )),
      );
    });

    test('post() should send POST request with body and return HttpResponse',
        () async {
      networkService.generalDioForTesting.httpClientAdapter =
          TestHttpClientAdapter(
        (options) async {
          expect(options.method, 'POST');
          expect(options.uri.toString(), 'https://example.com/api');
          expect(options.data, equals({'key': 'value'}));

          return ResponseBody.fromString(
            '{"status": "ok"}',
            201,
            headers: {
              'content-type': ['application/json'],
            },
          );
        },
      );

      final response = await networkService.post(
        'https://example.com/api',
        body: {'key': 'value'},
      );

      expect(response.statusCode, 201);
      expect(response.body, contains('status'));
    });

    test('post() should catch DioException and return error HttpResponse',
        () async {
      networkService.generalDioForTesting.httpClientAdapter =
          TestHttpClientAdapter(
        (options) async {
          throw DioException(
            requestOptions: options,
            message: 'Server error',
            response: Response(
              requestOptions: options,
              statusCode: 500,
            ),
          );
        },
      );

      final response = await networkService.post('https://example.com/error');

      expect(response.statusCode, 500);
      expect(response.body, contains('Server error'));
    });
  });

  group('NetworkService AI Request Data Adjustment Tests', () {
    late NetworkService networkService;

    setUp(() {
      networkService = NetworkService.instance;
    });

    test('should convert string "true" stream parameter to boolean true', () {
      final inputData = {'stream': 'true', 'prompt': 'hello'};
      final adjusted =
          networkService.adjustAIDataForTesting(inputData, null, null);

      expect(adjusted['stream'], isTrue);
    });

    test('should default non-bool stream parameter to true', () {
      final inputData = {'stream': 123, 'prompt': 'hello'};
      final adjusted =
          networkService.adjustAIDataForTesting(inputData, null, null);

      expect(adjusted['stream'], isTrue);
    });

    test('should populate provider default model, temperature, and max_tokens',
        () {
      final provider = AIProviderSettings(
        id: 'p1',
        name: 'Provider1',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        apiKey: 'key',
        model: 'gpt-4o',
        temperature: 0.7,
        maxTokens: 2000,
      );

      final inputData = <String, dynamic>{'messages': []};
      final adjusted =
          networkService.adjustAIDataForTesting(inputData, provider, null);

      expect(adjusted['model'], 'gpt-4o');
      expect(adjusted['temperature'], 0.7);
      expect(adjusted['max_tokens'], 2000);
    });

    test('should preserve existing model in input data if provided', () {
      final provider = AIProviderSettings(
        id: 'p1',
        name: 'Provider1',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        apiKey: 'key',
        model: 'gpt-4o',
      );

      final inputData = <String, dynamic>{
        'model': 'custom-model',
        'messages': [],
      };
      final adjusted =
          networkService.adjustAIDataForTesting(inputData, provider, null);

      expect(adjusted['model'], 'custom-model');
    });

    test('should fallback to legacy settings if provider is null', () {
      final legacy = AISettings(
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        apiKey: 'key',
        model: 'gpt-3.5-turbo',
        temperature: 0.5,
        maxTokens: 1000,
      );

      final inputData = <String, dynamic>{'messages': []};
      final adjusted =
          networkService.adjustAIDataForTesting(inputData, null, legacy);

      expect(adjusted['model'], 'gpt-3.5-turbo');
      expect(adjusted['temperature'], 0.5);
      expect(adjusted['max_tokens'], 1000);
    });
  });

  group('NetworkService AI Request and Stream Request Tests', () {
    late NetworkService networkService;

    setUp(() async {
      networkService = NetworkService.instance;
      await networkService.init();
    });

    test('aiRequest() should send POST request with adjusted headers and data',
        () async {
      final provider = AIProviderSettings(
        id: 'p1',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        apiKey: 'sk-test',
        model: 'gpt-4o',
      );

      networkService.aiDioForTesting.httpClientAdapter = TestHttpClientAdapter(
        (options) async {
          expect(options.method, 'POST');
          expect(options.headers['Authorization'], 'Bearer sk-test');
          expect(options.data['model'], 'gpt-4o');

          return ResponseBody.fromString(
            '{"choices": [{"message": {"content": "Hello AI"}}]}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          );
        },
      );

      final response = await networkService.aiRequest(
        url: 'https://api.openai.com/v1/chat/completions',
        data: {'messages': []},
        provider: provider,
      );

      expect(response.statusCode, 200);
      expect(response.data['choices'][0]['message']['content'], 'Hello AI');
    });

    test(
        'aiStreamRequest() should process OpenAI SSE stream chunks and trigger callbacks',
        () async {
      networkService.aiDioForTesting.httpClientAdapter = TestHttpClientAdapter(
        (options) async {
          expect(options.data['stream'], isTrue);

          final streamData = [
            'data: {"choices":[{"delta":{"content":"Hello"}}]}\n',
            'data: {"choices":[{"delta":{"content":" World"}}]}\n',
            'data: [DONE]\n',
          ].join('');

          return ResponseBody.fromString(
            streamData,
            200,
            headers: {
              'content-type': ['text/event-stream']
            },
          );
        },
      );

      final receivedChunks = <String>[];
      String? completedBuffer;

      await networkService.aiStreamRequest(
        url: 'https://api.openai.com/v1/chat/completions',
        data: {},
        onData: (chunk) => receivedChunks.add(chunk),
        onComplete: (fullText) => completedBuffer = fullText,
        onError: (err) => fail('Should not encounter error: $err'),
      );

      expect(receivedChunks, ['Hello', ' World']);
      expect(completedBuffer, 'Hello World');
    });

    test('aiStreamRequest() should process Anthropic stream chunks', () async {
      networkService.aiDioForTesting.httpClientAdapter = TestHttpClientAdapter(
        (options) async {
          final streamData = [
            'data: {"delta":{"text":"Anthropic "}}\n',
            'data: {"delta":{"text":"Response"}}\n',
            'data: [DONE]\n',
          ].join('');

          return ResponseBody.fromString(
            streamData,
            200,
            headers: {
              'content-type': ['text/event-stream']
            },
          );
        },
      );

      final receivedChunks = <String>[];
      String? completedBuffer;

      await networkService.aiStreamRequest(
        url: 'https://api.anthropic.com/v1/messages',
        data: {},
        onData: (chunk) => receivedChunks.add(chunk),
        onComplete: (fullText) => completedBuffer = fullText,
        onError: (err) => fail('Should not fail: $err'),
      );

      expect(receivedChunks, ['Anthropic ', 'Response']);
      expect(completedBuffer, 'Anthropic Response');
    });

    test(
        'aiStreamRequest() should invoke onError callback when exception occurs',
        () async {
      networkService.aiDioForTesting.httpClientAdapter = TestHttpClientAdapter(
        (options) async {
          throw DioException(
            requestOptions: options,
            message: 'Stream connection dropped',
          );
        },
      );

      Exception? capturedError;

      await networkService.aiStreamRequest(
        url: 'https://api.openai.com/v1/chat/completions',
        data: {},
        onData: (_) {},
        onComplete: (_) {},
        onError: (err) => capturedError = err,
      );

      expect(capturedError, isNotNull);
      expect(capturedError.toString(), contains('AI流式请求失败'));
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
          contains('非安全URL'),
        )),
      );
    });

    // 「本地明文端点要放行」不在这里断言：判据一旦放行，`aiRequest` 就会真的去连
    // http://127.0.0.1:1234，撞上重试退避直接把用例拖超时。那条规则由
    // `test/unit/utils/ai_endpoint_security_test.dart` 覆盖（纯函数，不碰网络），
    // 接线由下面这条「公网明文被拦」和设置页那条 localhost 夹具用例共同证明。

    test('aiRequest should allow uppercase HTTPS URL scheme', () async {
      try {
        await networkService.aiRequest(
          url: 'HTTPS://api.openai.com/v1/chat/completions',
          data: {},
        );
      } catch (e) {
        expect(e.toString(), isNot(contains('非安全URL')));
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
        contains('非安全URL'),
      );
    });
  });
}
