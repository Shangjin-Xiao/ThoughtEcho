import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/utils/ai_network_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class _FakeUnifiedLogService implements UnifiedLogService {
  final List<Map<String, dynamic>> records = [];

  List<Map<String, dynamic>> get errorRecords =>
      records.where((r) => r['level'] == UnifiedLogLevel.error).toList();

  @override
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.verbose,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.debug,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.info,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.warning,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.error,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void log(
    UnifiedLogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    records.add({
      'level': level,
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDio extends Fake implements Dio {
  final Future<Response<dynamic>> Function(
    String path,
    Object? data,
    Options? options,
  ) onPost;

  final List<String> requestedUrls = [];

  _FakeDio(this.onPost);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    requestedUrls.add(path);
    final res = await onPost(path, data, options);
    return Response<T>(
      requestOptions: res.requestOptions,
      data: res.data as T?,
      statusCode: res.statusCode,
      statusMessage: res.statusMessage,
      headers: res.headers,
      extra: res.extra,
    );
  }
}

void main() {
  late _FakeUnifiedLogService fakeLogService;

  setUp(() {
    fakeLogService = _FakeUnifiedLogService();
    AppLogger.serviceForTesting = fakeLogService;
    AINetworkManager.clearProviderFailures();
  });

  tearDown(() {
    AINetworkManager.clearProviderFailures();
    AINetworkManager.dioInstanceForTesting = null;
    AppLogger.initialize();
  });

  group('AINetworkManager logging and failover', () {
    test(
      'handles non-DioException once without crashing and fails over to next provider',
      () async {
        const primary = AIProviderSettings(
          id: 'p1',
          name: 'Primary',
          apiKey: 'key-1',
          apiUrl: 'https://primary.example.com/v1/chat/completions',
          model: 'gpt-4',
        );
        const backup = AIProviderSettings(
          id: 'p2',
          name: 'Backup',
          apiKey: 'key-2',
          apiUrl: 'https://backup.example.com/v1/chat/completions',
          model: 'gpt-4',
        );

        final fakeDio = _FakeDio((path, data, options) async {
          if (path.contains('primary.example.com')) {
            throw StateError('ordinary non-dio failure');
          }
          return Response<dynamic>(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'ok': true},
          );
        });
        AINetworkManager.dioInstanceForTesting = fakeDio;

        final response = await AINetworkManager.makeRequest(
          url: '',
          data: {
            'messages': [
              {'role': 'user', 'content': 'hello'},
            ],
          },
          multiSettings: const MultiAISettings(
            providers: [primary, backup],
            currentProviderId: 'p1',
            enableFailover: true,
          ),
        );

        expect(response.statusCode, 200);
        expect(response.data, {'ok': true});
        expect(fakeDio.requestedUrls, [
          'https://primary.example.com/v1/chat/completions',
          'https://backup.example.com/v1/chat/completions',
        ]);

        expect(fakeLogService.errorRecords, hasLength(1));
        final errLog = fakeLogService.errorRecords.single;
        expect(errLog['message'], 'AI请求失败 for Primary (p1)');
        expect(errLog['source'], 'AINetworkManager');
        expect(errLog['error'], isA<StateError>());
        expect(errLog['stackTrace'], isNotNull);
      },
    );

    test(
      'streaming onError logs once with stackTrace and requestContext and reuses handled error',
      () async {
        const provider = AIProviderSettings(
          id: 'stream-p1',
          name: 'StreamProvider',
          apiKey: 'key-stream',
          apiUrl: 'https://stream.example.com/v1/chat/completions',
          model: 'gpt-4',
        );

        final expectedStack = StackTrace.fromString('custom-stream-stack');
        final streamDioError = DioException(
          requestOptions: RequestOptions(path: provider.apiUrl),
          type: DioExceptionType.connectionError,
          message: 'stream dropped',
        );

        final controller = StreamController<List<int>>();
        final fakeDio = _FakeDio((path, data, options) async {
          return Response<dynamic>(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: controller.stream,
          );
        });
        AINetworkManager.dioInstanceForTesting = fakeDio;

        final callbackErrors = <Exception>[];
        Object? awaitedError;

        final future = AINetworkManager.makeStreamRequest(
          url: '',
          data: {
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          },
          provider: provider,
          onData: (_) {},
          onComplete: (_) {},
          onError: callbackErrors.add,
        ).catchError((Object e) {
          awaitedError = e;
        });

        // Allow _makeBaseRequest to subscribe, then emit stream error with stackTrace
        await Future<void>.delayed(Duration.zero);
        controller.addError(streamDioError, expectedStack);
        await controller.close();
        await future;

        expect(callbackErrors, hasLength(1));
        expect(awaitedError, same(callbackErrors.single));
        expect(
          callbackErrors.single.toString(),
          contains('网络连接超时，请检查网络设置或稍后重试'),
        );

        expect(fakeLogService.errorRecords, hasLength(1));
        final errLog = fakeLogService.errorRecords.single;
        expect(
          errLog['message'],
          'AI Request Error: Connection/Timeout Error (connectionError) for StreamProvider (stream-p1)',
        );
        expect(errLog['source'], 'AINetworkManager');
        expect(errLog['error'], same(streamDioError));
        expect(errLog['stackTrace'], same(expectedStack));
      },
    );

    test(
      'stream failover logs once per failed provider and succeeds on backup stream',
      () async {
        const primary = AIProviderSettings(
          id: 'sp1',
          name: 'StreamPrimary',
          apiKey: 'key-1',
          apiUrl: 'https://stream1.example.com/v1/chat/completions',
          model: 'gpt-4',
        );
        const backup = AIProviderSettings(
          id: 'sp2',
          name: 'StreamBackup',
          apiKey: 'key-2',
          apiUrl: 'https://stream2.example.com/v1/chat/completions',
          model: 'gpt-4',
        );

        final fakeDio = _FakeDio((path, data, options) async {
          if (path.contains('stream1.example.com')) {
            throw FormatException('bad primary stream setup');
          }
          final chunk = utf8.encode(
            'data: {"choices":[{"delta":{"content":"ok"}}]}\n'
            'data: [DONE]\n',
          );
          return Response<dynamic>(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: Stream<List<int>>.fromIterable([chunk]),
          );
        });
        AINetworkManager.dioInstanceForTesting = fakeDio;

        final chunks = <String>[];
        String? completed;
        final errors = <Exception>[];

        await AINetworkManager.makeStreamRequest(
          url: '',
          data: {
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          },
          multiSettings: const MultiAISettings(
            providers: [primary, backup],
            currentProviderId: 'sp1',
            enableFailover: true,
          ),
          onData: chunks.add,
          onComplete: (full) => completed = full,
          onError: errors.add,
        );

        expect(chunks, ['ok']);
        expect(completed, 'ok');
        expect(errors, isEmpty);
        expect(fakeLogService.errorRecords, hasLength(1));
        expect(
          fakeLogService.errorRecords.single['message'],
          'AI请求失败 for StreamPrimary (sp1)',
        );
      },
    );

    test(
      'includes requestContext suffix when 500 error body JSON parsing fails',
      () async {
        const provider = AIProviderSettings(
          id: 'p500',
          name: 'BrokenServer',
          apiKey: 'key-500',
          apiUrl: 'https://broken.example.com/v1/chat/completions',
          model: 'gpt-4',
        );

        final fakeDio = _FakeDio((path, data, options) async {
          final reqOptions = RequestOptions(path: path);
          throw DioException(
            requestOptions: reqOptions,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: reqOptions,
              statusCode: 500,
              data: 'not-json-body',
            ),
          );
        });
        AINetworkManager.dioInstanceForTesting = fakeDio;

        Object? thrown;
        try {
          await AINetworkManager.makeRequest(
            url: '',
            data: {
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
            },
            provider: provider,
          );
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isA<Exception>());
        expect(thrown.toString(), contains('AI服务器内部错误 (500)'));
        expect(fakeLogService.errorRecords, hasLength(2));
        expect(
          fakeLogService.errorRecords[0]['message'],
          'Failed to parse 500 error body JSON for BrokenServer (p500)',
        );
        expect(fakeLogService.errorRecords[0]['source'], 'AINetworkManager');
        expect(fakeLogService.errorRecords[0]['stackTrace'], isNotNull);
        expect(
          fakeLogService.errorRecords[1]['message'],
          'AI Request Error: 500 Internal Server Error for BrokenServer (p500)',
        );
      },
    );
  });
}
