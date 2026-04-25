import 'package:flutter/foundation.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import '../models/quote_model.dart';
import '../models/chat_message.dart';
import '../models/ai_provider_settings.dart';
import '../services/settings_service.dart' show SettingsService;
import '../services/api_key_manager.dart';
import '../services/openai_stream_service.dart';
import 'dart:async';
import '../utils/daily_prompt_generator.dart';
import '../utils/ai_prompt_manager.dart';
import '../utils/ai_request_helper.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import '../gen_l10n/app_localizations.dart';
import 'web_fetch_service.dart';

// 定义流式响应的回调类型
typedef StreamingResponseCallback = void Function(String text);
typedef StreamingCompleteCallback = void Function(String fullText);
typedef StreamingErrorCallback = void Function(dynamic error);

class AIService extends ChangeNotifier {
  final SettingsService _settingsService;
  final APIKeyManager _apiKeyManager = APIKeyManager();
  final AIPromptManager _promptManager = AIPromptManager();
  final AIRequestHelper _requestHelper = AIRequestHelper();
  final OpenAIStreamService _openAIStreamService = OpenAIStreamService();

  AIService({required SettingsService settingsService})
      : _settingsService = settingsService;

  Future<void> _validateSettings({bool testNetwork = false}) async {
    try {
      final multiSettings = _settingsService.multiAISettings;

      // 1. 检查是否选择了AI服务商
      if (multiSettings.currentProvider == null) {
        throw Exception('请先选择AI服务商');
      }

      final currentProvider = multiSettings.currentProvider!;

      // 2. 验证API URL
      if (currentProvider.apiUrl.trim().isEmpty) {
        throw Exception('请先配置 API URL');
      }

      final urlValid =
          Uri.tryParse(currentProvider.apiUrl)?.isAbsolute ?? false;
      if (!urlValid) {
        throw Exception('API URL格式无效，请输入完整的URL地址');
      }

      // 3. 验证模型名称
      if (currentProvider.model.trim().isEmpty) {
        throw Exception('AI模型名称不能为空');
      }

      // 4. 验证API密钥（统一检查）
      final hasApiKey = await _apiKeyManager.hasValidProviderApiKey(
        currentProvider.id,
      );
      if (!hasApiKey) {
        throw Exception('请先为 ${currentProvider.name} 配置有效的API密钥');
      }

      // 记录验证成功信息
      final apiKey = await _apiKeyManager.getProviderApiKey(currentProvider.id);
      logDebug(
        '验证设置成功 - Provider: ${currentProvider.name}, API Key长度: ${apiKey.length}',
      );

      // 5. 可选的网络连接测试
      if (testNetwork) {
        final hasConnection = await _testConnection(currentProvider);
        if (!hasConnection) {
          throw Exception('无法连接到AI服务，请检查网络连接和配置');
        }
      }
    } catch (e) {
      if (e.toString().contains('请先')) {
        rethrow;
      }
      throw Exception('AI设置验证失败: $e');
    }
  }

  /// 验证网络连接（可选调用，避免每次验证都进行网络请求）
  Future<bool> _testConnection(AIProviderSettings provider) async {
    try {
      final content = await _chatCompletionViaOpenAI(
        systemPrompt: AIPromptManager.connectionTestPrompt,
        userMessage: '测试连接',
        provider: provider,
        temperature: 0.1,
        maxTokens: 50,
      );

      final preview =
          content.length > 20 ? '${content.substring(0, 20)}...' : content;
      logDebug('AI连接测试成功: $preview');
      return true;
    } catch (e) {
      logDebug('AI连接测试失败: $e');
      return false;
    }
  }

  /// 同步检查API Key是否有效 (用于UI快速判断)
  /// 注意：这个方法只做基本检查，实际验证需要使用异步方法
  bool hasValidApiKey() {
    try {
      final multiSettings = _settingsService.multiAISettings;

      // 检查当前provider的API Key
      if (multiSettings.currentProvider != null) {
        final currentProvider = multiSettings.currentProvider!;

        // 首先检查provider是否启用
        if (!currentProvider.isEnabled) {
          return false;
        }

        // 基本检查：provider存在且启用
        // 实际的API Key验证通过异步方法进行
        return true;
      }

      // 如果没有当前provider，检查是否有任何可用的provider
      final availableProviders =
          multiSettings.providers.where((p) => p.isEnabled).toList();

      return availableProviders.isNotEmpty;
    } catch (e) {
      logDebug('检查API Key有效性失败: $e');
      return false;
    }
  }

  /// 异步检查当前供应商的API Key是否有效（从安全存储验证）
  Future<bool> hasValidApiKeyAsync() async {
    try {
      final multiSettings = _settingsService.multiAISettings;

      if (multiSettings.currentProvider != null) {
        final currentProvider = multiSettings.currentProvider!;

        // 检查provider是否启用
        if (!currentProvider.isEnabled) {
          return false;
        }

        // 从安全存储验证API密钥
        final hasValidKey = await _apiKeyManager.hasValidProviderApiKey(
          currentProvider.id,
        );

        return hasValidKey;
      }

      return false;
    } catch (e) {
      logDebug('异步检查API Key有效性失败: $e');
      return false;
    }
  }

