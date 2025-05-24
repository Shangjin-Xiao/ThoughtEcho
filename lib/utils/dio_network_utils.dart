import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/ai_settings.dart';
import '../models/ai_provider_settings.dart';

/// 基于Dio的改进网络请求工具类
/// 提供更好的连接管理、错误处理、流式支持和多服务商切换
class DioNetworkUtils {
  static Dio? _dioInstance;
  static final Map<String, DateTime> _failedProviders = {};
  static const Duration _providerCooldown = Duration(minutes: 5);

  /// 获取单例Dio实例
  static Dio get _dio {
    if (_dioInstance == null) {
      _dioInstance = Dio();
      _configureDio(_dioInstance!);
    }
    return _dioInstance!;
  }

  /// 配置Dio实例
  static void _configureDio(Dio dio) {
    dio.options.baseUrl = '';
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 300);
    dio.options.sendTimeout = const Duration(seconds: 60);
    
    // 添加拦截器用于日志记录
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: false, // 避免记录敏感数据
        responseBody: false,
        requestHeader: false, // 避免记录API密钥
        responseHeader: false,
        error: true,
        logPrint: (obj) => debugPrint('[DIO] $obj'),
      ));
    }    // 添加重试拦截器，限制最大重试次数
    dio.interceptors.add(RetryInterceptor(
      dio: dio,
      logPrint: (obj) => debugPrint('[RETRY] $obj'),
      retries: 2, // 最多重试2次
      retryDelays: const [
        Duration(seconds: 2),
        Duration(seconds: 5),
      ],
    ));
  }

  /// 重置Dio实例（用于测试或配置更改）
  static void resetDio() {
    _dioInstance?.close();
    _dioInstance = null;
  }

  /// 发送普通HTTP POST请求
  static Future<Response> makeRequest(
    String url,
    Map<String, dynamic> data,
    AISettings settings, {
    Duration? timeout,
  }) async {
    try {
      final headers = _buildHeaders(settings);
      
      final response = await _dio.post(
        url,
        data: data,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );

      return response;
    } catch (e) {
      debugPrint('HTTP请求失败: $e');
      throw _handleError(e);
    }
  }

  /// 发送流式HTTP请求
  static Future<void> makeStreamRequest(
    String url,
    Map<String, dynamic> data,
    AISettings settings, {
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(Exception) onError,
    Duration? timeout,
  }) async {
    try {
      final headers = _buildHeaders(settings);
      final streamData = {...data, 'stream': true};
      
      final response = await _dio.post(
        url,
        data: streamData,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );

      if (response.statusCode == 200) {
        await _processStreamResponse(
          response.data as Stream<List<int>>,
          onData,
          onComplete,
          onError,
        );
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'HTTP ${response.statusCode}: ${response.statusMessage}',
        );
      }
    } catch (e) {
      debugPrint('流式请求失败: $e');
      onError(_handleError(e));
    }
  }

  /// 构建请求头
  static Map<String, String> _buildHeaders(AISettings settings) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    // 根据不同的AI服务提供商设置认证头
    if (settings.apiUrl.contains('openai.com') || 
        settings.apiUrl.contains('api.openai.com')) {
      headers['Authorization'] = 'Bearer ${settings.apiKey}';
    } else if (settings.apiUrl.contains('anthropic.com')) {
      headers['x-api-key'] = settings.apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else if (settings.apiUrl.contains('cohere.ai')) {
      headers['Authorization'] = 'Bearer ${settings.apiKey}';
    } else {
      // 默认使用Bearer token
      headers['Authorization'] = 'Bearer ${settings.apiKey}';
    }

    return headers;
  }

  /// 处理流式响应
  static Future<void> _processStreamResponse(
    Stream<List<int>> stream,
    Function(String) onData,
    Function(String) onComplete,
    Function(Exception) onError,
  ) async {
    final completer = Completer<void>();
    final buffer = StringBuffer();
    String partialLine = '';

    try {
      await for (final chunk in stream) {
        final text = utf8.decode(chunk);
        final lines = (partialLine + text).split('\n');
        
        partialLine = lines.removeLast(); // 保存最后一个可能不完整的行
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            
            if (data == '[DONE]') {
              onComplete(buffer.toString());
              completer.complete();
              return;
            }
            
            try {
              final jsonData = json.decode(data);
              final content = _extractContentFromResponse(jsonData);
              
              if (content.isNotEmpty) {
                buffer.write(content);
                onData(content);
              }
            } catch (e) {
              debugPrint('解析流式响应JSON失败: $e, data: $data');
              // 继续处理其他数据块，不中断整个流
            }
          }
        }
      }
      
      // 处理剩余的部分行
      if (partialLine.trim().isNotEmpty && partialLine.startsWith('data: ')) {
        final data = partialLine.substring(6).trim();
        if (data != '[DONE]') {
          try {
            final jsonData = json.decode(data);
            final content = _extractContentFromResponse(jsonData);
            if (content.isNotEmpty) {
              buffer.write(content);
              onData(content);
            }
          } catch (e) {
            debugPrint('解析最后流式响应JSON失败: $e');
          }
        }
      }
      
      if (!completer.isCompleted) {
        onComplete(buffer.toString());
        completer.complete();
      }
    } catch (e) {
      if (!completer.isCompleted) {
        onError(Exception('流式响应处理错误: $e'));
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// 从响应JSON中提取内容
  static String _extractContentFromResponse(Map<String, dynamic> jsonData) {
    // OpenAI格式
    if (jsonData['choices'] != null && 
        jsonData['choices'] is List && 
        jsonData['choices'].isNotEmpty) {
      final choice = jsonData['choices'][0];
      if (choice['delta'] != null && choice['delta']['content'] != null) {
        return choice['delta']['content'].toString();
      }
    }
    
    // Anthropic格式
    if (jsonData['delta'] != null && jsonData['delta']['text'] != null) {
      return jsonData['delta']['text'].toString();
    }
    
    // 其他格式
    if (jsonData['content'] != null) {
      return jsonData['content'].toString();
    }
    
    return '';
  }

  /// 处理错误
  static Exception _handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return Exception('连接超时，请检查网络连接');
        case DioExceptionType.sendTimeout:
          return Exception('发送请求超时');
        case DioExceptionType.receiveTimeout:
          return Exception('接收响应超时');
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode ?? 0;
          final message = _parseErrorMessage(statusCode, error.response?.data);
          return Exception(message);
        case DioExceptionType.cancel:
          return Exception('请求已取消');
        case DioExceptionType.badCertificate:
          return Exception('SSL证书验证失败');
        case DioExceptionType.connectionError:
          return Exception('网络连接错误，请检查网络状态');
        default:
          return Exception('网络请求失败: ${error.message}');
      }
    }
    
    return error is Exception ? error : Exception(error.toString());
  }

  /// 解析错误消息
  static String _parseErrorMessage(int statusCode, dynamic responseData) {
    String errorBody = '';
    
    if (responseData != null) {
      if (responseData is Map) {
        errorBody = json.encode(responseData);
      } else {
        errorBody = responseData.toString();
      }
    }
    
    if (statusCode == 401) {
      return 'API密钥无效或已过期 (401)，请检查API密钥设置';
    } else if (statusCode == 429) {
      return 'API调用频率超限 (429)，请稍后重试';
    } else if (statusCode == 500) {
      String errorMessage = 'AI服务器内部错误 (500)';
      
      try {
        final errorData = json.decode(errorBody);
        if (errorData['error'] != null) {
          final error = errorData['error'];
          if (error['message'] != null) {
            errorMessage += '：${error['message']}';
          }
        }
      } catch (e) {
        if (errorBody.contains('model')) {
          errorMessage += '：可能是模型不存在或不可用';
        }
      }
      
      return '$errorMessage\n\n建议：\n1. 检查选择的AI模型是否正确\n2. 稍后重试\n3. 如果问题持续，请检查API服务状态';
    } else if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return 'AI服务暂时不可用 ($statusCode 错误)，请稍后重试';
    } else {
      return 'AI服务请求失败：$statusCode\n$errorBody';
    }
  }

  /// 使用多服务商配置发送请求（带自动切换）
  static Future<Response> makeRequestWithFailover(
    String url,
    Map<String, dynamic> data,
    MultiAISettings multiSettings, {
    Duration? timeout,
  }) async {
    final availableProviders = multiSettings.availableProviders;
    
    if (availableProviders.isEmpty) {
      throw Exception('没有可用的AI服务商，请在设置中配置API密钥');
    }
    
    // 首先尝试当前选择的服务商
    var currentProvider = multiSettings.currentProvider;
    if (currentProvider != null && 
        availableProviders.contains(currentProvider) &&
        !_isProviderInCooldown(currentProvider.id)) {
      try {
        return await makeRequestWithProvider(url, data, currentProvider, timeout: timeout);
      } catch (e) {
        debugPrint('当前服务商 ${currentProvider.name} 请求失败: $e');
        _markProviderFailed(currentProvider.id);
        
        if (!multiSettings.enableFailover) {
          rethrow; // 如果禁用故障转移，直接抛出错误
        }
      }
    }
    
    // 如果当前服务商失败或不可用，尝试其他服务商
    if (multiSettings.enableFailover) {
      for (final provider in availableProviders) {
        if (provider.id == currentProvider?.id) continue; // 跳过已经尝试过的
        if (_isProviderInCooldown(provider.id)) continue; // 跳过冷却期的服务商
        
        try {
          debugPrint('尝试切换到服务商: ${provider.name}');
          return await makeRequestWithProvider(url, data, provider, timeout: timeout);
        } catch (e) {
          debugPrint('服务商 ${provider.name} 请求失败: $e');
          _markProviderFailed(provider.id);
          continue; // 尝试下一个服务商
        }
      }
    }
    
    throw Exception('所有AI服务商都不可用，请稍后重试或检查网络连接');
  }

  /// 使用指定服务商发送请求
  static Future<Response> makeRequestWithProvider(
    String url,
    Map<String, dynamic> data,
    AIProviderSettings provider, {
    Duration? timeout,
  }) async {
    try {
      final headers = _buildHeadersForProvider(provider);
      final adjustedData = _adjustDataForProvider(data, provider);
      final finalUrl = url.isNotEmpty ? url : provider.apiUrl;
      
      final response = await _dio.post(
        finalUrl,
        data: adjustedData,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );

      return response;
    } catch (e) {
      debugPrint('服务商 ${provider.name} HTTP请求失败: $e');
      throw _handleError(e);
    }
  }

  /// 使用多服务商配置发送流式请求
  static Future<void> makeStreamRequestWithFailover(
    String url,
    Map<String, dynamic> data,
    MultiAISettings multiSettings, {
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(Exception) onError,
    Duration? timeout,
  }) async {
    final availableProviders = multiSettings.availableProviders;
    
    if (availableProviders.isEmpty) {
      onError(Exception('没有可用的AI服务商，请在设置中配置API密钥'));
      return;
    }
    
    // 首先尝试当前选择的服务商
    var currentProvider = multiSettings.currentProvider;
    if (currentProvider != null && 
        availableProviders.contains(currentProvider) &&
        !_isProviderInCooldown(currentProvider.id)) {
      try {
        await makeStreamRequestWithProvider(
          url, data, currentProvider,
          onData: onData,
          onComplete: onComplete,          onError: (e) {
            debugPrint('当前服务商 ${currentProvider.name} 流式请求失败: $e');
            _markProviderFailed(currentProvider.id);
            throw e; // 抛出错误以便外层捕获并尝试其他服务商
          },
          timeout: timeout,
        );
        return; // 成功完成
      } catch (e) {
        if (!multiSettings.enableFailover) {
          onError(e is Exception ? e : Exception(e.toString()));
          return;
        }
      }
    }
    
    // 如果当前服务商失败，尝试其他服务商
    if (multiSettings.enableFailover) {
      for (final provider in availableProviders) {
        if (provider.id == currentProvider?.id) continue;
        if (_isProviderInCooldown(provider.id)) continue;
        
        try {
          debugPrint('尝试切换到服务商: ${provider.name}');
          await makeStreamRequestWithProvider(
            url, data, provider,
            onData: onData,
            onComplete: onComplete,
            onError: (e) => throw e,
            timeout: timeout,
          );
          return; // 成功完成
        } catch (e) {
          debugPrint('服务商 ${provider.name} 流式请求失败: $e');
          _markProviderFailed(provider.id);
          continue;
        }
      }
    }
    
    onError(Exception('所有AI服务商都不可用，请稍后重试或检查网络连接'));
  }

  /// 使用指定服务商发送流式请求
  static Future<void> makeStreamRequestWithProvider(
    String url,
    Map<String, dynamic> data,
    AIProviderSettings provider, {
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(Exception) onError,
    Duration? timeout,
  }) async {
    try {
      final headers = _buildHeadersForProvider(provider);
      final adjustedData = _adjustDataForProvider({...data, 'stream': true}, provider);
      final finalUrl = url.isNotEmpty ? url : provider.apiUrl;
      
      final response = await _dio.post(
        finalUrl,
        data: adjustedData,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );

      if (response.statusCode == 200) {
        await _processStreamResponse(
          response.data as Stream<List<int>>,
          onData,
          onComplete,
          onError,
        );
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'HTTP ${response.statusCode}: ${response.statusMessage}',
        );
      }
    } catch (e) {
      debugPrint('服务商 ${provider.name} 流式请求失败: $e');
      onError(_handleError(e));
    }
  }

  /// 为指定服务商构建请求头
  static Map<String, String> _buildHeadersForProvider(AIProviderSettings provider) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (provider.apiUrl.contains('openai.com') || 
        provider.apiUrl.contains('openrouter.ai') ||
        provider.id == 'openai' || provider.id == 'openrouter') {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
      if (provider.id == 'openrouter') {
        headers['HTTP-Referer'] = 'https://thoughtecho.app';
        headers['X-Title'] = 'ThoughtEcho App';
      }
    } else if (provider.apiUrl.contains('anthropic.com') || provider.id == 'anthropic') {
      headers['x-api-key'] = provider.apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else if (provider.apiUrl.contains('deepseek.com') || provider.id == 'deepseek') {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    } else {
      // 默认使用Bearer token
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    return headers;
  }

  /// 为指定服务商调整请求数据
  static Map<String, dynamic> _adjustDataForProvider(
    Map<String, dynamic> data, 
    AIProviderSettings provider
  ) {
    final adjustedData = Map<String, dynamic>.from(data);
    
    // 确保包含必要的字段
    adjustedData['model'] = adjustedData['model'] ?? provider.model;
    adjustedData['temperature'] = adjustedData['temperature'] ?? provider.temperature;
    adjustedData['max_tokens'] = adjustedData['max_tokens'] ?? provider.maxTokens;
    
    return adjustedData;
  }

  /// 检查服务商是否在冷却期
  static bool _isProviderInCooldown(String providerId) {
    final failTime = _failedProviders[providerId];
    if (failTime == null) return false;
    
    final now = DateTime.now();
    final isInCooldown = now.difference(failTime) < _providerCooldown;
    
    if (!isInCooldown) {
      _failedProviders.remove(providerId); // 清除过期的记录
    }
    
    return isInCooldown;
  }

  /// 标记服务商失败
  static void _markProviderFailed(String providerId) {
    _failedProviders[providerId] = DateTime.now();
  }

  /// 清除服务商失败记录
  static void clearProviderFailures() {
    _failedProviders.clear();  }

  /// 发送普通HTTP POST请求（保持向后兼容）
  static Future<Response> makeMultiRequest(
    String url,
    Map<String, dynamic> data,
    MultiAISettings multiSettings, {
    Duration? timeout,
  }) async {
    return await makeRequestWithFailover(url, data, multiSettings, timeout: timeout);
  }
  /// 发送流式HTTP请求（保持向后兼容）
  static Future<void> makeMultiStreamRequest(
    String url,
    Map<String, dynamic> data,
    MultiAISettings multiSettings, {
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(Exception) onError,    Duration? timeout,
  }) async {
    return await makeStreamRequestWithFailover(
      url, data, multiSettings,
      onData: onData,
      onComplete: onComplete,
      onError: onError,
      timeout: timeout,
    );
  }
}

