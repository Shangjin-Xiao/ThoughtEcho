import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/quote_model.dart';
import '../models/ai_settings.dart';
import '../services/settings_service.dart' show SettingsService;
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/api_key_manager.dart';
import 'dart:async';
import '../utils/daily_prompt_generator.dart';
import '../utils/ai_network_manager.dart'; // 使用新的统一网络管理器

// 定义流式响应的回调类型
typedef StreamingResponseCallback = void Function(String text);
typedef StreamingCompleteCallback = void Function(String fullText);
typedef StreamingErrorCallback = void Function(dynamic error);

class AIService extends ChangeNotifier {
  final SettingsService _settingsService;
  final LocationService _locationService; // 新增
  final WeatherService _weatherService; // 新增
  final APIKeyManager _apiKeyManager = APIKeyManager(); // 新增

  AIService({
    required SettingsService settingsService,
    required LocationService locationService, // 新增
    required WeatherService weatherService, // 新增
  }) : _settingsService = settingsService,
       _locationService = locationService, // 新增
       _weatherService = weatherService; // 新增

  // 根据分析类型选择系统提示词
  String _getAnalysisTypePrompt(String analysisType) {
    switch (analysisType) {
      case 'emotional':
        return '''你是一位专业的心理分析师和情感咨询师。请分析用户笔记中的情感状态、情绪变化和心理健康。
          
任务：
1. 识别笔记中表达的主要情绪和情感模式
2. 分析情绪变化的趋势和可能的触发因素
3. 提供关于情绪管理和心理健康的建议
4. 以尊重和专业的方式表达你的分析

格式要求：
- 使用"# 情感洞察分析"作为主标题
- 包含"## 总体情感状态"部分
- 包含"## 情绪变化趋势"部分
- 包含"## 建议与反思"部分
- 适当使用markdown格式增强可读性''';

      case 'mindmap':
        return '''你是一位专业的思维导图和知识系统构建专家。请分析用户笔记，构建他们思考的结构和思维习惯。
          
任务：
1. 识别笔记中的主要思考主题和思维模式
2. 分析这些主题之间的联系和层次结构
3. 评估思维的深度、广度和连贯性
4. 提供关于如何拓展和深化思考的建议

格式要求：
- 使用"# 思维导图分析"作为主标题
- 包含"## 核心思考主题"部分
- 包含"## 思维结构图"部分(用文字描述思维图的结构)
- 包含"## 思维特点分析"部分
- 包含"## 思维发展建议"部分
- 适当使用markdown格式增强可读性''';

      case 'growth':
        return '''你是一位专业的个人成长教练和学习顾问。请基于用户笔记分析他们的成长轨迹并提供发展建议。
          
任务：
1. 识别用户的兴趣、价值观和目标
2. 分析用户的学习模式和成长轨迹
3. 发现可能的成长盲点和发展机会
4. 提供具体、实用的成长和进步建议

格式要求：
- 使用"# 成长建议分析"作为主标题
- 包含"## 个人特质与价值观"部分
- 包含"## 成长轨迹分析"部分
- 包含"## 发展机会"部分
- 包含"## 具体行动建议"部分
- 适当使用markdown格式增强可读性''';

      case 'comprehensive':
      default:
        return '''你是一位专业的思想分析师和洞察专家。请全面分析用户的笔记内容，发掘其中的思想价值和模式。

任务：
1. 分析笔记中的核心思想和主题
2. 识别重复出现的关键概念和模式
3. 探究潜在的思维模式和价值观
4. 提供有深度的洞察和反思建议

格式要求：
- 使用"# 思想洞察分析"作为主标题
- 包含"## 核心思想概述"部分
- 包含"## 主题与模式"部分
- 包含"## 深度洞察"部分
- 包含"## 思考与建议"部分
- 适当使用markdown格式增强可读性''';
    }
  }