  /// 获取带有API Key的当前provider副本
  /// 这个方法确保返回的provider包含从加密存储读取的真实API Key
  Future<AIProviderSettings> _getCurrentProviderWithApiKey() async {
    final multiSettings = _settingsService.multiAISettings;

    if (multiSettings.currentProvider == null) {
      throw Exception('请先选择AI服务商');
    }

    final currentProvider = multiSettings.currentProvider!;

    // 从加密存储获取真实的API Key
    final apiKey = await _apiKeyManager.getProviderApiKey(currentProvider.id);
    logDebug(
      '获取当前Provider - ${currentProvider.name}, API Key长度: ${apiKey.length}',
    );

    // 创建provider副本并注入API Key
    final providerWithApiKey = currentProvider.copyWith(
      apiKey: apiKey, // 注入真实的API Key
    );

    return providerWithApiKey;
  }

  /// 构建聊天消息列表（用于 OpenAIStreamService）
  ///
  /// 将系统提示词和用户消息转换为 openai_dart 的
  /// ChatMessage 格式，支持可选的历史对话上下文。
  List<openai.ChatMessage> _buildChatMessages({
    required String systemPrompt,
    required String userMessage,
    List<ChatMessage>? history,
  }) {
    final messages = <openai.ChatMessage>[
      openai.ChatMessage.system(systemPrompt),
    ];

    if (history != null && history.isNotEmpty) {
      final contextMessages = history
          .where(
            (m) =>
                m.includedInContext &&
                !m.isLoading &&
                (m.role == 'user' || m.role == 'assistant'),
          )
          .toList();

      // Token 预算截断：保留近期的对话历史
      int usedChars = 0;
      final budget = 6000 - userMessage.length;
      final singleMessageCap = 1200;

      for (int i = contextMessages.length - 1; i >= 0; i--) {
        String content = contextMessages[i].content;
        if (content.length > singleMessageCap) {
          content = '${content.substring(0, singleMessageCap)}...';
        }
        if (usedChars + content.length > budget) break;
        usedChars += content.length;
        messages.insert(
          messages.length,
          contextMessages[i].isUser
              ? openai.ChatMessage.user(content)
              : openai.ChatMessage.assistant(content: content),
        );
      }
    }

    messages.add(openai.ChatMessage.user(userMessage));
    return messages;
  }

  /// 内部流式请求辅助方法（通过 OpenAIStreamService）
  ///
  /// 统一封装流式请求逻辑：验证 → 获取 provider → 构建消息 → 调用流式服务。
  /// 所有迁移到 OpenAIStreamService 的流式方法都用此辅助方法。
  Stream<String> _streamViaOpenAI({
    required String systemPrompt,
    required String userMessage,
    List<ChatMessage>? history,
    double? temperature,
    int? maxTokens,
    bool? enableThinking,
    Function(String)? onThinking,
  }) {
    final controller = StreamController<String>(sync: true);

    () async {
      try {
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        var provider = await _getCurrentProviderWithApiKey();
        if (enableThinking != null) {
          provider = provider.copyWith(enableThinking: enableThinking);
        }

        final messages = _buildChatMessages(
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          history: history,
        );

        await for (final chunk in _openAIStreamService.streamChatWithThinking(
          provider: provider,
          messages: messages,
          temperature: temperature ?? provider.temperature,
          maxTokens:
              maxTokens ?? (provider.maxTokens > 0 ? provider.maxTokens : null),
          enableThinking: enableThinking,
          onThinking: onThinking,
        )) {
          if (controller.isClosed) break;
          controller.add(chunk);
        }
      } catch (e, stack) {
        logError('AIService._streamViaOpenAI', error: e, stackTrace: stack);
        if (!controller.isClosed) {
          controller.addError(e, stack);
        }
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  /// 内部非流式请求辅助方法（通过 OpenAIStreamService）
  ///
  /// 用于非流式请求如 generateSessionTitle，避免 405 错误。
  Future<String> _chatCompletionViaOpenAI({
    required String systemPrompt,
    required String userMessage,
    AIProviderSettings? provider,
    double? temperature,
    int? maxTokens,
    bool? enableThinking,
  }) async {
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    await _validateSettings();
    final resolvedProvider = provider != null
        ? provider.copyWith(
            apiKey: await _apiKeyManager.getProviderApiKey(provider.id),
          )
        : await _getCurrentProviderWithApiKey();

    final messages = <openai.ChatMessage>[
      openai.ChatMessage.system(systemPrompt),
      openai.ChatMessage.user(userMessage),
    ];

    return await _openAIStreamService.chatCompletion(
      provider: resolvedProvider,
      messages: messages,
      temperature: temperature ?? resolvedProvider.temperature,
      maxTokens: maxTokens ??
          (resolvedProvider.maxTokens > 0 ? resolvedProvider.maxTokens : null),
      enableThinking: enableThinking,
    );
  }

  Future<String> summarizeNote(Quote quote) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
        final content =
            StringUtils.removeObjectReplacementChar(quote.content).trim();

        if (content.isEmpty) {
          throw Exception('没有可分析的文本内容');
        }

        final userMessage = _promptManager.buildUserMessage(content);
        return await _chatCompletionViaOpenAI(
          systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
          userMessage: userMessage,
        );
      },
      context: '笔记分析',
    );
  } // 流式笔记分析（支持完整元数据）

