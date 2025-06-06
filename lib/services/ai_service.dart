import 'package:flutter/foundation.dart';
import '../models/quote_model.dart';
import '../services/settings_service.dart' show SettingsService;
import '../services/api_key_manager.dart';
import 'dart:async';
import '../utils/daily_prompt_generator.dart';
import '../utils/ai_network_manager.dart';
import '../utils/ai_prompt_manager.dart';
import '../utils/ai_request_helper.dart';

// 定义流式响应的回调类型
typedef StreamingResponseCallback = void Function(String text);
typedef StreamingCompleteCallback = void Function(String fullText);
typedef StreamingErrorCallback = void Function(dynamic error);

class AIService extends ChangeNotifier {
  final SettingsService _settingsService;
  final APIKeyManager _apiKeyManager = APIKeyManager();
  final AIPromptManager _promptManager = AIPromptManager();
  final AIRequestHelper _requestHelper = AIRequestHelper();

  AIService({
    required SettingsService settingsService,
  }) : _settingsService = settingsService;



  Future<void> _validateSettings() async {
    try {
      final settings = _settingsService.aiSettings;

      // 检查API Key是否存在（使用统一的API密钥管理器）
      final hasApiKey = await _apiKeyManager.hasValidApiKey(settings);

      if (!hasApiKey) {
        throw Exception('请先在设置中配置 API Key');
      }

      if (settings.apiUrl.isEmpty) {
        throw Exception('请先在设置中配置 API URL');
      }

      if (settings.model.isEmpty) {
        throw Exception('请先在设置中配置 AI 模型');
      }
    } catch (e) {
      if (e.toString().contains('请先在设置中配置')) {
        rethrow;
      }
      throw Exception('AI设置尚未初始化，请稍后再试: $e');
    }
  }

  /// 同步检查API Key是否有效 (用于UI快速判断)
  /// 使用API密钥管理器的缓存机制
  bool hasValidApiKey() {
    try {
      final settings = _settingsService.aiSettings;
      return _apiKeyManager.hasValidApiKeySync(settings);
    } catch (e) {
      return false;
    }
  }