  // 根据分析风格修改提示词
  String _appendAnalysisStylePrompt(String systemPrompt, String analysisStyle) {
    String stylePrompt;

    switch (analysisStyle) {
      case 'friendly':
        stylePrompt = '''表达风格：
- 使用温暖、鼓励和支持性的语言
- 以友好的"你"称呼读者
- 像一位知心朋友或支持性的导师给予建议
- 避免过于学术或技术化的语言
- 强调积极的方面和成长的可能性''';
        break;

      case 'humorous':
        stylePrompt = '''表达风格：
- 运用适当的幽默和风趣元素
- 使用生动的比喻和有趣的类比
- 保持轻松愉快的语调
- 在严肃洞察中穿插幽默观察
- 避免过于严肃或教条的表达方式''';
        break;

      case 'literary':
        stylePrompt = '''表达风格：
- 使用优美、富有文学色彩的语言
- 适当引用诗歌、文学作品或哲学观点
- 运用丰富的修辞手法和意象
- 以优雅流畅的叙事风格展开分析
- 注重文字的节奏感和美感''';
        break;

      case 'professional':
      default:
        stylePrompt = '''表达风格：
- 使用专业、清晰和客观的语言
- 保持分析的系统性和结构化
- 提供基于证据的观察和推理
- 使用恰当的专业术语（但避免过于晦涩）
- 以第三人称或中性语气表达''';
        break;
    }

    return '$systemPrompt\n\n$stylePrompt';
  }

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

  // 简化的网络请求方法
  Future<Response> _makeRequest(
    String url,
    Map<String, dynamic> body,
    AISettings settings,
  ) async {
    return await AINetworkManager.makeRequest(
      url: url,
      data: body,
      legacySettings: settings,
      timeout: const Duration(seconds: 300),
    );
  }

  // 简化的流式请求方法
  Future<void> _makeStreamRequest(
    String url,
    Map<String, dynamic> body,
    AISettings settings,
    StreamingResponseCallback onResponse,
    StreamingCompleteCallback onComplete,
    StreamingErrorCallback onError,
  ) async {
    await AINetworkManager.makeStreamRequest(
      url: url,
      data: body,
      legacySettings: settings,
      onData: onResponse,
      onComplete: onComplete,
      onError: onError,
      timeout: const Duration(seconds: 300),
    );
  }