/// 自定义重试拦截器
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;
  final void Function(Object object)? logPrint;

  RetryInterceptor({
    required this.dio,
    this.retries = 2,
    this.retryDelays = const [
      Duration(seconds: 3),
      Duration(seconds: 6),
    ],
    this.logPrint,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retryCount = extra['retryCount'] ?? 0;

    if (retryCount < retries && _shouldRetry(err)) {
      final delay = retryDelays.length > retryCount 
          ? retryDelays[retryCount] 
          : retryDelays.last;
      
      logPrint?.call('重试请求 ${retryCount + 1}/$retries，延迟${delay.inSeconds}秒: ${err.message}');
      
      await Future.delayed(delay);
      
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      
      try {
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e) {
        if (e is DioException) {
          return onError(e, handler);
        }
        handler.reject(e as DioException);
        return;
      }
    }
    
    handler.next(err);
  }

  bool _shouldRetry(DioException error) {
    // 500、502、503、504错误可以重试
    if (error.response?.statusCode != null) {
      final statusCode = error.response!.statusCode!;
      if ([500, 502, 503, 504].contains(statusCode)) {
        // 检查是否是持久性500错误
        if (statusCode == 500) {
          final responseData = error.response?.data?.toString() ?? '';
          if (responseData.contains('model') && 
              (responseData.contains('not found') || 
               responseData.contains('does not exist') ||
               responseData.contains('invalid model'))) {
            return false; // 模型不存在错误不重试
          }
        }
        return true;
      }
    }
    
    // 网络连接错误可以重试
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    
    return false;
  }
}
