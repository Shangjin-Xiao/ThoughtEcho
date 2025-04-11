import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/quote_model.dart';
import '../models/ai_settings.dart';
import '../services/settings_service.dart' show SettingsService;
import '../services/location_service.dart'; // 新增导入
import '../services/weather_service.dart'; // 新增导入
import 'dart:math'; // 用于随机选择

class AIService extends ChangeNotifier {
  final SettingsService _settingsService;
  final LocationService _locationService; // 新增
  final WeatherService _weatherService; // 新增

  AIService({
    required SettingsService settingsService,
    required LocationService locationService, // 新增
    required WeatherService weatherService, // 新增
  })  : _settingsService = settingsService,
        _locationService = locationService, // 新增
        _weatherService = weatherService; // 新增

  Future<void> _validateSettings() async {
    final settings = _settingsService.aiSettings;
    if (settings.apiKey.isEmpty) {
      throw Exception('请先在设置中配置 API Key');
    }
    if (settings.apiUrl.isEmpty) {
      throw Exception('请先在设置中配置 API URL');
    }
    if (settings.model.isEmpty) {
      throw Exception('请先在设置中配置 AI 模型');
    }
  }

  Future<http.Response> _makeRequest(String url, Map<String, dynamic> body, AISettings settings) async {
    if (body['messages'] is! List) {
      throw Exception('messages字段格式错误');
    }

    final requestBody = {
      'model': settings.model,
      'messages': body['messages'],
      'temperature': body['temperature'] ?? 0.7,
      'max_tokens': body['max_tokens'] ?? 1000,
      'stream': false
    };

    debugPrint('API请求体: ${json.encode(requestBody)}');

    final Uri uri = Uri.parse(settings.apiUrl);
    debugPrint('请求URL: $uri,  完整URL: ${uri.toString()}');

    try {
      final client = http.Client();
      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${settings.apiKey}',
        },
        body: json.encode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.statusCode != 200) {
        final errorBody = response.body;
        debugPrint('API错误响应: $errorBody');
        throw Exception('API请求失败：${response.statusCode}\n$errorBody');
      }

