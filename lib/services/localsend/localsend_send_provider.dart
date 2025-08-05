import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'api_route_builder.dart';
import 'models/device.dart';
import 'models/file_dto.dart';
import 'models/file_type.dart';
import 'models/info_register_dto.dart';
import 'models/multicast_dto.dart';
import 'models/prepare_upload_request_dto.dart';
import 'models/prepare_upload_response_dto.dart';
import 'models/session_status.dart';
import 'constants.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

const _uuid = Uuid();

/// Simplified send provider for ThoughtEcho
/// Based on LocalSend's send_provider but with minimal dependencies
class LocalSendProvider {
  final Map<String, SendSession> _sessions = {};
  
  /// Start a file transfer session
  Future<String> startSession({
    required Device target,
    required List<File> files,
    bool background = true,
  }) async {
    final sessionId = _uuid.v4();
    
    // Create session
    final session = SendSession(
      sessionId: sessionId,
      target: target,
      files: files,
      status: SessionStatus.waiting,
    );
    
    _sessions[sessionId] = session;
    
    try {
      // Prepare upload request
      final requestDto = PrepareUploadRequestDto(
        info: InfoRegisterDto(
          alias: 'ThoughtEcho',
          version: protocolVersion,
          deviceModel: 'ThoughtEcho App',
          deviceType: DeviceType.mobile,
          fingerprint: 'thoughtecho-${DateTime.now().millisecondsSinceEpoch}',
          port: defaultPort,
          protocol: ProtocolType.http,
          download: true,
        ),
        files: {
          for (int i = 0; i < files.length; i++)
            'file_$i': FileDto(
              id: 'file_$i',
              fileName: files[i].path.split('/').last,
              size: await files[i].length(),
              fileType: FileType.other,
              hash: null,
              preview: null,
              legacy: target.version == '1.0',
              metadata: null,
            ),
        },
      );
      
      // Send prepare upload request with timeout and retry
      final url = ApiRoute.prepareUpload.target(target);
      debugPrint('发送prepare-upload请求到: $url (设备端口: ${target.port})');

      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'ThoughtEcho/1.0',
          },
          body: jsonEncode(requestDto.toJson()),
        ).timeout(const Duration(seconds: 30));

        debugPrint('prepare-upload响应状态: ${response.statusCode}');
        debugPrint('响应内容: ${response.body.substring(0, response.body.length.clamp(0, 200))}...');

        if (response.statusCode == 200) {
          final responseDto = PrepareUploadResponseDto.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>
          );

          // Update session with response
          _sessions[sessionId] = session.copyWith(
            status: SessionStatus.sending,
            remoteSessionId: responseDto.sessionId,
            fileTokens: responseDto.files,
          );

          // Start file uploads
          await _uploadFiles(sessionId);

          return sessionId;
        } else {
          throw Exception('Failed to prepare upload: ${response.statusCode} - ${response.body}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finishedWithErrors,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }
  
  /// Upload files for a session with enhanced error handling and progress tracking
  Future<void> _uploadFiles(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    try {
      for (int i = 0; i < session.files.length; i++) {
        final file = session.files[i];
        final fileId = 'file_$i';
        final token = session.fileTokens?[fileId];

        if (token == null) {
          debugPrint('跳过文件 $fileId: 没有令牌');
          continue;
        }

        // Verify file exists and is readable
        if (!await file.exists()) {
          throw Exception('File not found: ${file.path}');
        }

        final fileSize = await file.length();
        debugPrint('准备上传文件: ${file.path} (大小: $fileSize 字节)');

        // Upload file with retry mechanism
        await _uploadSingleFile(session, fileId, token, file, fileSize);
      }

      // Mark as completed
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finished,
      );
      debugPrint('所有文件上传完成: $sessionId');

    } catch (e) {
      debugPrint('文件上传失败: $e');
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finishedWithErrors,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Upload a single file with retry mechanism
  Future<void> _uploadSingleFile(
    SendSession session,
    String fileId,
    String token,
    File file,
    int fileSize,
  ) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        // 构建带查询参数的URL
        final url = ApiRoute.upload.target(session.target, query: {
          'sessionId': session.remoteSessionId!,
          'fileId': fileId,
          'token': token,
        });
        debugPrint('上传文件到: $url (文件: ${file.path}, 尝试: ${attempt + 1}/$maxRetries)');

        final request = http.MultipartRequest('POST', Uri.parse(url));

        // Add headers
        request.headers['User-Agent'] = 'ThoughtEcho/1.0';

        // Add file
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        // Send request with timeout
        final response = await request.send().timeout(const Duration(minutes: 5));

        debugPrint('文件上传响应状态: ${response.statusCode}');

        if (response.statusCode == 200) {
          debugPrint('文件上传成功: ${file.path}');
          return; // Success, exit retry loop
        } else {
          final responseBody = await response.stream.bytesToString();
          throw Exception('Upload failed with status ${response.statusCode}: $responseBody');
        }
      } catch (e) {
        attempt++;
        debugPrint('文件上传尝试 $attempt 失败: $e');

        if (attempt >= maxRetries) {
          throw Exception('Failed to upload file after $maxRetries attempts: $e');
        }

        // Wait before retry
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }
  
  /// Get session status
  SendSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }
  
  /// Cancel a session
  void cancelSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session != null) {
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.canceledBySender,
      );
    }
  }
  
  /// Close a session
  void closeSession(String sessionId) {
    _sessions.remove(sessionId);
  }
  
  /// Get all active sessions
  Map<String, SendSession> get sessions => Map.unmodifiable(_sessions);
  
  void dispose() {
    _sessions.clear();
  }
}

/// Simplified send session model
class SendSession {
  final String sessionId;
  final String? remoteSessionId;
  final Device target;
  final List<File> files;
  final SessionStatus status;
  final Map<String, String>? fileTokens;
  final String? errorMessage;
  
  const SendSession({
    required this.sessionId,
    this.remoteSessionId,
    required this.target,
    required this.files,
    required this.status,
    this.fileTokens,
    this.errorMessage,
  });
  
  SendSession copyWith({
    String? sessionId,
    String? remoteSessionId,
    Device? target,
    List<File>? files,
    SessionStatus? status,
    Map<String, String>? fileTokens,
    String? errorMessage,
  }) {
    return SendSession(
      sessionId: sessionId ?? this.sessionId,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      target: target ?? this.target,
      files: files ?? this.files,
      status: status ?? this.status,
      fileTokens: fileTokens ?? this.fileTokens,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
