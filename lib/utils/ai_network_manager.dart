import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/ai_settings.dart';
import '../models/ai_provider_settings.dart';
import '../models/multi_ai_settings.dart' as multi_ai;
import '../models/ai_config.dart';
import '../services/api_key_manager.dart';
import 'api_key_debugger.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 统一的AI网络请求管理器
/// 负责处理所有AI相关的网络请求，包括普通请求和流式请求
/// 使用统一的API密钥管理器
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
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          logDebug('AI请求: ${options.method} ${options.uri}');
          // 隐藏敏感信息后打印请求头
          final safeHeaders = Map<String, dynamic>.from(options.headers);
          _hideSensitiveInfo(safeHeaders);
          logDebug('请求头: $safeHeaders');
          handler.next(options);
        },
        onResponse: (response, handler) {
          logDebug('AI响应: ${response.statusCode}');
          handler.next(response);
        },
        onError: (error, handler) {
          logDebug('AI请求错误: ${error.message}');
          handler.next(error);
        },
      ),
    );
  }

  /// 重置Dio实例
  static void resetDio() {
    _dioInstance?.close();
    _dioInstance = null;
  }

  /// 通用AI请求方法
  static Future<Response> _makeBaseRequest({
    required AIConfig config,
    required Map<String, dynamic> data,
    required ResponseType responseType,
    String? urlOverride,
    Duration? timeout,
  }) async {
    try {
      final headers = config.buildHeaders();
      final adjustedData = config.adjustData(data);
      final finalUrl = urlOverride?.isNotEmpty == true
          ? urlOverride!
          : config.apiUrl;

      // 调试信息：检查stream参数类型
      if (adjustedData.containsKey('stream')) {
        logDebug(
          'Stream parameter type: ${adjustedData['stream'].runtimeType}, value: ${adjustedData['stream']}',
        );
        // 确保stream参数是boolean类型
        final streamValue = adjustedData['stream'];
        if (streamValue is String) {
          logDebug(
            'Warning: stream parameter is String, converting to boolean',
          );
          adjustedData['stream'] = streamValue.toLowerCase() == 'true';
        } else if (streamValue is! bool) {
          logDebug(
            'Warning: stream parameter is not boolean (${streamValue.runtimeType}), setting to true',
          );
          adjustedData['stream'] = true;
        }
      }

      // 验证其他关键参数的类型
      if (adjustedData.containsKey('temperature') &&
          adjustedData['temperature'] is! num) {
        logDebug('Warning: temperature parameter type issue, fixing');
        adjustedData['temperature'] = 0.7;
      }
      if (adjustedData.containsKey('max_tokens') &&
          adjustedData['max_tokens'] is! int) {
        logDebug('Warning: max_tokens parameter type issue, fixing');
        adjustedData['max_tokens'] = 1000;
      }

      // 验证JSON编码是否会出错
      try {
        final testJson = jsonEncode(adjustedData);
        logDebug('JSON编码测试成功，数据长度: ${testJson.length}');
      } catch (e) {
        logDebug('JSON编码测试失败: $e');
        logDebug('数据类型检查:');
        adjustedData.forEach((key, value) {
          logDebug('  $key: ${value.runtimeType} = $value');
        });
        throw Exception('请求数据JSON编码失败: $e');
      }

      final response = await _dio.post(
        finalUrl,
        data: adjustedData,
        options: Options(
          headers: headers,
          responseType: responseType,
          receiveTimeout: timeout ?? const Duration(seconds: 300),
        ),
      );
      return response;
    } catch (e) {
      logDebug('AI请求失败 for ${config.name} (${config.id}): $e');
      throw _handleError(e);
    }
  }

  /// 发送普通AI请求
  static Future<Response> makeRequest({
    required String url,
    required Map<String, dynamic> data,
    AISettings? legacySettings,
    AIProviderSettings? provider,
    multi_ai.MultiAISettings? multiSettings,
    Duration? timeout,
  }) async {
    if (provider != null) {
      // 在发送请求前先从加密存储加载API Key
      final providerWithApiKey = await _loadApiKeyForProvider(provider);
      return await _makeBaseRequest(
        config: providerWithApiKey,
        data: data,
        responseType: ResponseType.json,
        urlOverride: url.isNotEmpty ? url : null,
        timeout: timeout,
      );
    } else if (multiSettings != null) {
      return await _makeRequestWithFailover(url, data, multiSettings, timeout);
    } else if (legacySettings != null) {
      return await _makeBaseRequest(
        config: LegacyAIConfigWrapper(legacySettings),
        data: data,
        responseType: ResponseType.json,
        urlOverride: url.isNotEmpty ? url : null,
        timeout: timeout,
      );
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
    multi_ai.MultiAISettings? multiSettings,
    Duration? timeout,
  }) async {
    if (provider != null) {
      // 在发送流式请求前先从加密存储加载API Key
      final providerWithApiKey = await _loadApiKeyForProvider(provider);
      final response = await _makeBaseRequest(
        config: providerWithApiKey,
        data: {...data, 'stream': true},
        responseType: ResponseType.stream,
        urlOverride: url.isNotEmpty ? url : null,
        timeout: timeout,
      );
      await _processStreamResponse(
        _getStreamFromResponse(response),
        onData,
        onComplete,
        onError,
      );
    } else if (multiSettings != null) {
      return await _makeStreamRequestWithFailover(
        url,
        data,
        multiSettings,
        onData,
        onComplete,
        onError,
        timeout,
      );
    } else if (legacySettings != null) {
      final response = await _makeBaseRequest(
        config: LegacyAIConfigWrapper(legacySettings),
        data: {...data, 'stream': true},
        responseType: ResponseType.stream,
        urlOverride: url.isNotEmpty ? url : null,
        timeout: timeout,
      );
      await _processStreamResponse(
        _getStreamFromResponse(response),
        onData,
        onComplete,
        onError,
      );
    } else {
      throw Exception('未提供有效的AI设置');
    }
  }

  /// 使用多Provider配置发送请求（带故障转移）
  static Future<Response> _makeRequestWithFailover(
    String url,
    Map<String, dynamic> data,
    multi_ai.MultiAISettings multiSettings,
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
        // 为当前provider加载API Key
        final providerWithApiKey = await _loadApiKeyForProvider(
          currentProvider,
        );
        return await _makeBaseRequest(
          config: providerWithApiKey,
          data: data,
          responseType: ResponseType.json,
          urlOverride: url.isNotEmpty ? url : null,
          timeout: timeout,
        );
      } catch (e) {
        logDebug('当前服务商 ${currentProvider.name} 请求失败: $e');
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
          logDebug('尝试切换到服务商: ${provider.name}');
          // 为故障转移的provider加载API Key
          final providerWithApiKey = await _loadApiKeyForProvider(provider);
          return await _makeBaseRequest(
            config: providerWithApiKey,
            data: data,
            responseType: ResponseType.json,
            urlOverride: url.isNotEmpty ? url : null,
            timeout: timeout,
          );
        } catch (e) {
          logDebug('服务商 ${provider.name} 请求失败: $e');
          _markProviderFailed(provider.id);
          lastError = _handleError(e);
          continue;
        }
      }
    }

    throw lastError ?? Exception('所有AI服务商都不可用，请稍后重试或检查网络连接');
  }

  /// 使用多Provider配置发送流式请求（带故障转移）
  static Future<void> _makeStreamRequestWithFailover(
    String url,
    Map<String, dynamic> data,
    multi_ai.MultiAISettings multiSettings,
    Function(String) onData,
    Function(String) onComplete,
    Function(Exception) onError,
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
        // 为当前provider加载API Key
        final providerWithApiKey = await _loadApiKeyForProvider(
          currentProvider,
        );
        final response = await _makeBaseRequest(
          config: providerWithApiKey,
          data: {...data, 'stream': true},
          responseType: ResponseType.stream,
          urlOverride: url.isNotEmpty ? url : null,
          timeout: timeout,
        );
        await _processStreamResponse(
          _getStreamFromResponse(response),
          onData,
          onComplete,
          onError,
        );
        return;
      } catch (e) {
        logDebug('当前服务商 ${currentProvider.name} 流式请求失败: $e');
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
          logDebug('尝试切换到服务商: ${provider.name}');
          // 为故障转移的provider加载API Key
          final providerWithApiKey = await _loadApiKeyForProvider(provider);
          final response = await _makeBaseRequest(
            config: providerWithApiKey,
            data: {...data, 'stream': true},
            responseType: ResponseType.stream,
            urlOverride: url.isNotEmpty ? url : null,
            timeout: timeout,
          );
          await _processStreamResponse(
            _getStreamFromResponse(response),
            onData,
            onComplete,
            onError,
          );
          return;
        } catch (e) {
          logDebug('服务商 ${provider.name} 流式请求失败: $e');
          _markProviderFailed(provider.id);
          lastError = _handleError(e);
          continue;
        }
      }
    }

    throw lastError ?? Exception('所有AI服务商都不可用，请稍后重试或检查网络连接');
  }

  /// 从响应中获取流数据
  static Stream<List<int>> _getStreamFromResponse(Response response) {
    final data = response.data;
    if (data is Stream<List<int>>) {
      return data;
    } else if (data is ResponseBody) {
      return data.stream;
    } else {
      throw Exception('无法从响应中获取流数据，响应类型: ${data.runtimeType}');
    }
  }

  /// 隐藏敏感信息
  static void _hideSensitiveInfo(Map<String, dynamic> headers) {
    if (headers.containsKey('Authorization')) {
      headers['Authorization'] = '[HIDDEN]';
    }
    if (headers.containsKey('x-api-key')) {
      headers['x-api-key'] = '[HIDDEN]';
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
    String partialLine = '';

    stream.listen(
      (data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          final lines = (partialLine + chunk).split('\n');
          partialLine = lines.removeLast();

          for (final line in lines) {
            if (line.startsWith('data:')) {
              final jsonStr = line.substring(5).trim();
              if (jsonStr == '[DONE]') {
                onComplete(buffer.toString());
                completer.complete();
                return;
              }
              try {
                final json = jsonDecode(jsonStr);

                // 处理OpenAI格式
                final content = json['choices']?[0]?['delta']?['content'];
                if (content != null &&
                    content is String &&
                    content.isNotEmpty) {
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
              } catch (e) {
                logDebug('解析流式响应JSON错误: $e, JSON: $jsonStr');
              }
            } else if (line.isNotEmpty && line.trim() != '') {
              logDebug('未知流式响应格式: $line');
            }
          }
        } catch (e) {
          logDebug('处理流式数据块错误: $e');
          onError(Exception('流式数据处理错误: $e'));
        }
      },
      onError: (error) {
        logDebug('流式响应错误: $error');
        onError(_handleError(error));
        if (!completer.isCompleted) {
          completer.completeError(_handleError(error));
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          onComplete(buffer.toString());
          completer.complete();
        }
      },
    );
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

        return Exception(
          '$errorMessage\n\n建议：\n1. 检查选择的AI模型是否正确\n2. 稍后重试\n3. 如果问题持续，请检查API服务状态',
        );
      } else if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError) {
        return Exception('网络连接超时，请检查网络设置或稍后重试');
      } else {
        return Exception('AI请求未知错误: ${error.message ?? error.toString()}');
      }
    } else {
      return Exception('未知错误: ${error.toString()}');
    }
  }

  /// 为provider加载API Key（从加密存储）
  static Future<AIProviderSettings> _loadApiKeyForProvider(
    AIProviderSettings provider,
  ) async {
    try {
      final apiKeyManager = APIKeyManager();
      final apiKey = await apiKeyManager.getProviderApiKey(provider.id);

      logDebug(
        '为Provider ${provider.name} 加载API Key: ${apiKey.isEmpty ? "未找到" : "${apiKey.length}字符"}',
      );

      // 调试API Key请求时的状态
      if (kDebugMode) {
        await ApiKeyDebugger.debugApiKeyInRequest(
          provider.id,
          provider.name,
          apiKey,
        );
      }

      // 返回带有API Key的新provider实例
      final providerWithApiKey = provider.copyWith(apiKey: apiKey);

      // 验证构建的headers
      final headers = providerWithApiKey.buildHeaders();
      final authHeader = headers['Authorization'] ?? headers['x-api-key'] ?? '';
      logDebug(
        '构建的请求头中的API Key: ${authHeader.isEmpty ? "空" : "${authHeader.replaceAll('Bearer ', '').replaceAll('x-api-key ', '').length}字符"}',
      );

      return providerWithApiKey;
    } catch (e) {
      logDebug('为Provider ${provider.name} 加载API Key失败: $e');
      return provider; // 返回原provider
    }
  }
}