  /// 流式笔记分析（支持完整元数据）
  ///
  /// 迁移到 OpenAIStreamService：内部委托给 _streamViaOpenAI，
  /// 公开签名不变，调用方零改动。
  Stream<String> streamSummarizeNote(Quote quote, {List<String>? tagNames}) {
    // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
    final content =
        StringUtils.removeObjectReplacementChar(quote.content).trim();

    if (content.isEmpty) {
      final controller = StreamController<String>(sync: true);
      controller.addError(Exception('没有可分析的文本内容'));
      controller.close();
      return controller.stream;
    }

    // 传递完整的笔记元数据给 AI（包括标签）
    final userMessage = _promptManager.buildAnalysisUserMessage(
      content,
      sourceAuthor: quote.sourceAuthor,
      sourceWork: quote.sourceWork,
      location: quote.location,
      weather: quote.weather,
      temperature: quote.temperature,
      dayPeriod: quote.dayPeriod,
      tagNames: tagNames,
    );

    return _streamViaOpenAI(
      systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
      userMessage: userMessage,
    );
  }

  /// 周期/年度报告：流式生成“诗意洞察”
  Stream<String> streamReportInsight({
    required String periodLabel,
    String? mostTimePeriod,
    String? mostWeather,
    String? topTag,
    required int activeDays,
    required int noteCount,
    required int totalWordCount,
    String? notesPreview,
    String? fullNotesContent, // 新增：完整笔记内容用于深度分析
    String? previousInsights, // 新增：历史洞察上下文
  }) {
    // 获取用户设置的语言代码
    final languageCode = _settingsService.localeCode;

    final prompt = _promptManager.getReportInsightSystemPrompt(
      'poetic',
      languageCode: languageCode,
    );
    final user = _promptManager.buildReportInsightUserMessage(
      periodLabel: periodLabel,
      mostTimePeriod: mostTimePeriod,
      mostWeather: mostWeather,
      topTag: topTag,
      activeDays: activeDays,
      noteCount: noteCount,
      totalWordCount: totalWordCount,
      notesPreview: notesPreview,
      fullNotesContent: fullNotesContent,
      previousInsights: previousInsights,
    );

    return _streamViaOpenAI(
      systemPrompt: prompt,
      userMessage: user,
    );
  }

  /// 本地生成报告洞察（不开启AI时）
  String buildLocalReportInsight({
    required String periodLabel,
    String? mostTimePeriod,
    String? mostWeather,
    String? topTag,
    required int activeDays,
    required int noteCount,
    required int totalWordCount,
  }) {
    // 获取用户设置的语言代码
    final languageCode = _settingsService.localeCode;

    return _promptManager.formatLocalReportInsight(
      periodLabel: periodLabel,
      mostTimePeriod: mostTimePeriod,
      mostWeather: mostWeather,
      topTag: topTag,
      activeDays: activeDays,
      noteCount: noteCount,
      totalWordCount: totalWordCount,
      languageCode: languageCode,
    );
  }

