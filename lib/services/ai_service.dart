import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/quote_model.dart';
import '../models/ai_settings.dart';
import '../services/settings_service.dart' show SettingsService;
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/secure_storage_service.dart';
import 'dart:async'; // 添加异步流支持
import '../utils/daily_prompt_generator.dart';

// 定义流式响应的回调类型
typedef StreamingResponseCallback = void Function(String text);
typedef StreamingCompleteCallback = void Function(String fullText);
typedef StreamingErrorCallback = void Function(dynamic error);

class AIService extends ChangeNotifier {
  final SettingsService _settingsService;
  final LocationService _locationService; // 新增
  final WeatherService _weatherService; // 新增

  AIService({
    required SettingsService settingsService,
    required LocationService locationService, // 新增
    required WeatherService weatherService, // 新增
  }) : _settingsService = settingsService,
       _locationService = locationService, // 新增
       _weatherService = weatherService; // 新增

  Future<void> _validateSettings() async {
    final settings = _settingsService.aiSettings;

    // 创建安全存储服务实例
    final secureStorage = SecureStorageService(); // 先检查settings中的API Key
    bool hasApiKey = settings.apiKey.isNotEmpty;
    // String? effectiveApiKey; // 在这里声明 // -- 已移除

    // 如果settings中没有API Key，则尝试从安全存储中获取
    if (!hasApiKey) {
      final secureApiKey = await secureStorage.getApiKey();
      hasApiKey = secureApiKey != null && secureApiKey.isNotEmpty;

      // 如果找到了安全存储的API Key，保存到临时变量中以供本次请求使用
      // if (hasApiKey) { // -- 已移除
      // effectiveApiKey = secureApiKey; // 初始化 // -- 已移除
      // } // -- 已移除
    } // else { // -- 已移除，因为不再需要为 effectiveApiKey 赋值
    // effectiveApiKey = settings.apiKey; // 如果设置中有，则使用设置中的 // -- 已移除
    // } // -- 已移除

    // 最终验证API Key
    if (!hasApiKey) {
      throw Exception('请先在设置中配置 API Key');
    }

    if (settings.apiUrl.isEmpty) {
      throw Exception('请先在设置中配置 API URL');
    }

    if (settings.model.isEmpty) {
      throw Exception('请先在设置中配置 AI 模型');
    }
  }

  // 判断API Key是否有效 (同步检查，用于UI显示判断)
  bool hasValidApiKey() {
    final key = _settingsService.aiSettings.apiKey;
    if (key.isNotEmpty) {
      return true; // 如果设置中有key则直接返回true
    }

    // 否则，我们无法同步获取安全存储的key
    // 对于UI判断，我们假定如果apiUrl和model已经配置，那么key也很可能已配置
    final settings = _settingsService.aiSettings;
    return settings.apiUrl.isNotEmpty && settings.model.isNotEmpty;
  }

  Future<http.Response> _makeRequest(
    String url,
    Map<String, dynamic> body,
    AISettings settings,
  ) async {
    if (body['messages'] is! List) {
      throw Exception('messages字段格式错误');
    }

    // 创建安全存储服务实例
    final secureStorage = SecureStorageService();

    // 获取API密钥 - 首先尝试从安全存储中获取，如果为空则尝试使用设置中的密钥（向后兼容）
    final secureApiKey = await secureStorage.getApiKey();
    final effectiveApiKey = secureApiKey ?? settings.apiKey;

    if (effectiveApiKey.isEmpty) {
      throw Exception('未找到有效的API密钥，请在设置中配置API密钥');
    }

    // 根据不同的AI服务提供商调整请求体格式
    Map<String, dynamic> requestBody;
    Map<String, String> headers = {'Content-Type': 'application/json'};

    // 判断服务提供商类型并相应调整请求
    if (url.contains('anthropic.com')) {
      // Anthropic Claude API格式
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'max_tokens': body['max_tokens'] ?? 2500,
      };

      // Anthropic使用x-api-key头而非Bearer认证
      headers['anthropic-version'] = '2023-06-01'; // 添加必需的API版本头
      headers['x-api-key'] = effectiveApiKey; // 使用有效的API密钥
    } else if (url.contains('openrouter.ai')) {
      // OpenRouter可能需要额外的头信息
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': false,
      };