  Future<String> summarizeNote(Quote quote) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {
          'role': 'system',
          'content':
              '你是一位资深的个人成长导师和思维教练，拥有卓越的洞察力和分析能力。你的任务是深入分析用户提供的笔记内容，帮助用户更好地理解自己的想法和情感。请像一位富有经验的导师一样，从以下几个方面进行专业、细致且富有启发性的分析：\n\n1. **核心思想 (Main Idea)**：  提炼并概括笔记内容的核心思想或主题，用简洁明了的语言点明笔记的重点。\n\n2. **情感色彩 (Emotional Tone)**：  分析笔记中流露出的情感倾向，例如积极、消极、平静、焦虑等，并尝试解读情感背后的原因。\n\n3. **行动启示 (Actionable Insights)**：  基于笔记内容和分析结果，为用户提供具体、可执行的行动建议或启示，帮助用户将思考转化为行动，促进个人成长和改进。\n\n请确保你的分析既专业深入，又通俗易懂，能够真正帮助用户理解自己，并获得成长和提升。',
        },
        {'role': 'user', 'content': '请分析以下内容：\n${quote.content}'},
      ];
      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.7,
      }, settings);

      final data = response.data;
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: $data');
        throw Exception('API响应格式错误');
      }
    } catch (e) {
      debugPrint('笔记分析错误: $e');
      rethrow;
    }
  } // 流式笔记分析

  Stream<String> streamSummarizeNote(Quote quote) {
    final controller = StreamController<String>.broadcast();

    () async {
      if (!hasValidApiKey()) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        controller.close();
        return;
      }

      try {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final messages = [
          {
            'role': 'system',
            'content':
                '你是一位资深的个人成长导师和思维教练，拥有卓越的洞察力和分析能力。你的任务是深入分析用户提供的笔记内容，帮助用户更好地理解自己的想法和情感。请像一位富有经验的导师一样，从以下几个方面进行专业、细致且富有启发性的分析：\n\n1. **核心思想 (Main Idea)**：  提炼并概括笔记内容的核心思想或主题，用简洁明了的语言点明笔记的重点。\n\n2. **情感色彩 (Emotional Tone)**：  分析笔记中流露出的情感倾向，例如积极、消极、平静、焦虑等，并尝试解读情感背后的原因。\n\n3. **行动启示 (Actionable Insights)**：  基于笔记内容和分析结果，为用户提供具体、可执行的行动建议或启示，帮助用户将思考转化为行动，促进个人成长和改进。\n\n请确保你的分析既专业深入，又通俗易懂，能够真正帮助用户理解自己，并获得成长和提升。',
          },
          {'role': 'user', 'content': '请分析以下内容：\n${quote.content}'},
        ];

        await _makeStreamRequest(
          settings.apiUrl,
          {'messages': messages, 'temperature': 0.7},
          settings,
          // 当收到新内容时
          (String text) {
            if (!controller.isClosed) {
              controller.add(text);
            }
          },
          // 当完成时
          (String fullText) {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          // 当发生错误时
          (error) {
            debugPrint('流式笔记分析错误: $error');
            if (!controller.isClosed) {
              controller.addError(error);
              controller.close();
            }
          },
        );
      } catch (e) {
        debugPrint('流式笔记分析错误: $e');
        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // 新增：流式生成每日提示
  Stream<String> streamGenerateDailyPrompt() async* {
    try {
      // 检查API Key是否有效
      if (!hasValidApiKey()) {
        debugPrint('API Key无效，使用DailyPromptGenerator生成每日提示');
        // 获取位置和天气信息用于生成上下文相关的提示
        String? city;
        String? weather;
        String? temperature;

        // 使用之前注入但未使用的位置服务
        if (_locationService.city != null) {
          city = _locationService.city;
        }

        // 使用之前注入但未使用的天气服务
        if (_weatherService.currentWeather != null) {
          weather = _weatherService.currentWeather;
          temperature = _weatherService.temperature;
        }

        // 使用上下文信息生成个性化的提示
        yield DailyPromptGenerator.generatePromptBasedOnContext(
          city: city,
          weather: weather,
          temperature: temperature,
        );
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

            // 构建给AI的提示
            final messages = [
              {
                'role': 'system',
                'content':
                    '你是一位富有智慧和启发性的思考引导者，每天为用户提供一个简洁的、引发深度思考的提示或问题，帮助用户进行日记记录。提示词应该简短、有新意、不重复，直接提出一个问题或一个观察点，激发用户写作的灵感。例如："今天让你停下来思考的小事是什么？"或"一个你最近学到的、改变了你对某事的看法是什么？"。只提供一个提示，不需要任何前缀或解释。',
              },
              {'role': 'user', 'content': '请给我一个今天的思考提示。'},
            ];

            // 使用StreamController来桥接_makeStreamRequest的回调和async* stream
            final controller = StreamController<String>.broadcast();

            _makeStreamRequest(
              settings.apiUrl,
              {
                'messages': messages,
                'temperature': 1.0, // 可以调整温度以获得更有创意的提示
                'max_tokens': 100, // 限制提示的长度
              },
              settings,
              (chunk) {
                // 当接收到数据块时，添加到StreamController
                if (!controller.isClosed) {
                  controller.add(chunk);
                }
              },
              (fullText) {
                // 当流完成时
                if (!controller.isClosed) {
                  controller.close();
                }
              },
              (error) {
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
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      // 将笔记数据转换为与备份还原功能类似的JSON格式
      final jsonData = {
        'metadata': {
          'app': '心迹',
          'version': '1.0',
          'exportTime': DateTime.now().toIso8601String(),
          'analysisType': analysisType,
          'analysisStyle': analysisStyle,
        },
        'quotes':
            quotes.map((quote) {
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

      // 将数据转换为格式化的JSON字符串
      final quotesText = const JsonEncoder.withIndent('  ').convert(jsonData);

      // 根据分析类型选择系统提示词
      String systemPrompt = _getAnalysisTypePrompt(analysisType);

      // 根据分析风格修改提示词
      systemPrompt = _appendAnalysisStylePrompt(systemPrompt, analysisStyle);

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '请分析以下结构化的笔记数据：\n\n$quotesText'},
      ];
      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 2500,
      }, settings);

      final data =
          response.data is String ? json.decode(response.data) : response.data;
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.data}');
        throw Exception('API响应格式错误');
      }
    } catch (e) {
      debugPrint('生成洞察错误: $e');
      rethrow;
    }
  }

  // 流式生成洞察
  Stream<String> streamGenerateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
    String? customPrompt,
  }) {
    final controller = StreamController<String>.broadcast();

    () async {
      if (!hasValidApiKey()) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        controller.close();
        return;
      }

      try {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        // 将笔记数据转换为与备份还原功能类似的JSON格式
        final jsonData = {
          'metadata': {
            'app': '心迹',
            'version': '1.0',
            'exportTime': DateTime.now().toIso8601String(),
            'analysisType': analysisType,
            'analysisStyle': analysisStyle,
            'customPromptUsed': customPrompt != null && customPrompt.isNotEmpty,
          },
          'quotes':
              quotes.map((quote) {
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

        // 将数据转换为格式化的JSON字符串
        final quotesText = const JsonEncoder.withIndent('  ').convert(jsonData);

        // 根据分析类型选择系统提示词 或 使用自定义提示词
        String systemPrompt;
        if (customPrompt != null && customPrompt.isNotEmpty) {
          systemPrompt = customPrompt;
        } else {
          systemPrompt = _getAnalysisTypePrompt(analysisType);
          systemPrompt = _appendAnalysisStylePrompt(
            systemPrompt,
            analysisStyle,
          );
        }

        final messages = [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '请分析以下结构化的笔记数据：\n\n$quotesText'},
        ];

        await _makeStreamRequest(
          settings.apiUrl,
          {'messages': messages, 'temperature': 0.7, 'max_tokens': 2500},
          settings,
          // 当收到新内容时
          (String text) {
            if (!controller.isClosed) {
              controller.add(text);
            }
          },
          // 当完成时
          (String fullText) {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          // 当发生错误时
          (error) {
            debugPrint('流式生成洞察错误: $error');
            if (!controller.isClosed) {
              controller.addError(error);
              controller.close();
            }
          },
        );
      } catch (e) {
        debugPrint('流式生成洞察异常: $e');
        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // 分析文本来源
  Future<String> analyzeSource(String content) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {
          'role': 'system',
          'content': '''你是一个专业的文本分析助手，你的任务是分析文本中可能提到的作者和作品。
请以JSON格式返回以下信息：
{
  "author": "推测的作者名称，如果无法确定则留空",
  "work": "推测的作品名称，如果无法确定则留空",
  "confidence": "高/中/低，表示你的推测置信度",
  "explanation": "简短解释你的推测依据"
}

非常重要：
1. 只返回JSON格式的数据，不要有其他文字说明
2. 如果你不确定或无法分析，请确保在适当的字段中返回空字符串，不要胡乱猜测
3. 对于中文引述格式常见形式是："——作者《作品》"
4. 作者名应该只包含人名，不包含头衔或其他描述词
5. 对于作品名，请去掉引号《》等标记符号''',
        },
        {'role': 'user', 'content': '请分析以下文本的可能来源：\n\n$content'},
      ];
      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.4, // 使用较低的温度确保格式一致性
        'max_tokens': 500,
      }, settings);

      final data =
          response.data is String ? json.decode(response.data) : response.data;
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.data}');
        throw Exception('API响应格式错误');
      }
    } catch (e) {
      debugPrint('分析来源错误: $e');
      rethrow;
    }
  }

  // 流式分析来源
  Stream<String> streamAnalyzeSource(String content) {
    final controller = StreamController<String>.broadcast();

    () async {
      if (!hasValidApiKey()) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        controller.close();
        return;
      }

      try {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final messages = [
          {
            'role': 'system',
            'content': '''你是一个专业的文本分析助手，你的任务是分析文本中可能提到的作者和作品。
请以JSON格式返回以下信息：
{
  "author": "推测的作者名称，如果无法确定则留空",
  "work": "推测的作品名称，如果无法确定则留空",
  "confidence": "高/中/低，表示你的推测置信度",
  "explanation": "简短解释你的推测依据"
}

非常重要：
1. 只返回JSON格式的数据，不要有其他文字说明
2. 如果你不确定或无法分析，请确保在适当的字段中返回空字符串，不要胡乱猜测
3. 对于中文引述格式常见形式是："——作者《作品》"
4. 作者名应该只包含人名，不包含头衔或其他描述词
5. 对于作品名，请去掉引号《》等标记符号''',
          },
          {'role': 'user', 'content': '请分析以下文本的可能来源：\n\n$content'},
        ];

        await _makeStreamRequest(
          settings.apiUrl,
          {
            'messages': messages,
            'temperature': 0.4, // 使用较低的温度确保格式一致性
            'max_tokens': 500,
          },
          settings,
          // 当收到新内容时
          (String text) {
            if (!controller.isClosed) {
              controller.add(text);
            }
          },
          // 当完成时
          (String fullText) {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          // 当发生错误时
          (error) {
            if (!controller.isClosed) {
              controller.addError(error);
              controller.close();
            }
          },
        );
      } catch (e) {
        debugPrint('流式分析来源错误: $e');
        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // 润色文本
  Future<String> polishText(String content) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {
          'role': 'system',
          'content': '''你是一个专业的文字润色助手，擅长改进文本的表达和结构。
请对用户提供的文本进行润色，使其更加流畅、优美、有深度。保持原文的核心意思和情感基调，但提升其文学价值和表达力。

注意：
1. 保持原文的核心思想不变
2. 提高语言的表现力和优美度
3. 修正语法、标点等问题
4. 适当使用修辞手法增强表达力
5. 返回完整的润色后文本''',
        },
        {'role': 'user', 'content': '请润色以下文本：\n\n$content'},
      ];

      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 1000,
      }, settings);

      final data =
          response.data is String ? json.decode(response.data) : response.data;
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.data}');
        throw Exception('API响应格式错误');
      }
    } catch (e) {
      debugPrint('文本润色错误: $e');
      rethrow;
    }
  }

  // 流式润色文本
  Stream<String> streamPolishText(String content) {
    final controller = StreamController<String>.broadcast();

    () async {
      if (!hasValidApiKey()) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        controller.close();
        return;
      }

      try {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final messages = [
          {
            'role': 'system',
            'content': '''你是一个专业的文字润色助手，擅长改进文本的表达和结构。
请对用户提供的文本进行润色，使其更加流畅、优美、有深度。保持原文的核心意思和情感基调，但提升其文学价值和表达力。

注意：
1. 保持原文的核心思想不变
2. 提高语言的表现力和优美度
3. 修正语法、标点等问题
4. 适当使用修辞手法增强表达力
5. 返回完整的润色后文本''',
          },
          {'role': 'user', 'content': '请润色以下文本：\n\n$content'},
        ];

        await _makeStreamRequest(
          settings.apiUrl,
          {'messages': messages, 'temperature': 0.7, 'max_tokens': 1000},
          settings,
          // 当收到新内容时
          (String text) {
            if (!controller.isClosed) {
              controller.add(text);
            }
          },
          // 当完成时
          (String fullText) {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          // 当发生错误时
          (error) {
            if (!controller.isClosed) {
              controller.addError(error);
              controller.close();
            }
          },
        );
      } catch (e) {
        debugPrint('流式润色文本错误: $e');
        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // 续写文本
  Future<String> continueText(String content) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {
          'role': 'system',
          'content': '''你是一个专业的文字续写助手，擅长根据已有文本继续创作。
请为用户提供的文本进行有创意且连贯的续写，保持一致的风格、语调和思路。

注意：
1. 续写内容应自然衔接原文末尾
2. 保持原文的风格、语气和写作特点
3. 延续原文的思路和主题
4. 创作至少100-200字的后续内容
5. 返回完整的续写部分，不要重复原文''',
        },
        {'role': 'user', 'content': '请续写以下文本：\n\n$content'},
      ];
      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.8, // 使用较高的温度以增加创意性
        'max_tokens': 1000,
      }, settings);

      final data =
          response.data is String ? json.decode(response.data) : response.data;
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.data}');
        throw Exception('API响应格式错误');
      }
    } catch (e) {
      debugPrint('文本续写错误: $e');
      rethrow;
    }
  }

  // 流式续写文本
  Stream<String> streamContinueText(String content) {
    final controller = StreamController<String>.broadcast();

    () async {
      if (!hasValidApiKey()) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        controller.close();
        return;
      }

      try {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final messages = [
          {
            'role': 'system',
            'content': '''你是一个专业的文字续写助手，擅长根据已有文本继续创作。
请为用户提供的文本进行有创意且连贯的续写，保持一致的风格、语调和思路。

注意：
1. 续写内容应自然衔接原文末尾
2. 保持原文的风格、语气和写作特点
3. 延续原文的思路和主题
4. 创作至少100-200字的后续内容
5. 返回完整的续写部分，不要重复原文''',
          },
          {'role': 'user', 'content': '请续写以下文本：\n\n$content'},
        ];

        await _makeStreamRequest(
          settings.apiUrl,
          {
            'messages': messages,
            'temperature': 0.8, // 使用较高的温度以增加创意性
            'max_tokens': 1000,
          },
          settings,
          // 当收到新内容时
          (String text) {
            if (!controller.isClosed) {
              controller.add(text);
            }
          },
          // 当完成时
          (String fullText) {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          // 当发生错误时
          (error) {
            if (!controller.isClosed) {
              controller.addError(error);
              controller.close();
            }
          },
        );
      } catch (e) {
        debugPrint('流式续写文本错误: $e');
        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // 向笔记提问
  Future<String> askQuestion(Quote quote, String question) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {
          'role': 'system',
          'content': '''你是一个专业的笔记助手，擅长回答关于用户笔记内容的问题。
请根据用户的笔记内容，回答他们提出的问题。

注意：
1. 只基于笔记中提供的信息回答问题
2. 如果笔记中没有相关信息，请诚实说明无法回答
3. 不要编造不在笔记中的信息
4. 回答应该有深度且有洞察力
5. 回答应该清晰、简洁且有条理''',
        },
        {
          'role': 'user',
          'content': '''笔记内容：

${quote.content}

我的问题：
$question''',
        },
      ];

      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.5,
        'max_tokens': 1000,
      }, settings);

      final data =
          response.data is String ? json.decode(response.data) : response.data;
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.data}');
        throw Exception('API响应格式错误');
      }
    } catch (e) {
      debugPrint('问答错误: $e');
      rethrow;
    }
  }

  // 流式问答
  Stream<String> streamAskQuestion(Quote quote, String question) {
    final controller = StreamController<String>.broadcast();

    () async {
      if (!hasValidApiKey()) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        controller.close();
        return;
      }

      try {
        await _validateSettings();
        final settings = _settingsService.aiSettings;

        final messages = [
          {
            'role': 'system',
            'content': '''你是一个专业的笔记助手，擅长回答关于用户笔记内容的问题。
请根据用户的笔记内容，回答他们提出的问题。

注意：
1. 只基于笔记中提供的信息回答问题
2. 如果笔记中没有相关信息，请诚实说明无法回答
3. 不要编造不在笔记中的信息
4. 回答应该有深度且有洞察力
5. 回答应该清晰、简洁且有条理''',
          },
          {
            'role': 'user',
            'content': '''笔记内容：

${quote.content}

我的问题：
$question''',
          },
        ];

        await _makeStreamRequest(
          settings.apiUrl,
          {'messages': messages, 'temperature': 0.5, 'max_tokens': 1000},
          settings,
          // 当收到新内容时
          (String text) {
            if (!controller.isClosed) {
              controller.add(text);
            }
          },
          // 当完成时
          (String fullText) {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          // 当发生错误时
          (error) {
            if (!controller.isClosed) {
              controller.addError(error);
              controller.close();
            }
          },
        );
      } catch (e) {
        debugPrint('流式问答错误: $e');
        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  /// 测试与AI服务的连接
  Future<void> testConnection() async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }

    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {'role': 'system', 'content': '你是一个AI助手。请简单回复"连接测试成功"。'},
        {'role': 'user', 'content': '测试连接'},
      ];

      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.1,
        'max_tokens': 50,
        'model': settings.model,
      }, settings);

      final data =
          response.data is String ? json.decode(response.data) : response.data;
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        debugPrint('AI连接测试成功: ${data['choices'][0]['message']['content']}');
        return;
      }

      throw Exception('API响应格式异常');
    } catch (e) {
      debugPrint('AI连接测试失败: $e');
      rethrow;
    }
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
