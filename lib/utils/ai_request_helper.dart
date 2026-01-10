import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/ai_settings.dart';
import '../models/ai_provider_settings.dart';
import '../models/quote_model.dart';
import '../services/local_ai/text_processing_service.dart';
import '../utils/ai_network_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// AI请求辅助工具
///
/// 统一处理AI请求的通用逻辑，减少重复代码
class AIRequestHelper {
  static final AIRequestHelper _instance = AIRequestHelper._internal();
  factory AIRequestHelper() => _instance;
  AIRequestHelper._internal();

  /// 标准请求参数
  static const Duration defaultTimeout = Duration(seconds: 300);
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
    final body = <String, dynamic>{'messages': messages};

    // 仅当调用方显式提供时才包含，可让服务端使用默认值
    if (temperature != null) {
      body['temperature'] = temperature;
    }

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
      model: model, // 不强制注入settings.model，允许省略以使用服务端默认
    );

    return await AINetworkManager.makeRequest(
      url: url,
      data: body,
      legacySettings: settings,
      timeout: defaultTimeout,
    );
  }

  /// 使用Provider发送普通AI请求
  Future<Response> makeRequestWithProvider({
    required String url,
    required String systemPrompt,
    required String userMessage,
    required AIProviderSettings provider,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    // 本地模型：使用 local:// scheme 走设备端推理，不发网络请求。
    if (_isLocalProviderUrl(url)) {
      final content = await _runLocalModel(systemPrompt: systemPrompt, userMessage: userMessage);
      return _buildOpenAICompatibleResponse(url: url, content: content);
    }

    final messages = createMessages(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );

    final body = createRequestBody(
      messages: messages,
      temperature: temperature, // 仅当显式传入时包含
      maxTokens: maxTokens, // 仅当显式传入时包含
      model: model, // 不强制注入provider.model，允许省略
    );

    return await AINetworkManager.makeRequest(
      url: url,
      data: body,
      provider: provider,
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
    try {
      final messages = createMessages(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
      );

      final body = createRequestBody(
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        model: model, // 不强制注入settings.model
        stream: true,
      );

      // 确保stream参数是boolean类型
      if (body.containsKey('stream') && body['stream'] is! bool) {
        logDebug(
          'Warning: stream parameter is not boolean, converting: ${body['stream']}',
        );
        body['stream'] = body['stream'] == true || body['stream'] == 'true';
      }

      // 暂时继续使用AINetworkManager，保持现有功能稳定
      await AINetworkManager.makeStreamRequest(
        url: url,
        data: body,
        legacySettings: settings,
        onData: onData,
        onComplete: onComplete,
        onError: onError,
        timeout: defaultTimeout,
      );
    } catch (e) {
      logDebug('流式请求设置错误: $e');
      onError(e);
    }
  }

  /// 使用Provider发送流式AI请求
  Future<void> makeStreamRequestWithProvider({
    required String url,
    required String systemPrompt,
    required String userMessage,
    required AIProviderSettings provider,
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(dynamic) onError,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    // 本地模型：不具备真正的 token streaming，这里用“生成后分片”来模拟流式输出。
    if (_isLocalProviderUrl(url)) {
      try {
        final content = await _runLocalModel(systemPrompt: systemPrompt, userMessage: userMessage);
        for (final chunk in _chunkString(content, 48)) {
          onData(chunk);
        }
        onComplete(content);
      } catch (e) {
        onError(e);
      }
      return;
    }

    final messages = createMessages(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );

    final body = createRequestBody(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      model: model, // 不强制注入provider.model，允许省略
    );

    await AINetworkManager.makeStreamRequest(
      url: url,
      data: body,
      provider: provider,
      onData: onData,
      onComplete: onComplete,
      onError: onError,
      timeout: defaultTimeout,
    );
  }

  bool _isLocalProviderUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.scheme == 'local';
  }

  Future<String> _runLocalModel({
    required String systemPrompt,
    required String userMessage,
  }) async {
    final service = TextProcessingService.instance;
    // 这里不依赖 SettingsService / LocalAISettings：AI provider 选择“本地模型”时，
    // 我们按需初始化并加载 Gemma；若模型不存在则由异常交给 UI 做本地化提示。
    return await service.generateFromPrompts(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );
  }

  Response _buildOpenAICompatibleResponse({
    required String url,
    required String content,
  }) {
    return Response(
      requestOptions: RequestOptions(path: url),
      statusCode: 200,
      data: {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': content,
            },
          },
        ],
      },
    );
  }

  Iterable<String> _chunkString(String s, int chunkSize) sync* {
    if (s.isEmpty) return;
    int i = 0;
    while (i < s.length) {
      final end = (i + chunkSize) > s.length ? s.length : (i + chunkSize);
      yield s.substring(i, end);
      i = end;
    }
  }

  /// 解析API响应
  String parseResponse(Response response) {
    final data =
        response.data is String ? json.decode(response.data) : response.data;

    if (data['choices'] != null &&
        data['choices'].isNotEmpty &&
        data['choices'][0]['message'] != null) {
      return data['choices'][0]['message']['content'];
    } else {
      logDebug('API响应格式错误: $data');
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
    required dynamic chunk, // 改为dynamic以便进行类型检查
  }) {
    if (!controller.isClosed) {
      // 确保chunk确实是字符串类型
      if (chunk is String) {
        controller.add(chunk);
      } else {
        logDebug('Warning: chunk不是字符串类型: ${chunk.runtimeType} = $chunk');
        // 尝试转换为字符串
        try {
          final stringChunk = chunk.toString();
          controller.add(stringChunk);
        } catch (e) {
          logDebug('无法将chunk转换为字符串: $e');
          handleStreamError(
            controller: controller,
            error: Exception('流式响应数据类型错误: ${chunk.runtimeType}'),
            context: '流式响应处理',
          );
        }
      }
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
      logDebug('$context错误: $error');
      // 添加更详细的错误信息
      if (error.toString().contains('type') &&
          error.toString().contains('subtype')) {
        logDebug('检测到类型转换错误，可能是stream参数类型问题');
        logDebug('错误详情: ${error.runtimeType} - $error');

        // 检查是否是布尔值到字符串的转换错误
        if (error.toString().contains('bool') &&
            error.toString().contains('String')) {
          logDebug('这是一个布尔值到字符串的类型转换错误');
          logDebug('可能的原因：');
          logDebug('1. API响应中的content字段是boolean而不是string');
          logDebug('2. 某个地方期望字符串但收到了boolean值');
          logDebug('3. JSON解析过程中的类型不匹配');
        }
      }

      // 打印完整的错误堆栈
      if (error is Exception) {
        logDebug('异常类型: ${error.runtimeType}');
      }
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
      logDebug('$context错误: $e');
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
        handleStreamError(controller: controller, error: e, context: context);
      }
    }();

    return controller.stream;
  }
}
