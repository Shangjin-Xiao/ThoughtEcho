import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// LocalSend协议的文件接收服务器
/// 专门用于接收来自其他设备的文件
class LocalSendFileReceiver {
  HttpServer? _server;
  int _port = 53319; // 使用不同的端口避免与LocalSendServer冲突
  
  bool get isRunning => _server != null;
  int get port => _port;

  /// 启动文件接收服务器
  Future<void> start({
    required String alias,
    required Function(String filePath) onFileReceived,
  }) async {
    if (_server != null) return;

    // Check if we're running on web platform
    if (kIsWeb) {
      debugPrint('LocalSendFileReceiver not supported on web platform');
      return;
    }

    try {
      // 尝试绑定到指定端口，如果失败则尝试其他端口
      _server = await _bindToAvailablePort();
      debugPrint('LocalSendFileReceiver启动在端口: $_port');

      await for (HttpRequest request in _server!) {
        await _handleRequest(request, alias, onFileReceived);
      }
    } catch (e) {
      debugPrint('LocalSendFileReceiver启动失败: $e');
      rethrow;
    }
  }

  /// 尝试绑定到可用端口
  Future<HttpServer> _bindToAvailablePort() async {
    final portsToTry = [53319, 53320, 53321, 0]; // 包含随机端口作为备选
    
    for (final port in portsToTry) {
      try {
        final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _port = server.port; // 更新实际端口
        debugPrint('LocalSendFileReceiver成功绑定到端口: $_port');
        return server;
      } catch (e) {
        debugPrint('端口 $port 绑定失败: $e');
        if (port == portsToTry.last) {
          rethrow; // 所有端口都失败了
        }
      }
    }
    
    throw Exception('无法绑定到任何可用端口');
  }

  /// 停止文件接收服务器
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    debugPrint('LocalSendFileReceiver已停止');
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
