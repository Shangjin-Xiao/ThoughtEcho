import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'constants.dart';
import 'receive_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/utils/app_logger.dart';

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
    // ensure fingerprint ready before advertising info endpoint
    await _receiveController.initializeFingerprint();

    try {
      logInfo('server_start_attempt port=$_port', source: 'LocalSend');

      // Try to bind to the specified port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server!.autoCompress = true;

      // Set up request handling
      _server!.listen(_handleRequest);

      _isRunning = true;
      logInfo('server_started port=$_port', source: 'LocalSend');
    } catch (e) {
      logWarning('server_start_fail port=$_port error=$e', source: 'LocalSend');

      // Try alternative ports with better range and logging
      logInfo('server_alt_ports', source: 'LocalSend');
      final alternativePorts = [
        _port + 1, _port + 2, _port + 3, // Try nearby ports first
        _port - 1, _port - 2, _port - 3, // Try lower ports
        0, // Let system choose
      ];

      for (int altPort in alternativePorts) {
        try {
          logDebug('server_try_port port=$altPort', source: 'LocalSend');
          _server = await HttpServer.bind(InternetAddress.anyIPv4, altPort);
          _server!.autoCompress = true;
          _server!.listen(_handleRequest);
          _port = altPort == 0 ? _server!.port : altPort;
          _isRunning = true;
          logInfo('server_started_alt port=$_port', source: 'LocalSend');
          break;
        } catch (e) {
          // Continue trying
          logWarning('server_try_fail port=$altPort error=$e',
              source: 'LocalSend');
        }
      }

      if (!_isRunning) {
        logError('server_all_ports_failed', source: 'LocalSend');
        throw Exception('Failed to start server on any port');
      }
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    if (!_isRunning) return;

    try {
      await _server?.close(force: true);
      _server = null;
      _receiveController.dispose();
      _isRunning = false;
      logInfo('server_stopped', source: 'LocalSend');
    } catch (e) {
      logWarning('server_stop_error error=$e', source: 'LocalSend');
    }
  }

  /// Handle incoming HTTP requests
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      logDebug('req method=${request.method} path=${request.uri.path}',
          source: 'LocalSend');

      // Add CORS headers
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add(
          'Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      request.response.headers
          .add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      request.response.headers.add('Connection', 'keep-alive');

      // Handle preflight requests
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 200;
        await request.response.close();
        logDebug('req_options', source: 'LocalSend');
        return;
      }

      final path = request.uri.path;
      final query = request.uri.queryParameters;

      // Route requests
      Map<String, dynamic> responseData;
      int statusCode = 200;

      try {
        logDebug('route path=$path query=${query.isNotEmpty}',
            source: 'LocalSend');

        if ((path == '/api/localsend/v2/info' ||
                path == '/api/localsend/v1/info') &&
            request.method == 'GET') {
          responseData = _receiveController.handleInfoRequest();
          logDebug('info_ok', source: 'LocalSend');
        } else if ((path == '/api/localsend/v2/prepare-upload' ||
                path == '/api/localsend/v1/send-request') &&
            request.method == 'POST') {
          logDebug('prepare_start', source: 'LocalSend');
          final bodyBytes = await request.fold<List<int>>(
            <int>[],
            (previous, element) => previous..addAll(element),
          );
          final bodyString = utf8.decode(bodyBytes);
          logDebug('prepare_body_len=${bodyString.length}',
              source: 'LocalSend');

          final requestData = jsonDecode(bodyString) as Map<String, dynamic>;
          responseData = _receiveController.handlePrepareUpload(requestData);
          logDebug('prepare_ok', source: 'LocalSend');
        } else if ((path == '/api/localsend/v2/upload' ||
                path == '/api/localsend/v1/send') &&
            request.method == 'POST') {
          logDebug('upload_route', source: 'LocalSend');
          final sessionId = query['sessionId'];
          final fileId = query['fileId'];
          final token = query['token'];

          if (sessionId == null || fileId == null || token == null) {
            logWarning(
                'upload_missing_params sessionId=$sessionId fileId=$fileId token=$token',
                source: 'LocalSend');
            statusCode = 400;
            responseData = {'error': 'Missing required parameters'};
          } else {
            try {
              responseData = await _receiveController.handleFileUpload(
                sessionId,
                fileId,
                token,
                request,
              );
              logInfo('upload_ok sessionId=$sessionId fileId=$fileId',
                  source: 'LocalSend');
            } catch (e) {
              logError(
                  'upload_fail sessionId=$sessionId fileId=$fileId error=$e',
                  source: 'LocalSend');
              statusCode = 500;
              responseData = {'error': 'File upload failed: $e'};
            }
          }
        } else {
          // 404 Not Found
          statusCode = 404;
          responseData = {'error': 'Not found', 'path': path};
          logWarning('route_404 path=$path', source: 'LocalSend');
        }
      } catch (e, stack) {
        logError('handle_error error=$e',
            error: e, stackTrace: stack, source: 'LocalSend');
        statusCode = 500;
        responseData = {'error': e.toString()};
      }

      // Send response
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      final body = jsonEncode(responseData);
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, utf8.encode(body).length);
      request.response.write(body);
      await request.response.close();
      logDebug('resp_sent status=$statusCode', source: 'LocalSend');
    } catch (e, stackTrace) {
      logError('fatal_req error=$e',
          error: e, stackTrace: stackTrace, source: 'LocalSend');

      try {
        request.response.statusCode = 500;
        request.response.headers.contentType = ContentType.json;
        const fallback = '{"error":"Internal server error"}';
        request.response.headers
            .set(HttpHeaders.contentLengthHeader, fallback.length);
        request.response.write(fallback);
        await request.response.close();
      } catch (e) {
        // Ignore errors when trying to send error response
        logWarning('fatal_resp_send_fail error=$e', source: 'LocalSend');
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
