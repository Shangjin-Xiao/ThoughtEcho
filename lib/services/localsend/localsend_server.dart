import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'constants.dart';
import 'receive_controller.dart';
import 'package:flutter/foundation.dart';

/// Simple HTTP server for LocalSend protocol
/// Based on LocalSend's server but simplified for ThoughtEcho
class LocalSendServer {
  HttpServer? _server;
  late ReceiveController _receiveController;
  bool _isRunning = false;
  int _port = defaultPort;
  
  bool get isRunning => _isRunning;
  int get port => _port;
  
  /// Start the HTTP server
  Future<void> start({
    int? port,
    Function(String filePath)? onFileReceived,
  }) async {
    if (_isRunning) return;

    // Check if we're running on web platform
    if (kIsWeb) {
      debugPrint('LocalSend server not supported on web platform');
      _isRunning = false;
      return;
    }

    _port = port ?? defaultPort;
    _receiveController = ReceiveController(onFileReceived: onFileReceived);

    try {
      debugPrint('尝试在端口 $_port 上启动LocalSend服务器...');
      
      // Try to bind to the specified port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);

      // Set up request handling
      _server!.listen(_handleRequest);

      _isRunning = true;
      debugPrint('LocalSend server started on port $_port');

    } catch (e) {
      debugPrint('Failed to start server on port $_port: $e');

      // Try alternative ports
      debugPrint('尝试在替代端口上启动服务器...');
      for (int altPort = _port + 1; altPort <= _port + 100; altPort++) {
        try {
          debugPrint('尝试端口 $altPort...');
          _server = await HttpServer.bind(InternetAddress.anyIPv4, altPort);
          _server!.listen(_handleRequest);
          _port = altPort;
          _isRunning = true;
          debugPrint('LocalSend server started on alternative port $altPort');
          break;
        } catch (e) {
          // Continue trying
          debugPrint('端口 $altPort 失败: $e');
        }
      }

      if (!_isRunning) {
        debugPrint('无法在任何端口上启动服务器');
        throw Exception('Failed to start server on any port');
      }
    }
  }
  
  /// Stop the HTTP server
  Future<void> stop() async {
    if (!_isRunning) return;
    
    try {
      await _server?.close();
      _server = null;
      _receiveController.dispose();
      _isRunning = false;
      debugPrint('LocalSend server stopped');
    } catch (e) {
      debugPrint('Error stopping server: $e');
    }
  }
  
  /// Handle incoming HTTP requests
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      debugPrint('收到请求: ${request.method} ${request.uri.path}');
      
      // Add CORS headers
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      
      // Handle preflight requests
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 200;
        await request.response.close();
        debugPrint('处理OPTIONS请求');
        return;
      }
      
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      
      // Route requests
      Map<String, dynamic> responseData;
      int statusCode = 200;
      
      try {
        debugPrint('处理路径: $path, 查询参数: $query');
        
        if (path == '/api/localsend/v2/info' && request.method == 'GET') {
          responseData = _receiveController.handleInfoRequest();
          debugPrint('处理INFO请求: ${jsonEncode(responseData)}');
          
        } else if (path == '/api/localsend/v2/prepare-upload' && request.method == 'POST') {
          debugPrint('处理prepare-upload请求');
          final bodyBytes = await request.fold<List<int>>(
            <int>[],
            (previous, element) => previous..addAll(element),
          );
          final bodyString = utf8.decode(bodyBytes);
          debugPrint('请求体: $bodyString');
          
          final requestData = jsonDecode(bodyString) as Map<String, dynamic>;
          responseData = _receiveController.handlePrepareUpload(requestData);
          debugPrint('响应: ${jsonEncode(responseData)}');
          
        } else if (path == '/api/localsend/v2/upload' && request.method == 'POST') {
          debugPrint('处理上传请求');
          final sessionId = query['sessionId'];
          final fileId = query['fileId'];
          final token = query['token'];
          
          if (sessionId == null || fileId == null || token == null) {
            debugPrint('缺少必要参数: sessionId=$sessionId, fileId=$fileId, token=$token');
            statusCode = 400;
            responseData = {'error': 'Missing required parameters'};
          } else {
            responseData = await _receiveController.handleFileUpload(
              sessionId,
              fileId,
              token,
              request,
            );
          }
          
        } else {
          // 404 Not Found
          statusCode = 404;
          responseData = {'error': 'Not found', 'path': path};
          debugPrint('未知路径: $path');
        }
      } catch (e, stack) {
        debugPrint('处理请求时出错: $e');
        debugPrint('堆栈: $stack');
        statusCode = 500;
        responseData = {'error': e.toString()};
      }
      
      // Send response
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseData));
      await request.response.close();
      debugPrint('响应已发送: 状态码=$statusCode');
      
    } catch (e, stackTrace) {
      debugPrint('处理请求时出现严重错误: $e');
      debugPrint('堆栈: $stackTrace');
      
      try {
        request.response.statusCode = 500;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Internal server error: $e'}));
        await request.response.close();
      } catch (e) {
        // Ignore errors when trying to send error response
        debugPrint('发送错误响应时失败: $e');
      }
    }
  }
  
  /// Get server info
  Map<String, dynamic> getServerInfo() {
    return {
      'isRunning': _isRunning,
      'port': _port,
      'sessions': _receiveController.sessions.length,
    };
  }
  
  /// Get receive controller
  ReceiveController get receiveController => _receiveController;
}
