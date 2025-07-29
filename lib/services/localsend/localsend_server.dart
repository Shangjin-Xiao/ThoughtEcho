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
      // Try to bind to the specified port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);

      // Set up request handling
      _server!.listen(_handleRequest);

      _isRunning = true;
      debugPrint('LocalSend server started on port $_port');

    } catch (e) {
      debugPrint('Failed to start server on port $_port: $e');

      // Try alternative ports
      for (int altPort = _port + 1; altPort <= _port + 100; altPort++) {
        try {
          _server = await HttpServer.bind(InternetAddress.anyIPv4, altPort);
          _server!.listen(_handleRequest);
          _port = altPort;
          _isRunning = true;
          debugPrint('LocalSend server started on alternative port $altPort');
          break;
        } catch (e) {
          // Continue trying
        }
      }

      if (!_isRunning) {
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
      // Add CORS headers
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      
      // Handle preflight requests
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 200;
        await request.response.close();
        return;
      }
      
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      
      debugPrint('${request.method} $path');
      
      // Route requests
      Map<String, dynamic> responseData;
      int statusCode = 200;
      
      try {
        if (path == '/api/localsend/v2/info' && request.method == 'GET') {
          responseData = _receiveController.handleInfoRequest();
          
        } else if (path == '/api/localsend/v2/prepare-upload' && request.method == 'POST') {
          final bodyBytes = await request.fold<List<int>>(
            <int>[],
            (previous, element) => previous..addAll(element),
          );
          final bodyString = utf8.decode(bodyBytes);
          final requestData = jsonDecode(bodyString) as Map<String, dynamic>;
          responseData = _receiveController.handlePrepareUpload(requestData);
          
        } else if (path == '/api/localsend/v2/upload' && request.method == 'POST') {
          final sessionId = query['sessionId'];
          final fileId = query['fileId'];
          final token = query['token'];
          
          if (sessionId == null || fileId == null || token == null) {
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
          responseData = {'error': 'Not found'};
        }
      } catch (e) {
        statusCode = 500;
        responseData = {'error': e.toString()};
      }
      
      // Send response
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseData));
      await request.response.close();
      
    } catch (e, stackTrace) {
      debugPrint('Error handling request: $e');
      debugPrint('Stack trace: $stackTrace');
      
      try {
        request.response.statusCode = 500;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Internal server error'}));
        await request.response.close();
      } catch (e) {
        // Ignore errors when trying to send error response
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
