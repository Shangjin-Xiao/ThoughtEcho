import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../utils/app_logger.dart';

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
    // 移除抖机灵类型
  };

  // 添加一个常量定义请求超时时间
  static const int _timeoutSeconds = 10;

  // 获取一言API数据
  static Future<Map<String, dynamic>> getDailyQuote(String type) async {
    try {
      // 处理多类型选择的情况
      String apiUrl = 'https://v1.hitokoto.cn/';

      // 如果类型包含逗号，说明是多类型选择
      if (type.contains(',')) {
        // 将逗号分隔的类型转换为c=a&c=b&c=d格式
        final types = type.split(',');
        final typeParams = types.map((t) => 'c=$t').join('&');
        apiUrl = '$apiUrl?$typeParams';
      } else {
        // 单类型选择
        apiUrl = '$apiUrl?c=$type';
      }

      logDebug('一言API请求URL: $apiUrl');
      // 使用带超时的HTTP请求
      final response = await NetworkService.instance
          .get(apiUrl, timeoutSeconds: _timeoutSeconds)
          .catchError((error) {
            logDebug('一言API请求错误: $error');
            throw error;
          });

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          // 验证返回的数据结构
          if (data is Map<String, dynamic> && data.containsKey('hitokoto')) {
            return {
              'content': data['hitokoto'],
              'source': data['from'],
              'author': data['from_who'],
              'type': data['type'],
              'from_who': data['from_who'],
              'from': data['from'],
            };
          } else {
            logDebug('一言API返回数据格式错误: $data');
            return _getDefaultQuote();
          }
        } catch (e) {
          logDebug('一言API JSON解析失败: $e, 响应体: ${response.body}');
          return _getDefaultQuote();
        }
      } else {
        logDebug('一言API请求失败: ${response.statusCode}, 响应体: ${response.body}');
        return _getDefaultQuote();
      }
    } catch (e) {
      logDebug('获取一言异常: $e');
      return _getDefaultQuote();
    }
  }

  // 提供默认引言，在网络请求失败时使用
  static Map<String, dynamic> _getDefaultQuote() {
    // 预设的引言列表
    final quotes = [
      {
        'content': '生活不止眼前的苟且，还有诗和远方。',
        'source': '未知',
        'author': '未知',
        'type': 'a',
        'from_who': '未知',
        'from': '未知',
      },
      {
        'content': '人生就像一场旅行，不必在乎目的地，在乎的是沿途的风景。',
        'source': '未知',
        'author': '未知',
        'type': 'a',
        'from_who': '未知',
        'from': '未知',
      },
      {
        'content': '不要等待机会，而要创造机会。',
        'source': '未知',
        'author': '未知',
        'type': 'a',
        'from_who': '未知',
        'from': '未知',
      },
    ];

    // 随机选择一条引言
    final random = DateTime.now().millisecondsSinceEpoch % quotes.length;
    return quotes[random];
  }

  void fetchData() {
    const req = Request();
    logDebug("请求发送：${req.toString()}");
  }
}