      return response;
    } catch (e) {
      debugPrint('API请求错误: $e');
      if (e.toString().contains('Failed host lookup')) {
        throw Exception('无法连接到API服务器，请确保服务器已启动');
      }
      rethrow;
    }
  }

  Future<String> summarizeNote(Quote quote) async {
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;
      
      final messages = [
        {
          'role': 'system',
          'content': '你是一位资深的个人成长导师和思维教练，拥有卓越的洞察力和分析能力。你的任务是深入分析用户提供的笔记内容，帮助用户更好地理解自己的想法和情感。请像一位富有经验的导师一样，从以下几个方面进行专业、细致且富有启发性的分析：\n\n1. **核心思想 (Main Idea)**：  提炼并概括笔记内容的核心思想或主题，用简洁明了的语言点明笔记的重点。\n\n2. **情感色彩 (Emotional Tone)**：  分析笔记中流露出的情感倾向，例如积极、消极、平静、焦虑等，并尝试解读情感背后的原因。\n\n3. **行动启示 (Actionable Insights)**：  基于笔记内容和分析结果，为用户提供具体、可执行的行动建议或启示，帮助用户将思考转化为行动，促进个人成长和改进。\n\n请确保你的分析既专业深入，又通俗易懂，能够真正帮助用户理解自己，并获得成长和提升。',
        },
        {
          'role': 'user',
          'content': '请分析以下内容：\n${quote.content}'
        }
      ];

      final response = await _makeRequest(
        settings.apiUrl,
        {
          'messages': messages,
          'temperature': 0.7
        },
        settings
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
      debugPrint('笔记分析错误: $e');
      rethrow;
    }
  }

  Future<String> generateDailyPrompt() async {
    final settings = _settingsService.aiSettings;

    // 检查 AI 配置是否有效
    if (settings.apiKey.isEmpty || settings.apiUrl.isEmpty || settings.model.isEmpty) {
      debugPrint('AI服务未配置，生成基于上下文的提示');
      return _generatePromptBasedOnContext();
    }

    // AI 配置有效，尝试调用 API
    try {
      
      final messages = [
        {
          'role': 'system',
          'content': '你是一个富有哲理和智慧的导师，请生成一个发人深省的问题或提示，引导用户进行思考和写作。'
        },
        {
          'role': 'user',
          'content': '请生成一个今日提示，帮助用户进行思考和写作。'
        }
      ];

      try {
        final response = await _makeRequest(
          settings.apiUrl,
          {
            'messages': messages,
            'temperature': 0.9
          },
          settings
        ).timeout(
          const Duration(seconds: 15),
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
      "今天，你有什么让自己感到特别感恩的事情吗？",
      "如果你能给过去的自己一个建议，那会是什么？",
      "你今天学到了什么新东西？有什么启发吗？",
      "有什么一直想尝试却还没有行动的事情？是什么阻碍了你？",
      "反思一下：最近有什么事情让你感到特别快乐或有成就感？",
      "你最近克服了什么困难？这个经历教会了你什么？",
      "如果时间和金钱都不是问题，明天你会做什么？",
      "今天遇到的最大挑战是什么？你是如何应对的？",
      "有哪些小习惯正在积极地改变你的生活？",
      "你最珍视的三个价值观是什么？为什么它们对你如此重要？"
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
    } else { // 深夜
      prompts.addAll([
        "夜深人静，有什么心事或灵感悄然浮现？",
        "此刻的寂静让你想到了什么？",
        "睡前放下杂念，记录下此刻的心情。",
      ]);
    }

    // --- 结合时间和天气的提示 ---
    if (weather != null) {
      if (timeOfDay == '早上') {
        if (weather.contains('晴')) {
          prompts.add("清晨的阳光洒满窗台，此刻你的心情如何？有什么新的计划吗？");
        } else if (weather.contains('雨')) {
          prompts.add("听着清晨的雨声，内心是否格外宁静？有什么特别的感悟？");
        } else if (weather.contains('云') || weather.contains('阴')) {
          prompts.add("云层微厚的早晨，适合放慢脚步，思考一下最近的得失。");
        }
      } else if (timeOfDay == '下午') {
         if (weather.contains('晴')) {
          prompts.add("午后暖阳正好，适合小憩片刻，或是记录下此刻的惬意。");
        } else if (weather.contains('雨')) {
          prompts.add("雨天的午后，窗外滴答作响，屋内适合读一本书或写点什么。");
        }
      } else if (timeOfDay == '晚上' || timeOfDay == '深夜') {
        if (weather.contains('晴')) {
           prompts.add("夜幕降临，星光或月色正好，此刻有什么心事或梦想？");
        } else if (weather.contains('雨')) {
           prompts.add("雨夜漫漫，适合独处思考，最近有什么让你困惑或欣喜的事？");
        } else if (weather.contains('风')) {
           prompts.add("晚风轻拂的夜晚，思绪是否也随风飘远？记录下此刻的灵感吧。");
        }
      }
    }

    // 基于天气的提示 (如果天气信息可用)
    if (weather != null) {
      if (weather.contains('晴')) {
        prompts.addAll([
          "阳光明媚的日子，有什么让你感到开心？",
          "这样的好天气，适合做些什么让你放松的事情？",
        ]);
      } else if (weather.contains('雨')) {
        prompts.addAll([
          "听着雨声，你的心情是怎样的？",
          "雨天适合沉思，有什么想法在脑海中萦绕？",
        ]);
      } else if (weather.contains('云') || weather.contains('阴')) {
        prompts.addAll([
          "多云的天空下，你的思绪飘向了何方？",
          "阴天有时也别有韵味，它让你想起了什么？",
        ]);
      } else if (weather.contains('雪')) {
         prompts.addAll([
          "窗外的雪景给你带来了怎样的感受？",
          "下雪天，适合窝在温暖的地方思考些什么？",
        ]);
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

  Future<String> generateInsights(List<Quote> quotes) async {
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final quotesText = quotes.map((quote) {
        return '日期：${quote.date}\n内容：${quote.content}';
      }).join('\n\n');

      final messages = [
        {
          'role': 'system',
          'content': '你是一位经验丰富、洞察敏锐的个人成长分析师和心理咨询师。你擅长从用户的日常记录中发现隐藏的模式和规律，并提供深刻的个人成长洞察。 你的任务是深入分析用户提供的所有笔记内容，从以下几个方面进行专业、全面且具有启发性的分析，帮助用户更好地了解自己：\n\n1. **核心主题与关注焦点 (Main Themes & Focus Areas)**：  分析用户笔记中反复出现的主题、关键词和概念，总结用户当前最关注的领域和核心议题。\n\n2. **情感变化趋势 (Emotional Trend Analysis)**：  分析用户在不同时期的笔记中表达的情感变化趋势，例如情绪波动、情感周期等，帮助用户了解自身情感状态的变化规律。\n\n3. **思维模式特点 (Thinking Pattern Characteristics)**：  分析用户的思维方式、认知偏好和思考习惯，例如理性思维、感性思维、发散思维、收敛思维等，帮助用户认识自己的思维优势和局限。\n\n4. **个性化成长建议 (Personalized Growth Recommendations)**：  基于以上分析，为用户提供量身定制的个人成长建议，例如提升专注力、改善情绪管理、拓展知识领域等， направлены на 促进用户的全面发展。\n\n请你运用你的专业知识和分析技巧，像一位贴心的私人顾问一样，为用户提供一份 содержательный, insightful, and actionable 个人洞察报告。',
        },
        {
          'role': 'user',
          'content': '请分析以下笔记内容：\n\n$quotesText'
        }
      ];

      final response = await _makeRequest(
        settings.apiUrl,
        {
          'messages': messages,
          'temperature': 0.7
        },
        settings
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
      debugPrint('生成洞察错误: $e');
      rethrow;
    }
  }

  Future<String> askQuestion(Quote quote, String question) async {
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;

      final messages = [
        {
          'role': 'system',
          'content': '你是一个专业的笔记分析助手，请根据用户的笔记内容回答问题。'
        },
        {
          'role': 'user',
          'content': '笔记内容：${quote.content}\n\n问题：$question'
        }
      ];

      final response = await _makeRequest(
        settings.apiUrl,
        {
          'messages': messages,
          'temperature': 0.7
        },
        settings
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
      debugPrint('提问错误: $e');
      rethrow;
    }
  }
}

class AiService {
  void analyzeData(dynamic data) {
    if (data is! String) return;
    print("Analyzing data: $data");
  }
}
