import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/quote_model.dart';
import '../models/ai_settings.dart';
import '../services/settings_service.dart' show SettingsService;
import '../services/location_service.dart'; // 新增导入
import '../services/weather_service.dart'; // 新增导入
import '../services/secure_storage_service.dart'; // 添加安全存储服务导入
import 'dart:math'; // 用于随机选择

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
    final secureStorage = SecureStorageService();    // 先检查settings中的API Key
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
      rethrow;
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
  }

  Future<String> generateDailyPrompt() async {
    final settings = _settingsService.aiSettings;

    // 检查 AI 配置是否有效
    if (!hasValidApiKey() ||
        settings.apiUrl.isEmpty ||
        settings.model.isEmpty) {
      debugPrint('AI服务未配置，生成基于上下文的提示');
      return _generatePromptBasedOnContext();
    }

    // AI 配置有效，尝试调用 API
    try {
      // 获取当前上下文信息
      final now = DateTime.now();
      final hour = now.hour;
      final weather = _weatherService.currentWeather;
      final temperature = _weatherService.temperature;
      final city = _locationService.city;

      // 确定时间段
      String timeOfDay;
      if (hour >= 5 && hour < 12) {
        timeOfDay = '早上';
      } else if (hour >= 12 && hour < 18) {
        timeOfDay = '下午';
      } else if (hour >= 18 && hour < 23) {
        timeOfDay = '晚上';
      } else {
        timeOfDay = '深夜';
      }

      // 构建上下文字符串
      String contextInfo = '当前时间段：$timeOfDay';
      if (city != null && city.isNotEmpty) {
        contextInfo += '，位置：$city';
      }
      if (weather != null) {
        contextInfo += '，天气：${WeatherService.getWeatherDescription(weather)}';
      }
      if (temperature != null && temperature.isNotEmpty) {
        contextInfo += '，温度：$temperature';
      }

      final messages = [
        {
          'role': 'system',
          'content':
              '你是一位充满文学素养的思考引导者。请根据提供的上下文信息（时间、位置、天气），生成一个富有诗意且引人深思的提示（不超过40个汉字），引导用户记录当下的思绪或感受。语言要优美、富有意境，像古典诗词或现代散文中的句子，可以适当使用比喻、拟人等修辞手法，但要确保简洁明了、一读即懂。注意：只需要输出你创作的内容，不要包含注解或者创作意图解释等其他内容！',
        },
        {'role': 'user', 'content': '请根据以下上下文生成今日思考提示：$contextInfo'},
      ];

      try {
        final response = await _makeRequest(settings.apiUrl, {
          'messages': messages,
          'temperature': 0.9,
        }, settings).timeout(
          const Duration(seconds: 30), // 超时时间为30秒
          onTimeout: () {
            debugPrint('生成每日提示超时');
            throw Exception('请求超时');
          },
        );

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
        debugPrint('生成每日提示网络错误: $e');
        return _getDefaultPrompt();
      }
    } catch (e) {
      // API 调用失败（例如网络错误），返回默认提示
      debugPrint('调用 AI 生成每日提示失败: $e');
      return _getDefaultPrompt();
    }
  }

  // 获取默认的每日提示
  String _getDefaultPrompt() {
    final List<String> defaultPrompts = [
      "今天有什么值得感恩的事？",
      "给过去的自己一句话，会说什么？",
      "今天学到了什么新东西？",
      "什么事想做却还没行动？",
      "最近什么让你感到快乐？",
      "克服困难后有什么感悟？",
      "如果明天完全自由，你会做什么？",
      "今天的挑战是什么？",
      "哪些小习惯正在改变你？",
      "此刻，你想对自己说什么？",
    ];

    // 使用日期为种子选择一个提示，确保同一天显示相同提示
    final today = DateTime.now();
    final dayOfYear = today.difference(DateTime(today.year, 1, 1)).inDays;
    final index = dayOfYear % defaultPrompts.length;
    return defaultPrompts[index];
  }

  // 根据时间和天气生成提示
  String _generatePromptBasedOnContext() {
    final now = DateTime.now();
    final hour = now.hour;
    final weather = _weatherService.currentWeather;
    final temperature = _weatherService.temperature;
    final city = _locationService.city;

    String timeOfDay;
    if (hour >= 5 && hour < 12) {
      timeOfDay = '早上';
    } else if (hour >= 12 && hour < 18) {
      timeOfDay = '下午';
    } else if (hour >= 18 && hour < 23) {
      timeOfDay = '晚上';
    } else {
      timeOfDay = '深夜';
    }

    List<String> prompts = [];

    // 通用提示
    prompts.addAll([
      "此刻，你有什么特别的想法或感受想要记录下来吗？",
      "回顾今天，有什么让你印象深刻的瞬间？",
      "静下心来，感受一下当下的情绪，它想告诉你什么？",
    ]);

    // 基于时间的提示
    if (timeOfDay == '早上') {
      prompts.addAll([
        "新的一天开始了，你对今天有什么期待？",
        "早晨的空气闻起来怎么样？它让你想起了什么？",
        "为今天设定一个小目标吧，可以是什么呢？",
      ]);
    } else if (timeOfDay == '下午') {
      prompts.addAll([
        "午后的阳光或微风，让你有什么感触？",
        "今天过半，有什么进展顺利或遇到挑战的事情吗？",
        "花点时间放松一下，想想让你感到平静的事物。",
      ]);
    } else if (timeOfDay == '晚上') {
      prompts.addAll([
        "夜幕降临，回顾今天，有什么值得回味或反思的？",
        "此刻的宁静适合思考，你脑海中浮现了什么？",
        "为明天做个简单的计划或设想吧。",
      ]);
    } else {
      // 深夜
      prompts.addAll([
        "夜深人静，有什么心事或灵感悄然浮现？",
        "此刻的寂静让你想到了什么？",
        "睡前放下杂念，记录下此刻的心情。",
      ]);
    }

    // --- 结合时间和天气的提示 ---
    if (weather != null) {
      final weatherKey = WeatherService.weatherKeyToLabel.keys.firstWhere(
        (k) =>
            weather == k || weather == WeatherService.getWeatherDescription(k),
        orElse: () => weather,
      );
      if (timeOfDay == '早上') {
        if (weatherKey == 'clear') {
          prompts.add("清晨的阳光洒满窗台，此刻你的心情如何？有什么新的计划吗？");
        } else if (weatherKey == 'rain') {
          prompts.add("听着清晨的雨声，内心是否格外宁静？有什么特别的感悟？");
        } else if (weatherKey == 'cloudy' || weatherKey == 'partly_cloudy') {
          prompts.add("云层微厚的早晨，适合放慢脚步，思考一下最近的得失。");
        }
      } else if (timeOfDay == '下午') {
        if (weatherKey == 'clear') {
          prompts.add("午后暖阳正好，适合小憩片刻，或是记录下此刻的惬意。");
        } else if (weatherKey == 'rain') {
          prompts.add("雨天的午后，窗外滴答作响，屋内适合读一本书或写点什么。");
        }
      } else if (timeOfDay == '晚上' || timeOfDay == '深夜') {
        if (weatherKey == 'clear') {
          prompts.add("夜幕降临，星光或月色正好，此刻有什么心事或梦想？");
        } else if (weatherKey == 'rain') {
          prompts.add("雨夜漫漫，适合独处思考，最近有什么让你困惑或欣喜的事？");
        } else if (weatherKey == 'wind') {
          prompts.add("晚风轻拂的夜晚，思绪是否也随风飘远？记录下此刻的灵感吧。");
        }
      }
    }

    // 基于天气的提示 (如果天气信息可用)
    if (weather != null) {
      final weatherKey = WeatherService.weatherKeyToLabel.keys.firstWhere(
        (k) =>
            weather == k || weather == WeatherService.getWeatherDescription(k),
        orElse: () => weather,
      );
      if (weatherKey == 'clear') {
        prompts.addAll(["阳光明媚的日子，有什么让你感到开心？", "这样的好天气，适合做些什么让你放松的事情？"]);
      } else if (weatherKey == 'rain') {
        prompts.addAll(["听着雨声，你的心情是怎样的？", "雨天适合沉思，有什么想法在脑海中萦绕？"]);
      } else if (weatherKey == 'cloudy' || weatherKey == 'partly_cloudy') {
        prompts.addAll(["多云的天空下，你的思绪飘向了何方？", "阴天有时也别有韵味，它让你想起了什么？"]);
      } else if (weatherKey == 'snow') {
        prompts.addAll(["窗外的雪景给你带来了怎样的感受？", "下雪天，适合窝在温暖的地方思考些什么？"]);
      }
    }

    // 基于温度的提示 (如果温度信息可用)
    if (temperature != null) {
      try {
        final tempValue = double.parse(temperature.replaceAll('°C', '').trim());
        if (tempValue > 28) {
          prompts.add("天气有点热，此刻你最想做什么来降降温？");
        } else if (tempValue < 10) {
          prompts.add("天气有点冷，注意保暖的同时，有什么温暖的想法吗？");
        }
      } catch (e) {
        debugPrint("解析温度失败: $e");
      }
    }

    // 基于城市的提示 (如果城市信息可用)
    if (city != null && city.isNotEmpty) {
      prompts.add("身在 $city，这座城市今天给你带来了什么灵感？");
    }

    // 随机选择一条提示（修改为只返回一条）
    final random = Random();
    prompts.shuffle(random); // 打乱列表顺序

    // 如果没有提示，返回一个默认值
    if (prompts.isEmpty) {
      return "今天，你有什么新的感悟或想法呢？";
    }

    // 返回随机选中的一条提示
    return prompts.first;
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
                'sourceWork': quote.sourceWork,
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

  // 根据分析类型获取基础提示词
  String _getAnalysisTypePrompt(String analysisType) {
    switch (analysisType) {
      case 'emotional':
        return '''你是一位专注情感分析的心理学家，擅长从文字中解读人们的情感状态和变化。
请分析用户的笔记内容，提供深入的情感洞察：

1. 情感状态总结：概括用户笔记中表达的主要情绪和情感状态
2. 情绪波动和模式：识别情绪变化的模式和可能触发因素
3. 积极/消极情绪比例：分析笔记中积极和消极情绪的大致比例
4. 情绪管理建议：提供有针对性的情绪管理策略和建议

请使用温和、理解的语气，像一位支持性的朋友一样，而非冷冰冰的分析。避免使用过于专业的术语，用通俗易懂的语言表达你的洞察。记住，你的目标是帮助用户更好地理解自己的情感世界。''';

      case 'mindmap':
        return '''你是一位思维导图专家和认知分析师，擅长分析人们的思考模式和思维结构。
请分析用户的笔记内容，揭示其思维模式和结构：

1. 核心思考主题：识别用户笔记中反复出现的核心概念和主题
2. 思维模式分析：分析用户的思维风格（如系统性思考、创造性思维、批判性思考等）
3. 思维连接：发现不同笔记之间的隐藏联系和思维路径
4. 思维盲点：温和地指出可能的思维盲区或固定思维模式
5. 思维拓展建议：提出拓展思考的方向和具体建议

请以清晰、结构化的方式组织你的回应，使用思维导图的概念来呈现分析结果。用友好、鼓励的语气，激发用户的思考深度和广度。''';

      case 'growth':
        return '''你是一位成长型思维教练和个人发展顾问，擅长发现人们的成长潜力和进步路径。
请分析用户的笔记内容，提供个性化的成长和进步建议：

1. 个人优势识别：发现并强调用户笔记中展现的能力和优势
2. 成长机会：识别潜在的个人成长机会和领域
3. 目标与价值观：从笔记中提炼用户可能的核心价值观和潜在目标
4. 具体行动建议：提供3-5个具体、可行的行动建议，帮助用户在个人成长道路上前进
5. 长期成长方向：温和地提出一些长期发展的可能方向和愿景

请使用鼓励、支持的语气，像一位有智慧的导师，而不是居高临下的评判者。注重实用性和可行动性，使你的建议切实可行。''';

      case 'comprehensive':
      default:
        return '''你是一位经验丰富、洞察敏锐的个人成长分析师和思维教练。你擅长从用户的日常记录中发现隐藏的模式和连接，并提供深刻的个人成长洞察。

请以一位贴心的私人顾问身份，分析以下笔记内容，创建一份结构清晰、内容丰富的个人洞察报告，帮助用户更好地了解自己：

1. 核心主题与思考焦点：发现笔记中反复出现的主题、关键概念和思考方向
2. 情感状态分析：解读笔记中表达的情绪变化和情感模式，以及可能的位置、天气等环境因素影响
3. 思维模式特点：分析用户的思考风格、视角和思维习惯
4. 个人成长亮点：指出笔记中展现的进步、成长和积极变化
5. 前进方向建议：根据分析结果，提供3-5个具体、个性化的成长建议

请使用温和、支持的语气，避免居高临下的评判。确保你的分析既有深度，又具有实用性，能真正帮助用户获得关于自己的新见解。''';
    }
  }

  // 根据分析风格调整提示词
  String _appendAnalysisStylePrompt(String basePrompt, String analysisStyle) {
    String styleAppendix = '';

    switch (analysisStyle) {
      case 'friendly':
        styleAppendix = '''
        
风格指导：请以非常友好、亲切的方式表达你的分析，就像与老朋友聊天一样。使用温暖、鼓励的语气，偶尔可以加入一些轻松的表达。避免过于正式或学术化的语言，保持亲近感和共情。使用"我们"、"你"等代词增强亲近感，并确保你的建议是鼓励性的，而不是指导性的。''';
        break;

      case 'humorous':
        styleAppendix = '''
        
风格指导：请以风趣幽默的方式呈现你的分析，像网易云音乐的歌单锐评一样。可以适当加入一些诙谐的比喻、俏皮的表达和轻松的调侃（但要尊重用户）。使用生动有趣的语言，避免过于严肃的表达方式。可以使用一些流行梗或轻松的修辞手法，让分析读起来既有深度又有趣味。记住，目标是让用户在会心一笑的同时获得有价值的洞察。''';
        break;

      case 'literary':
        styleAppendix = '''
        
风格指导：请以优美的文学风格呈现你的分析，仿佛在撰写一篇散文或随笔。使用富有诗意的语言、生动的比喻和优雅的表达。可以引用一些经典文学作品或古诗词来点缀你的分析。结构上可以更加灵活流畅，像讲述一个故事一样展开你的洞察。通过文学性的表达方式，让用户感受到思考的美和自我探索的意义。''';
        break;

      case 'professional':
      default:
        styleAppendix = '''
        
风格指导：请保持专业、清晰的分析风格，注重逻辑性和实用性。使用结构化的段落和清晰的标题，确保分析易于理解和应用。语言应该精确但不过于学术化，避免使用过多专业术语。保持适度的客观性，同时传达出足够的理解和支持。''';
        break;
    }

    return basePrompt + styleAppendix;
  }

  // 使用自定义提示词生成洞察
  Future<String> generateCustomInsights(
    List<Quote> quotes,
    String customPrompt,
  ) async {
    if (!hasValidApiKey()) {
      throw Exception('请先在设置中配置 API Key');
    }
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final quotesText = quotes
          .map((quote) {
            String quoteText = '日期：${quote.date}\n内容：${quote.content}';
            // 添加额外的笔记元数据，如果存在的话
            if (quote.location != null && quote.location!.isNotEmpty) {
              quoteText += '\n位置：${quote.location}';
            }
            if (quote.weather != null && quote.weather!.isNotEmpty) {
              quoteText += '\n天气：${quote.weather}';
            }
            if (quote.temperature != null && quote.temperature!.isNotEmpty) {
              quoteText += '\n温度：${quote.temperature}';
            }
            if (quote.source != null && quote.source!.isNotEmpty) {
              quoteText += '\n来源：${quote.source}';
            }
            return quoteText;
          })
          .join('\n\n');

      final messages = [
        {
          'role': 'system',
          'content': '''你是一位资深的笔记分析和个人成长顾问。你的任务是根据用户的特定要求，分析他们的笔记内容。
请以专业、友好且有洞察力的方式回应用户的特定分析请求。注重提供有用、实用且个性化的洞察。
避免使用过于学术或抽象的语言，保持回应亲切自然。请遵循用户的具体指示进行分析。

分析时，请特别注意笔记中包含的环境因素（如位置、天气、温度）对用户心情和思考的潜在影响，如果这些信息可用的话。''',
        },
        {
          'role': 'user',
          'content': '请根据以下要求分析我的笔记：\n\n$customPrompt\n\n笔记内容：\n\n$quotesText',
        },
      ];

      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 3000,
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
      debugPrint('生成自定义洞察错误: $e');
      rethrow;
    }
  }

  Future<String> askQuestion(Quote quote, String question) async {
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {'role': 'system', 'content': '你是一个专业的笔记分析助手，请根据用户的笔记内容回答问题。'},
        {'role': 'user', 'content': '笔记内容：${quote.content}\n\n问题：$question'},
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
      debugPrint('提问错误: $e');
      rethrow;
    }
  }

  // 分析来源，返回JSON格式的结果
  Future<String> analyzeSource(String content) async {
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

  // 润色文本
  Future<String> polishText(String content) async {
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
      debugPrint('润色文本错误: $e');
      rethrow;
    }
  }

  // 续写文本
  Future<String> continueText(String content) async {
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {
          'role': 'system',
          'content': '''你是一个专业的文本创作助手，擅长根据已有内容进行续写。
请根据用户提供的文本，以相同的风格和语调进行自然的延伸和续写。在保持连贯性和一致性的同时，提供有深度和意义的内容。

注意：
1. 保持与原文一致的风格、语气和主题
2. 续写的内容应当是原文的自然延伸
3. 不要重复原文的内容
4. 续写的长度大约为原文的一半到相当长度
5. 确保内容有深度，不要流于表面''',
        },
        {'role': 'user', 'content': '请续写以下文本：\n\n$content'},
      ];

      final response = await _makeRequest(settings.apiUrl, {
        'messages': messages,
        'temperature': 0.8, // 使用较高的创意性
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
      debugPrint('续写文本错误: $e');
      rethrow;
    }
  }
}

class AiService {
  void analyzeData(dynamic data) {
    if (data is! String) return;
    // 使用日志记录代替print
    debugPrint("Analyzing data: $data");
  }
}
