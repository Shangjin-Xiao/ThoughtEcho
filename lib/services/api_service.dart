import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/http_utils.dart';

/// 一言响应数据模型
class HitokotoResponse {
  final String id;
  final String hitokoto;
  final String type;
  final String from;
  final String? fromWho;
  final int created;

  HitokotoResponse({
    required this.id,
    required this.hitokoto,
    required this.type,
    required this.from,
    this.fromWho,
    required this.created,
  });

  factory HitokotoResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('id') || !json.containsKey('hitokoto')) {
      throw FormatException('一言API返回数据格式错误');
    }
    
    return HitokotoResponse(
      id: json['id'].toString(),
      hitokoto: json['hitokoto'],
      type: json['type'] ?? '',
      from: json['from'] ?? '',
      fromWho: json['from_who'],
      created: json['created'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toQuoteMap() {
    return {
      'content': hitokoto,
      'source': from,
      'author': fromWho,
      'type': type,
      'from_who': fromWho,
      'from': from,
      'id': id,
      'created': created,
    };
  }
}

/// 一言服务异常
class HitokotoException implements Exception {
  final String message;
  final int? statusCode;

  HitokotoException(this.message, {this.statusCode});

  @override
  String toString() => statusCode != null ? '$message (状态码: $statusCode)' : message;
}

/// API服务类
class ApiService {
  static const String baseUrl = 'https://v1.hitokoto.cn/';
  
  /// 一言类型常量
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

  /// 请求超时时间（秒）
  static const int _timeoutSeconds = 10;

  /// 获取一言数据
  /// [type] 一言类型，可以是单个类型或逗号分隔的多个类型
  /// 抛出 [HitokotoException] 当请求失败或解析错误时
  static Future<Map<String, dynamic>> getDailyQuote(String type) async {
    try {
      // 构建API URL
      final String apiUrl;
      if (type == 'l') {
        // 抖机灵类型随机使用其他类型
        final validTypes = hitokotoTypes.keys.where((k) => k != 'l').toList();
        final randomType = validTypes[Random().nextInt(validTypes.length)];
        apiUrl = '$baseUrl?c=$randomType';
      } else if (type.contains(',')) {
        // 多类型请求，排除抖机灵类型
        final types = type.split(',').where((t) => t != 'l').join(',');
        if (types.isEmpty) {
          throw HitokotoException('无效的类型选择');
        }
        final typeParams = types.split(',').map((t) => 'c=$t').join('&');
        apiUrl = '$baseUrl?$typeParams';
      } else {
        apiUrl = '$baseUrl?c=$type';
      }
      
      debugPrint('一言API请求URL: $apiUrl');
      
      // 发送请求
      final response = await HttpUtils.secureGet(
        apiUrl,
        timeoutSeconds: _timeoutSeconds,
      );

      // 处理响应
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final hitokoto = HitokotoResponse.fromJson(data);
        return hitokoto.toQuoteMap();
      } else if (response.statusCode == 429) {
        throw HitokotoException('请求过于频繁，请稍后再试', statusCode: response.statusCode);
      } else {
        throw HitokotoException('服务器返回错误', statusCode: response.statusCode);
      }
    } on FormatException catch (e) {
      debugPrint('一言数据格式错误: $e');
      throw HitokotoException('一言数据格式错误: ${e.message}');
    } on HitokotoException {
      rethrow;
    } catch (e) {
      debugPrint('获取一言发生异常: $e');
      throw HitokotoException('网络请求失败，请检查网络连接');
    }
  }

  /// 格式化显示文本
  static String formatDisplayText(Map<String, dynamic> quote) {
    if (!quote.containsKey('content')) {
      throw HitokotoException('无效的一言数据格式');
    }

    final StringBuffer buffer = StringBuffer();
    
    buffer.write(quote['content']);
    
    final String? author = quote['from_who'];
    final String? source = quote['from'];
    
    if ((author?.isNotEmpty ?? false) || (source?.isNotEmpty ?? false)) {
      buffer.write('\n');
      
      if (author?.isNotEmpty ?? false) {
        buffer.write('——$author');
      }
      
      if (source?.isNotEmpty ?? false) {
        if (author?.isNotEmpty ?? false) {
          buffer.write(' ');
        } else {
          buffer.write('——');
        }
        buffer.write('《$source》');
      }
    }
    
    return buffer.toString();
  }
}
