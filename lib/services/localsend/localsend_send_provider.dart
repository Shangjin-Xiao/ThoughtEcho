import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common/api_route_builder.dart';
import 'package:common/model/device.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/file_type.dart';
import 'package:common/model/dto/info_register_dto.dart';
import 'package:common/model/dto/multicast_dto.dart';
import 'package:common/model/dto/prepare_upload_request_dto.dart';
import 'package:common/model/dto/prepare_upload_response_dto.dart';
import 'package:common/model/session_status.dart';
import 'constants.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

const _uuid = Uuid();

/// Simplified send provider for ThoughtEcho LocalSend integration
/// Based on LocalSend's send_provider but with minimal dependencies
class LocalSendProvider {
  static const String _logTag = "LocalSendProvider";
  
  final Map<String, SendSession> _sessions = {};
  
  /// Start a file transfer session
  Future<String> startSession({
    required Device target,
    required List<File> files,
    bool background = true,
  }) async {
    // Validate inputs
    if (files.isEmpty) {
      throw ArgumentError("Files list cannot be empty");
    }
    
    // Validate target device
    if (target.ip?.isEmpty ?? true) {
      throw ArgumentError("Target device must have a valid IP address");
    }
    
    final sessionId = _uuid.v4();
    
    // Create session
    final session = SendSession(
      sessionId: sessionId,
      remoteSessionId: '',
      target: target,
      files: files,
      status: SessionStatus.waiting,
      progress: 0.0,
    );
    
    _sessions[sessionId] = session;
    
    try {
      // Prepare upload request
      final requestDto = PrepareUploadRequestDto(
        info: InfoRegisterDto(
          alias: 'ThoughtEcho',
          version: protocolVersion,
          deviceModel: 'Mobile',
          deviceType: DeviceType.mobile,
          fingerprint: target.fingerprint,
        ),
        files: {
          for (int i = 0; i < files.length; i++)
            'file_$i': FileDto(
              id: 'file_$i',
              fileName: files[i].path.split('/').last,
              size: files[i].lengthSync(),
              fileType: _determineFileType(files[i]),
              hash: null,
              preview: null,
              metadata: null,
            ),
        },
      );
      
      // Send prepare upload request
      final url = ApiRoute.prepareUpload.target(target);
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestDto.toJson()),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final responseDto = PrepareUploadResponseDto.fromJson(jsonDecode(response.body));
        
        // Update session with remote session ID
        _sessions[sessionId] = session.copyWith(
          remoteSessionId: responseDto.sessionId,
          status: SessionStatus.sending,
          fileTokens: responseDto.files,
        );
        
        // Start upload in background
        if (background) {
          unawaited(_uploadFiles(sessionId));
        }
        
        return sessionId;
      } else {
        throw Exception('Failed to prepare upload: ${response.statusCode}');
      }
    } catch (e) {
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finishedWithErrors,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }
  
  /// Upload files for a session
  Future<void> _uploadFiles(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError("Session not found: $sessionId");
    }
    
    try {
      for (int i = 0; i < session.files.length; i++) {
        final file = session.files[i];
        final fileId = 'file_$i';
        final token = session.fileTokens?[fileId];
        
        if (token == null) {
          throw StateError("Token not found for file: $fileId");
        }
        
        // Create multipart request
        final request = http.MultipartRequest(
          'POST',
          Uri.parse(ApiRoute.upload.target(session.target, query: {
            'fileId': fileId,
            'token': token,
            'sessionId': session.remoteSessionId,
          })),
        );
        
        // Add file to request
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        
        // Send request with timeout
        final response = await request.send().timeout(const Duration(minutes: 5));
        
        if (response.statusCode != 200) {
          await response.stream.drain(); // Consume response stream
          throw Exception('Failed to upload file: ${response.statusCode}');
        }
        
        // Update progress
        final progress = (i + 1) / session.files.length;
        _sessions[sessionId] = session.copyWith(progress: progress);
      }
      
      // Mark as completed
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finished,
        progress: 1.0,
      );
      
    } catch (e) {
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finishedWithErrors,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }
  
  /// Determine file type based on extension
  FileType _determineFileType(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return FileType.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
        return FileType.video;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return FileType.audio;
      case 'txt':
      case 'md':
      case 'json':
      case 'xml':
      case 'html':
        return FileType.text;
      case 'pdf':
        return FileType.pdf;
      default:
        return FileType.other;
    }
  }
  
  /// Get session status
  SendSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }
  
  /// Cancel a session
  void cancelSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError("Session not found: $sessionId");
    }
    
    _sessions[sessionId] = session.copyWith(
      status: SessionStatus.canceledBySender,
    );
  }
  
  /// Close a session
  void closeSession(String sessionId) {
    _sessions.remove(sessionId);
  }
  
  /// Get all active sessions
  Map<String, SendSession> get sessions => Map.unmodifiable(_sessions);
  
  /// Cancel all active sessions and cleanup resources
  void dispose() {
    // Cancel all active sessions
    for (final sessionId in _sessions.keys.toList()) {
      if (_sessions[sessionId]?.status == SessionStatus.sending) {
        cancelSession(sessionId);
      }
    }
    _sessions.clear();
  }
}

/// Simplified send session model
class SendSession {
  final String sessionId;
  final String remoteSessionId;
  final Device target;
  final List<File> files;
  final SessionStatus status;
  final Map<String, String>? fileTokens;
  final String? errorMessage;
  final double progress;
  
  const SendSession({
    required this.sessionId,
    required this.remoteSessionId,
    required this.target,
    required this.files,
    required this.status,
    this.fileTokens,
    this.errorMessage,
    this.progress = 0.0,
  });
  
  SendSession copyWith({
    String? sessionId,
    String? remoteSessionId,
    Device? target,
    List<File>? files,
    SessionStatus? status,
    Map<String, String>? fileTokens,
    String? errorMessage,
    double? progress,
  }) {
    return SendSession(
      sessionId: sessionId ?? this.sessionId,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      target: target ?? this.target,
      files: files ?? this.files,
      status: status ?? this.status,
      fileTokens: fileTokens ?? this.fileTokens,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
    );
  }
}

/// Helper function to run async code without waiting
void unawaited(Future<void> future) {
  future.catchError((error) {
    // Log error but don't crash
    print('[$_logTag] Unhandled async error: $error');
  });
}