import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dio_network_utils.dart';

class HttpUtils {
  // 单例Dio实例
  static Dio? _dioInstance;

  // 获取Dio实例
  static Dio get _dio {
    if (_dioInstance == null) {
      _dioInstance = Dio();
      _configureDio(_dioInstance!);
    }
    return _dioInstance!;
  }

  // 配置Dio实例
  static void _configureDio(Dio dio) {
    dio.options.connectTimeout = Duration(seconds: 15);
    dio.options.receiveTimeout = Duration(seconds: 15);
    dio.options.sendTimeout = Duration(seconds: 15);
    
    // 添加日志拦截器
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        requestHeader: false,
        responseHeader: false,
        error: true,
        logPrint: (obj) => debugPrint('[HTTP] $obj'),
      ));
    }
    
    // 添加重试拦截器
    dio.interceptors.add(RetryInterceptor(
      dio: dio,
      logPrint: (obj) => debugPrint('[RETRY] $obj'),
      retries: 1,
    ));
  }

  // 兼容旧的http.Response格式
  static http.Response _convertDioResponseToHttpResponse(Response dioResponse) {
    Map<String, String> convertedHeaders = {};
    dioResponse.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        convertedHeaders[name] = values.join(", ");
      }
    });
    
    return http.Response(
      dioResponse.data is String ? dioResponse.data : dioResponse.data.toString(),
      dioResponse.statusCode ?? 0,
      headers: convertedHeaders,
    );
  }

  // 安全的GET请求 (Dio实现)
  static Future<http.Response> secureGet(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    try {
      // 一言API特殊处理，允许HTTP请求
      if (!url.startsWith('https://') && !url.contains('hitokoto.cn')) {
        debugPrint('警告: 使用非HTTPS URL: $url');
      }
      
      final response = await _dio.get(
        url,
        options: Options(
          headers: headers,
          receiveTimeout: timeoutSeconds != null ? Duration(seconds: timeoutSeconds) : null,
        ),
      );
      
      return _convertDioResponseToHttpResponse(response);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout || 
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return http.Response(
          '{"error": "Request timeout"}',
          408,
          headers: {'content-type': 'application/json'},
        );
      }
      
      return http.Response(
        '{"error": "${e.message}"}',
        e.response?.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // 安全的POST请求 (Dio实现)
  static Future<http.Response> securePost(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    try {
      // 检查是否为HTTPS URL
      if (!url.startsWith('https://')) {
        throw Exception('非安全URL: 所有请求必须使用HTTPS');
      }
      
      final response = await _dio.post(
        url,
        data: body,
        options: Options(
          headers: headers,
        ),
      );
      
      return _convertDioResponseToHttpResponse(response);
    } on DioException catch (e) {
      return http.Response(
        '{"error": "${e.message}"}',
        e.response?.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
