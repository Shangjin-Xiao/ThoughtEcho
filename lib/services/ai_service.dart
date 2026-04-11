import 'package:flutter/foundation.dart';
import '../models/quote_model.dart';
import '../models/chat_message.dart';
import '../models/ai_provider_settings.dart';
import '../services/settings_service.dart' show SettingsService;
import '../services/api_key_manager.dart';
import 'dart:async';
import '../utils/daily_prompt_generator.dart';
import '../utils/ai_network_manager.dart';
import '../utils/ai_prompt_manager.dart';
import '../utils/ai_request_helper.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import '../gen_l10n/app_localizations.dart';

// 定义流式响应的回调类型
typedef StreamingResponseCallback = void Function(String text);
typedef StreamingCompleteCallback = void Function(String fullText);
typedef StreamingErrorCallback = void Function(dynamic error);

class AIService extends ChangeNotifier {
  final SettingsService _settingsService;
  final APIKeyManager _apiKeyManager = APIKeyManager();
  final AIPromptManager _promptManager = AIPromptManager();
  final AIRequestHelper _requestHelper = AIRequestHelper();

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
      final response = await _requestHelper.makeRequestWithProvider(
        url: provider.apiUrl,
        systemPrompt: AIPromptManager.connectionTestPrompt,
        userMessage: '测试连接',
        provider: provider,
        temperature: 0.1,
        maxTokens: 50,
      );

      final content = _requestHelper.parseResponse(response);
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
    final providerWithApiKey = AIProviderSettings(
      id: currentProvider.id,
      name: currentProvider.name,
      apiUrl: currentProvider.apiUrl,
      model: currentProvider.model,
      apiKey: apiKey, // 注入真实的API Key
      isEnabled: currentProvider.isEnabled,
      maxTokens: currentProvider.maxTokens,
      temperature: currentProvider.temperature,
    );

