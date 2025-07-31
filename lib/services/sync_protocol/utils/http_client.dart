import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// HTTP响应包装器
class HttpResponseWrapper {
  final int statusCode;
  final Map<String, dynamic>? jsonBody;
  final String? textBody;
  final Map<String, String> headers;

  HttpResponseWrapper({
    required this.statusCode,
    this.jsonBody,
    this.textBody,
    this.headers = const {},
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// 同步协议专用HTTP客户端
class SyncHttpClient {
  final HttpClient _httpClient = HttpClient();
  final Duration _timeout = const Duration(seconds: 30);

  /// 发送POST请求
  Future<HttpResponseWrapper> post(
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.parse(url);
      final request = await _httpClient.postUrl(uri);
      
      // 设置超时
      request.persistentConnection = false;
      
      // 设置请求头
      request.headers.contentType = ContentType.json;
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      // 写入请求体
      if (body != null) {
        final jsonString = jsonEncode(body);
        request.write(jsonString);
      }

      // 发送请求并获取响应
      final response = await request.close().timeout(_timeout);
      final responseBody = await response.transform(utf8.decoder).join();
      
      // 解析响应
      Map<String, dynamic>? jsonResponse;
      try {
        jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (e) {
        // 如果不是JSON格式，保留原始文本
        debugPrint('响应不是JSON格式: $e');
      }

      return HttpResponseWrapper(
        statusCode: response.statusCode,
        jsonBody: jsonResponse,
        textBody: jsonResponse == null ? responseBody : null,
        headers: _extractHeaders(response.headers),
      );

    } catch (e) {
      debugPrint('HTTP POST请求失败: $e');
      return HttpResponseWrapper(
        statusCode: 500,
        textBody: 'Request failed: $e',
      );
    }
  }

  /// 上传文件
  Future<HttpResponseWrapper> uploadFile(
    String url,
    File file, {
    String fileFieldName = 'file',
    Map<String, String>? fields,
  }) async {
    try {
      final uri = Uri.parse(url);
      final request = await _httpClient.postUrl(uri);
      request.persistentConnection = false;

      // 生成边界字符串
      final boundary = 'dart-boundary-${DateTime.now().millisecondsSinceEpoch}';
      request.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});

      // 构建multipart数据
      final multipartData = <List<int>>[];

      // 添加表单字段
      if (fields != null) {
        for (final entry in fields.entries) {
          multipartData.add(utf8.encode('--$boundary\r\n'));
          multipartData.add(utf8.encode('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'));
          multipartData.add(utf8.encode('${entry.value}\r\n'));
        }
      }

      // 添加文件
      multipartData.add(utf8.encode('--$boundary\r\n'));
      multipartData.add(utf8.encode('Content-Disposition: form-data; name="$fileFieldName"; filename="${file.path.split('/').last}"\r\n'));
      multipartData.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
      
      // 读取文件内容
      final fileBytes = await file.readAsBytes();
      multipartData.add(fileBytes);
      
      multipartData.add(utf8.encode('\r\n--$boundary--\r\n'));

      // 写入所有数据
      for (final data in multipartData) {
        request.add(data);
      }

      // 发送请求
      final response = await request.close().timeout(_timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      // 解析响应
      Map<String, dynamic>? jsonResponse;
      try {
        jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('文件上传响应不是JSON格式: $e');
      }

      return HttpResponseWrapper(
        statusCode: response.statusCode,
        jsonBody: jsonResponse,
        textBody: jsonResponse == null ? responseBody : null,
        headers: _extractHeaders(response.headers),
      );

    } catch (e) {
      debugPrint('文件上传失败: $e');
      return HttpResponseWrapper(
        statusCode: 500,
        textBody: 'File upload failed: $e',
      );
    }
  }

  /// 发送GET请求
  Future<HttpResponseWrapper> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.parse(url);
      final request = await _httpClient.getUrl(uri);
      request.persistentConnection = false;

      // 设置请求头
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      // 发送请求
      final response = await request.close().timeout(_timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      // 解析响应
      Map<String, dynamic>? jsonResponse;
      try {
        jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('GET响应不是JSON格式: $e');
      }

      return HttpResponseWrapper(
        statusCode: response.statusCode,
        jsonBody: jsonResponse,
        textBody: jsonResponse == null ? responseBody : null,
        headers: _extractHeaders(response.headers),
      );

    } catch (e) {
      debugPrint('HTTP GET请求失败: $e');
      return HttpResponseWrapper(
        statusCode: 500,
        textBody: 'Request failed: $e',
      );
    }
  }

  /// 提取响应头
  Map<String, String> _extractHeaders(HttpHeaders httpHeaders) {
    final headers = <String, String>{};
    httpHeaders.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return headers;
  }

  /// 释放资源
  void dispose() {
    _httpClient.close();
  }
}