  // 新增：流式生成每日提示
  ///
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI，
  /// 保留 API Key 失败时的降级逻辑。
  Stream<String> streamGenerateDailyPrompt(
    AppLocalizations l10n, {
    String? city,
    String? weather,
    String? temperature,
    String? historicalInsights,
  }) {
    // 获取用户设置的语言代码
    final languageCode = _settingsService.localeCode;

    final controller = StreamController<String>(sync: true);

    () async {
      try {
        // 异步检查API Key是否有效
        if (!await hasValidApiKeyAsync()) {
          logDebug('API Key无效，使用DailyPromptGenerator生成每日提示');
          controller.add(DailyPromptGenerator.getDefaultPrompt(l10n));
          await controller.close();
          return;
        }

        // 验证AI设置是否已初始化
        try {
          await _validateSettings();
        } catch (e) {
          logDebug('AI设置验证失败: $e，将使用默认提示');
          controller.add(DailyPromptGenerator.getDefaultPrompt(l10n));
          await controller.close();
          return;
        }

        // 获取包含环境信息的系统提示词
        final systemPromptWithContext =
            _promptManager.getDailyPromptSystemPromptWithContext(
          city: city,
          weather: weather,
          temperature: temperature,
          historicalInsights: historicalInsights,
          languageCode: languageCode,
        );

        final userMessage = _promptManager.buildDailyPromptUserMessage(
          city: city,
          weather: weather,
          temperature: temperature,
        );

        await for (final chunk in _streamViaOpenAI(
          systemPrompt: systemPromptWithContext,
          userMessage: userMessage,
          temperature: 1.0,
          maxTokens: 100,
          // 传空 onThinking 阻止 reasoning 回退到 content，
          // 避免 reasoning-only 模型把思考过程当作每日提示输出
          onThinking: (_) {},
        )) {
          if (controller.isClosed) break;
          controller.add(chunk);
        }
      } catch (e, stack) {
        logError('AIService.streamGenerateDailyPrompt',
            error: e, stackTrace: stack);
        if (!controller.isClosed) {
          controller.addError(e, stack);
        }
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  Future<String> generateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
  }) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        // 将笔记数据转换为JSON格式
        final jsonData = _requestHelper.convertQuotesToJson(
          quotes,
          analysisType: analysisType,
          analysisStyle: analysisStyle,
        );
        final quotesText = _requestHelper.formatJsonData(jsonData);

        // 根据分析类型选择系统提示词
        String systemPrompt = _promptManager.getAnalysisTypePrompt(
          analysisType,
        );
        systemPrompt = _promptManager.appendAnalysisStylePrompt(
          systemPrompt,
          analysisStyle,
        );

        final userMessage = '请分析以下结构化的笔记数据：\n\n$quotesText';
        return await _chatCompletionViaOpenAI(
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          maxTokens: 2500,
        );
      },
      context: '生成洞察',
    );
  }

  // 流式生成洞察
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI。
  Stream<String> streamGenerateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
    String? customPrompt,
  }) {
    // 将笔记数据转换为JSON格式
    final jsonData = _requestHelper.convertQuotesToJson(
      quotes,
      analysisType: analysisType,
      analysisStyle: analysisStyle,
    );
    jsonData['metadata']['customPromptUsed'] =
        (customPrompt != null && customPrompt.isNotEmpty).toString();
    final quotesText = _requestHelper.formatJsonData(jsonData);

    // 根据分析类型选择系统提示词
    String systemPrompt;
    if (customPrompt != null && customPrompt.isNotEmpty) {
      systemPrompt = customPrompt;
    } else {
      systemPrompt = _promptManager.getAnalysisTypePrompt(analysisType);
      systemPrompt = _promptManager.appendAnalysisStylePrompt(
        systemPrompt,
        analysisStyle,
      );
    }

    final userMessage = '请分析以下结构化的笔记数据：\n\n$quotesText';

    return _streamViaOpenAI(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      maxTokens: 2500,
    );
  }

  /// 分析文本来源
  ///
  /// [content] 要分析的文本内容
  /// [existingAuthor] 用户已填写的作者（如有），AI 会验证是否正确
  /// [existingWork] 用户已填写的出处（如有），AI 会验证是否正确
  Future<String> analyzeSource(
    String content, {
    String? existingAuthor,
    String? existingWork,
  }) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        final userMessage = _promptManager.buildSourceAnalysisUserMessage(
          content,
          existingAuthor: existingAuthor,
          existingWork: existingWork,
        );
        return await _chatCompletionViaOpenAI(
          systemPrompt: AIPromptManager.sourceAnalysisPrompt,
          userMessage: userMessage,
          temperature: 0.4, // 使用较低的温度确保格式一致性
          maxTokens: 500,
        );
      },
      context: '分析来源',
    );
  }

  // 生成年度报告HTML
  Future<String> generateAnnualReportHTML(String prompt) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        String result = await _chatCompletionViaOpenAI(
          systemPrompt: AIPromptManager.annualReportPrompt,
          userMessage: _buildEnhancedAnnualReportPrompt(prompt),
          temperature: 0.3, // 使用较低的温度确保格式一致性
          maxTokens: 4000, // 增加token限制以支持完整HTML
        );

        // 验证返回内容是否为HTML格式
        if (!_isValidHtml(result)) {
          // 如果不是HTML格式，尝试包装或生成备用HTML
          result = _generateFallbackHtml(result, prompt);
        }

        return result;
      },
      context: '生成年度报告',
    );
  }

  // 验证是否为有效的HTML格式
  bool _isValidHtml(String content) {
    final trimmed = content.trim();
    return trimmed.toLowerCase().startsWith('<!doctype html') ||
        trimmed.toLowerCase().startsWith('<html');
  }

  // 生成备用HTML报告
  String _generateFallbackHtml(String content, String prompt) {
    // 从prompt中提取数据
    final yearMatch = RegExp(r'年份：(\d{4})').firstMatch(prompt);
    final notesMatch = RegExp(r'总笔记数：(\d+)').firstMatch(prompt);
    final wordsMatch = RegExp(r'总字数：(\d+)').firstMatch(prompt);

    final year = yearMatch?.group(1) ?? DateTime.now().year.toString();
    final totalNotes = notesMatch?.group(1) ?? '0';
    final totalWords = wordsMatch?.group(1) ?? '0';

    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>心迹 $year 年度报告</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
            line-height: 1.6;
        }
        .container {
            max-width: 414px;
            margin: 0 auto;
            background: white;
            min-height: 100vh;
            box-shadow: 0 0 50px rgba(0,0,0,0.1);
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 50px 20px;
            text-align: center;
        }
        .year {
            font-size: 52px;
            font-weight: 800;
            margin-bottom: 10px;
            text-shadow: 0 4px 8px rgba(0,0,0,0.3);
        }
        .subtitle {
            font-size: 20px;
            opacity: 0.95;
            margin-bottom: 30px;
            font-weight: 300;
        }
        .stats {
            display: flex;
            justify-content: space-around;
            background: rgba(255,255,255,0.1);
            border-radius: 20px;
            padding: 20px;
        }
        .stat { text-align: center; flex: 1; }
        .stat-number { font-size: 28px; font-weight: 700; display: block; }
        .stat-label { font-size: 13px; opacity: 0.9; }
        .content {
            padding: 30px 25px;
        }
        .section {
            margin-bottom: 30px;
            padding: 25px;
            background: #f8f9fa;
            border-radius: 16px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }
        .section-title {
            font-size: 20px;
            font-weight: 700;
            margin-bottom: 15px;
            color: #2c3e50;
        }
        .ai-content {
            white-space: pre-wrap;
            word-wrap: break-word;
            font-size: 14px;
            line-height: 1.6;
            color: #444;
        }
        .error-note {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-radius: 8px;
            padding: 15px;
            color: #856404;
            font-size: 13px;
            margin-top: 20px;
        }
        .footer {
            text-align: center;
            padding: 30px;
            background: #f8f9fa;
            border-top: 1px solid #dee2e6;
        }
        .footer-text {
            font-size: 14px;
            color: #6c757d;
            margin-bottom: 10px;
        }
        .footer-logo {
            font-size: 18px;
            font-weight: 700;
            background: linear-gradient(135deg, #667eea, #764ba2);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="year">$year</div>
            <div class="subtitle">✨ 我的思考轨迹 ✨</div>
            <div class="stats">
                <div class="stat">
                    <span class="stat-number">$totalNotes</span>
                    <div class="stat-label">📝 总笔记数</div>
                </div>
                <div class="stat">
                    <span class="stat-number">$totalWords</span>
                    <div class="stat-label">✏️ 总字数</div>
                </div>
                <div class="stat">
                    <span class="stat-number">365</span>
                    <div class="stat-label">📅 记录时光</div>
                </div>
            </div>
        </div>
        
        <div class="content">
            <div class="section">
                <div class="section-title">🎯 AI生成的年度总结</div>
                <div class="ai-content">${content.replaceAll(RegExp(r'[{}"\[\]]'), '').trim()}</div>
                
                ${!content.toLowerCase().contains('html') ? '''
                <div class="error-note">
                    💡 提示：AI返回了文本格式的总结而非HTML报告。这可能是由于模型理解偏差导致的。
                    建议您重新生成报告或联系开发者改进AI提示词。
                </div>
                ''' : ''}
            </div>
            
            <div class="section">
                <div class="section-title">📈 数据回顾</div>
                <div class="ai-content">
今年，您在心迹中记录了 $totalNotes 条珍贵的思考，累计 $totalWords 个字的思想财富。

每一条记录都是您成长路上的足迹，每一个文字都承载着您的思考与感悟。

感谢您与心迹一起，记录下这一年的精彩时光！
                </div>
            </div>
        </div>
        
        <div class="footer">
            <div class="footer-text">🙏 感谢你与心迹一起记录美好的 $year 年</div>
            <div class="footer-text">🚀 继续在 ${int.parse(year) + 1} 年捕捉每一个珍贵的想法 ✨</div>
            <div class="footer-logo">心迹 ThoughtEcho</div>
        </div>
    </div>
</body>
</html>''';
  }

  /// 构建年度报告的增强提示词
  String _buildEnhancedAnnualReportPrompt(String userDataPrompt) {
    return '''$userDataPrompt

重要格式要求：
你必须生成一个完整的HTML文档。以下是基本结构，请参考但不要直接复制，而是根据用户数据生成个性化内容：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>心迹 2024 年度报告</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            min-height: 100vh;
        }
        .container {
            max-width: 400px;
            margin: 0 auto;
            background: white;
            min-height: 100vh;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 20px;
            text-align: center;
        }
        .year { font-size: 48px; font-weight: bold; }
        .stats { display: flex; justify-content: space-around; margin: 20px 0; }
        .section { padding: 30px 20px; border-bottom: 1px solid #eee; }
        .section-title { font-size: 20px; font-weight: bold; margin-bottom: 15px; color: #2c3e50; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="year">2024</div>
            <div>我的思考轨迹</div>
            <div class="stats">
                <div>📝 100篇</div>
                <div>✏️ 5000字</div>
                <div>📅 200天</div>
            </div>
        </div>
        <div class="section">
            <div class="section-title">📊 数据概览</div>
            <p>根据真实数据生成内容...</p>
        </div>
        <div class="section">
            <div class="section-title">✨ 精彩回顾</div>
            <p>展示用户的积极内容...</p>
        </div>
        <div class="section">
            <div class="section-title">🚀 未来展望</div>
            <p>鼓励性的建议...</p>
        </div>
    </div>
</body>
</html>
```

关键要求：
1. 必须输出完整HTML，不要输出JSON、解释文字或代码块标记
2. 用用户的真实数据替换示例数据
3. 保持移动端友好的设计
4. 使用温暖积极的语调
5. 只展示正面积极的内容
6. 确保HTML格式正确

请直接输出HTML代码：''';
  }

  // 流式分析来源
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI。
  Stream<String> streamAnalyzeSource(String content) {
    final userMessage = _promptManager.buildSourceAnalysisUserMessage(content);

    return _streamViaOpenAI(
      systemPrompt: AIPromptManager.sourceAnalysisPrompt,
      userMessage: userMessage,
      temperature: 0.4,
      maxTokens: 500,
    );
  }

  // 润色文本
  Future<String> polishText(String content) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        final userMessage = _promptManager.buildPolishUserMessage(content);
        return await _chatCompletionViaOpenAI(
          systemPrompt: AIPromptManager.textPolishPrompt,
          userMessage: userMessage,
          maxTokens: 1000,
        );
      },
      context: '文本润色',
    );
  }

  // 流式润色文本
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI。
  Stream<String> streamPolishText(String content) {
    final userMessage = _promptManager.buildPolishUserMessage(content);

    return _streamViaOpenAI(
      systemPrompt: AIPromptManager.textPolishPrompt,
      userMessage: userMessage,
      maxTokens: 1000,
    );
  }

  // 续写文本
  Future<String> continueText(String content) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        final userMessage = _promptManager.buildContinuationUserMessage(
          content,
        );
        return await _chatCompletionViaOpenAI(
          systemPrompt: AIPromptManager.textContinuationPrompt,
          userMessage: userMessage,
          temperature: 0.8, // 使用较高的温度以增加创意性
          maxTokens: 1000,
        );
      },
      context: '文本续写',
    );
  }

  // 流式续写文本
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI。
  Stream<String> streamContinueText(String content) {
    final userMessage = _promptManager.buildContinuationUserMessage(content);

    return _streamViaOpenAI(
      systemPrompt: AIPromptManager.textContinuationPrompt,
      userMessage: userMessage,
      temperature: 0.8,
      maxTokens: 1000,
    );
  }

  /// 生成SVG卡片内容
  /// 专门用于AI卡片生成服务的SVG生成方法
  Future<String> generateSVG(String prompt) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        return await _chatCompletionViaOpenAI(
          systemPrompt:
              'You are an expert SVG designer. Generate clean, valid SVG code based on the user\'s requirements. Only return the SVG code without any explanations or markdown formatting.',
          userMessage: prompt,
          temperature: 0.7, // 适中的创意性
          maxTokens: 2000, // 足够生成完整的SVG
        );
      },
      context: 'SVG生成',
    );
  }

  // 向笔记提问
  Future<String> askQuestion(Quote quote, String question) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
        final content =
            StringUtils.removeObjectReplacementChar(quote.content).trim();

        if (content.isEmpty) {
          throw Exception('没有可分析的文本内容');
        }

        final userMessage = _promptManager.buildQAUserMessage(
          content,
          question,
        );
        return await _chatCompletionViaOpenAI(
          systemPrompt: AIPromptManager.noteQAAssistantPrompt,
          userMessage: userMessage,
          temperature: 0.5,
          maxTokens: 1000,
        );
      },
      context: '问答',
    );
  }

  // 流式问答（支持完整笔记元数据）
  /// 流式问答（支持完整笔记元数据 + thinking 回调）
  ///
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI，
  /// 支持 onThinking 回调接收推理内容。
  Stream<String> streamAskQuestion(
    Quote quote,
    String question, {
    List<ChatMessage>? history,
    bool? enableThinking,
    Function(String)? onThinking,
  }) {
    // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
    final content =
        StringUtils.removeObjectReplacementChar(quote.content).trim();

    if (content.isEmpty) {
      final controller = StreamController<String>(sync: true);
      controller.addError(Exception('没有可分析的文本内容'));
      controller.close();
      return controller.stream;
    }

    // 传递完整的笔记元数据给 AI
    final userMessage = _promptManager.buildQAUserMessage(
      content,
      question,
      sourceAuthor: quote.sourceAuthor,
      sourceWork: quote.sourceWork,
      location: quote.location,
      weather: quote.weather,
      temperature: quote.temperature,
      dayPeriod: quote.dayPeriod,
    );

    return _streamViaOpenAI(
      systemPrompt: AIPromptManager.noteQAAssistantPrompt,
      userMessage: userMessage,
      history: history,
      temperature: 0.5,
      maxTokens: 1000,
      enableThinking: enableThinking,
      onThinking: onThinking,
    );
  }

  /// 测试与AI服务的连接
  Future<void> testConnection() async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    await _requestHelper.executeWithErrorHandling(
      operation: () async {
        final content = await _chatCompletionViaOpenAI(
          systemPrompt: AIPromptManager.connectionTestPrompt,
          userMessage: '测试连接',
          temperature: 0.1,
          maxTokens: 50,
          enableThinking: false,
        );

        final preview =
            content.length > 20 ? '${content.substring(0, 20)}...' : content;
        logDebug('AI连接测试成功: $preview');
      },
      context: 'AI连接测试',
    );
  }

  /// 使用多provider测试连接
  Future<void> testConnectionWithMultiProvider() async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    await _requestHelper.executeWithErrorHandling(
      operation: () async {
        final content = await _chatCompletionViaOpenAI(
          systemPrompt: '你是一个AI助手。请简单回复"连接测试成功"。',
          userMessage: '测试连接',
          temperature: 0.1,
          maxTokens: 50,
          enableThinking: false,
        );
        logDebug('多provider连接测试成功: $content');
      },
      context: '多provider连接测试',
    );
  }

  /// 使用多provider进行笔记分析（新版本）
  Future<String> summarizeNoteWithMultiProvider(Quote quote) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    try {
      return await summarizeNote(quote);
    } catch (e) {
      logDebug('多provider笔记分析错误: $e');
      rethrow;
    }
  }

  /// 流式普通对话（支持 thinking 回调）
  ///
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI，
  /// 支持 onThinking 回调接收推理内容。
  Stream<String> streamGeneralConversation(
    String question, {
    List<ChatMessage>? history,
    String? systemContext,
    bool? enableThinking,
    Function(String)? onThinking,
  }) {
    final buffer = StringBuffer();

    if (systemContext != null && systemContext.trim().isNotEmpty) {
      buffer.writeln(systemContext.trim());
      buffer.writeln();
    }

    if (history != null && history.isNotEmpty) {
      final contextHistory = history
          .where((m) => m.includedInContext && !m.isLoading)
          .take(6)
          .toList();
      if (contextHistory.isNotEmpty) {
        buffer.writeln('【最近对话】');
        for (final message in contextHistory) {
          final role = message.isUser ? '用户' : '助手';
          buffer.writeln('$role：${message.content}');
        }
        buffer.writeln();
      }
    }

    buffer.writeln('【当前问题】');
    buffer.write(question);

    return _streamViaOpenAI(
      systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
      userMessage: buffer.toString(),
      history: history,
      maxTokens: 1200,
      enableThinking: enableThinking,
      onThinking: onThinking,
    );
  }

  /// 高级流式对话方法 - SOTA 实时显示支持
  ///
  /// 迁移到 OpenAIStreamService：使用 _streamViaOpenAI。
  /// 注意：原方法返回 Stream<dynamic>，现在返回 Stream<String>，
  /// 因为 OpenAIStreamService 只产生文本 chunk。
  /// 调用方式不变（.listen 仍然工作，String 是 dynamic 的子类型）。
  Stream<dynamic> streamMessageChunks(
    String question, {
    List<ChatMessage>? history,
    String? systemContext,
  }) {
    final buffer = StringBuffer();

    if (systemContext != null && systemContext.trim().isNotEmpty) {
      buffer.writeln(systemContext.trim());
      buffer.writeln();
    }

    if (history != null && history.isNotEmpty) {
      final contextHistory = history
          .where((m) => m.includedInContext && !m.isLoading)
          .take(6)
          .toList();
      if (contextHistory.isNotEmpty) {
        buffer.writeln('【最近对话】');
        for (final message in contextHistory) {
          final role = message.isUser ? '用户' : '助手';
          buffer.writeln('$role：${message.content}');
        }
        buffer.writeln();
      }
    }

    buffer.writeln('【当前问题】');
    buffer.write(question);

    return _streamViaOpenAI(
      systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
      userMessage: buffer.toString(),
      history: history,
      maxTokens: 1200,
    );
  }

  /// 抓取网页内容
  /// [url] 要抓取的网页URL
  /// 返回Markdown格式的网页内容和总结
  Future<String> fetchWebContent(String url) async {
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        // 验证URL格式
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.isAbsolute) {
          throw Exception('无效的URL地址，请提供完整的URL');
        }

        // 真正抓取网页内容（已转为 Markdown 格式）
        final webFetchService = WebFetchService();
        final markdown = await webFetchService.fetchText(url);

        if (markdown.trim().isEmpty) {
          throw Exception('无法从该网页提取到有效文本内容');
        }

        // 截断过长内容，避免超出 token 限制
        final truncated = markdown.length > 6000
            ? '${markdown.substring(0, 6000)}\n\n[内容已截断]'
            : markdown;

        final userMessage = '以下是从 $url 抓取到的网页内容（Markdown 格式），'
            '请总结其中的关键信息和要点：\n\n$truncated';

        return await _chatCompletionViaOpenAI(
          systemPrompt: '你是一个内容总结专家。用户会提供从网页抓取的 Markdown 内容，'
              '请提炼关键信息，生成结构清晰的摘要。',
          userMessage: userMessage,
          maxTokens: 2000,
          temperature: 0.3,
        );
      },
      context: '网页抓取',
    );
  }

  /// 为聊天会话生成标题
  /// [firstUserMessage] 首条用户消息内容
  /// 返回生成的标题（≤50字）
  /// 为聊天会话生成标题
  ///
  /// 迁移到 OpenAIStreamService：使用 _chatCompletionViaOpenAI
  /// 避免 405 错误（openai_dart 正确构造 URL）。
  Future<String> generateSessionTitle(String firstUserMessage) async {
    try {
      if (firstUserMessage.isEmpty) return 'Chat';

      // 优先尝试用 AI 生成标题
      if (await hasValidApiKeyAsync()) {
        try {
          // 限制消息长度为100字以内
          final truncated = firstUserMessage.length > 100
              ? firstUserMessage.substring(0, 100) + '...'
              : firstUserMessage;

          final title = await _chatCompletionViaOpenAI(
            systemPrompt:
                'You are a title generator. Generate a SHORT title (max 10 words, in the same language as the message, no quotes) for the following message.',
            userMessage: truncated,
            temperature: 0.3,
            maxTokens: 30,
            enableThinking: false,
          );

          final trimmedTitle = title.trim();

          // 有效性检查：排除 reasoning-only 模型返回的思考过程
          final lowerTitle = trimmedTitle.toLowerCase();
          final isValidTitle = trimmedTitle.isNotEmpty &&
              trimmedTitle.length <= 50 &&
              !lowerTitle.contains('the user') &&
              !lowerTitle.contains('first,') &&
              !lowerTitle.contains('i need to') &&
              !lowerTitle.contains('let me') &&
              !lowerTitle.contains('thinking');

          if (isValidTitle) {
            return trimmedTitle;
          }

          // 无效标题，降级到本地方法
          logDebug('AI 生成的标题无效（可能是思考过程），降级到本地方法');
        } catch (e) {
          logDebug('AI 标题生成失败，降级到本地方法: $e');
          // 降级：使用本地方法生成标题
        }
      }

      // Fallback: 本地生成标题（取前20个字）
      final cleanMsg = firstUserMessage.trim();
      if (cleanMsg.isEmpty) return 'Chat';

      final maxLen = 20;
      final title = cleanMsg.length > maxLen
          ? cleanMsg.substring(0, maxLen) + '...'
          : cleanMsg;
      return title;
    } catch (e) {
      logError(
        'AIService.generateSessionTitle',
        error: e,
        stackTrace: StackTrace.current,
      );
      return 'Chat';
    }
  }

  /// [url] 要抓取的网页URL
  /// 返回实时推送的Markdown格式内容
  /// 流式网页内容抓取
  ///
  /// 迁移到 OpenAIStreamService：先抓取网页内容，
  /// 再通过 _streamViaOpenAI 进行流式总结。
  Stream<String> streamFetchWebContent(String url) {
    final controller = StreamController<String>(sync: true);

    () async {
      try {
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();

        // 验证URL格式
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.isAbsolute) {
          controller.addError(Exception('无效的URL地址，请提供完整的URL'));
          return;
        }

        // 真正抓取网页内容（已转为 Markdown 格式）
        final webFetchService = WebFetchService();
        final markdown = await webFetchService.fetchText(url);

        if (markdown.trim().isEmpty) {
          controller.addError(Exception('无法从该网页提取到有效文本内容'));
          return;
        }

        // 截断过长内容，避免超出 token 限制
        final truncated = markdown.length > 6000
            ? '${markdown.substring(0, 6000)}\n\n[内容已截断]'
            : markdown;

        final userMessage = '以下是从 $url 抓取到的网页内容（Markdown 格式），'
            '请总结其中的关键信息和要点：\n\n$truncated';

        await for (final chunk in _streamViaOpenAI(
          systemPrompt: '你是一个内容总结专家。用户会提供从网页抓取的 Markdown 内容，'
              '请提炼关键信息，生成结构清晰的摘要。',
          userMessage: userMessage,
          maxTokens: 2000,
          temperature: 0.3,
        )) {
          if (controller.isClosed) break;
          controller.add(chunk);
        }
      } catch (e, stack) {
        logError('AIService.streamFetchWebContent',
            error: e, stackTrace: stack);
        if (!controller.isClosed) {
          controller.addError(e, stack);
        }
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }
}
