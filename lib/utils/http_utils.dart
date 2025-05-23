import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/material.dart';

class HttpUtils {
  // 创建一个配置安全的HTTP客户端
  static http.Client createSecureClient() {
    return http.Client();
  }

  // 安全的GET请求
  static Future<http.Response> secureGet(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    final client = createSecureClient();
    try {
      final uri = Uri.parse(url);

      // 一言API特殊处理，允许HTTP请求
      if (!url.startsWith('https://') && !url.contains('hitokoto.cn')) {
        debugPrint('警告: 使用非HTTPS URL: $url');
      }

      final response = client.get(uri, headers: headers);

      if (timeoutSeconds != null) {
        return await response.timeout(
          Duration(seconds: timeoutSeconds),
          onTimeout: () {
            client.close();
            // 返回一个超时响应而不是抛出异常
            return http.Response(
              '{"error": "Request timeout"}',
              408,
              headers: {'content-type': 'application/json'},
            );
          },
        );
      }

      return await response;
    } finally {
      client.close();
    }
  }

  // 安全的POST请求
  static Future<http.Response> securePost(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final client = createSecureClient();
    try {
      final uri = Uri.parse(url);

      // 检查是否为HTTPS URL
      if (!url.startsWith('https://')) {
        throw Exception('非安全URL: 所有请求必须使用HTTPS');
      }

      return await client.post(uri, headers: headers, body: body);
    } finally {
      client.close();
    }
  }
}
