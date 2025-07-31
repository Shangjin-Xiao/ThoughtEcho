import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../common/lib/api_route_builder.dart';
import '../../common/lib/model/device.dart';
import '../../common/lib/model/dto/file_dto.dart';
import '../../common/lib/model/file_type.dart';
import '../../common/lib/model/dto/info_register_dto.dart';
import '../../common/lib/model/dto/multicast_dto.dart';
import '../../common/lib/model/dto/prepare_upload_request_dto.dart';
import '../../common/lib/model/dto/prepare_upload_response_dto.dart';
import '../../common/lib/model/session_status.dart';
import '../../common/lib/constants.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

const _uuid = Uuid();

/// Simplified send provider for ThoughtEcho
/// Based on LocalSend's send_provider but with minimal dependencies
class LocalSendProvider {
  static const String _logTag = "LocalSendProvider";
  
  final Map<String, SendSession> _sessions = {};
  
  /// Start a file transfer session
  Future<String> startSession({
    required Device target,
    required List<File> files,
    bool background = false,
  }) async {
    // Validate inputs
    if (files.isEmpty) {
      throw ArgumentError("Files list cannot be empty");
    }

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
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final responseDto = PrepareUploadResponseDto.fromJson(response.body);
        
        // Update session with response
        _sessions[sessionId] = session.copyWith(
          status: SessionStatus.sending,
          remoteSessionId: responseDto.sessionId,
          fileTokens: Map<String, String>.from(responseDto.files),
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
        
        final uploadUrl = ApiRoute.upload.target(session.target, query: {
          'sessionId': session.remoteSessionId!,
          'fileId': fileId,
          'token': token,
        });
        
        final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        
        final streamedResponse = await request.send().timeout(const Duration(minutes: 10));
        final response = await http.Response.fromStream(streamedResponse);
        
        if (response.statusCode != 200) {
          throw Exception('Failed to upload file ${file.path}: ${response.statusCode}');
        }
      }
      
      // Mark session as completed
      _sessions[sessionId] = session.copyWith(status: SessionStatus.finished);
      
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
      _sessions[sessionId] = session.copyWith(status: SessionStatus.canceledBySender);
    }
  }
  
  /// Dispose provider and cleanup resources
  void dispose() {
    _sessions.clear();
  }
}

/// Session model for tracking file transfers
class SendSession {
  final String sessionId;
  final Device target;
  final List<File> files;
  final SessionStatus status;
  final String? remoteSessionId;
  final Map<String, String>? fileTokens;
  final String? errorMessage;
  
  const SendSession({
    required this.sessionId,
    required this.target,
    required this.files,
    required this.status,
    this.remoteSessionId,
    this.fileTokens,
    this.errorMessage,
  });
  
  SendSession copyWith({
    String? sessionId,
    Device? target,
    List<File>? files,
    SessionStatus? status,
    String? remoteSessionId,
    Map<String, String>? fileTokens,
    String? errorMessage,
  }) {
    return SendSession(
      sessionId: sessionId ?? this.sessionId,
      target: target ?? this.target,
      files: files ?? this.files,
      status: status ?? this.status,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      fileTokens: fileTokens ?? this.fileTokens,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}