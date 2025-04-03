import 'package:http/http.dart' as http;
import 'dart:io';

class HttpUtils {
  // 创建一个配置安全的HTTP客户端
  static http.Client createSecureClient() {
    return http.Client();
  }
  
  // 安全的GET请求
  static Future<http.Response> secureGet(String url, {Map<String, String>? headers}) async {
    final client = createSecureClient();
    try {
      final uri = Uri.parse(url);
      
      // 检查是否为HTTPS URL
      if (!url.startsWith('https://')) {
        throw Exception('非安全URL: 所有请求必须使用HTTPS');
      }
      
      return await client.get(
        uri,
        headers: headers,
      );
    } finally {
      client.close();
    }
  }
  
  // 安全的POST请求
  static Future<http.Response> securePost(
    String url, 
    {Map<String, String>? headers, Object? body}
  ) async {
    final client = createSecureClient();
    try {
      final uri = Uri.parse(url);
      
      // 检查是否为HTTPS URL
      if (!url.startsWith('https://')) {
        throw Exception('非安全URL: 所有请求必须使用HTTPS');
      }
      
      return await client.post(
        uri,
        headers: headers,
        body: body,
      );
    } finally {
      client.close();
    }
  }
} 