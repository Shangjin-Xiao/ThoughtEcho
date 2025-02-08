import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static Future<String> getDailyQuote() async {
    try {
      final response = await http.get(Uri.parse('https://v1.hitokoto.cn/'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['hitokoto'];
      }
      return '获取失败，请稍后重试。';
    } catch (e) {
      return '网络错误，请检查网络连接。';
    }
  }
} 