    return providerWithApiKey;
  }

  Future<String> summarizeNote(Quote quote) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final multiSettings = _settingsService.multiAISettings;
        final currentProvider = multiSettings.currentProvider!;

        // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
        final content =
            StringUtils.removeObjectReplacementChar(quote.content).trim();

        if (content.isEmpty) {
          throw Exception('没有可分析的文本内容');
        }

        final userMessage = _promptManager.buildUserMessage(content);
        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
          userMessage: userMessage,
          provider: currentProvider,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '笔记分析',
    );
  } // 流式笔记分析（支持完整元数据）

  Stream<String> streamSummarizeNote(Quote quote, {List<String>? tagNames}) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        // 在异步操作中验证API Key
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final multiSettings = _settingsService.multiAISettings;
        final currentProvider = multiSettings.currentProvider!;

        // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
        final content =
            StringUtils.removeObjectReplacementChar(quote.content).trim();

        if (content.isEmpty) {
          controller.addError(Exception('没有可分析的文本内容'));
          return;
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
        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '流式笔记分析',
          ),
        );
      },
      context: '流式笔记分析',
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
    final controller = _requestHelper.createStreamController();

    // 获取用户设置的语言代码
    final languageCode = _settingsService.localeCode;

    _requestHelper
        .executeStreamOperation(
          operation: (innerController) async {
            try {
              if (!await hasValidApiKeyAsync()) {
                innerController.addError(Exception('请先在设置中配置 API Key'));
                return;
              }

              await _validateSettings();
              final provider = await _getCurrentProviderWithApiKey();

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
                fullNotesContent: fullNotesContent, // 传递完整内容
                previousInsights: previousInsights, // 传递历史洞察
              );

              await _requestHelper.makeStreamRequestWithProvider(
                url: provider.apiUrl,
                systemPrompt: prompt,
                userMessage: user,
                provider: provider,
                onData: (text) => _requestHelper.handleStreamResponse(
                  controller: innerController,
                  chunk: text,
                ),
                onComplete: (fullText) => _requestHelper.handleStreamComplete(
                  controller: innerController,
                  fullText: fullText,
                ),
                onError: (error) => _requestHelper.handleStreamError(
                  controller: innerController,
                  error: error,
                  context: '报告洞察流式',
                ),
              );
            } catch (e) {
              _requestHelper.handleStreamError(
                controller: innerController,
                error: e,
                context: '报告洞察流式异常',
              );
            }
          },
          context: '报告洞察流式',
        )
        .listen(
          (chunk) => controller.add(chunk),
          onError: controller.addError,
          onDone: controller.close,
        );

    return controller.stream;
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
  Stream<String> streamGenerateDailyPrompt(
    AppLocalizations l10n, {
    String? city,
    String? weather,
    String? temperature,
    String? historicalInsights, // 新增：历史洞察参考
  }) {
    // 获取用户设置的语言代码
    final languageCode = _settingsService.localeCode;

    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        // 异步检查API Key是否有效
        if (!await hasValidApiKeyAsync()) {
          logDebug('API Key无效，使用DailyPromptGenerator生成每日提示');
          // 使用默认提示生成器
          controller.add(DailyPromptGenerator.getDefaultPrompt(l10n));
          controller.close();
          return;
        }

        // 验证AI设置是否已初始化
        bool settingsValid = false;
        AIProviderSettings? currentProvider;
        try {
          await _validateSettings(); // 确保其他设置也有效
          // 获取带有API Key的当前provider
          currentProvider = await _getCurrentProviderWithApiKey();
          settingsValid = true;
        } catch (e) {
          logDebug('AI设置验证失败: $e，将使用默认提示');
          settingsValid = false;
        }

        // 如果设置有效，调用AI生成流式提示
        if (settingsValid && currentProvider != null) {
          logDebug('API Key有效，使用AI生成每日提示');

          // 获取包含环境信息的系统提示词
          final systemPromptWithContext =
              _promptManager.getDailyPromptSystemPromptWithContext(
            city: city,
            weather: weather,
            temperature: temperature,
            historicalInsights: historicalInsights, // 传递历史洞察
            languageCode: languageCode, // 传递语言代码
          );

          final userMessage = _promptManager.buildDailyPromptUserMessage(
            city: city,
            weather: weather,
            temperature: temperature,
          );

          await _requestHelper.makeStreamRequestWithProvider(
            url: currentProvider.apiUrl,
            systemPrompt: systemPromptWithContext,
            userMessage: userMessage,
            provider: currentProvider,
            onData: (text) => _requestHelper.handleStreamResponse(
              controller: controller,
              chunk: text,
            ),
            onComplete: (fullText) => _requestHelper.handleStreamComplete(
              controller: controller,
              fullText: fullText,
            ),
            onError: (error) => _requestHelper.handleStreamError(
              controller: controller,
              error: error,
              context: 'AI生成每日提示',
            ),
            temperature: 1.0, // 可以调整温度以获得更有创意的提示
            maxTokens: 100, // 限制提示的长度
          );
        } else {
          // 如果设置无效，使用默认提示生成器
          controller.add(DailyPromptGenerator.getDefaultPrompt(l10n));
          controller.close();
        }
      },
      context: '流式生成每日提示',
    );
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

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
        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          maxTokens: 2500,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '生成洞察',
    );
  }

  // 流式生成洞察
  Stream<String> streamGenerateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
    String? customPrompt,
  }) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        // 在异步操作中验证API Key
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        // 将笔记数据转换为JSON格式
        final jsonData = _requestHelper.convertQuotesToJson(
          quotes,
          analysisType: analysisType,
          analysisStyle: analysisStyle,
        );
        // 添加自定义提示词使用标记（转换为字符串以避免类型错误）
        jsonData['metadata']['customPromptUsed'] =
            (customPrompt != null && customPrompt.isNotEmpty).toString();
        final quotesText = _requestHelper.formatJsonData(jsonData);

        // 根据分析类型选择系统提示词 或 使用自定义提示词
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
        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '流式生成洞察',
          ),
          maxTokens: 2500,
        );
      },
      context: '流式生成洞察',
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final userMessage = _promptManager.buildSourceAnalysisUserMessage(
          content,
          existingAuthor: existingAuthor,
          existingWork: existingWork,
        );
        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.sourceAnalysisPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          temperature: 0.4, // 使用较低的温度确保格式一致性
          maxTokens: 500,
        );

        return _requestHelper.parseResponse(response);
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.annualReportPrompt,
          userMessage: _buildEnhancedAnnualReportPrompt(prompt),
          provider: currentProvider,
          temperature: 0.3, // 使用较低的温度确保格式一致性
          maxTokens: 4000, // 增加token限制以支持完整HTML
        );

        String result = _requestHelper.parseResponse(response);

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
  Stream<String> streamAnalyzeSource(String content) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        // 在异步操作中验证API Key
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final userMessage = _promptManager.buildSourceAnalysisUserMessage(
          content,
        );
        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.sourceAnalysisPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '流式分析来源',
          ),
          temperature: 0.4, // 使用较低的温度确保格式一致性
          maxTokens: 500,
        );
      },
      context: '流式分析来源',
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final userMessage = _promptManager.buildPolishUserMessage(content);
        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.textPolishPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          maxTokens: 1000,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '文本润色',
    );
  }

  // 流式润色文本
  Stream<String> streamPolishText(String content) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        // 在异步操作中验证API Key
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final userMessage = _promptManager.buildPolishUserMessage(content);
        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.textPolishPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '流式润色文本',
          ),
          maxTokens: 1000,
        );
      },
      context: '流式润色文本',
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final userMessage = _promptManager.buildContinuationUserMessage(
          content,
        );
        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.textContinuationPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          temperature: 0.8, // 使用较高的温度以增加创意性
          maxTokens: 1000,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '文本续写',
    );
  }

  // 流式续写文本
  Stream<String> streamContinueText(String content) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        // 在异步操作中验证API Key
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final userMessage = _promptManager.buildContinuationUserMessage(
          content,
        );
        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.textContinuationPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '流式续写文本',
          ),
          temperature: 0.8, // 使用较高的温度以增加创意性
          maxTokens: 1000,
        );
      },
      context: '流式续写文本',
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt:
              'You are an expert SVG designer. Generate clean, valid SVG code based on the user\'s requirements. Only return the SVG code without any explanations or markdown formatting.',
          userMessage: prompt,
          provider: currentProvider,
          temperature: 0.7, // 适中的创意性
          maxTokens: 2000, // 足够生成完整的SVG
        );

        return _requestHelper.parseResponse(response);
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

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
        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.noteQAAssistantPrompt,
          userMessage: userMessage,
          provider: currentProvider,
          temperature: 0.5,
          maxTokens: 1000,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '问答',
    );
  }

  // 流式问答（支持完整笔记元数据）
  Stream<String> streamAskQuestion(
    Quote quote,
    String question, {
    List<ChatMessage>? history,
  }) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        // 在异步操作中验证API Key
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
        final content =
            StringUtils.removeObjectReplacementChar(quote.content).trim();

        if (content.isEmpty) {
          controller.addError(Exception('没有可分析的文本内容'));
          return;
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
        // 构建消息列表：system prompt + 历史 + 当前问题
        final List<Map<String, dynamic>> messages;
        if (history != null && history.isNotEmpty) {
          messages = _requestHelper.createMessagesWithHistory(
            systemPrompt: AIPromptManager.noteQAAssistantPrompt,
            history: history,
            currentUserMessageLength: userMessage.length,
          );
        } else {
          messages = [
            {
              'role': 'system',
              'content': AIPromptManager.noteQAAssistantPrompt,
            },
          ];
        }
        // 追加当前轮用户消息（含笔记全文 + 元数据 + 问题）
        messages.add({'role': 'user', 'content': userMessage});

        final body = _requestHelper.createRequestBody(
          messages: messages,
          temperature: 0.5,
          maxTokens: 1000,
        );

        await AINetworkManager.makeStreamRequest(
          url: currentProvider.apiUrl,
          data: body,
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '流式问答',
          ),
        );
      },
      context: '流式问答',
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.connectionTestPrompt,
          userMessage: '测试连接',
          provider: currentProvider,
          temperature: 0.1,
          maxTokens: 50,
        );

        final content = _requestHelper.parseResponse(response);
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

    try {
      final multiSettings = _settingsService.multiAISettings;

      final messages = [
        {'role': 'system', 'content': '你是一个AI助手。请简单回复"连接测试成功"。'},
        {'role': 'user', 'content': '测试连接'},
      ];
      final response = await AINetworkManager.makeRequest(
        url: '',
        data: {'messages': messages, 'temperature': 0.1, 'max_tokens': 50},
        multiSettings: multiSettings,
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['choices'] != null &&
            data['choices'].isNotEmpty &&
            data['choices'][0]['message'] != null) {
          logDebug(
            '多provider连接测试成功: ${data['choices'][0]['message']['content']}',
          );
          return;
        }
      }

      throw Exception('API响应格式异常');
    } catch (e) {
      logDebug('多provider连接测试失败: $e');
      rethrow;
    }
  }

  /// 使用多provider进行笔记分析（新版本）
  Future<String> summarizeNoteWithMultiProvider(Quote quote) async {
    // 使用异步验证确保API Key有效性
    if (!await hasValidApiKeyAsync()) {
      throw Exception('请先在设置中配置 API Key');
    }

    try {
      final multiSettings = _settingsService.multiAISettings;

      // 直接使用Quote的content字段（纯文本内容），移除媒体占位符
      final content =
          StringUtils.removeObjectReplacementChar(quote.content).trim();

      if (content.isEmpty) {
        throw Exception('没有可分析的文本内容');
      }

      final messages = [
        {
          'role': 'system',
          'content':
              '你是一位资深的个人成长导师和思维教练，拥有卓越的洞察力和分析能力。你的任务是深入分析用户笔记内容，帮助用户更好地理解自己的想法和情感。请像一位富有经验的导师一样，从以下几个方面进行专业、细致且富有启发性的分析：\n\n1. **核心思想 (Main Idea)**：  提炼并概括笔记内容的核心思想或主题，用简洁明了的语言点明笔记的重点。\n\n2. **情感色彩 (Emotional Tone)**：  分析笔记中流露出的情感倾向，例如积极、消极、平静、焦虑等，并尝试解读情感背后的原因。\n\n3. **行动启示 (Actionable Insights)**：  基于笔记内容和分析结果，为用户提供具体、可执行的行动建议或启示，帮助用户将思考转化为行动，促进个人成长和改进。\n\n请确保你的分析既专业深入，又通俗易懂，能够真正帮助用户理解自己，并获得成长和提升。',
        },
        {'role': 'user', 'content': '请分析以下内容：\n$content'},
      ];
      final response = await AINetworkManager.makeRequest(
        url: '',
        data: {'messages': messages, 'temperature': 0.7},
        multiSettings: multiSettings,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['choices'] != null &&
            data['choices'].isNotEmpty &&
            data['choices'][0]['message'] != null) {
          return data['choices'][0]['message']['content'];
        }
      }

      throw Exception('API响应格式错误');
    } catch (e) {
      logDebug('多provider笔记分析错误: $e');
      rethrow;
    }
  }

  Stream<String> streamGeneralConversation(
    String question, {
    List<ChatMessage>? history,
    String? systemContext,
  }) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();
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

        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
          userMessage: buffer.toString(),
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '普通对话',
          ),
          maxTokens: 1200,
        );
      },
      context: '普通对话',
    );
  }

  /// 高级流式对话方法 - SOTA 实时显示支持
  ///
  /// 返回 Stream<ChatMessageChunk>，支持：
  /// - 实时推送thinking过程（思考块）
  /// - 实时推送response内容（回复块）
  /// - 每个字符/句子立即显示，无延迟
  /// - 完整的错误处理和中断支持
  ///
  /// 使用示例：
  /// ```dart
  /// _aiService.streamMessageChunks(text, history: history).listen((chunk) {
  ///   setState(() {
  ///     if (chunk.type == 'thinking') {
  ///       _thinkingText += chunk.content;
  ///     } else if (chunk.type == 'response') {
  ///       _responseText += chunk.content;
  ///     }
  ///   });
  /// });
  /// ```
  Stream<dynamic> streamMessageChunks(
    String question, {
    List<ChatMessage>? history,
    String? systemContext,
  }) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();
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

        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
          userMessage: buffer.toString(),
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '高级流式对话',
          ),
          maxTokens: 1200,
        );
      },
      context: '高级流式对话',
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
        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        // 验证URL格式
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.isAbsolute) {
          throw Exception('无效的URL地址，请提供完整的URL');
        }

        // 构建用户消息
        final userMessage = '请抓取以下网页的内容并用Markdown格式总结主要内容：\n\nURL: $url';

        final response = await _requestHelper.makeRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt:
              '你是一个网页内容抓取和总结专家。当用户提供URL时，请获取网页内容，提取主要信息，并用清晰的Markdown格式呈现。包括标题、关键内容、重点要点等。',
          userMessage: userMessage,
          provider: currentProvider,
          maxTokens: 2000,
          temperature: 0.3,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '网页抓取',
    );
  }

  /// 为聊天会话生成标题
  /// [firstUserMessage] 首条用户消息内容
  /// 返回生成的标题（≤50字）
  Future<String> generateSessionTitle(String firstUserMessage) async {
    try {
      if (firstUserMessage.isEmpty) return 'Chat';

      if (!await hasValidApiKeyAsync()) {
        throw Exception('请先在设置中配置 API Key');
      }

      await _validateSettings();
      final currentProvider = await _getCurrentProviderWithApiKey();

      // 限制消息长度为100字以内
      final truncated = firstUserMessage.length > 100
          ? firstUserMessage.substring(0, 100) + '...'
          : firstUserMessage;

      final response = await _requestHelper.makeRequestWithProvider(
        url: currentProvider.apiUrl,
        systemPrompt: 'You are a title generator. Generate a SHORT title (max 10 words, in the same language as the message, no quotes) for the following message.',
        userMessage: truncated,
        provider: currentProvider,
        temperature: 0.3,
        maxTokens: 30,
      );

      final title = _requestHelper.parseResponse(response).trim();

      // 如果生成的标题超长，裁剪
      return title.length > 50 ? title.substring(0, 50) + '...' : title;
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
  Stream<String> streamFetchWebContent(String url) {
    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        if (!await hasValidApiKeyAsync()) {
          controller.addError(Exception('请先在设置中配置 API Key'));
          return;
        }

        await _validateSettings();
        final currentProvider = await _getCurrentProviderWithApiKey();

        // 验证URL格式
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.isAbsolute) {
          controller.addError(Exception('无效的URL地址，请提供完整的URL'));
          return;
        }

        final userMessage = '请抓取以下网页的内容并用Markdown格式总结主要内容：\n\nURL: $url';

        await _requestHelper.makeStreamRequestWithProvider(
          url: currentProvider.apiUrl,
          systemPrompt:
              '你是一个网页内容抓取和总结专家。当用户提供URL时，请获取网页内容，提取主要信息，并用清晰的Markdown格式呈现。包括标题、关键内容、重点要点等。',
          userMessage: userMessage,
          provider: currentProvider,
          onData: (text) => _requestHelper.handleStreamResponse(
            controller: controller,
            chunk: text,
          ),
          onComplete: (fullText) => _requestHelper.handleStreamComplete(
            controller: controller,
            fullText: fullText,
          ),
          onError: (error) => _requestHelper.handleStreamError(
            controller: controller,
            error: error,
            context: '流式网页抓取',
          ),
          maxTokens: 2000,
          temperature: 0.3,
        );
      },
      context: '流式网页抓取',
    );
  }
}
