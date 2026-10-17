import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/ai_settings.dart';
import '../models/ai_provider_settings.dart';
import '../models/quote_model.dart';
import '../utils/ai_network_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import '../models/chat_message.dart';

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

  /// 构建带历史上下文的消息列表（token 预算截断）
  ///
  /// 返回 [system prompt, ...selected history]。
  /// **不追加当前轮 userMessage**——调用方自行追加。
  List<Map<String, dynamic>> createMessagesWithHistory({
    required String systemPrompt,
    required List<ChatMessage> history,
    int currentUserMessageLength = 0,
    int maxChars = 6000,
    int singleMessageCap = 1200,
  }) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    // 只保留 includedInContext && 非 loading 的 user/assistant 消息
    final contextMessages = history
        .where(
          (m) =>
              m.includedInContext &&
              !m.isLoading &&
              (m.role == 'user' || m.role == 'assistant'),
        )
        .toList();

    if (contextMessages.isEmpty) return messages;

    int usedChars = 0;
    final budget = maxChars - currentUserMessageLength;
    final selected = <Map<String, dynamic>>[];

    for (int i = contextMessages.length - 1; i >= 0; i--) {
      final msg = contextMessages[i];
      String content = msg.content;
      final meta = msg.parsedMeta;
      if (msg.role == 'assistant' &&
          meta != null &&
          (meta['saved_note_id'] != null || meta['applied'] == true)) {
        content += '\n\n[系统提示：用户已采纳并应用了上述提案/编辑建议]';
      }
      if (content.length > singleMessageCap) {
        content = '${content.substring(0, singleMessageCap)}...';
      }
      if (usedChars + content.length > budget) break;
      usedChars += content.length;
      selected.insert(0, {'role': msg.role, 'content': content});
    }

    messages.addAll(selected);
    return messages;
  }

  /// 创建标准请求体
  @Deprecated('Use OpenAIStreamService instead')
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
  @Deprecated('Use OpenAIStreamService instead')
  Future<Response> makeRequestWithProvider({
    required String url,
    required String systemPrompt,
    required String userMessage,
    required AIProviderSettings provider,
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
  @Deprecated('Use OpenAIStreamService instead')
  Future<void> makeStreamRequestWithProvider({
    required String url,
    required String systemPrompt,
    required String userMessage,
    required AIProviderSettings provider,
    required Function(String) onData,
    required Function(String) onComplete,
    required Function(dynamic) onError,
    Function(String)? onThinking,
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

  /// 解析API响应
  String parseResponse(Response response) {
    final data =
        response.data is String ? json.decode(response.data) : response.data;

    if (data['choices'] != null &&
        data['choices'].isNotEmpty &&
        data['choices'][0]['message'] != null) {
      return data['choices'][0]['message']['content'];
    } else {
      if (kDebugMode) {
        logDebug('API响应格式错误: $data');
      }
      throw Exception('API响应格式错误');
    }
  }

  /// 创建流式控制器并处理通用逻辑
  StreamController<String> createStreamController() {
    return StreamController<String>(sync: true);
  }

  /// 单次洞察分析最多送出的笔记条数。
  ///
  /// 调用方传进来的往往是「全部笔记」，攒了几年的库直接整个进请求体，
  /// context 先炸、token 后烧。取最近的这些条已经足够看出长期模式。
  static const int maxQuotesForAnalysis = 200;

  /// 单次洞察分析最多送出的正文字符数（在条数上限之上再兜一道）。
  ///
  /// 200 条短笔记和 200 条长文差着一个数量级，只卡条数拦不住后者。
  static const int maxContentCharsForAnalysis = 60000;

  /// 单条笔记最多送出的正文字符数。
  ///
  /// 没有这道限制的话，一条超长笔记就能把总预算整个吃掉——原来「第一条无条件
  /// 收下」的写法更极端：单条 20 万字也照发不误，字数上限形同虚设。
  static const int maxCharsPerQuote = 4000;

  /// 把单条正文压到 [maxCharsPerQuote] 以内，截断时留个明显的标记。
  static String clampQuoteContent(String content) {
    if (content.length <= maxCharsPerQuote) return content;
    return '${content.substring(0, maxCharsPerQuote)}……（后略）';
  }

  /// 挑出送去分析的笔记：按时间倒序取最近的，卡住条数和字数两道上限，
  /// 再按时间正序还回去——成长轨迹类的分析要顺着读才成立。
  ///
  /// 字数按截断后的长度计，所以三道上限（单条 / 总字数 / 条数）是同时成立的。
  List<Quote> selectQuotesForAnalysis(List<Quote> quotes) {
    final sorted = List<Quote>.from(quotes)
      ..sort((a, b) => b.date.compareTo(a.date));

    final picked = <Quote>[];
    var chars = 0;
    for (final quote in sorted) {
      if (picked.length >= maxQuotesForAnalysis) break;
      final length = clampQuoteContent(quote.content).length;
      // 第一条无条件收下：截断之后它已经不超过 maxCharsPerQuote 了，不至于
      // 撑爆预算，但空手交给模型更没意义。
      if (picked.isNotEmpty && chars + length > maxContentCharsForAnalysis) {
        break;
      }
      picked.add(quote);
      chars += length;
    }

    return picked.reversed.toList();
  }

  /// 将笔记列表转换为JSON格式（用于洞察分析）
  ///
  /// 超出上限时只送最近的一段，并在 metadata 里说明被截断过——不写清楚
  /// 的话模型会把「最近 200 条」当成用户的全部记录来下结论。
  Map<String, dynamic> convertQuotesToJson(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
    String? userNickname,
    String? defaultAuthor,
    String? defaultSource,
    Iterable<String>? userAliases,
  }) {
    final selected = selectQuotesForAnalysis(quotes);
    final truncated = selected.length < quotes.length ||
        selected.any((quote) => quote.content.length > maxCharsPerQuote);

    return {
      'metadata': {
        'app': '心迹',
        'version': '1.0',
        'exportTime': DateTime.now().toIso8601String(),
        'analysisType': analysisType,
        'analysisStyle': analysisStyle,
        'totalQuotes': quotes.length,
        'includedQuotes': selected.length,
        // 摘录 / 原创的条数摆在开头：一组里九成是摘录时，"这个人这周在想
        // 什么"根本无从谈起，模型得先知道自己手上是什么，而不是读完全部
        // 再回头改口。
        'originalCount': selected
            .where((quote) => quote.isOriginal(
                  userNickname: userNickname,
                  defaultAuthor: defaultAuthor,
                  defaultSource: defaultSource,
                  userAliases: userAliases,
                ))
            .length,
        'excerptCount': selected
            .where((quote) => quote.isExcerpt(
                  userNickname: userNickname,
                  defaultAuthor: defaultAuthor,
                  defaultSource: defaultSource,
                  userAliases: userAliases,
                ))
            .length,
        'truncated': truncated,
        if (truncated) 'truncationNote': '内容有截断：只含最近的部分笔记，超长笔记的正文也被截短',
      },
      'quotes': selected.map((quote) {
        return {
          // 不送 id：36 个字符的 UUID 对分析毫无信息量，只是在烧 token。
          //
          // type 放在第一位：模型得先知道这段是谁写的，再读正文。放在
          // sourceAuthor 后面等于让它读完整段才发现"哦这是摘录"——而它
          // 那时已经把这段当成用户的自白读进去了。
          'type': quote.resolveAttributionKind(
            userNickname: userNickname,
            defaultAuthor: defaultAuthor,
            defaultSource: defaultSource,
            userAliases: userAliases,
          ),
          'content': clampQuoteContent(quote.content),
          'date': quote.date,
          'source': quote.source,
          'sourceAuthor': quote.sourceAuthor,
          'sourceWork': quote.sourceWork,
          'tagIds': quote.tagIds,
          'categoryId': quote.categoryId,
          'location': quote.location,
          'weather': quote.weather,
          'temperature': quote.temperature,
          'dayPeriod': quote.dayPeriod,
        };
      }).toList(),
    };
  }

  /// 将JSON数据转换为格式化字符串
  ///
  /// 不缩进：这份 JSON 是发给模型的，不是给人读的，缩进只是把空白字符
  /// 当 token 卖钱。
  String formatJsonData(Map<String, dynamic> jsonData) {
    return json.encode(jsonData);
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
}
