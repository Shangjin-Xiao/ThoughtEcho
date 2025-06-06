import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/ai_settings.dart';
import '../models/quote_model.dart';
import '../utils/ai_network_manager.dart';

/// AI请求辅助工具
/// 
/// 统一处理AI请求的通用逻辑，减少重复代码
class AIRequestHelper {
  static final AIRequestHelper _instance = AIRequestHelper._internal();
  factory AIRequestHelper() => _instance;
  AIRequestHelper._internal();

  /// 标准请求参数
  static const Duration defaultTimeout = Duration(seconds: 300);
  static const double defaultTemperature = 0.7;
  static const int defaultMaxTokens = 2500;

  /// 创建标准消息格式
  List<Map<String, dynamic>> createMessages({
    required String systemPrompt,
    required String userMessage,
  }) {
    return [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userMessage},
    ];
  }

  /// 创建标准请求体
  Map<String, dynamic> createRequestBody({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    String? model,
    bool stream = false,
  }) {
    final body = <String, dynamic>{
      'messages': messages,
      'temperature': temperature ?? defaultTemperature,
    };

    if (maxTokens != null) {
      body['max_tokens'] = maxTokens;
    }

    if (model != null && model.isNotEmpty) {
      body['model'] = model;
    }

    if (stream) {
      body['stream'] = true;
    }

    return body;
  }

  /// 发送普通AI请求
  Future<Response> makeRequest({
    required String url,
    required String systemPrompt,
    required String userMessage,
    required AISettings settings,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    final messages = createMessages(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );

    final body = createRequestBody(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      model: model ?? settings.model,
    );

    return await AINetworkManager.makeRequest(
      url: url,
      data: body,
      legacySettings: settings,
      timeout: defaultTimeout,
    );
  }

  /// 发送流式AI请求
  Future<void> makeStreamRequest({
    required String url,
    required String systemPrompt,
    required String userMessage,
    required AISettings settings,
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(dynamic) onError,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    final messages = createMessages(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );

    final body = createRequestBody(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      model: model ?? settings.model,
      stream: true,
    );

    await AINetworkManager.makeStreamRequest(
      url: url,
      data: body,
      legacySettings: settings,
      onData: onData,
      onComplete: onComplete,
      onError: onError,
      timeout: defaultTimeout,
    );
  }

  /// 解析API响应
  String parseResponse(Response response) {
    final data = response.data is String ? json.decode(response.data) : response.data;
    
    if (data['choices'] != null &&
        data['choices'].isNotEmpty &&
        data['choices'][0]['message'] != null) {
      return data['choices'][0]['message']['content'];
    } else {
      debugPrint('API响应格式错误: $data');
      throw Exception('API响应格式错误');
    }
  }

  /// 创建流式控制器并处理通用逻辑
  StreamController<String> createStreamController() {
    return StreamController<String>.broadcast();
  }

  /// 处理流式响应的通用逻辑
  void handleStreamResponse({
    required StreamController<String> controller,
    required String chunk,
  }) {
    if (!controller.isClosed) {
      controller.add(chunk);
    }
  }

  /// 处理流式完成的通用逻辑
  void handleStreamComplete({
    required StreamController<String> controller,
    String? fullText,
  }) {
    if (!controller.isClosed) {
      controller.close();
    }
  }

  /// 处理流式错误的通用逻辑
  void handleStreamError({
    required StreamController<String> controller,
    required dynamic error,
    String? context,
  }) {
    if (context != null) {
      debugPrint('$context错误: $error');
    }
    if (!controller.isClosed) {
      controller.addError(error);
      controller.close();
    }
  }

  /// 将笔记列表转换为JSON格式（用于洞察分析）
  Map<String, dynamic> convertQuotesToJson(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
  }) {
    return {
      'metadata': {
        'app': '心迹',
        'version': '1.0',
        'exportTime': DateTime.now().toIso8601String(),
        'analysisType': analysisType,
        'analysisStyle': analysisStyle,
      },
      'quotes': quotes.map((quote) {
        return {
          'id': quote.id,
          'content': quote.content,
          'date': quote.date,
          'source': quote.source,
          'sourceAuthor': quote.sourceAuthor,
          'tagIds': quote.tagIds,
          'categoryId': quote.categoryId,
          'location': quote.location,
          'weather': quote.weather,
          'temperature': quote.temperature,
        };
      }).toList(),
    };
  }

  /// 将JSON数据转换为格式化字符串
  String formatJsonData(Map<String, dynamic> jsonData) {
    return const JsonEncoder.withIndent('  ').convert(jsonData);
  }

  /// 执行带有通用错误处理的异步操作
  Future<T> executeWithErrorHandling<T>({
    required Future<T> Function() operation,
    required String context,
  }) async {
    try {
      return await operation();
    } catch (e) {
      debugPrint('$context错误: $e');
      rethrow;
    }
  }

  /// 创建并执行流式操作的通用模式
  Stream<String> executeStreamOperation({
    required Future<void> Function(StreamController<String>) operation,
    required String context,
  }) {
    final controller = createStreamController();

    () async {
      try {
        await operation(controller);
      } catch (e) {
        handleStreamError(
          controller: controller,
          error: e,
          context: context,
        );
      }
    }();

    return controller.stream;
  }
}
