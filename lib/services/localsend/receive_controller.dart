import 'dart:async';
import 'dart:io';
import '../device_identity_manager.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';
import 'models/file_dto.dart';
import 'models/info_register_dto.dart';
import 'models/prepare_upload_request_dto.dart';
import 'models/prepare_upload_response_dto.dart';
import 'models/session_status.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:thoughtecho/utils/app_logger.dart';

/// Simplified receive controller for ThoughtEcho
/// Based on LocalSend's receive_controller but with minimal dependencies
class ReceiveController {
  final Function(String filePath)? onFileReceived;
  final void Function(int received, int total)? onReceiveProgress;
  final void Function(String sessionId, int totalBytes, String senderAlias)?
      onSessionCreated; // 通知有新的会话（等待审批）
  final Future<bool> Function(
          String sessionId, int totalBytes, String senderAlias)?
      onApprovalNeeded; // 需要用户审批时回调，true 继续 false 取消
  final bool Function(String? fingerprint)?
      consumePreApproval; // 若返回true表示已存在预批准并已消费
  final Map<String, ReceiveSession> _sessions = {};
  final Duration sessionTimeout = const Duration(minutes: 2);
  Timer? _gcTimer;
  String? _cachedFingerprint; // initialized explicitly before serving info

  ReceiveController(
      {this.onFileReceived,
      this.onReceiveProgress,
      this.onSessionCreated,
      this.onApprovalNeeded,
      this.consumePreApproval});

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
    return {
      'alias': 'ThoughtEcho',
      'version': protocolVersion,
      'deviceModel': 'ThoughtEcho App',
      'deviceType': 'mobile',
      'fingerprint': _cachedFingerprint ?? 'uninitialized',
      'download': true,
    };
  }

  /// Explicitly set fingerprint when server starts to avoid 'loading' flicker
  Future<void> initializeFingerprint() async {
    try {
      _cachedFingerprint = await DeviceIdentityManager.I.getFingerprint();
      logDebug('fingerprint_initialized fp=$_cachedFingerprint',
          source: 'LocalSend');
    } catch (e) {
      logWarning('fingerprint_init_fail $e', source: 'LocalSend');
    }
  }

  /// Handle prepare upload request
  Future<Map<String, dynamic>> handlePrepareUpload(
      Map<String, dynamic> requestData) async {
    try {
      // 确保指纹已就绪
      // fingerprint already initialized by server; if null attempt once lazily
      if (_cachedFingerprint == null) {
        initializeFingerprint();
      }
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

      // 计算总大小
      int totalBytes = 0;
      for (final f in prepareRequest.files.values) {
        totalBytes += f.size;
      }

      // 预批准检测（ handshake 已批准 ）
      bool approved = false;
      final senderFp = prepareRequest.info.fingerprint;
      if (consumePreApproval?.call(senderFp) == true) {
        approved = true;
      } else {
        // 通知 UI 有新会话（等待审批）
        try {
          onSessionCreated?.call(
              sessionId, totalBytes, prepareRequest.info.alias);
        } catch (_) {}

        approved = true; // 默认通过除非显式需要用户确认
        if (onApprovalNeeded != null) {
          try {
            approved = await onApprovalNeeded!(
                sessionId, totalBytes, prepareRequest.info.alias);
          } catch (_) {
            approved = false;
          }
        }
      }

      if (!approved) {
        // 标记取消
        _sessions[sessionId] = session.copyWith(
          status: SessionStatus.canceledByReceiver,
          lastActivity: DateTime.now(),
        );
        throw Exception('接收端已拒绝');
      }

      // 生成 tokens（审批通过）
      final fileTokens = <String, String>{};
      const uuid = Uuid();
      for (final fileId in prepareRequest.files.keys) {
        fileTokens[fileId] = uuid.v4();
      }

      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.sending,
        fileTokens: fileTokens,
        lastActivity: DateTime.now(),
      );
      _startGcTimer();

      final response =
          PrepareUploadResponseDto(sessionId: sessionId, files: fileTokens);
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
    RandomAccessFile? raf;
    try {
      logInfo('recv_upload_start session=$sessionId fileId=$fileId',
          source: 'LocalSend');
      final session = _sessions[sessionId];
      if (session == null) {
        throw Exception('Session not found');
      }
      if (session.fileTokens?[fileId] != token) {
        throw Exception('Invalid token');
      }
      final fileDto = session.files[fileId];
      if (fileDto == null) {
        throw Exception('File not found');
      }
      if (fileDto.size <= 0) {
        throw Exception('Invalid file size');
      }
      final lowerName = fileDto.fileName.toLowerCase();
      const blockedExtensions = ['.exe', '.bat', '.sh', '.cmd'];
      if (blockedExtensions.any((b) => lowerName.endsWith(b))) {
        throw Exception('Blocked file type');
      }

      final tempDir = Directory.systemTemp;
      final sanitizedName = _sanitizeFileName(fileDto.fileName);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final targetPath =
          p.join(tempDir.path, 'thoughtecho_${timestamp}_$sanitizedName');
      tempFile = File(targetPath);
      raf = await tempFile.open(mode: FileMode.write);

      int received = 0;
      final contentType = request.headers.contentType;
      final boundary = contentType?.parameters['boundary'];

      if (contentType != null &&
          contentType.mimeType == 'multipart/form-data' &&
          boundary != null) {
        // Multipart streaming
        final transformer = MimeMultipartTransformer(boundary);
        final parts = request.cast<List<int>>().transform(transformer);
        await for (final part in parts) {
          final currentSession = _sessions[sessionId];
          if (currentSession != null &&
              currentSession.status == SessionStatus.canceledByReceiver) {
            logWarning('recv_aborted_by_user session=$sessionId',
                source: 'LocalSend');
            throw Exception('接收已取消');
          }
          final headers = part.headers;
          final disposition = headers['content-disposition'] ?? '';
          if (!disposition.contains('filename=')) {
            // Skip non-file fields
            await part.drain();
            continue;
          }
          await for (final chunk in part) {
            received += chunk.length;
            await raf.writeFrom(chunk);
            if (received % (64 * 1024) == 0) {
              logDebug('recv_progress bytes=$received size=${fileDto.size}',
                  source: 'LocalSend');
              onReceiveProgress?.call(received, fileDto.size);
            }
          }
        }
      } else {
        // Raw body streaming
        await for (final chunk in request) {
          final currentSession = _sessions[sessionId];
          if (currentSession != null &&
              currentSession.status == SessionStatus.canceledByReceiver) {
            logWarning('recv_aborted_by_user session=$sessionId',
                source: 'LocalSend');
            throw Exception('接收已取消');
          }
          received += chunk.length;
          await raf.writeFrom(chunk);
          if (received % (64 * 1024) == 0) {
            logDebug('recv_progress bytes=$received size=${fileDto.size}',
                source: 'LocalSend');
            onReceiveProgress?.call(received, fileDto.size);
          }
        }
      }

      await raf.close();
      raf = null;
      final finalSize = await tempFile.length();
      if (finalSize == 0) {
        throw Exception('Received empty file');
      }
      if (finalSize != fileDto.size) {
        logWarning(
            'recv_size_mismatch expected=${fileDto.size} actual=$finalSize',
            source: 'LocalSend');
      }

      // update session lastActivity
      _sessions[sessionId] = session.copyWith(lastActivity: DateTime.now());

      if (onFileReceived != null) {
        onFileReceived!(tempFile.path);
        final deletePath = tempFile.path;
        Future.delayed(const Duration(seconds: 30), () async {
          try {
            final f = File(deletePath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        });
      }

      logInfo(
          'recv_upload_done session=$sessionId fileId=$fileId size=$finalSize path=${tempFile.path}',
          source: 'LocalSend');
      // 最终完成进度
      onReceiveProgress?.call(finalSize, fileDto.size);
      return {
        'message': 'File uploaded successfully',
        'fileId': fileId,
        'size': finalSize,
      };
    } catch (e, stack) {
      logError('recv_upload_fail session=$sessionId fileId=$fileId error=$e',
          error: e, stackTrace: stack, source: 'LocalSend');
      try {
        await raf?.close();
      } catch (_) {}
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      throw Exception('Upload failed: $e');
    }
  }

  /// Get session info
  ReceiveSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  /// Cancel session
  void cancelSession(String sessionId) {
    final s = _sessions[sessionId];
    if (s != null) {
      _sessions[sessionId] =
          s.copyWith(status: SessionStatus.canceledByReceiver);
    }
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
