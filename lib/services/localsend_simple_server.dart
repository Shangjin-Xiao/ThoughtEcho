import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';

final _logger = Logger('SimpleServer');

/// Simple HTTP server implementation for LocalSend integration
class SimpleServer {
  HttpServer? _server;
  bool _isRunning = false;
  int _port = 53317;

  bool get isRunning => _isRunning;
  int get port => _port;

  /// Start the server
  Future<void> start({int? customPort}) async {
    if (_isRunning) {
      _logger.warning('Server is already running');
      return;
    }

    _port = customPort ?? 53317;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isRunning = true;
      
      // Handle incoming requests
      await for (final request in _server!) {
        _handleRequest(request);
      }
      
    } catch (e) {
      _logger.severe('Failed to start server: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// Stop the server
  Future<void> stop() async {
    if (!_isRunning || _server == null) {
      return;
    }

    try {
      await _server!.close();
      _isRunning = false;
      _server = null;
      _logger.info('Server stopped');
    } catch (e) {
      _logger.severe('Failed to stop server: $e');
    }
  }

  /// Handle incoming HTTP requests
  void _handleRequest(HttpRequest request) {
    try {
      if (request.uri.path == '/api/v1/info') {
        _handleInfoRequest(request);
      } else {
        _handle404(request);
      }
    } catch (e) {
      _logger.severe('Error handling request: $e');
      _handle500(request, e.toString());
    }
  }

  /// Handle info requests
  void _handleInfoRequest(HttpRequest request) {
    final response = {
      'alias': 'ThoughtEcho',
      'version': '2.0',
      'deviceModel': 'ThoughtEcho',
      'deviceType': 'mobile',
      'fingerprint': 'thoughtecho-device',
      'download': false,
    };

    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(response));
    request.response.close();
  }

  /// Handle 404 errors
  void _handle404(HttpRequest request) {
    request.response
      ..statusCode = 404
      ..write('Not Found');
    request.response.close();
  }

  /// Handle 500 errors
  void _handle500(HttpRequest request, String error) {
    request.response
      ..statusCode = 500
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': error}));
    request.response.close();
  }
}