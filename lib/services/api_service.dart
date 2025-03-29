import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static Future<Map<String, dynamic>> getDailyQuote([String? type]) async {
    int retryCount = 0;
    const maxRetries = 2;
    
    while (retryCount < maxRetries) {
      try {
        final uri = type != null
            ? Uri.parse('https://v1.hitokoto.cn/?c=$type')
            : Uri.parse('https://v1.hitokoto.cn/');
        final response = await http.get(uri);
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          return {
            'content': data['hitokoto'],
            'source': data['from'] ?? '未知',
            'type': data['type'] ?? 'a'
          };
        } else if (response.statusCode == 429) {
          await Future.delayed(Duration(seconds: 1));
          retryCount++;
          continue;
        }
        
        return {
          'content': '获取失败，请稍后重试。',
          'source': '系统',
          'type': 'a'
        };
      } catch (e) {
        print('获取一言失败: $e');
        if (retryCount < maxRetries - 1) {
          await Future.delayed(Duration(seconds: 1));
          retryCount++;
          continue;
        }
        return {
          'content': '网络错误，请检查网络连接。',
          'source': '系统',
          'type': 'a'
        };
      }
    }
    
    return {
      'content': '获取失败，请稍后重试。',
      'source': '系统',
      'type': 'a'
    };
  }
}