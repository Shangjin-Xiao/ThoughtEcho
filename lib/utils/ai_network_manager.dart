import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/ai_settings.dart';
import '../models/ai_provider_settings.dart';
import '../services/secure_storage_service.dart';

/// 统一的AI网络请求管理器
/// 负责处理所有AI相关的网络请求，包括普通请求和流式请求
class AINetworkManager {
  static Dio? _dioInstance;
  static final Map<String, DateTime> _failedProviders = {};
  static const Duration _providerCooldown = Duration(minutes: 5);

  /// 获取Dio实例
  static Dio get _dio {
    if (_dioInstance == null) {
      _dioInstance = Dio();
      _configureDio(_dioInstance!);
    }
    return _dioInstance!;
  }

  /// 配置Dio实例
  static void _configureDio(Dio dio) {
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 300);
    dio.options.sendTimeout = const Duration(seconds: 30);
    
    // 添加请求拦截器
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        debugPrint('AI请求: ${options.method} ${options.uri}');
        // 隐藏敏感信息后打印请求头
        final safeHeaders = Map<String, dynamic>.from(options.headers);
        _hideSensitiveInfo(safeHeaders);
        debugPrint('请求头: $safeHeaders');
        handler.next(options);
      },
      onResponse: (response, handler) {
        debugPrint('AI响应: ${response.statusCode}');
        handler.next(response);
      },
      onError: (error, handler) {
        debugPrint('AI请求错误: ${error.message}');
        handler.next(error);
      },
    ));
  }

  /// 重置Dio实例
  static void resetDio() {
    _dioInstance?.close();
    _dioInstance = null;
  }

  /// 发送普通AI请求
  static Future<Response> makeRequest({
    required String url,
    required Map<String, dynamic> data,
    AISettings? legacySettings,
    AIProviderSettings? provider,
    MultiAISettings? multiSettings,
    Duration? timeout,
  }) async {
    // 优先级：provider > multiSettings > legacySettings
    if (provider != null) {
      return await _makeRequestWithProvider(url, data, provider, timeout);
    } else if (multiSettings != null) {
      return await _makeRequestWithFailover(url, data, multiSettings, timeout);
    } else if (legacySettings != null) {
      return await _makeRequestWithLegacySettings(url, data, legacySettings, timeout);
    } else {
      throw Exception('未提供有效的AI设置');
    }
  }

  /// 发送流式AI请求
  static Future<void> makeStreamRequest({
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
    // 优先级：provider > multiSettings > legacySettings
    if (provider != null) {
      return await _makeStreamRequestWithProvider(
        url, data, provider, onData, onComplete, onError, timeout);
    } else if (multiSettings != null) {
      return await _makeStreamRequestWithFailover(
        url, data, multiSettings, onData, onComplete, onError, timeout);
    } else if (legacySettings != null) {
      return await _makeStreamRequestWithLegacySettings(
        url, data, legacySettings, onData, onComplete, onError, timeout);
    } else {
      throw Exception('未提供有效的AI设置');
    }
  }

  /// 使用特定Provider发送请求
  static Future<Response> _makeRequestWithProvider(
    String url,
    Map<String, dynamic> data,
    AIProviderSettings provider,
    Duration? timeout,
  ) async {
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
      debugPrint('Provider ${provider.name} 请求失败: $e');
      throw _handleError(e);
    }
  }

  /// 使用多Provider配置发送请求（带故障转移）
  static Future<Response> _makeRequestWithFailover(
    String url,
    Map<String, dynamic> data,
    MultiAISettings multiSettings,
    Duration? timeout,
  ) async {
    final availableProviders = multiSettings.availableProviders;
    
    if (availableProviders.isEmpty) {
      throw Exception('没有可用的AI服务商，请在设置中配置API密钥');
    }
    
    Exception? lastError;
    
    // 首先尝试当前选择的服务商
    var currentProvider = multiSettings.currentProvider;
    if (currentProvider != null && 
        availableProviders.contains(currentProvider) &&
        !_isProviderInCooldown(currentProvider.id)) {
      try {
        return await _makeRequestWithProvider(url, data, currentProvider, timeout);
      } catch (e) {
        debugPrint('当前服务商 ${currentProvider.name} 请求失败: $e');
        _markProviderFailed(currentProvider.id);
        lastError = _handleError(e);
        
        if (!multiSettings.enableFailover) {
          throw lastError;
        }
      }
    }
    
    // 如果当前服务商失败或故障转移启用，尝试其他服务商
    if (multiSettings.enableFailover) {
      for (final provider in availableProviders) {
        if (provider.id == currentProvider?.id) continue;
        if (_isProviderInCooldown(provider.id)) continue;
        
        try {
          debugPrint('尝试切换到服务商: ${provider.name}');
          return await _makeRequestWithProvider(url, data, provider, timeout);
        } catch (e) {
          debugPrint('服务商 ${provider.name} 请求失败: $e');
          _markProviderFailed(provider.id);
          lastError = _handleError(e);
          continue;
        }
      }
    }
    
    throw lastError ?? Exception('所有AI服务商都不可用，请稍后重试或检查网络连接');
  }

  /// 使用传统AI设置发送请求
  static Future<Response> _makeRequestWithLegacySettings(
    String url,
    Map<String, dynamic> data,
    AISettings settings,
    Duration? timeout,
  ) async {
    try {
      final apiKey = await _getEffectiveApiKey(settings);
      final headers = _buildHeadersForLegacySettings(settings, apiKey);
      final adjustedData = _adjustDataForLegacySettings(data, settings);
      
      final response = await _dio.post(
        settings.apiUrl,
        data: adjustedData,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );

      return response;
    } catch (e) {
      debugPrint('传统AI设置请求失败: $e');
      throw _handleError(e);
    }
  }

  /// 使用特定Provider发送流式请求
  static Future<void> _makeStreamRequestWithProvider(
    String url,
    Map<String, dynamic> data,
    AIProviderSettings provider,
    Function(String) onData,
    Function(String) onComplete,
    Function(Exception) onError,
    Duration? timeout,
  ) async {
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
      debugPrint('Provider ${provider.name} 流式请求失败: $e');
      onError(_handleError(e));
    }
  }

  /// 使用多Provider配置发送流式请求（带故障转移）
  static Future<void> _makeStreamRequestWithFailover(
    String url,
    Map<String, dynamic> data,
    MultiAISettings multiSettings,
    Function(String) onData,
    Function(String) onComplete,
    Function(Exception) onError,
    Duration? timeout,
  ) async {
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
        await _makeStreamRequestWithProvider(
          url, data, currentProvider, onData, onComplete, onError, timeout);
        return;
      } catch (e) {
        debugPrint('当前服务商 ${currentProvider.name} 流式请求失败: $e');
        _markProviderFailed(currentProvider.id);
        
        if (!multiSettings.enableFailover) {
          onError(_handleError(e));
          return;
        }
      }
    }
    
    // 如果当前服务商失败或故障转移启用，尝试其他服务商
    if (multiSettings.enableFailover) {
      for (final provider in availableProviders) {
        if (provider.id == currentProvider?.id) continue;
        if (_isProviderInCooldown(provider.id)) continue;
        
        try {
          debugPrint('尝试切换到服务商: ${provider.name}');
          await _makeStreamRequestWithProvider(
            url, data, provider, onData, onComplete, onError, timeout);
          return;
        } catch (e) {
          debugPrint('服务商 ${provider.name} 流式请求失败: $e');
          _markProviderFailed(provider.id);
          continue;
        }
      }
    }
    
    onError(Exception('所有AI服务商都不可用，请稍后重试或检查网络连接'));
  }

  /// 使用传统AI设置发送流式请求
  static Future<void> _makeStreamRequestWithLegacySettings(
    String url,
    Map<String, dynamic> data,
    AISettings settings,
    Function(String) onData,
    Function(String) onComplete,
    Function(Exception) onError,
    Duration? timeout,
  ) async {
    try {
      final apiKey = await _getEffectiveApiKey(settings);
      final headers = _buildHeadersForLegacySettings(settings, apiKey);
      final adjustedData = _adjustDataForLegacySettings({...data, 'stream': true}, settings);
      
      final response = await _dio.post(
        settings.apiUrl,
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
      debugPrint('传统AI设置流式请求失败: $e');
      onError(_handleError(e));
    }
  }

  /// 为Provider构建请求头
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
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    return headers;
  }

  /// 为传统AI设置构建请求头
  static Map<String, String> _buildHeadersForLegacySettings(AISettings settings, String apiKey) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (settings.apiUrl.contains('openai.com') || 
        settings.apiUrl.contains('api.openai.com')) {
      headers['Authorization'] = 'Bearer $apiKey';
    } else if (settings.apiUrl.contains('anthropic.com')) {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else if (settings.apiUrl.contains('openrouter.ai')) {
      headers['Authorization'] = 'Bearer $apiKey';
      headers['HTTP-Referer'] = 'https://thoughtecho.app';
      headers['X-Title'] = 'ThoughtEcho App';
    } else if (settings.apiUrl.contains('deepseek.com')) {
      headers['Authorization'] = 'Bearer $apiKey';
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    return headers;
  }

  /// 为Provider调整请求数据
  static Map<String, dynamic> _adjustDataForProvider(
    Map<String, dynamic> data, 
    AIProviderSettings provider
  ) {
    final adjustedData = Map<String, dynamic>.from(data);
    
    // 确保包含必要的字段
    adjustedData['model'] = adjustedData['model'] ?? provider.model;
    adjustedData['temperature'] = adjustedData['temperature'] ?? provider.temperature;
    adjustedData['max_tokens'] = adjustedData['max_tokens'] ?? provider.maxTokens;
    
    // Anthropic特殊处理
    if (provider.apiUrl.contains('anthropic.com') || provider.id == 'anthropic') {
      // Anthropic API不在请求体中包含model，而是在URL中
      adjustedData.remove('model');
    }
    
    return adjustedData;
  }

  /// 为传统AI设置调整请求数据
  static Map<String, dynamic> _adjustDataForLegacySettings(
    Map<String, dynamic> data, 
    AISettings settings
  ) {
    final adjustedData = Map<String, dynamic>.from(data);
    
    // 确保包含必要的字段
    adjustedData['model'] = adjustedData['model'] ?? settings.model;
    adjustedData['temperature'] = adjustedData['temperature'] ?? settings.temperature;
    adjustedData['max_tokens'] = adjustedData['max_tokens'] ?? settings.maxTokens;
    
    // Anthropic特殊处理
    if (settings.apiUrl.contains('anthropic.com')) {
      adjustedData.remove('model');
    }
    
    return adjustedData;
  }

  /// 获取有效的API密钥
  static Future<String> _getEffectiveApiKey(AISettings settings) async {
    try {
      final secureStorage = SecureStorageService();
      final secureApiKey = await secureStorage.getApiKey();
      
      final effectiveKey = secureApiKey ?? settings.apiKey;
      
      if (effectiveKey.isEmpty) {
        throw Exception('未找到有效的API密钥');
      }
      
      return effectiveKey;
    } catch (e) {
      debugPrint('获取API密钥失败: $e');
      return settings.apiKey;
    }
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
    
    try {
      await for (final chunk in stream) {
        final chunkString = utf8.decode(chunk);
        final lines = chunkString.split('\n');
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          if (!line.startsWith('data: ')) continue;
          
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            onComplete(buffer.toString());
            completer.complete();
            return;
          }
          
          try {
            final json = jsonDecode(data);
            if (json['choices'] != null && json['choices'].isNotEmpty) {
              final delta = json['choices'][0]['delta'];
              if (delta != null && delta['content'] != null) {
                final content = delta['content'] as String;
                buffer.write(content);
                onData(content);
              }
            }
          } catch (e) {
            debugPrint('解析流式响应失败: $e, 数据: $data');
          }
        }
      }
      
      if (!completer.isCompleted) {
        onComplete(buffer.toString());
        completer.complete();
      }
    } catch (e) {
      if (!completer.isCompleted) {
        onError(Exception('流式响应处理失败: $e'));
        completer.complete();
      }
    }
    
    return completer.future;
  }

  /// 检查服务商是否在冷却期
  static bool _isProviderInCooldown(String providerId) {
    final failTime = _failedProviders[providerId];
    if (failTime == null) return false;
    
    final now = DateTime.now();
    final isInCooldown = now.difference(failTime) < _providerCooldown;
    
    if (!isInCooldown) {
      _failedProviders.remove(providerId);
    }
    
    return isInCooldown;
  }

  /// 标记服务商失败
  static void _markProviderFailed(String providerId) {
    _failedProviders[providerId] = DateTime.now();
  }

  /// 清除服务商失败记录
  static void clearProviderFailures() {
    _failedProviders.clear();
  }

  /// 处理错误
  static Exception _handleError(dynamic error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final errorBody = error.response?.data?.toString() ?? error.message ?? '';
      
      if (statusCode == 401) {
        return Exception('API密钥无效或已过期 (401)，请检查API密钥设置');
      } else if (statusCode == 429) {
        return Exception('API调用频率超限 (429)，请稍后重试');
      } else if (statusCode == 500) {
        String errorMessage = 'AI服务器内部错误 (500)';
        
        try {
          final errorData = json.decode(errorBody);
          if (errorData['error'] != null) {
            final errorInfo = errorData['error'];
            if (errorInfo['message'] != null) {
              errorMessage += '：${errorInfo['message']}';
            }
          }
        } catch (e) {
          if (errorBody.contains('model')) {
            errorMessage += '：可能是模型不存在或不可用';
          }
        }
        
        return Exception('$errorMessage\n\n建议：\n1. 检查选择的AI模型是否正确\n2. 稍后重试\n3. 如果问题持续，请检查API服务状态');
      } else if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return Exception('AI服务暂时不可用 ($statusCode 错误)，请稍后重试');
      } else {
        return Exception('AI服务请求失败：$statusCode\n$errorBody');
      }
    } else if (error.toString().contains('Failed host lookup')) {
      return Exception('无法连接到AI服务器，请检查网络连接或服务器状态');
    } else if (error.toString().contains('Connection refused')) {
      return Exception('连接被拒绝，请检查API URL和服务器状态');
    } else {
      return Exception('网络请求失败: ${error.toString()}');
    }
  }

  /// 隐藏敏感信息
  static void _hideSensitiveInfo(Map<String, dynamic> headers) {
    if (headers.containsKey('Authorization')) {
      headers['Authorization'] = '[API_KEY_HIDDEN]';
    }
    if (headers.containsKey('x-api-key')) {
      headers['x-api-key'] = '[API_KEY_HIDDEN]';
    }
  }
}
