import 'dart:convert';
import 'package:http/http.dart' as http;

class Request {
  const Request();
}

class ApiService {
  static const String baseUrl = 'https://v1.hitokoto.cn/';

  // 一言类型常量
  static const Map<String, String> hitokotoTypes = {
    'a': '动画',
    'b': '漫画',
    'c': '游戏',
    'd': '文学',
    'e': '原创',
    'f': '来自网络',
    'g': '其他',
    'h': '影视',
    'i': '诗词',
    'j': '网易云',
    'k': '哲学',
    'l': '抖机灵',
  };

  static Future<Map<String, dynamic>> getDailyQuote([String? type]) async {
    try {
      final uri = type != null
          ? Uri.parse('$baseUrl?c=$type')
          : Uri.parse(baseUrl);
      
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'content': data['hitokoto'],
          'from': data['from'] ?? '',
          'from_who': data['from_who'] ?? '',
          'type': data['type'] ?? ''
        };
      } else {
        return {
          'content': '获取每日一言失败',
          'from_who': '',
          'from': ''
        };
      }
    } catch (e) {
      return {
        'content': '网络连接错误',
        'from_who': '',
        'from': ''
      };
    }
  }

  void fetchData() {
    final req = const Request();
    print("请求发送：${req.toString()}");
  }
}