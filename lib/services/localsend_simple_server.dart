import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 简化的HTTP服务器，用于接收文件
class SimpleServer {
  HttpServer? _server;
  final int _port = 53318; // ThoughtEcho端口（避免与LocalSend冲突）
  
  bool get isRunning => _server != null;
  int get port => _port;

  /// 启动服务器
  Future<void> start({
    required String alias,
    required Function(String filePath) onFileReceived,
  }) async {
    if (_server != null) return;

    // Check if we're running on web platform
    if (kIsWeb) {
      debugPrint('SimpleServer not supported on web platform');
      return;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      debugPrint('ThoughtEcho服务器启动在端口: $_port');

      await for (HttpRequest request in _server!) {
        await _handleRequest(request, alias, onFileReceived);
      }
    } catch (e) {
      debugPrint('服务器启动失败: $e');
      rethrow;
    }
  }

  /// 停止服务器
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    debugPrint('ThoughtEcho服务器已停止');
  }

  /// 处理HTTP请求
  Future<void> _handleRequest(
    HttpRequest request,
    String alias,
    Function(String filePath) onFileReceived,
  ) async {
    try {
      final uri = request.uri;
      
      if (uri.path == '/api/localsend/v2/info' && request.method == 'GET') {
        // 设备信息请求
        await _handleInfoRequest(request, alias);
      } else if (uri.path == '/api/localsend/v2/upload' && request.method == 'POST') {
        // 文件上传请求
        await _handleUploadRequest(request, onFileReceived);
      } else {
        // 未知请求
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (e) {
      debugPrint('请求处理失败: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  /// 处理设备信息请求
  Future<void> _handleInfoRequest(HttpRequest request, String alias) async {
    final deviceInfo = {
      'alias': alias,
      'version': '2.0',
      'deviceModel': 'ThoughtEcho',
      'deviceType': 'desktop',
      'fingerprint': 'thoughtecho-${DateTime.now().millisecondsSinceEpoch}',
      'port': _port,
      'protocol': 'http',
      'download': true,
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(deviceInfo));
    await request.response.close();
  }

  /// 处理文件上传请求
  Future<void> _handleUploadRequest(
    HttpRequest request,
    Function(String filePath) onFileReceived,
  ) async {
    try {
      // 获取文件名
      final fileName = request.uri.queryParameters['fileName'] ?? 'received_file';
      
      // 创建临时文件
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');
      
      // 写入文件内容
      final sink = file.openWrite();
      await sink.addStream(request);
      await sink.close();
      
      // 通知文件接收完成
      onFileReceived(file.path);
      
      // 响应成功
      request.response.statusCode = 200;
      await request.response.close();
      
      debugPrint('文件接收完成: ${file.path}');
    } catch (e) {
      debugPrint('文件接收失败: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }
}