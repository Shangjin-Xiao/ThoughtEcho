import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http_server/http_server.dart';

import 'constants.dart';
import 'models/file_dto.dart';
import 'models/info_register_dto.dart';
import 'models/prepare_upload_request_dto.dart';
import 'models/prepare_upload_response_dto.dart';
import 'models/session_status.dart';
import 'package:flutter/foundation.dart';


/// Simplified receive controller for ThoughtEcho
/// Based on LocalSend's receive_controller but with minimal dependencies
class ReceiveController {
  final Function(String filePath)? onFileReceived;
  final Map<String, ReceiveSession> _sessions = {};
  
  ReceiveController({this.onFileReceived});

  /// Handle info request - returns device information
  Map<String, dynamic> handleInfoRequest() {
    return {
      'alias': 'ThoughtEcho',
      'version': protocolVersion,
      'deviceModel': 'ThoughtEcho App',
      'deviceType': 'mobile',
      'fingerprint': _getStableFingerprint(),
      'download': true,
    };
  }

  /// 生成稳定的设备指纹
  String _getStableFingerprint() {
    // 使用稳定的设备标识符，而不是时间戳
    final hostname = Platform.localHostname;
    final os = Platform.operatingSystem;
    // 使用当前进程ID与主机名/系统组合，确保稳定
    final processId = pid;
    return 'thoughtecho-$hostname-$os-$processId';
  }

  /// Handle prepare upload request
  Map<String, dynamic> handlePrepareUpload(Map<String, dynamic> requestData) {
    try {
      final prepareRequest = PrepareUploadRequestDto.fromJson(requestData);
      
      // Create session
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      final session = ReceiveSession(
        sessionId: sessionId,
        senderInfo: prepareRequest.info,
        files: prepareRequest.files,
        status: SessionStatus.waiting,
      );
      
      _sessions[sessionId] = session;
      
      // Auto-accept all files for ThoughtEcho
      final fileTokens = <String, String>{};
      for (final fileId in prepareRequest.files.keys) {
        fileTokens[fileId] = 'token_$fileId';
      }
      
      // Update session status
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.sending,
        fileTokens: fileTokens,
      );
      
      // Create response
      final response = PrepareUploadResponseDto(
        sessionId: sessionId,
        files: fileTokens,
      );
      
      return response.toJson();
      
    } catch (e) {
      throw Exception('Invalid prepare upload request: $e');
    }
  }

  /// Handle file upload with enhanced error handling and streaming support
  Future<Map<String, dynamic>> handleFileUpload(
    String sessionId,
    String fileId,
    String token,
    HttpRequest request,
  ) async {
    File? tempFile;
    try {
      debugPrint('接收文件上传请求: sessionId=$sessionId, fileId=$fileId');
      final session = _sessions[sessionId];
      if (session == null) {
        debugPrint('找不到会话: $sessionId');
        throw Exception('Session not found');
      }

      // Validate token
      if (session.fileTokens?[fileId] != token) {
        debugPrint('令牌无效: 预期 ${session.fileTokens?[fileId]}, 实际 $token');
        throw Exception('Invalid token');
      }

      // Get file info
      final fileDto = session.files[fileId];
      if (fileDto == null) {
        debugPrint('找不到文件: $fileId');
        throw Exception('File not found');
      }

      // Create temporary file path
      final tempDir = Directory.systemTemp;
      final fileName = _sanitizeFileName(fileDto.fileName);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final targetPath = '${tempDir.path}/thoughtecho_${timestamp}_$fileName';

      // Parse body using http_server helper (handles multipart/raw)
      final body = await HttpBodyHandler.processRequest(request);
      if (body.type == 'multipart') {
        final parts = body.body as List;
        bool saved = false;
        for (final part in parts) {
          if (part is HttpBodyFileUpload) {
            // Prefer a part with a filename
            final filename = part.filename ?? fileName;
            final actualPath = '${tempDir.path}/thoughtecho_${timestamp}_${_sanitizeFileName(filename)}';
            tempFile = File(actualPath);

            final sink = tempFile.openWrite();
            final content = part.content;
            if (content is List<int>) {
              sink.add(content);
            } else if (content is String) {
              sink.add(utf8.encode(content));
            }
            await sink.flush();
            await sink.close();

            final finalSize = await tempFile.length();
            debugPrint('文件保存完成(MULTIPART): ${tempFile.path}, 大小: $finalSize 字节');
            saved = true;
            break;
          }
        }
        if (!saved) {
          throw Exception('No upload file found in multipart body');
        }
      } else {
        // Treat whole body as file content
        tempFile = File(targetPath);
        final sink = tempFile.openWrite();
        final content = body.body;
        if (content is List<int>) {
          sink.add(content);
        } else if (content is String) {
          sink.add(utf8.encode(content));
        } else {
          // Fallback: stream directly
          await for (final chunk in request) {
            sink.add(chunk);
          }
        }
        await sink.flush();
        await sink.close();
        final finalSize = await tempFile.length();
        debugPrint('文件保存完成(RAW): ${tempFile.path}, 大小: $finalSize 字节');
      }

      // Validate file size if provided
      if (tempFile != null) {
        final finalSize = await tempFile.length();
        if (fileDto.size != finalSize) {
          debugPrint('警告: 文件大小不匹配 - 预期: ${fileDto.size}, 实际: $finalSize');
        }
      }

      // Notify file received
      if (onFileReceived != null && tempFile != null) {
        debugPrint('通知上层服务接收到文件');
        onFileReceived!(tempFile.path);
      }

      debugPrint('文件上传处理完成: ${fileDto.fileName} -> ${tempFile?.path}');

      return {
        'message': 'File uploaded successfully',
        'fileId': fileId,
        'size': await tempFile!.length(),
      };
    } catch (e, stack) {
      debugPrint('文件上传处理失败: $e');
      debugPrint('堆栈: $stack');
      throw Exception('Upload failed: $e');
    }
  }

  /// Get session info
  ReceiveSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  /// Cancel session
  void cancelSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  /// Get all sessions
  Map<String, ReceiveSession> get sessions => Map.unmodifiable(_sessions);

  /// Sanitize file name to prevent path traversal and invalid characters
  String _sanitizeFileName(String fileName) {
    // Remove path separators and invalid characters
    String sanitized = fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll('..', '_')
        .trim();

    // Ensure filename is not empty and not too long
    if (sanitized.isEmpty) {
      sanitized = 'unknown_file';
    }
    if (sanitized.length > 255) {
      sanitized = sanitized.substring(0, 255);
    }

    return sanitized;
  }

  /// Dispose resources
  void dispose() {
    _sessions.clear();
  }
}

/// Simplified receive session model
class ReceiveSession {
  final String sessionId;
  final InfoRegisterDto senderInfo;
  final Map<String, FileDto> files;
  final SessionStatus status;
  final Map<String, String>? fileTokens;
  
  const ReceiveSession({
    required this.sessionId,
    required this.senderInfo,
    required this.files,
    required this.status,
    this.fileTokens,
  });
  
  ReceiveSession copyWith({
    String? sessionId,
    InfoRegisterDto? senderInfo,
    Map<String, FileDto>? files,
    SessionStatus? status,
    Map<String, String>? fileTokens,
  }) {
    return ReceiveSession(
      sessionId: sessionId ?? this.sessionId,
      senderInfo: senderInfo ?? this.senderInfo,
      files: files ?? this.files,
      status: status ?? this.status,
      fileTokens: fileTokens ?? this.fileTokens,
    );
  }
}
