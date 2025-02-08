import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/quote_model.dart';
import '../models/ai_settings.dart';
import '../services/settings_service.dart' show SettingsService;

class AIService extends ChangeNotifier {
  final SettingsService _settingsService;

  AIService({required SettingsService settingsService})
      : _settingsService = settingsService;

  Future<void> _validateSettings() async {
    final settings = _settingsService.aiSettings;
    if (settings.apiKey.isEmpty) {
      throw Exception('请先在设置中配置 API Key');
    }
  }

  Future<http.Response> _makeRequest(String url, Map<String, dynamic> body, AISettings settings) async {
    if (!body.containsKey('messages') || !(body['messages'] is List)) {
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
    try {
      await _validateSettings();
      final settings = _settingsService.aiSettings;
      
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

      final response = await _makeRequest(
        settings.apiUrl,
        {
          'messages': messages,
          'temperature': 0.9
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
      debugPrint('生成每日提示错误: $e');
      rethrow;
    }
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
