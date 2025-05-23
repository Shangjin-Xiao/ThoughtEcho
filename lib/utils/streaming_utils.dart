import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_settings.dart';
import '../services/secure_storage_service.dart';

// 定义流式响应的回调类型
typedef StreamingResponseCallback = void Function(String text);
typedef StreamingCompleteCallback = void Function(String fullText);
typedef StreamingErrorCallback = void Function(dynamic error);

/// 流式传输工具类
/// 处理各种AI服务提供商的流式HTTP请求
class StreamingUtils {
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

  /// 获取有效的API密钥
  static Future<String> _getEffectiveApiKey(AISettings settings) async {
    try {
      final secureStorage = SecureStorageService();
      final secureApiKey = await secureStorage.getApiKey();
      return secureApiKey ?? settings.apiKey;
    } catch (e) {
      debugPrint('获取安全存储API密钥失败: $e，使用设置中的密钥');
      return settings.apiKey;
    }
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
        'stream': true,
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
        'stream': true,
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
        'stream': true,
      };
      headers['Authorization'] = 'Bearer $apiKey';
    } else {
      // 默认格式(适用于OpenAI及其兼容API)
      requestBody = {
        'model': body['model'],
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true,
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
    final Uri uri = Uri.parse(url);
    debugPrint('流式请求URL: $uri');

    // 打印安全的请求信息（隐藏敏感信息）
    final safeHeaders = Map<String, String>.from(headers);
    _hideSensitiveInfo(safeHeaders);
    debugPrint('请求头: $safeHeaders');
    debugPrint('请求体: ${json.encode(requestBody)}');

    http.Client? client;
    try {
      client = http.Client();
      final request = http.Request('POST', uri);
      request.headers.addAll(headers);
      request.body = json.encode(requestBody);

      final streamedResponse = await client
          .send(request)
          .timeout(
            timeout,
            onTimeout: () {
              onError(Exception('请求超时，AI分析可能需要更长时间，请稍后再试'));
              client?.close();
              // 返回一个空的StreamedResponse
              return http.StreamedResponse(
                Stream.fromIterable([]),
                408, // Request Timeout
                headers: {},
              );
            },
          );

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        final errorMessage = _parseErrorMessage(
          streamedResponse.statusCode,
          errorBody,
        );
        onError(Exception(errorMessage));
        return;
      }

      // 处理流式响应
      await _processStreamResponse(
        streamedResponse,
        onResponse,
        onComplete,
        onError,
      );
    } catch (e) {
      debugPrint('流式请求异常: $e');
      onError(e);
    } finally {
      client?.close();
    }
  }

  /// 处理流式响应数据
  static Future<void> _processStreamResponse(
    http.StreamedResponse streamedResponse,
    StreamingResponseCallback onResponse,
    StreamingCompleteCallback onComplete,
    StreamingErrorCallback onError,
  ) async {
    String fullText = '';
    String currentChunk = '';

    try {
      await for (String chunk in streamedResponse.stream.transform(
        utf8.decoder,
      )) {
        currentChunk += chunk;

        // 按行处理数据
        final lines = currentChunk.split('\n');
        currentChunk = lines.last; // 保留最后一行（可能是不完整的）

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty || !line.startsWith('data: ')) continue;

          if (line == 'data: [DONE]') {
            debugPrint('流式响应完成');
            onComplete(fullText);
            return;
          }

          final content = _extractContentFromLine(line);
          if (content != null && content.isNotEmpty) {
            fullText += content;
            onResponse(content);
          }
        }
      }

      debugPrint('流式响应接收完毕');
      onComplete(fullText);
    } catch (e) {
      debugPrint('处理流式响应时出错: $e');
      onError(e);
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
          return choice['delta']['content'];
        }

        // 旧格式 (text)
        if (choice['text'] != null) {
          return choice['text'];
        }
      }

      return null;
    } catch (e) {
      debugPrint('解析流式数据失败: $e, 原始数据: $line');
      return null;
    }
  }

  /// 解析错误消息
  static String _parseErrorMessage(int statusCode, String errorBody) {
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
    } else {
      return 'AI服务请求失败：$statusCode\n$errorBody';
    }
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
}

/// 内部类：调整后的请求数据
class _AdjustedRequest {
  final Map<String, dynamic> requestBody;
  final Map<String, String> headers;

  _AdjustedRequest({required this.requestBody, required this.headers});
}
