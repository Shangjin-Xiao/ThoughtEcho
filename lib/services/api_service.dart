import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static Future<Map<String, dynamic>> getDailyQuote([String? type]) async {
    try {
      final uri = type != null
          ? Uri.parse('https://v1.hitokoto.cn/?c=$type')
          : Uri.parse('https://v1.hitokoto.cn/');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['hitokoto'];
      }
      return {
        'content': '获取失败，请稍后重试。',
        'source': '系统',
        'type': 'a'
      };
    } catch (e) {
      return {
        'content': '网络错误，请检查网络连接。',
        'source': '系统',
        'type': 'a'
      };
    }
  }
} 