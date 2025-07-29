import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      
      // Send prepare upload request
      final url = ApiRoute.prepareUpload.target(target);
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestDto.toJson()),
      );
      
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
    if (session == null) return;
    
    try {
      for (int i = 0; i < session.files.length; i++) {
        final file = session.files[i];
        final fileId = 'file_$i';
        final token = session.fileTokens?[fileId];
        
        if (token == null) continue;
        
        // Upload file
        final url = ApiRoute.upload.target(session.target);
        final request = http.MultipartRequest('POST', Uri.parse(url));
        
        // Add query parameters
        request.fields['sessionId'] = session.remoteSessionId!;
        request.fields['fileId'] = fileId;
        request.fields['token'] = token;
        
        // Add file
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        
        // Send request
        final response = await request.send();
        
        if (response.statusCode != 200) {
          throw Exception('Failed to upload file: ${response.statusCode}');
        }
      }
      
      // Mark as completed
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finished,
      );
      
    } catch (e) {
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finishedWithErrors,
        errorMessage: e.toString(),
      );
      rethrow;
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
