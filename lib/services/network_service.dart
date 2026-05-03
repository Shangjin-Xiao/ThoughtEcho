import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../utils/http_response.dart';
import '../models/ai_settings.dart';
import '../models/ai_provider_settings.dart';
import '../models/multi_ai_settings.dart';
import '../utils/app_logger.dart';

/// 统一的网络服务管理器
/// 整合所有网络请求功能，提供统一的接口
class NetworkService {
  static NetworkService? _instance;
  static NetworkService get instance => _instance ??= NetworkService._();
  NetworkService._();

  // 不同用途的Dio实例
  late final Dio _generalDio; // 通用HTTP请求
  late final Dio _aiDio; // AI服务请求

  bool _initialized = false;

  /// 初始化网络服务
  Future<void> init() async {
    if (_initialized) return;

    _generalDio = Dio();
    _aiDio = Dio();

    _configureGeneralDio();
    _configureAIDio();

    _initialized = true;
    logDebug('NetworkService 初始化完成');
  }

  /// 配置通用Dio实例
  void _configureGeneralDio() {
    _generalDio.options.connectTimeout = const Duration(seconds: 15);
    _generalDio.options.receiveTimeout = const Duration(seconds: 15);
    _generalDio.options.sendTimeout = const Duration(seconds: 15);

    // 添加日志拦截器
    if (kDebugMode) {
      _generalDio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
          error: true,
          logPrint: (obj) => logDebug('[HTTP] $obj'),
        ),
      );
    }

    // 添加重试拦截器
    _generalDio.interceptors.add(
      RetryInterceptor(
        dio: _generalDio,
        logPrint: (obj) => logDebug('[RETRY] $obj'),
        retries: 1,
      ),
    );
  }

  /// 配置AI专用Dio实例
  void _configureAIDio() {
    _aiDio.options.connectTimeout = const Duration(seconds: 30);
    _aiDio.options.receiveTimeout = const Duration(seconds: 300);
    _aiDio.options.sendTimeout = const Duration(seconds: 60);

    // AI请求的日志拦截器
    if (kDebugMode) {
      _aiDio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: false, // AI响应可能很长，不打印
          requestHeader: false, // 避免泄露API密钥
          responseHeader: false,
          error: true,
          logPrint: (obj) => logDebug('[AI] $obj'),
        ),
      );
    }
  }

  /// 通用HTTP GET请求
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    _ensureInitialized();

    try {
      // 安全检查
      if (!url.startsWith('https://') && !url.contains('hitokoto.cn')) {
        logDebug('警告: 使用非HTTPS URL: $url');
      }

      final response = await _generalDio.get(
        url,
        options: Options(
          headers: headers,
          receiveTimeout: timeoutSeconds != null
              ? Duration(seconds: timeoutSeconds)
              : null,
          responseType: url.contains('hitokoto.cn')
              ? ResponseType.json
              : ResponseType.plain,
        ),
      );

      return _convertDioResponseToHttpResponse(response);
    } on DioException catch (e, stack) {
      AppLogger.e(
        'GET请求失败: $url',
        error: e,
        stackTrace: stack,
        source: 'NetworkService',
      );
      return HttpResponse(
        '{"error": "${e.message}"}',
        e.response?.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// 通用HTTP POST请求
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    _ensureInitialized();

    try {
      // 检查是否为HTTPS URL
      if (!url.startsWith('https://')) {
        throw Exception('非安全URL: 所有请求必须使用HTTPS');
      }

      final response = await _generalDio.post(
        url,
        data: body,
        options: Options(headers: headers),
      );

      return _convertDioResponseToHttpResponse(response);
    } on DioException catch (e, stack) {
      AppLogger.e(
        'POST请求失败: $url',
        error: e,
        stackTrace: stack,
        source: 'NetworkService',
      );
      return HttpResponse(
        '{"error": "${e.message}"}',
        e.response?.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// AI请求（普通）
  Future<Response> aiRequest({
    required String url,
    required Map<String, dynamic> data,
    AISettings? legacySettings,
    AIProviderSettings? provider,
    MultiAISettings? multiSettings,
    Duration? timeout,
  }) async {
    _ensureInitialized();

    try {
      final headers = _buildAIHeaders(provider, legacySettings);
      final adjustedData = _adjustAIData(data, provider, legacySettings);

      final response = await _aiDio.post(
        url,
        data: adjustedData,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );

      return response;
    } catch (e, stack) {
      AppLogger.e(
        'AI请求失败',
        error: e,
        stackTrace: stack,
        source: 'NetworkService',
      );
      rethrow;
    }
  }

  /// AI流式请求
  Future<void> aiStreamRequest({
    required String url,
    required Map<String, dynamic> data,
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(Exception) onError,
    AISettings? legacySettings,
    AIProviderSettings? provider,
    MultiAISettings? multiSettings,
    Duration? timeout,
  }) async {
    _ensureInitialized();

    try {
      final headers = _buildAIHeaders(provider, legacySettings);
      final adjustedData = _adjustAIData(data, provider, legacySettings);
      adjustedData['stream'] = true; // 确保是流式请求

      final response = await _aiDio.post(
        url,
        data: adjustedData,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );

      await _processAIStreamResponse(
        response.data.stream,
        onData,
        onComplete,
        onError,
      );
    } catch (e, stack) {
      AppLogger.e(
        'AI流式请求失败',
        error: e,
        stackTrace: stack,
        source: 'NetworkService',
      );
      onError(Exception('AI流式请求失败: $e'));
    }
  }

  /// 确保服务已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('NetworkService 未初始化，请先调用 init()');
    }
  }

  /// 转换Dio响应为HttpResponse
  HttpResponse _convertDioResponseToHttpResponse(Response dioResponse) {
    Map<String, String> convertedHeaders = {};
    dioResponse.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        convertedHeaders[name] = values.join(", ");
      }
    });

    String responseBody;
    // 特殊处理一言API的响应
    if (dioResponse.requestOptions.uri.toString().contains('hitokoto.cn')) {
      if (dioResponse.data is Map<String, dynamic>) {
        responseBody = json.encode(dioResponse.data);
      } else if (dioResponse.data is String) {
        responseBody = dioResponse.data;
      } else {
        responseBody = dioResponse.data.toString();
      }
    } else {
      responseBody = dioResponse.data is String
          ? dioResponse.data
          : dioResponse.data.toString();
    }

    return HttpResponse(
      responseBody,
      dioResponse.statusCode ?? 0,
      headers: convertedHeaders,
    );
  }

  /// 构建AI请求头
  Map<String, String> _buildAIHeaders(
    AIProviderSettings? provider,
    AISettings? legacySettings,
  ) {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (provider != null) {
      // 使用新版服务商配置
      if (provider.apiUrl.contains('anthropic.com')) {
        headers['anthropic-version'] = '2023-06-01';
        headers['x-api-key'] = provider.apiKey;
      } else if (provider.apiUrl.contains('openrouter.ai')) {
        headers['Authorization'] = 'Bearer ${provider.apiKey}';
        headers['HTTP-Referer'] = 'https://thoughtecho.app';
        headers['X-Title'] = 'ThoughtEcho App';
      } else {
        headers['Authorization'] = 'Bearer ${provider.apiKey}';
      }
    } else if (legacySettings != null) {
      // 使用旧版配置
      headers['Authorization'] = 'Bearer ${legacySettings.apiKey}';
    }

    return headers;
  }

  /// 调整AI请求数据
  Map<String, dynamic> _adjustAIData(
    Map<String, dynamic> data,
    AIProviderSettings? provider,
    AISettings? legacySettings,
  ) {
    final adjustedData = Map<String, dynamic>.from(data);

    // 确保stream参数是boolean类型
    if (adjustedData.containsKey('stream')) {
      final streamValue = adjustedData['stream'];
      if (streamValue is String) {
        adjustedData['stream'] = streamValue.toLowerCase() == 'true';
      } else if (streamValue is! bool) {
        adjustedData['stream'] = true;
      }
    }

    // 根据服务商调整数据
    if (provider != null) {
      adjustedData['model'] = adjustedData['model'] ?? provider.model;
      adjustedData['temperature'] =
          adjustedData['temperature'] ?? provider.temperature;
      adjustedData['max_tokens'] =
          adjustedData['max_tokens'] ?? provider.maxTokens;

      // Anthropic特殊处理
      if (provider.apiUrl.contains('anthropic.com')) {
        adjustedData.remove('model'); // Anthropic不在请求体中包含model
      }
    } else if (legacySettings != null) {
      adjustedData['model'] = adjustedData['model'] ?? legacySettings.model;
      adjustedData['temperature'] =
          adjustedData['temperature'] ?? legacySettings.temperature;
      adjustedData['max_tokens'] =
          adjustedData['max_tokens'] ?? legacySettings.maxTokens;
    }

    return adjustedData;
  }

  /// 处理AI流式响应
  Future<void> _processAIStreamResponse(
    Stream<List<int>> stream,
    Function(String) onData,
    Function(String) onComplete,
    Function(Exception) onError,
  ) async {
    final buffer = StringBuffer();
    String partialLine = '';

    try {
      await for (final data in stream) {
        final chunk = String.fromCharCodes(data);
        final lines = (partialLine + chunk).split('\n');
        partialLine = lines.removeLast();

        for (final line in lines) {
          if (line.startsWith('data:')) {
            final jsonStr = line.substring(5).trim();
            if (jsonStr == '[DONE]') {
              onComplete(buffer.toString());
              return;
            }

            try {
              final json = jsonDecode(jsonStr);

              // 处理OpenAI格式
              final content = json['choices']?[0]?['delta']?['content'];
              if (content != null && content is String && content.isNotEmpty) {
                buffer.write(content);
                onData(content);
                continue;
              }

              // 处理Anthropic格式
              final anthropicContent = json['delta']?['text'];
              if (anthropicContent != null &&
                  anthropicContent is String &&
                  anthropicContent.isNotEmpty) {
                buffer.write(anthropicContent);
                onData(anthropicContent);
                continue;
              }
            } catch (e, stack) {
              AppLogger.e(
                '解析流式响应JSON错误',
                error: e,
                stackTrace: stack,
                source: 'NetworkService',
              );
            }
          }
        }
      }

      onComplete(buffer.toString());
    } catch (e, stack) {
      AppLogger.e(
        '流式响应处理错误',
        error: e,
        stackTrace: stack,
        source: 'NetworkService',
      );
      onError(Exception('流式响应处理错误: $e'));
    }
  }

  /// 清理资源
  void dispose() {
    _generalDio.close();
    _aiDio.close();
    _initialized = false;
    logDebug('NetworkService 已清理');
  }
}

/// 重试拦截器
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final Function(Object)? logPrint;

  RetryInterceptor({required this.dio, this.retries = 1, this.logPrint});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.requestOptions.extra['retryCount'] == null) {
      err.requestOptions.extra['retryCount'] = 0;
    }

    final retryCount = err.requestOptions.extra['retryCount'] as int;

    if (retryCount < retries && _shouldRetry(err)) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      logPrint?.call(
        '重试请求 ${retryCount + 1}/$retries: ${err.requestOptions.uri}',
      );

      try {
        await Future.delayed(Duration(seconds: retryCount + 1));
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e, stack) {
        AppLogger.e(
          '重试请求失败: ${err.requestOptions.uri}',
          error: e,
          stackTrace: stack,
          source: 'NetworkService_Retry',
        );
        // 继续到下一个重试或失败
      }
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);
  }
}