      headers['Authorization'] = 'Bearer $effectiveApiKey'; // 使用有效的API密钥
      headers['HTTP-Referer'] = 'https://thoughtecho.app'; // 可能需要指定来源
      headers['X-Title'] = 'ThoughtEcho App'; // 应用名称
    } else if (url.contains('deepseek.com')) {
      // DeepSeek API格式
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': false,
      };

      headers['Authorization'] = 'Bearer $effectiveApiKey'; // 使用有效的API密钥
    } else {
      // 默认格式(适用于OpenAI及其兼容API)
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': false,
      };

      headers['Authorization'] = 'Bearer $effectiveApiKey'; // 使用有效的API密钥
    }

    debugPrint('API请求体: ${json.encode(requestBody)}');
    // 打印请求头但隐藏敏感信息
    final safeHeaders = Map<String, String>.from(headers);
    if (safeHeaders.containsKey('Authorization')) {
      safeHeaders['Authorization'] = safeHeaders['Authorization']!.replaceFirst(
        effectiveApiKey,
        '[API_KEY_HIDDEN]',
      );
    }
    if (safeHeaders.containsKey('x-api-key')) {
      safeHeaders['x-api-key'] = '[API_KEY_HIDDEN]';
    }
    debugPrint('请求头: $safeHeaders');

    final Uri uri = Uri.parse(settings.apiUrl);
    debugPrint('请求URL: $uri,  完整URL: ${uri.toString()}');

    try {
      final client = http.Client();
      final response = await client
          .post(uri, headers: headers, body: json.encode(requestBody))
          .timeout(
            const Duration(seconds: 300), // 超时时间改为300秒
            onTimeout: () {
              throw Exception('请求超时，AI分析可能需要更长时间，请稍后再试');
            },
          );

      if (response.statusCode != 200) {
        final errorBody = response.body;
        debugPrint('API错误响应: $errorBody');
        throw Exception('AI服务请求失败：${response.statusCode}\n$errorBody');
      }

      return response;
    } catch (e) {
      debugPrint('API请求错误: $e');
      if (e.toString().contains('Failed host lookup')) {
        throw Exception('无法连接到AI服务器，请检查网络连接或服务器状态');
      }

      // 特殊处理本地服务器连接错误
      if (e.toString().contains('Connection refused') &&
          uri.toString().contains('0.0.0.0')) {
        throw Exception('无法连接到本地AI服务器，请确保服务器已启动或更改API URL');
      }

      rethrow;
    }
  }

  // 新增：流式API请求方法
  Future<void> _makeStreamRequest(
    String url,
    Map<String, dynamic> body,
    AISettings settings,
    StreamingResponseCallback onResponse,
    StreamingCompleteCallback onComplete,
    StreamingErrorCallback onError,
  ) async {
    if (body['messages'] is! List) {
      onError(Exception('messages字段格式错误'));
      return;
    }

    // 创建安全存储服务实例
    final secureStorage = SecureStorageService();

    // 获取API密钥 - 首先尝试从安全存储中获取，如果为空则尝试使用设置中的密钥
    final secureApiKey = await secureStorage.getApiKey();
    final effectiveApiKey = secureApiKey ?? settings.apiKey;

    if (effectiveApiKey.isEmpty) {
      onError(Exception('未找到有效的API密钥，请在设置中配置API密钥'));
      return;
    }

    // 根据不同的AI服务提供商调整请求体格式
    Map<String, dynamic> requestBody;
    Map<String, String> headers = {'Content-Type': 'application/json'};

    // 判断服务提供商类型并相应调整请求
    if (url.contains('anthropic.com')) {
      // Anthropic Claude API格式
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 设置为true以启用流式响应
      };

      // Anthropic使用x-api-key头而非Bearer认证
      headers['anthropic-version'] = '2023-06-01'; // 添加必需的API版本头
      headers['x-api-key'] = effectiveApiKey; // 使用有效的API密钥
    } else if (url.contains('openrouter.ai')) {
      // OpenRouter可能需要额外的头信息
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 设置为true以启用流式响应
      };

      headers['Authorization'] = 'Bearer $effectiveApiKey'; // 使用有效的API密钥
      headers['HTTP-Referer'] = 'https://thoughtecho.app'; // 可能需要指定来源
      headers['X-Title'] = 'ThoughtEcho App'; // 应用名称
    } else if (url.contains('deepseek.com')) {
      // DeepSeek API格式
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 设置为true以启用流式响应
      };

      headers['Authorization'] = 'Bearer $effectiveApiKey'; // 使用有效的API密钥
    } else {
      // 默认格式(适用于OpenAI及其兼容API)
      requestBody = {
        'model': settings.model,
        'messages': body['messages'],
        'temperature': body['temperature'] ?? 0.7,
        'max_tokens': body['max_tokens'] ?? 2500,
        'stream': true, // 设置为true以启用流式响应
      };

      headers['Authorization'] = 'Bearer $effectiveApiKey'; // 使用有效的API密钥
    }

    debugPrint('API请求体: ${json.encode(requestBody)}');
    // 打印请求头但隐藏敏感信息
    final safeHeaders = Map<String, String>.from(headers);
    if (safeHeaders.containsKey('Authorization')) {
      safeHeaders['Authorization'] = safeHeaders['Authorization']!.replaceFirst(
        effectiveApiKey,
        '[API_KEY_HIDDEN]',
      );
    }
    if (safeHeaders.containsKey('x-api-key')) {
      safeHeaders['x-api-key'] = '[API_KEY_HIDDEN]';
    }
    debugPrint('请求头: $safeHeaders');

    final Uri uri = Uri.parse(settings.apiUrl);
    debugPrint('请求URL: $uri,  完整URL: ${uri.toString()}');

    try {
      final client = http.Client();
      final request = http.Request('POST', uri);
      request.headers.addAll(headers);
      request.body = json.encode(requestBody);

      final streamedResponse = await client
          .send(request)
          .timeout(
            const Duration(seconds: 300), // 超时时间为300秒
            onTimeout: () async {
              onError(Exception('请求超时，AI分析可能需要更长时间，请稍后再试'));
              // 使用 IOStreamedResponse 匹配正确的返回类型
              return http.StreamedResponse(
                Stream<List<int>>.fromIterable(
                  [],
                ).asBroadcastStream(), // 空流，使用广播流，明确类型为 Stream<List<int>>
                408, // Request Timeout
              );
            },
          );

      if (streamedResponse.statusCode != 200) {
        // 读取错误响应
        final errorBody = await streamedResponse.stream.bytesToString();
        debugPrint('API错误响应: $errorBody');

        // 增强错误处理，提供更具体的错误信息
        if (errorBody.contains('rate_limit_exceeded') ||
            errorBody.contains('rate limit') ||
            errorBody.contains('429')) {
          onError(Exception('请求频率超限，请稍后再试 (429 错误)'));
        } else if (errorBody.contains('authentication') ||
            errorBody.contains('invalid_api_key') ||
            errorBody.contains('401')) {
          onError(Exception('API密钥无效或已过期，请更新API密钥 (401 错误)'));
        } else if (errorBody.contains('insufficient_quota') ||
            errorBody.contains('billing') ||
            errorBody.contains('429')) {
          onError(Exception('API额度不足，请检查账户余额 (429 错误)'));
        } else {
          onError(
            Exception('AI服务请求失败：${streamedResponse.statusCode}\n$errorBody'),
          );
        }
        return;
      }

      // 处理流式响应
      String fullText = '';
      String currentChunk = '';

      streamedResponse.stream
          .transform(utf8.decoder)
          .listen(
            (String chunk) {
              currentChunk += chunk;

              // 尝试从数据块中提取有效部分
              final lines = currentChunk.split('\n');
              currentChunk = '';

              for (var i = 0; i < lines.length; i++) {
                var line = lines[i];

                // 如果不是最后一行，或者是完整的行
                if (i < lines.length - 1 ||
                    line.endsWith('\n') ||
                    line.trim().isEmpty) {
                  if (line.startsWith('data: ') && line != 'data: [DONE]') {
                    try {
                      final jsonData = line.substring(6).trim();
                      if (jsonData.isNotEmpty) {
                        final data = json.decode(jsonData);
                        if (data['choices'] != null &&
                            data['choices'].isNotEmpty) {
                          String content = '';
                          // 处理不同API的响应格式
                          if (data['choices'][0]['delta'] != null &&
                              data['choices'][0]['delta']['content'] != null) {
                            content = data['choices'][0]['delta']['content'];
                          } else if (data['choices'][0]['text'] != null) {
                            content = data['choices'][0]['text'];
                          } else if (data['choices'][0]['message'] != null &&
                              data['choices'][0]['message']['content'] !=
                                  null) {
                            content = data['choices'][0]['message']['content'];
                          }

                          if (content.isNotEmpty) {
                            fullText += content;
                            onResponse(content);
                          }
                        }
                      }
                    } catch (e) {
                      debugPrint('解析流式响应数据失败: $e, 行内容: $line');
                      // 尝试更宽松的解析方式，获取可能的内容
                      try {
                        if (line.contains('"content"')) {
                          final contentIndex = line.indexOf('"content"');
                          final colonIndex = line.indexOf(':', contentIndex);
                          if (colonIndex != -1) {
                            final quoteIndex = line.indexOf('"', colonIndex);
                            if (quoteIndex != -1) {
                              final endQuoteIndex = line.indexOf(
                                '"',
                                quoteIndex + 1,
                              );
                              if (endQuoteIndex != -1) {
                                final content = line.substring(
                                  quoteIndex + 1,
                                  endQuoteIndex,
                                );
                                if (content.isNotEmpty) {
                                  fullText += content;
                                  onResponse(content);
                                }
                              }
                            }
                          }
                        }
                      } catch (e2) {
                        debugPrint('备选解析方法也失败: $e2');
                      }
                    }
                  }
                } else {
                  // 不完整的行，保留到下一个块处理
                  currentChunk = line;
                }
              }
            },
            onDone: () {
              debugPrint('流式响应接收完毕');
              onComplete(fullText);
              client.close();
            },
            onError: (e) {
              debugPrint('流式响应错误: $e');
              onError(e);
              client.close();
            },
          );
    } catch (e) {
      debugPrint('API请求错误: $e');
      if (e.toString().contains('Failed host lookup')) {
        onError(Exception('无法连接到AI服务器，请检查网络连接或服务器状态'));
      } else if (e.toString().contains('Connection refused') &&
              uri.toString().contains('0.0.0.0') ||
          uri.toString().contains('localhost')) {
        onError(Exception('无法连接到本地AI服务器，请确保服务器已启动或更改API URL'));
      } else if (e.toString().contains('certificate')) {
        onError(Exception('证书验证失败，请检查HTTPS配置或使用HTTP连接'));
      } else {
        onError(e);
      }
    }
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

      final data = json.decode(response.body);
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.body}');
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
      // 如果API Key有效，调用AI生成流式提示
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

      final data = json.decode(response.body);
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.body}');
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

      final data = json.decode(response.body);
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.body}');
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

      final data = json.decode(response.body);
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.body}');
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

      final data = json.decode(response.body);
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.body}');
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

      final data = json.decode(response.body);
      if (data['choices'] != null &&
          data['choices'].isNotEmpty &&
          data['choices'][0]['message'] != null) {
        return data['choices'][0]['message']['content'];
      } else {
        debugPrint('API响应格式错误: ${response.body}');
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
- 保持客观、清晰和专业的语调
- 使用精确的语言和分析性表达
- 基于事实和观察提供见解
- 结构化呈现信息和分析
- 保持适当的专业距离''';
        break;
    }

    return '$systemPrompt\n\n$stylePrompt';
  }
}
