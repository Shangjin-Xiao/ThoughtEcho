import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as openai;

import '../models/ai_provider_settings.dart';
import '../utils/app_logger.dart';

/// OpenAI 兼容服务的流式传输核心
///
/// 封装 openai_dart 的 OpenAIClient，提供：
/// - `streamChat()`: 流式聊天 → `Stream<String>`
/// - `streamChatWithThinking()`: 流式聊天带思考内容回调
/// - `chatCompletion()`: 非流式聊天 → `Future<String>`
///
/// URL 构造由 openai_dart 内部处理（客户端会自动追加
/// `/chat/completions`），不再手动拼接路径，避免 405 错误。
class OpenAIStreamService extends ChangeNotifier {
  /// 规范化 OpenAI 兼容的 base URL
  ///
  /// 将用户配置的各种 URL 格式统一为 openai_dart 能正确处理的格式：
  /// - `https://api.openai.com/v1/chat/completions` →
  ///   `https://api.openai.com/v1`
  /// - `http://localhost:11434/v1` → `http://localhost:11434/v1`
  /// - `http://localhost:11434` → `http://localhost:11434/v1`
  /// - `https://api.deepseek.com` → `https://api.deepseek.com/v1`
  ///
  /// openai_dart 会自动在 baseUrl 后追加 `/chat/completions`，
  /// 所以我们只需要提供不含 `/chat/completions` 的 baseUrl。
  static String normalizeOpenAIBaseUrl(String apiUrl) {
    final trimmed = apiUrl.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('无效的 API URL 格式: 空字符串');
    }

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (e) {
      throw FormatException('无效的 API URL 格式: "$trimmed"');
    }

    var path = uri.path;

    // 移除 /chat/completions 后缀（用户可能直接粘贴完整 endpoint）
    const chatSuffix = '/chat/completions';
    if (path.endsWith(chatSuffix)) {
      path = path.substring(0, path.length - chatSuffix.length);
      if (path.isEmpty) {
        path = '/v1';
      }
    }

    // 移除末尾斜杠
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    // 如果路径为空或只有 /，则添加 /v1
    if (path.isEmpty || path == '/') {
      path = '/v1';
    }

    // 如果路径不以 /v1 结尾且不是已知的 API 路径（如
    // OpenRouter 的 /api/v1），则追加 /v1。
    // 对于已有路径如 /api/v1 的保持不变
    if (!path.endsWith('/v1') && !path.contains('/v1/') && path != '/v1') {
      path = '$path/v1';
    }

    // 移除 query 和 fragment
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  /// 从 AIProviderSettings 构建 OpenAIConfig
  ///
  /// 为每个请求构建独立的 client 配置，支持多 provider 切换。
  static openai.OpenAIConfig buildOpenAIConfig(
    AIProviderSettings provider,
  ) {
    final normalizedUrl = normalizeOpenAIBaseUrl(provider.apiUrl);

    // 构建请求头（排除 Content-Type，由 http 包自动处理）
    final headers = Map<String, String>.from(provider.buildHeaders())
      ..removeWhere((key, _) => key.toLowerCase() == 'content-type');

    // OpenRouter 需要额外的头
    if (provider.id == 'openrouter' ||
        provider.apiUrl.contains('openrouter.ai')) {
      headers['HTTP-Referer'] ??= 'https://thoughtecho.app';
      headers['X-Title'] ??= 'ThoughtEcho App';
    }

    return openai.OpenAIConfig(
      baseUrl: normalizedUrl,
      authProvider: provider.apiKey.isNotEmpty
          ? openai.ApiKeyProvider(provider.apiKey)
          : null,
      defaultHeaders: headers,
      timeout: const Duration(minutes: 3),
      retryPolicy: const openai.RetryPolicy(maxRetries: 2),
    );
  }

  /// 构建 ChatCompletionCreateRequest
  ///
  /// 根据提供商设置和请求参数构建 openai_dart 的请求对象。
  /// 注意：openai_dart 的 `ChatCompletionCreateRequest` 不含
  /// `stream` 参数——`createStream()` 方法会自动在请求体中
  /// 注入 `stream: true`。
  static openai.ChatCompletionCreateRequest buildChatRequest({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
  }) {
    return openai.ChatCompletionCreateRequest(
      model: provider.model,
      messages: messages,
      temperature: temperature ?? provider.temperature,
      maxTokens:
          maxTokens ?? (provider.maxTokens > 0 ? provider.maxTokens : null),
    );
  }

