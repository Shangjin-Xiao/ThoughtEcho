import 'dart:async';
import 'dart:io';

import 'constants.dart';
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
      'fingerprint': 'thoughtecho-${DateTime.now().millisecondsSinceEpoch}',
      'download': true,
    };
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

  /// Handle file upload
  Future<Map<String, dynamic>> handleFileUpload(
    String sessionId,
    String fileId,
    String token,
    HttpRequest request,
  ) async {
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
      
      // Save file to temporary location
      final tempDir = Directory.systemTemp;
      final fileName = fileDto.fileName ?? 'unknown_file';
      final filePath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final file = File(filePath);
      
      debugPrint('开始保存文件到: $filePath');
      
      // Write file data - 修正为使用fold来收集请求数据
      final bytes = await request.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      await file.writeAsBytes(bytes);
      
      debugPrint('文件保存完成: $filePath, 大小: ${await file.length()} 字节');
      
      // Notify file received
      if (onFileReceived != null) {
        debugPrint('通知上层服务接收到文件');
        onFileReceived!(filePath);
      }
      
      debugPrint('文件上传处理完成: ${fileDto.fileName} -> $filePath');
      
      return {'message': 'File uploaded successfully'};
      
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

  /// Dispose resources
  void dispose() {
    _sessions.clear();
  }
}

/// Simplified receive session model
class ReceiveSession {
  final String sessionId;
  final InfoRegisterDto senderInfo;
  final Map<String, dynamic> files;
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
    Map<String, dynamic>? files,
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
