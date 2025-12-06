import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import '../models/ai_settings.dart';
import 'package:thoughtecho/utils/app_logger.dart';

// 定义流式响应的回调类型
typedef StreamingResponseCallback = void Function(String text);
typedef StreamingCompleteCallback = void Function(String fullText);
typedef StreamingErrorCallback = void Function(dynamic error);

/// 流式传输工具类
/// 处理各种AI服务提供商的流式HTTP请求
class StreamingUtils {
  // 添加请求去重机制
  static final Map<String, DateTime> _activeRequests = {};
  static const Duration _requestCooldown = Duration(seconds: 5);

  /// 生成请求的唯一标识符
  static String _generateRequestKey(
    String url,
    Map<String, dynamic> requestBody,
  ) {
    // 使用URL和消息内容的哈希作为唯一标识
    final messagesContent = requestBody['messages']?.toString() ?? '';
    return '${url}_${messagesContent.hashCode}';
  }

  /// 检查是否应该阻止重复请求
  static bool _shouldBlockDuplicateRequest(String requestKey) {
    final now = DateTime.now();
    final lastRequestTime = _activeRequests[requestKey];

    if (lastRequestTime != null) {
      final timeSinceLastRequest = now.difference(lastRequestTime);
      if (timeSinceLastRequest < _requestCooldown) {
        logDebug('阻止重复请求，距上次请求仅${timeSinceLastRequest.inSeconds}秒');
        return true;
      }
    }

    // 记录新的请求时间
    _activeRequests[requestKey] = now;

    // 清理过期的请求记录（超过1分钟的）
    _activeRequests.removeWhere(
      (key, time) => now.difference(time) > const Duration(minutes: 1),
    );

    return false;
  }

  /// 清除特定请求的记录
  static void _clearRequestRecord(String requestKey) {
    _activeRequests.remove(requestKey);
  }

  /// 创建一个流式请求
  ///
  /// [url] API endpoint URL
  /// [requestBody] 请求体，包含messages等参数
  /// [settings] AI设置，包含API密钥等信息
  /// [onResponse] 接收到数据块时的回调
  /// [onComplete] 流式传输完成时的回调
  /// [onError] 发生错误时的回调
  static Future<void> makeStreamRequest(
    String url,
    Map<String, dynamic> requestBody,
    AISettings settings, {
    required StreamingResponseCallback onResponse,
    required StreamingCompleteCallback onComplete,
    required StreamingErrorCallback onError,
    Duration timeout = const Duration(seconds: 300),
  }) async {
    // 验证输入参数
    if (requestBody['messages'] is! List) {
      onError(Exception('messages字段格式错误'));
      return;
    }

    try {
      // 获取有效的API密钥
      final effectiveApiKey = await _getEffectiveApiKey(settings);
      if (effectiveApiKey.isEmpty) {
        onError(Exception('未找到有效的API密钥，请在设置中配置API密钥'));
        return;
      }

      // 根据API提供商调整请求格式
      final adjustedRequest = _adjustRequestForProvider(
        url,
        requestBody,
        effectiveApiKey,
      );

      // 发送流式请求
      await _sendStreamRequest(
        url,
        adjustedRequest.requestBody,
        adjustedRequest.headers,
        onResponse,
        onComplete,
        onError,
        timeout,
      );
    } catch (e) {
      onError(e);
    }
  }

  /// 获取有效的API密钥（使用多供应商API密钥管理器）
  static Future<String> _getEffectiveApiKey(AISettings settings) async {
    // 注意：这个方法现在已过时，应该使用多供应商API
    // 为了向后兼容，返回空字符串
    return '';
  }

