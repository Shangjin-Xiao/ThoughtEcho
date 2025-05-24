import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dio_network_utils.dart';
import 'http_response.dart';

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
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 15);
    dio.options.sendTimeout = const Duration(seconds: 15);
    
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
  }  // 兼容旧的http.Response格式
  static HttpResponse _convertDioResponseToHttpResponse(Response dioResponse) {
    Map<String, String> convertedHeaders = {};
    dioResponse.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        convertedHeaders[name] = values.join(", ");
      }
    });
    
    String responseBody;
    // 特殊处理一言API的响应
    if (dioResponse.requestOptions.uri.toString().contains('hitokoto.cn')) {
      if (dioResponse.data is Map<String, dynamic>) {
        // 如果Dio已经解析为Map，转换为JSON字符串
        responseBody = json.encode(dioResponse.data);
      } else if (dioResponse.data is String) {
        responseBody = dioResponse.data;
      } else {
        responseBody = dioResponse.data.toString();
      }
    } else {
      responseBody = dioResponse.data is String ? dioResponse.data : dioResponse.data.toString();
    }
    
    return HttpResponse(
      responseBody,
      dioResponse.statusCode ?? 0,
      headers: convertedHeaders,
    );
  }

  // 安全的GET请求 (Dio实现)
  static Future<HttpResponse> secureGet(
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
          // 对一言API使用JSON响应类型，让Dio自动解析
          responseType: url.contains('hitokoto.cn') ? ResponseType.json : ResponseType.plain,
        ),
      );
      
      return _convertDioResponseToHttpResponse(response);    } on DioException catch (e) {
      debugPrint('HTTP请求异常: ${e.type}, 消息: ${e.message}');
      
      if (e.type == DioExceptionType.connectionTimeout || 
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return HttpResponse(
          '{"error": "Request timeout"}',
          408,
          headers: {'content-type': 'application/json'},
        );
      }
      
      // 对于一言API的错误，尝试获取实际的错误响应体
      String errorBody = '{"error": "Unknown error"}';
      int statusCode = e.response?.statusCode ?? 500;
      
      try {
        if (e.response?.data != null) {
          if (e.response!.data is String) {
            errorBody = e.response!.data;
          } else {
            errorBody = e.response!.data.toString();
          }
        }
      } catch (readError) {
        debugPrint('读取错误响应体失败: $readError');
        errorBody = '{"error": "${e.message ?? "Unknown error"}"}';
      }
      
      return HttpResponse(
        errorBody,
        statusCode,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // 安全的POST请求 (Dio实现)
  static Future<HttpResponse> securePost(
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
      return HttpResponse(
        '{"error": "${e.message}"}',
        e.response?.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
