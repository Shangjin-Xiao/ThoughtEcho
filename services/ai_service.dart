import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/quote_model.dart';
import 'settings_service.dart';

class AIService {
  SettingsService settingsService;

  AIService(this.settingsService);

  Future<void> _validateSettings() async {
    final settings = settingsService.aiSettings;
    if (settings == null || settings.apiKey.isEmpty || settings.apiUrl.isEmpty) {
      throw Exception('AI设置未完成，请先在设置页面配置API信息');
    }
  }

  Future<String> generateInsights(List<Quote> quotes) async {
    try {
      await _validateSettings();
      final settings = settingsService.aiSettings!;

      final messages = [
        {"role": "system", "content": "你是一个专业的笔记整理和分析助手，请分析用户的日记内容并给出洞察。"},
        {
          "role": "user",
          "content": "基于以下日记内容，给出一份深入的分析：\n" +
              quotes.map((q) {
                final content = "日期：${q.date}\n内容：${q.content}";
                return content;
              }).join("\n\n")
        }
      ];

      final response = await http.post(
        Uri.parse(settings.apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${settings.apiKey}',
        },
        body: jsonEncode({
          'model': settings.model,
          'messages': messages,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('AI请求失败: ${response.body}');
      }
    } catch (e) {
      debugPrint('AI服务错误: $e');
      rethrow;
    }
  }
}