  /// 根据不同的AI服务提供商调整请求格式
  static _AdjustedRequest _adjustRequestForProvider(
    String url,
    Map<String, dynamic> body,
    String apiKey,
  ) {
    Map<String, dynamic> requestBody;
    Map<String, String> headers = {'Content-Type': 'application/json'};

    if (url.contains('anthropic.com')) {
      // Anthropic Claude API格式
      requestBody = {
        'model': body['model'],
        'messages': body['messages'],
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 确保是boolean类型
      };
      headers['anthropic-version'] = '2023-06-01';
      headers['x-api-key'] = apiKey;
    } else if (url.contains('openrouter.ai')) {
      // OpenRouter API格式
      requestBody = {
        'model': body['model'],
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 确保是boolean类型
      };
      headers['Authorization'] = 'Bearer $apiKey';
      headers['HTTP-Referer'] = 'https://thoughtecho.app';
      headers['X-Title'] = 'ThoughtEcho App';
    } else if (url.contains('deepseek.com')) {
      // DeepSeek API格式
      requestBody = {
        'model': body['model'],
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 确保是boolean类型
      };
      headers['Authorization'] = 'Bearer $apiKey';
    } else if (url.contains('siliconflow.cn')) {
      // 硅基流动 API格式
      requestBody = {
        'model': body['model'],
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 确保是boolean类型
      };
      headers['Authorization'] = 'Bearer $apiKey';
    } else {
      // 默认格式(适用于OpenAI及其兼容API)
      requestBody = {
        'model': body['model'],
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 确保是boolean类型
      };
      headers['Authorization'] = 'Bearer $apiKey';
    }

    return _AdjustedRequest(requestBody: requestBody, headers: headers);
  }

  /// 发送流式HTTP请求
  static Future<void> _sendStreamRequest(
    String url,
    Map<String, dynamic> requestBody,
    Map<String, String> headers,
    StreamingResponseCallback onResponse,
    StreamingCompleteCallback onComplete,
    StreamingErrorCallback onError,
    Duration timeout,
  ) async {
    logDebug('流式请求URL: $url');

    // 验证和修复请求体中的数据类型
    final validatedRequestBody = Map<String, dynamic>.from(requestBody);

    // 确保stream参数是boolean类型
    if (validatedRequestBody.containsKey('stream')) {
      final streamValue = validatedRequestBody['stream'];
      if (streamValue is String) {
        validatedRequestBody['stream'] = streamValue.toLowerCase() == 'true';
        logDebug('Warning: 修复stream参数类型从String到boolean');
      } else if (streamValue is! bool) {
        validatedRequestBody['stream'] = true;
        logDebug('Warning: 修复stream参数类型到boolean');
      }
    }

    // 打印安全的请求信息（隐藏敏感信息）
    final safeHeaders = Map<String, String>.from(headers);
    _hideSensitiveInfo(safeHeaders);
    logDebug('请求头: $safeHeaders');

    // 安全的JSON编码，避免类型转换错误
    try {
      final jsonString = json.encode(validatedRequestBody);
      logDebug('请求体: $jsonString');
    } catch (e) {
      logDebug('JSON编码错误: $e');
      logDebug('请求体数据类型检查:');
      validatedRequestBody.forEach((key, value) {
        logDebug('  $key: ${value.runtimeType} = $value');
      });
      // 尝试修复数据类型问题
      final fixedRequestBody = _fixDataTypes(validatedRequestBody);
      try {
        final jsonString = json.encode(fixedRequestBody);
        logDebug('修复后的请求体: $jsonString');
        // 使用修复后的数据
        validatedRequestBody.clear();
        validatedRequestBody.addAll(fixedRequestBody);
      } catch (e2) {
        logDebug('修复后仍然无法编码JSON: $e2');
        throw Exception('请求数据格式错误: $e2');
      }
    }

    Dio? dio;
    CancelToken? cancelToken;
    try {
      dio = Dio();
      cancelToken = CancelToken();

      // 配置Dio
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = timeout;
      dio.options.sendTimeout = const Duration(seconds: 60);

      final response = await dio.post(
        url,
        data: validatedRequestBody,
        options: Options(headers: headers, responseType: ResponseType.stream),
        cancelToken: cancelToken,
      );

      if (response.statusCode != 200) {
        String errorBody = '';
        if (response.data is Stream) {
          final chunks = <int>[];
          await for (final chunk in response.data) {
            chunks.addAll(chunk);
          }
          errorBody = utf8.decode(chunks);
        } else {
          errorBody = response.data?.toString() ?? '';
        }
        final errorMessage = _parseErrorMessage(
          response.statusCode!,
          errorBody,
        );
        onError(Exception(errorMessage));
        return;
      }

      // 处理流式响应
      await _processStreamResponseDio(
        response.data,
        onResponse,
        onComplete,
        onError,
      );
    } on DioException catch (e) {
      logDebug('Dio流式请求异常: $e');
      if (e.type == DioExceptionType.receiveTimeout) {
        onError(Exception('请求超时，AI分析可能需要更长时间，请稍后再试'));
      } else if (e.type == DioExceptionType.connectionTimeout) {
        onError(Exception('连接超时，请检查网络连接'));
      } else if (e.type == DioExceptionType.cancel) {
        onError(Exception('请求被取消'));
      } else {
        // 正确处理响应体，特别是对于流式响应
        String errorBody = '';
        try {
          if (e.response?.data != null) {
            final responseData = e.response!.data;
            if (responseData is String) {
              errorBody = responseData;
            } else if (responseData is Stream) {
              // 对于流式响应，需要读取流数据
              final chunks = <int>[];
              await for (final chunk in responseData) {
                if (chunk is List<int>) {
                  chunks.addAll(chunk);
                }
              }
              errorBody = utf8.decode(chunks);
            } else {
              errorBody = responseData.toString();
            }
          }
        } catch (readError) {
          logDebug('读取错误响应体失败: $readError');
          errorBody = e.message ?? '未知错误';
        }

        final errorMessage = _parseErrorMessage(
          e.response?.statusCode ?? 0,
          errorBody.isEmpty ? (e.message ?? '未知错误') : errorBody,
        );
        onError(Exception(errorMessage));
      }
    } catch (e) {
      logDebug('流式请求异常: $e');
      onError(Exception(e.toString()));
    } finally {
      cancelToken?.cancel();
      dio?.close();
    }
  }