  Future<String> summarizeNote(Quote quote) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildUserMessage(quote.content);
        final response = await _requestHelper.makeRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
          userMessage: userMessage,
          settings: settings,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '笔记分析',
    );
  } // 流式笔记分析

  Stream<String> streamSummarizeNote(Quote quote) {
    if (!hasValidApiKey()) {
      return Stream.error(Exception('请先在设置中配置 API Key'));
    }

    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildUserMessage(quote.content);
        await _requestHelper.makeStreamRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.personalGrowthCoachPrompt,
          userMessage: userMessage,
          settings: settings,
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

  // 新增：流式生成每日提示
  Stream<String> streamGenerateDailyPrompt() async* {
    try {
      // 检查API Key是否有效
      if (!hasValidApiKey()) {
        debugPrint('API Key无效，使用DailyPromptGenerator生成每日提示');
        // 使用默认提示生成器
        yield DailyPromptGenerator.getDefaultPrompt();
        // 为了模拟流式效果，可以稍作延迟（可选）
        await Future.delayed(const Duration(milliseconds: 50));
      } else {
        // 验证AI设置是否已初始化
        bool settingsValid = false;
        try {
          await _validateSettings(); // 确保其他设置也有效
          // 检查_settingsService.aiSettings是否可用
          final _ = _settingsService.aiSettings;
          settingsValid = true;
        } catch (e) {
          debugPrint('AI设置验证失败: $e，将使用默认提示');
          settingsValid = false;
        }

        // 如果设置有效，调用AI生成流式提示
        if (settingsValid) {
          debugPrint('API Key有效，使用AI生成每日提示');
          try {
            await _validateSettings(); // 确保其他设置也有效
            final settings = _settingsService.aiSettings;

            // 使用StreamController来桥接_makeStreamRequest的回调和async* stream
            final controller = StreamController<String>.broadcast();

            await _requestHelper.makeStreamRequest(
              url: settings.apiUrl,
              systemPrompt: AIPromptManager.dailyPromptGeneratorPrompt,
              userMessage: '请给我一个今天的思考提示。',
              settings: settings,
              temperature: 1.0, // 可以调整温度以获得更有创意的提示
              maxTokens: 100, // 限制提示的长度
              onData: (chunk) {
                // 当接收到数据块时，添加到StreamController
                if (!controller.isClosed) {
                  controller.add(chunk);
                }
              },
              onComplete: (fullText) {
                // 当流完成时
                if (!controller.isClosed) {
                  controller.close();
                }
              },
              onError: (error) {
                // 当发生错误时
                if (!controller.isClosed) {
                  controller.addError(error);
                  controller.close();
                }
              },
            );

            // 通过yield* 将StreamController的流内容输出到async* stream
            yield* controller.stream;
          } catch (e) {
            debugPrint('AI生成每日提示错误: $e');
            // 在流中发送错误信息
            yield* Stream.error(e);
          }
        } else {
          // 如果设置无效，使用默认提示生成器
          yield DailyPromptGenerator.getDefaultPrompt();
        }
      }
    } catch (e) {
      debugPrint('streamGenerateDailyPrompt主流程错误: $e');
      yield* Stream.error(e);
    }
  }

  // 保留旧的generateDailyPrompt方法，以防其他地方仍在使用
  // 它将直接返回DailyPromptGenerator的当前提示
  String generateDailyPrompt() {
    debugPrint('调用了旧的generateDailyPrompt方法，建议切换到streamGenerateDailyPrompt');
    // 旧方法仍然返回 DailyPromptGenerator 的默认提示
    return DailyPromptGenerator.getDefaultPrompt();
  }

  Future<String> generateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
  }) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        // 将笔记数据转换为JSON格式
        final jsonData = _requestHelper.convertQuotesToJson(
          quotes,
          analysisType: analysisType,
          analysisStyle: analysisStyle,
        );
        final quotesText = _requestHelper.formatJsonData(jsonData);

        // 根据分析类型选择系统提示词
        String systemPrompt = _promptManager.getAnalysisTypePrompt(analysisType);
        systemPrompt = _promptManager.appendAnalysisStylePrompt(systemPrompt, analysisStyle);

        final userMessage = '请分析以下结构化的笔记数据：\n\n$quotesText';
        final response = await _requestHelper.makeRequest(
          url: settings.apiUrl,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          settings: settings,
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
    if (!hasValidApiKey()) {
      return Stream.error(Exception('请先在设置中配置 API Key'));
    }

    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        // 将笔记数据转换为JSON格式
        final jsonData = _requestHelper.convertQuotesToJson(
          quotes,
          analysisType: analysisType,
          analysisStyle: analysisStyle,
        );
        // 添加自定义提示词使用标记
        jsonData['metadata']['customPromptUsed'] = customPrompt != null && customPrompt.isNotEmpty;
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
        await _requestHelper.makeStreamRequest(
          url: settings.apiUrl,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          settings: settings,
          maxTokens: 2500,
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
        );
      },
      context: '流式生成洞察',
    );
  }

  // 分析文本来源
  Future<String> analyzeSource(String content) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildSourceAnalysisUserMessage(content);
        final response = await _requestHelper.makeRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.sourceAnalysisPrompt,
          userMessage: userMessage,
          settings: settings,
          temperature: 0.4, // 使用较低的温度确保格式一致性
          maxTokens: 500,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '分析来源',
    );
  }

  // 流式分析来源
  Stream<String> streamAnalyzeSource(String content) {
    if (!hasValidApiKey()) {
      return Stream.error(Exception('请先在设置中配置 API Key'));
    }

    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildSourceAnalysisUserMessage(content);
        await _requestHelper.makeStreamRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.sourceAnalysisPrompt,
          userMessage: userMessage,
          settings: settings,
          temperature: 0.4, // 使用较低的温度确保格式一致性
          maxTokens: 500,
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
        );
      },
      context: '流式分析来源',
    );
  }

  // 润色文本
  Future<String> polishText(String content) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildPolishUserMessage(content);
        final response = await _requestHelper.makeRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.textPolishPrompt,
          userMessage: userMessage,
          settings: settings,
          maxTokens: 1000,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '文本润色',
    );
  }

  // 流式润色文本
  Stream<String> streamPolishText(String content) {
    if (!hasValidApiKey()) {
      return Stream.error(Exception('请先在设置中配置 API Key'));
    }

    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildPolishUserMessage(content);
        await _requestHelper.makeStreamRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.textPolishPrompt,
          userMessage: userMessage,
          settings: settings,
          maxTokens: 1000,
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
        );
      },
      context: '流式润色文本',
    );
  }

  // 续写文本
  Future<String> continueText(String content) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildContinuationUserMessage(content);
        final response = await _requestHelper.makeRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.textContinuationPrompt,
          userMessage: userMessage,
          settings: settings,
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
    if (!hasValidApiKey()) {
      return Stream.error(Exception('请先在设置中配置 API Key'));
    }

    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildContinuationUserMessage(content);
        await _requestHelper.makeStreamRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.textContinuationPrompt,
          userMessage: userMessage,
          settings: settings,
          temperature: 0.8, // 使用较高的温度以增加创意性
          maxTokens: 1000,
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
        );
      },
      context: '流式续写文本',
    );
  }

  // 向笔记提问
  Future<String> askQuestion(Quote quote, String question) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    return await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildQAUserMessage(quote.content, question);
        final response = await _requestHelper.makeRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.noteQAAssistantPrompt,
          userMessage: userMessage,
          settings: settings,
          temperature: 0.5,
          maxTokens: 1000,
        );

        return _requestHelper.parseResponse(response);
      },
      context: '问答',
    );
  }

  // 流式问答
  Stream<String> streamAskQuestion(Quote quote, String question) {
    if (!hasValidApiKey()) {
      return Stream.error(Exception('请先在设置中配置 API Key'));
    }

    return _requestHelper.executeStreamOperation(
      operation: (controller) async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final userMessage = _promptManager.buildQAUserMessage(quote.content, question);
        await _requestHelper.makeStreamRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.noteQAAssistantPrompt,
          userMessage: userMessage,
          settings: settings,
          temperature: 0.5,
          maxTokens: 1000,
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
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    await _requestHelper.executeWithErrorHandling(
      operation: () async {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final response = await _requestHelper.makeRequest(
          url: settings.apiUrl,
          systemPrompt: AIPromptManager.connectionTestPrompt,
          userMessage: '测试连接',
          settings: settings,
          temperature: 0.1,
          maxTokens: 50,
          model: settings.model,
        );

        final content = _requestHelper.parseResponse(response);
        debugPrint('AI连接测试成功: $content');
      },
      context: 'AI连接测试',
    );
  }

  /// 使用多provider测试连接
  Future<void> testConnectionWithMultiProvider() async {
    if (!hasValidApiKey()) {
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
          debugPrint(
            '多provider连接测试成功: ${data['choices'][0]['message']['content']}',
          );
          return;
        }
      }

      throw Exception('API响应格式异常');
    } catch (e) {
      debugPrint('多provider连接测试失败: $e');
      rethrow;
    }
  }

  /// 使用多provider进行笔记分析（新版本）
  Future<String> summarizeNoteWithMultiProvider(Quote quote) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    try {
      final multiSettings = _settingsService.multiAISettings;

      final messages = [
        {
          'role': 'system',
          'content':
              '你是一位资深的个人成长导师和思维教练，拥有卓越的洞察力和分析能力。你的任务是深入分析用户笔记内容，帮助用户更好地理解自己的想法和情感。请像一位富有经验的导师一样，从以下几个方面进行专业、细致且富有启发性的分析：\n\n1. **核心思想 (Main Idea)**：  提炼并概括笔记内容的核心思想或主题，用简洁明了的语言点明笔记的重点。\n\n2. **情感色彩 (Emotional Tone)**：  分析笔记中流露出的情感倾向，例如积极、消极、平静、焦虑等，并尝试解读情感背后的原因。\n\n3. **行动启示 (Actionable Insights)**：  基于笔记内容和分析结果，为用户提供具体、可执行的行动建议或启示，帮助用户将思考转化为行动，促进个人成长和改进。\n\n请确保你的分析既专业深入，又通俗易懂，能够真正帮助用户理解自己，并获得成长和提升。',
        },
        {'role': 'user', 'content': '请分析以下内容：\n${quote.content}'},
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
      debugPrint('多provider笔记分析错误: $e');
      rethrow;
    }
  }
}