  /// 流式聊天，返回 `Stream<String>`
  ///
  /// 每个 String chunk 是增量文本（一个或多个 token）。
  /// 流在完成后自动关闭。
  Stream<String> streamChat({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
  }) {
    return processStreamToText(
      _createStream(
        provider: provider,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
  }

  /// 流式聊天带思考内容回调
  ///
  /// [onThinking] 在收到 reasoning_content/reasoning delta 时回调。
  /// 同时仍然返回 `Stream<String>` 用于普通响应文本。
  ///
  /// 对于 Ollama 模型，当 [enableThinking] 为 true 时，
  /// 会在请求体中注入 `think: true` 参数（通过自定义 SSE 流）。
  Stream<String> streamChatWithThinking({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
    bool? enableThinking,
    void Function(String thinkingContent)? onThinking,
  }) {
    return processStreamToText(
      _createStream(
        provider: provider,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        enableThinking: enableThinking,
      ),
      onThinking: onThinking,
    );
  }

  /// 非流式聊天完成请求
  ///
  /// 返回完整的响应文本。
  Future<String> chatCompletion({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
  }) async {
    final config = buildOpenAIConfig(provider);
    final client = openai.OpenAIClient(config: config);

    try {
      final request = openai.ChatCompletionCreateRequest(
        model: provider.model,
        messages: messages,
        temperature: temperature ?? provider.temperature,
        maxTokens:
            maxTokens ?? (provider.maxTokens > 0 ? provider.maxTokens : null),
      );

      logDebug(
        '[OpenAIStreamService] chatCompletion: '
        'model=${provider.model}, baseUrl=${config.baseUrl}',
      );

      final response = await client.chat.completions.create(request);
      return extractTextFromCompletion(response);
    } catch (e, stack) {
      logError(
        'OpenAIStreamService.chatCompletion',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 将 `Stream<ChatStreamEvent>` 转换为 `Stream<String>`
  ///
  /// 提取每个 delta 中的 content 文本，跳过空内容。
  /// 可选的 [onThinking] 回调接收 reasoning_content delta。
  static Stream<String> processStreamToText(
    Stream<openai.ChatStreamEvent> stream, {
    void Function(String thinkingContent)? onThinking,
  }) {
    return stream.asyncExpand((event) {
      final chunks = <String>[];
      final choices = event.choices;
      if (choices == null || choices.isEmpty) {
        return Stream.fromIterable(chunks);
      }

      for (final choice in choices) {
        final delta = choice.delta;

        // 提取普通文本 delta
        if (delta.content != null && delta.content!.isNotEmpty) {
          chunks.add(delta.content!);
        }

        // 提取思考/推理内容（DeepSeek reasoning_content、
        // OpenRouter reasoning）
        if (onThinking != null) {
          if (delta.reasoningContent != null &&
              delta.reasoningContent!.isNotEmpty) {
            onThinking(delta.reasoningContent!);
          }
          if (delta.reasoning != null && delta.reasoning!.isNotEmpty) {
            onThinking(delta.reasoning!);
          }
        }
      }

      return Stream.fromIterable(chunks);
    });
  }

  /// 从 ChatCompletion 响应中提取文本
  static String extractTextFromCompletion(
    openai.ChatCompletion completion,
  ) {
    if (completion.choices.isEmpty) {
      return '';
    }
    return completion.choices.first.message.content ?? '';
  }

  // ========= 私有方法 =========

  /// 创建底层的 `Stream<ChatStreamEvent>`
  ///
  /// 使用 openai_dart 的 `createStream` 方法发起流式请求，
  /// 通过 `StreamController` 管理生命周期并确保 client 正确关闭。
  ///
  /// 对于 Ollama 提供商且 enableThinking=true 的情况，
  /// 需要在请求体中注入 `think: true` 参数。
  /// 由于 openai_dart 4.0.1 的 `ChatCompletionCreateRequest`
  /// 不直接支持 `think` 字段，此处使用原始 HTTP SSE 方式
  /// 发送自定义请求体。
  Stream<openai.ChatStreamEvent> _createStream({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
    bool? enableThinking,
  }) {
    final controller = StreamController<openai.ChatStreamEvent>();

    () async {
      openai.OpenAIClient? client;
      try {
        final config = buildOpenAIConfig(provider);
        final request = buildChatRequest(
          provider: provider,
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
        );

        logDebug(
          '[OpenAIStreamService] streamChat: '
          'model=${provider.model}, '
          'baseUrl=${config.baseUrl}, '
          'thinking=$enableThinking',
        );

        // 判断是否需要注入额外参数（如 Ollama think: true）
        final needsCustomBody =
            enableThinking == true && _isOllamaProvider(provider);

        if (needsCustomBody) {
          // Ollama + thinking: 使用自定义 HTTP 请求注入 think: true
          // 因为 openai_dart 不直接支持此参数
          final requestBody = request.toJson();
          requestBody['think'] = true;
          await _streamWithCustomBody(
            config: config,
            requestBody: requestBody,
            controller: controller,
          );
        } else {
          // 普通请求：直接使用 openai_dart 的 createStream
          client = openai.OpenAIClient(config: config);
          final stream = client.chat.completions.createStream(request);

          await for (final event in stream) {
            if (controller.isClosed) break;
            controller.add(event);
          }
        }

        if (!controller.isClosed) {
          await controller.close();
        }
      } catch (e, stack) {
        logError(
          'OpenAIStreamService._createStream',
          error: e,
          stackTrace: stack,
        );
        if (!controller.isClosed) {
          controller.addError(e, stack);
          await controller.close();
        }
      } finally {
        client?.close();
      }
    }();

    return controller.stream;
  }

  /// 使用自定义 JSON body 发起 SSE 流式请求
  ///
  /// 当需要在请求体中注入 openai_dart 不支持的自定义参数
  /// （如 Ollama 的 `think: true`）时，绕过 openai_dart 的
  /// `createStream`，直接使用 HTTP 请求。
  ///
  /// 此方法手动构建 SSE 请求，将响应体解析为
  /// `ChatStreamEvent` 对象。
  Future<void> _streamWithCustomBody({
    required openai.OpenAIConfig config,
    required Map<String, dynamic> requestBody,
    required StreamController<openai.ChatStreamEvent> controller,
  }) async {
    // 确保流式请求标记
    requestBody['stream'] = true;

    // 构建请求 URL: baseUrl + /chat/completions
    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final url = Uri.parse('$baseUrl/chat/completions');

    // 构建请求头
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
    };

    // 添加认证头
    if (config.authProvider case final auth?) {
      headers.addAll(auth.getHeaders());
    }

    // 添加默认头
    headers.addAll(config.defaultHeaders);

    final jsonBody = jsonEncode(requestBody);
    logDebug(
      '[OpenAIStreamService] _streamWithCustomBody: '
      'POST $url, body length=${jsonBody.length}',
    );

    final httpClient = http.Client();
    try {
      final request = http.Request('POST', url)
        ..headers.addAll(headers)
        ..body = jsonBody;

      final response = await httpClient.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception(
          'AI 请求失败 (HTTP ${response.statusCode}): $body',
        );
      }

      await for (final chunk in response.stream.transform(
        utf8.decoder,
      )) {
        if (controller.isClosed) break;

        // 解析 SSE 数据
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          if (trimmed.startsWith('data: ')) {
            final data = trimmed.substring(6);
            if (data == '[DONE]') continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final event = openai.ChatStreamEvent.fromJson(json);
              if (!controller.isClosed) {
                controller.add(event);
              }
            } catch (e) {
              // 忽略解析错误的行（可能是不完整的 JSON）
              logDebug(
                '[OpenAIStreamService] SSE 解析错误: $e',
              );
            }
          }
        }
      }
    } finally {
      httpClient.close();
    }
  }

  /// 判断是否为 Ollama 提供商
  static bool _isOllamaProvider(AIProviderSettings provider) {
    return provider.id == 'ollama' ||
        provider.apiUrl.contains('localhost:11434') ||
        provider.apiUrl.contains('127.0.0.1:11434') ||
        provider.apiUrl.contains('ollama');
  }
}