  /// 处理Dio流式响应数据
  static Future<void> _processStreamResponseDio(
    Stream<List<int>> responseStream,
    StreamingResponseCallback onResponse,
    StreamingCompleteCallback onComplete,
    StreamingErrorCallback onError,
  ) async {
    String currentChunk = '';

    try {
      await for (List<int> chunk in responseStream) {
        final chunkString = utf8.decode(chunk);
        currentChunk += chunkString;

        // 按行处理数据
        final lines = currentChunk.split('\n');
        currentChunk = lines.last; // 保留最后一行（可能是不完整的）

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty || !line.startsWith('data: ')) continue;

          if (line == 'data: [DONE]') {
            logDebug('流式响应完成');
            onComplete('');
            return;
          }

          final content = _extractContentFromLine(line);
          if (content != null && content.isNotEmpty) {
            // 按块解码并立即回调，避免全量缓存
            onResponse(content);
          }
        }
      }

      logDebug('流式响应接收完毕');
      // 流处理结束，只回调完成通知，不传递内容
      onComplete('');
    } catch (e) {
      logDebug('处理流式响应时出错: $e');
      onError(Exception(e.toString()));
    }
  }

  /// 从SSE数据行中提取内容
  static String? _extractContentFromLine(String line) {
    try {
      final jsonString = line.substring(6); // 移除 "data: " 前缀
      final data = json.decode(jsonString);

      // 处理不同格式的响应
      if (data['choices'] != null && data['choices'].isNotEmpty) {
        final choice = data['choices'][0];

        // 新格式 (delta.content)
        if (choice['delta'] != null && choice['delta']['content'] != null) {
          final content = choice['delta']['content'];
          if (content is String) {
            return content;
          }
        }

        // 旧格式 (text)
        if (choice['text'] != null) {
          final text = choice['text'];
          if (text is String) {
            return text;
          }
        }
      }

      return null;
    } catch (e) {
      logDebug('解析流式数据失败: $e, 原始数据: $line');
      // 检查是否是类型转换错误
      if (e.toString().contains('type') && e.toString().contains('subtype')) {
        logDebug('检测到类型转换错误，可能是API响应格式问题');
      }
      return null;
    }
  }

  /// 解析错误消息
  static String _parseErrorMessage(int statusCode, String errorBody) {
    logDebug('解析错误 - 状态码: $statusCode, 响应体: $errorBody');

    if (errorBody.contains('rate_limit_exceeded') ||
        errorBody.contains('rate limit') ||
        statusCode == 429) {
      return '请求频率超限，请稍后再试 (429 错误)';
    } else if (errorBody.contains('authentication') ||
        errorBody.contains('invalid_api_key') ||
        statusCode == 401) {
      return 'API密钥无效或已过期，请更新API密钥 (401 错误)';
    } else if (errorBody.contains('insufficient_quota') ||
        errorBody.contains('billing')) {
      return 'API额度不足，请检查账户余额';
    } else if (statusCode == 500) {
      // 专门处理500错误
      String errorMessage = 'AI服务器内部错误 (500)';

      // 尝试解析具体错误信息
      try {
        final errorData = json.decode(errorBody);
        if (errorData['error'] != null) {
          final error = errorData['error'];
          if (error['message'] != null) {
            errorMessage += '：${error['message']}';
          } else if (error['code'] != null) {
            errorMessage += '：错误代码 ${error['code']}';
          }
        }
      } catch (e) {
        // 如果无法解析JSON，检查常见错误模式
        if (errorBody.contains('model')) {
          errorMessage += '：可能是模型不存在或不可用';
        } else if (errorBody.contains('timeout')) {
          errorMessage += '：服务器处理超时';
        } else if (errorBody.contains('overload')) {
          errorMessage += '：服务器过载，请稍后重试';
        } else if (errorBody.isNotEmpty) {
          // 截取错误信息的前100个字符
          final truncatedError = errorBody.length > 100
              ? '${errorBody.substring(0, 100)}...'
              : errorBody;
          errorMessage += '：$truncatedError';
        }
      }

      return '$errorMessage\n\n建议：\n1. 检查选择的AI模型是否正确\n2. 稍后重试\n3. 如果问题持续，请检查API服务状态';
    } else if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return 'AI服务暂时不可用 ($statusCode 错误)，请稍后重试';
    } else if (statusCode == 400) {
      return '请求格式错误 (400)，请检查API设置和模型配置';
    } else if (statusCode == 403) {
      return '无权限访问该API服务 (403)，请检查API密钥权限';
    } else if (statusCode == 404) {
      return 'API端点不存在 (404)，请检查API URL配置';
    } else {
      return 'AI服务请求失败：$statusCode\n$errorBody';
    }
  }

  /// 修复数据类型问题
  static Map<String, dynamic> _fixDataTypes(Map<String, dynamic> data) {
    final fixedData = <String, dynamic>{};

    data.forEach((key, value) {
      if (value == null) {
        fixedData[key] = null;
      } else if (value is bool) {
        fixedData[key] = value; // 布尔值保持不变
      } else if (value is num) {
        fixedData[key] = value; // 数字保持不变
      } else if (value is String) {
        fixedData[key] = value; // 字符串保持不变
      } else if (value is List) {
        // 递归处理列表
        fixedData[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _fixDataTypes(item);
          }
          return item;
        }).toList();
      } else if (value is Map<String, dynamic>) {
        // 递归处理嵌套Map
        fixedData[key] = _fixDataTypes(value);
      } else {
        // 其他类型转换为字符串
        logDebug('Warning: 将 $key 的值从 ${value.runtimeType} 转换为字符串: $value');
        fixedData[key] = value.toString();
      }
    });

    return fixedData;
  }

  /// 隐藏敏感信息
  static void _hideSensitiveInfo(Map<String, String> headers) {
    if (headers.containsKey('Authorization')) {
      headers['Authorization'] = '[API_KEY_HIDDEN]';
    }
    if (headers.containsKey('x-api-key')) {
      headers['x-api-key'] = '[API_KEY_HIDDEN]';
    }
  }

  /// 创建一个带重试机制的流式请求
  ///
  /// [maxRetries] 最大重试次数
  /// [retryDelay] 重试间隔时间
  static Future<void> makeStreamRequestWithRetry(
    String url,
    Map<String, dynamic> requestBody,
    AISettings settings, {
    required StreamingResponseCallback onResponse,
    required StreamingCompleteCallback onComplete,
    required StreamingErrorCallback onError,
    Duration timeout = const Duration(seconds: 300),
    int maxRetries = 1, // 降低默认重试次数，减少500错误时的重复请求
    Duration retryDelay = const Duration(seconds: 5), // 增加重试延迟
  }) async {
    // 生成请求唯一标识符
    final requestKey = _generateRequestKey(url, requestBody);

    // 检查是否应该阻止重复请求
    if (_shouldBlockDuplicateRequest(requestKey)) {
      onError(Exception('请求过于频繁，请稍后再试'));
      return;
    }

    int retryCount = 0;
    Exception? lastError;

    try {
      while (retryCount <= maxRetries) {
        try {
          bool hasCompleted = false;
          bool hasError = false;

          await makeStreamRequest(
            url,
            requestBody,
            settings,
            onResponse: onResponse,
            onComplete: (fullText) {
              hasCompleted = true;
              // 请求成功完成，清除请求记录以允许新的相同请求
              _clearRequestRecord(requestKey);
              onComplete(fullText);
            },
            onError: (error) {
              if (hasCompleted) return; // 如果已经完成，不处理错误
              hasError = true;
              lastError =
                  error is Exception ? error : Exception(error.toString());
            },
            timeout: timeout,
          );

          // 如果成功完成，直接返回
          if (hasCompleted) {
            return;
          }
          // 如果有错误，检查是否需要重试
          if (hasError && lastError != null) {
            if (retryCount < maxRetries && _isRetryableError(lastError!)) {
              logDebug(
                '请求失败，将在${_calculateRetryDelay(retryCount, retryDelay).inSeconds}秒后重试 ${retryCount + 1}/$maxRetries: $lastError',
              );
              retryCount++;

              // 使用指数退避策略
              await Future.delayed(
                _calculateRetryDelay(retryCount - 1, retryDelay),
              );
              continue; // 继续重试
            } else {
              // 达到最大重试次数或不可重试的错误，调用原始错误回调
              onError(lastError!);
              return;
            }
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());

          if (retryCount >= maxRetries || !_isRetryableError(lastError!)) {
            onError(lastError!);
            return;
          }

          logDebug(
            '请求失败，将在${_calculateRetryDelay(retryCount, retryDelay).inSeconds}秒后重试 ${retryCount + 1}/$maxRetries: $lastError',
          );
          retryCount++;

          if (retryCount <= maxRetries) {
            await Future.delayed(
              _calculateRetryDelay(retryCount - 1, retryDelay),
            );
          }
        }
      }
    } finally {
      // 确保在所有情况下都清除请求记录
      _clearRequestRecord(requestKey);
    }
  }

  /// 计算重试延迟时间（指数退避）
  static Duration _calculateRetryDelay(int retryCount, Duration baseDelay) {
    // 指数退避：第一次重试3秒，第二次重试6秒，第三次重试12秒...
    const multiplier = 1; // 基础倍数
    final actualMultiplier =
        (retryCount == 0) ? multiplier : (1 << retryCount); // 2^retryCount
    final delayMs = baseDelay.inMilliseconds * actualMultiplier;

    // 最大延迟不超过30秒
    const maxDelayMs = 30000;
    return Duration(milliseconds: delayMs > maxDelayMs ? maxDelayMs : delayMs);
  }

  /// 判断错误是否可重试
  static bool _isRetryableError(dynamic error) {
    final errorString = error.toString();

    // 500错误需要更精细的判断
    if (errorString.contains('500')) {
      // 这些500错误通常是持久性问题，不应该重试
      if (errorString.contains('model') &&
          (errorString.contains('not found') ||
              errorString.contains('does not exist') ||
              errorString.contains('invalid model') ||
              errorString.contains('不存在') ||
              errorString.contains('不可用'))) {
        logDebug('检测到模型相关的500错误，停止重试: $errorString');
        return false;
      }

      // API格式错误通常也是持久性问题
      if (errorString.contains('invalid request') ||
          errorString.contains('bad request') ||
          errorString.contains('malformed') ||
          errorString.contains('格式错误')) {
        logDebug('检测到请求格式相关的500错误，停止重试: $errorString');
        return false;
      }

      // 其他500错误可能是临时的服务器问题，可以重试
      logDebug('检测到可重试的500错误: $errorString');
      return true;
    }

    // 502, 503, 504 网关错误，通常是临时问题，可以重试
    if (errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return true;
    }

    // 网络连接问题，可以重试
    if (errorString.contains('Failed host lookup') ||
        errorString.contains('Connection refused') ||
        errorString.contains('timeout') ||
        errorString.contains('网络')) {
      return true;
    }

    // 401（认证失败）、400（请求格式错误）等不应该重试
    if (errorString.contains('401') ||
        errorString.contains('400') ||
        errorString.contains('403') ||
        errorString.contains('404')) {
      return false;
    }

    // 429（频率限制）暂时不重试，让用户手动重试
    if (errorString.contains('429')) return false;

    // 默认不重试
    return false;
  }
}

/// 内部类：调整后的请求数据
class _AdjustedRequest {
  final Map<String, dynamic> requestBody;
  final Map<String, String> headers;

  _AdjustedRequest({required this.requestBody, required this.headers});
}
