import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http_server/http_server.dart';
import '../device_identity_manager.dart';
import 'package:uuid/uuid.dart';

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
  final Duration sessionTimeout = const Duration(minutes: 2);
  Timer? _gcTimer;
  
  ReceiveController({this.onFileReceived});

  void _startGcTimer() {
    _gcTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      final toRemove = <String>[];
      _sessions.forEach((id, s) {
        if (now.difference(s.lastActivity).compareTo(sessionTimeout) > 0) {
          toRemove.add(id);
        }
      });
      for (final id in toRemove) {
        _sessions.remove(id);
      }
    });
  }

  /// Handle info request - returns device information
  Map<String, dynamic> handleInfoRequest() {
    // 异步预热指纹（不阻塞）
    DeviceIdentityManager.I.getFingerprint();
    return {
      'alias': 'ThoughtEcho',
      'version': protocolVersion,
      'deviceModel': 'ThoughtEcho App',
      'deviceType': 'mobile',
      // 指纹异步载入期间可能为空，用占位符避免空字符串
      'fingerprint': _cachedFingerprint ?? 'loading',
      'download': true,
    };
  }

  String? _cachedFingerprint;
  Future<void> _ensureFingerprint() async {
    _cachedFingerprint ??= await DeviceIdentityManager.I.getFingerprint();
  }

  /// Handle prepare upload request
  Map<String, dynamic> handlePrepareUpload(Map<String, dynamic> requestData) {
    try {
      // 确保指纹已就绪
      _ensureFingerprint();
      final prepareRequest = PrepareUploadRequestDto.fromJson(requestData);
      
      // Create session
      final sessionId = const Uuid().v4();
      final session = ReceiveSession(
        sessionId: sessionId,
        senderInfo: prepareRequest.info,
        files: prepareRequest.files,
        status: SessionStatus.waiting,
        lastActivity: DateTime.now(),
      );
      
      _sessions[sessionId] = session;
      
      // Auto-accept all files for ThoughtEcho
      final fileTokens = <String, String>{};
      final uuid = const Uuid();
      for (final fileId in prepareRequest.files.keys) {
        fileTokens[fileId] = uuid.v4();
      }
      
      // Update session status
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.sending,
        fileTokens: fileTokens,
        lastActivity: DateTime.now(),
      );
      _startGcTimer();
      
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

      // 基础校验：仅要求大于0
      if (fileDto.size <= 0) {
        throw Exception('Invalid file size');
      }
      final lowerName = fileDto.fileName.toLowerCase();
      const blockedExtensions = ['.exe', '.bat', '.sh', '.cmd'];
      if (blockedExtensions.any((b) => lowerName.endsWith(b))) {
        throw Exception('Blocked file type');
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
            final filename = part.filename;
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
        // 简单延迟清理：由上层复制/处理后 30 秒删除
        final pathToDelete = tempFile.path;
        Future.delayed(const Duration(seconds: 30), () async {
          try {
            final f = File(pathToDelete);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (_) {}
        });
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
  _gcTimer?.cancel();
  }
}

/// Simplified receive session model
class ReceiveSession {
  final String sessionId;
  final InfoRegisterDto senderInfo;
  final Map<String, FileDto> files;
  final SessionStatus status;
  final Map<String, String>? fileTokens;
  final DateTime lastActivity;
  
  const ReceiveSession({
    required this.sessionId,
    required this.senderInfo,
    required this.files,
    required this.status,
    this.fileTokens,
  required this.lastActivity,
  });
  
  ReceiveSession copyWith({
    String? sessionId,
    InfoRegisterDto? senderInfo,
    Map<String, FileDto>? files,
    SessionStatus? status,
    Map<String, String>? fileTokens,
    DateTime? lastActivity,
  }) {
    return ReceiveSession(
      sessionId: sessionId ?? this.sessionId,
      senderInfo: senderInfo ?? this.senderInfo,
      files: files ?? this.files,
      status: status ?? this.status,
      fileTokens: fileTokens ?? this.fileTokens,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}
