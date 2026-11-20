import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
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
  /// Safe file extensions permitted for incoming transfers.
  static const Set<String> allowedExtensions = {
    '.zip',
    '.json',
    '.db',
    '.sqlite',
    '.txt',
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.heic',
    '.heif',
    '.bmp',
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.flac',
    '.opus',
    '.mp4',
    '.mov',
    '.webm',
    '.mkv',
    '.avi',
  };

  final Function(String filePath)? onFileReceived;
  final void Function(int received, int total)? onReceiveProgress;
  final void Function(String sessionId, int totalBytes, String senderAlias)?
      onSessionCreated; // 通知有新的会话（等待审批）
  final Future<bool> Function(
    String sessionId,
    int totalBytes,
    String senderAlias,
  )? onApprovalNeeded; // 需要用户审批时回调，true 继续 false 取消
  final void Function(
    String sessionId,
    String? senderIp,
    int? senderPort,
    String? senderFingerprint,
  )? onSenderInfoReceived;
  final DateTime Function() _now;
  final Map<String, ReceiveSession> _sessions = {};
  final Map<String, int> _activeUploads = {};
  final Duration sessionTimeout = const Duration(minutes: 2);
  Timer? _gcTimer;
  String? _cachedFingerprint; // initialized explicitly before serving info

  ReceiveController({
    this.onFileReceived,
    this.onReceiveProgress,
    this.onSessionCreated,
    this.onApprovalNeeded,
    this.onSenderInfoReceived,
    @visibleForTesting DateTime Function()? nowProvider,
  }) : _now = nowProvider ?? DateTime.now;

  void _startGcTimer() {
    _gcTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      final now = _now();
      final toRemove = <String>[];
      _sessions.forEach((id, s) {
        if (now.difference(s.lastActivity).compareTo(sessionTimeout) > 0) {
          toRemove.add(id);
        }
      });
      for (final id in toRemove) {
        _sessions.remove(id);
        _activeUploads.remove(id);
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
      logDebug(
        'fingerprint_initialized fp=$_cachedFingerprint',
        source: 'LocalSend',
      );
    } catch (e, stack) {
      logError(
        'fingerprint_init_fail',
        error: e,
        stackTrace: stack,
        source: 'LocalSend',
      );
    }
  }

  /// Handle prepare upload request
  Future<Map<String, dynamic>> handlePrepareUpload(
    Map<String, dynamic> requestData, {
    String? remoteIp,
    int? remotePort,
  }) async {
    try {
      // 确保指纹已就绪
      // fingerprint already initialized by server; if null attempt once lazily
      if (_cachedFingerprint == null) {
        initializeFingerprint();
      }
      final prepareRequest = await Isolate.run(
        () => PrepareUploadRequestDto.fromJson(requestData),
      );

      // Create session
      final sessionId = const Uuid().v4();
      final session = ReceiveSession(
        sessionId: sessionId,
        senderInfo: prepareRequest.info,
        files: prepareRequest.files,
        status: SessionStatus.waiting,
        lastActivity: _now(),
      );

      _sessions[sessionId] = session;

      // 计算总大小
      int totalBytes = 0;
      for (final f in prepareRequest.files.values) {
        totalBytes += f.size;
      }

      final infoPort = prepareRequest.info.port;
      final effectivePort =
          (infoPort != null && infoPort > 0 && infoPort <= 65535)
              ? infoPort
              : null;
      final trimmedFp = prepareRequest.info.fingerprint?.trim();
      final effectiveFp =
          (trimmedFp != null && trimmedFp.isNotEmpty) ? trimmedFp : null;

      // Fingerprints are public metadata, not authorization. Approve this
      // preparation and its file list even when a sync intent was approved.
      bool approved = false;
      try {
        onSenderInfoReceived?.call(
          sessionId,
          remoteIp,
          effectivePort,
          effectiveFp,
        );
      } catch (e, stack) {
        logError(
          '[ReceiveController] onSenderInfoReceived callback failed',
          error: e,
          stackTrace: stack,
          source: 'LocalSend',
        );
      }

      // 通知 UI 有新会话（等待审批）
      try {
        onSessionCreated?.call(
          sessionId,
          totalBytes,
          prepareRequest.info.alias,
        );
      } catch (e, stack) {
        logError(
          '[ReceiveController] onSessionCreated callback failed',
          error: e,
          stackTrace: stack,
          source: 'LocalSend',
        );
      }

      if (onApprovalNeeded != null) {
        try {
          approved = await onApprovalNeeded!(
            sessionId,
            totalBytes,
            prepareRequest.info.alias,
          );
        } catch (e, stack) {
          logError(
            '[ReceiveController] onApprovalNeeded callback failed',
            error: e,
            stackTrace: stack,
            source: 'LocalSend',
          );
        }
      }

      final currentSession = _sessions[sessionId];
      if (!approved ||
          currentSession == null ||
          currentSession.status != SessionStatus.waiting) {
        // 标记取消
        if (currentSession != null) {
          _sessions[sessionId] = currentSession.copyWith(
            status: SessionStatus.canceledByReceiver,
            lastActivity: _now(),
          );
        }
        logInfo('recv_prepare_rejected session=$sessionId',
            source: 'LocalSend');
        throw Exception('接收端已拒绝');
      }

      // 生成 tokens（审批通过）
      final fileTokens = <String, String>{};
      const uuid = Uuid();
      for (final fileId in prepareRequest.files.keys) {
        fileTokens[fileId] = uuid.v4();
      }

      _sessions[sessionId] = currentSession.copyWith(
        status: SessionStatus.sending,
        fileTokens: fileTokens,
        lastActivity: _now(),
      );
      _startGcTimer();

      final response = PrepareUploadResponseDto(
        sessionId: sessionId,
        files: fileTokens,
      );
      return await Isolate.run(() => response.toJson());
    } catch (e, stack) {
      if (e.toString().contains('接收端已拒绝')) {
        rethrow;
      }
      logError(
        'Invalid prepare upload request',
        error: e,
        stackTrace: stack,
        source: 'LocalSend',
      );
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
    Directory? uploadTempDir;
    File? tempFile;
    RandomAccessFile? raf;
    var tokenConsumed = false;
    var uploadCounted = false;

    void releaseActiveUpload() {
      if (!uploadCounted) return;
      uploadCounted = false;
      final active = _activeUploads[sessionId] ?? 0;
      if (active <= 1) {
        _activeUploads.remove(sessionId);
      } else {
        _activeUploads[sessionId] = active - 1;
      }
    }

    try {
      logInfo(
        'recv_upload_start session=$sessionId fileId=$fileId',
        source: 'LocalSend',
      );
      final session = _requireSendingSession(sessionId);
      final currentTokens = session.fileTokens;
      if (token.isEmpty ||
          currentTokens == null ||
          currentTokens[fileId] != token) {
        throw Exception('Invalid token');
      }
      // Consume single-use token before any async I/O to prevent replay/races.
      final remainingTokens = Map<String, String>.from(currentTokens)
        ..remove(fileId);
      _activeUploads[sessionId] = (_activeUploads[sessionId] ?? 0) + 1;
      uploadCounted = true;
      _sessions[sessionId] = session.copyWith(fileTokens: remainingTokens);
      tokenConsumed = true;

      final fileDto = session.files[fileId];
      if (fileDto == null) {
        throw Exception('File not found');
      }
      if (fileDto.size <= 0) {
        throw Exception('Invalid file size');
      }
      final fileName = fileDto.fileName;
      if (fileName.isEmpty ||
          fileName.contains('..') ||
          fileName.contains('/') ||
          fileName.contains('\\') ||
          fileName.contains('\x00')) {
        throw Exception('Invalid file name');
      }
      final ext = p.extension(fileName).toLowerCase();
      if (ext.isEmpty || !allowedExtensions.contains(ext)) {
        throw Exception('Blocked file type');
      }

      uploadTempDir =
          await Directory.systemTemp.createTemp('thoughtecho_recv_');
      final sanitizedName = _sanitizeFileName(fileName);
      final targetPath = p.join(uploadTempDir.path, sanitizedName);
      if (!p.isWithin(
        p.canonicalize(uploadTempDir.path),
        p.canonicalize(targetPath),
      )) {
        throw Exception('Invalid file path');
      }
      tempFile = await File(targetPath).create(exclusive: true);
      raf = await tempFile.open(mode: FileMode.write);

      int received = 0;
      final contentType = request.headers.contentType;
      final boundary = contentType?.parameters['boundary'];

      // Tracking last reported bytes to throttle updates (e.g. every 100KB)
      int lastReportedBytes = 0;
      const int progressThreshold = 100 * 1024;

      if (contentType != null &&
          contentType.mimeType == 'multipart/form-data' &&
          boundary != null) {
        // Multipart streaming
        final transformer = MimeMultipartTransformer(boundary);
        final parts = request.cast<List<int>>().transform(transformer);
        await for (final part in parts) {
          _requireSendingSession(sessionId);
          final headers = part.headers;
          final disposition = headers['content-disposition'] ?? '';
          if (!disposition.contains('filename=')) {
            // Skip non-file fields
            await part.drain();
            continue;
          }
          await for (final chunk in part) {
            _requireSendingSession(sessionId);
            received += chunk.length;
            await raf.writeFrom(chunk);
            _requireSendingSession(sessionId);
            // Report progress if we've received enough new bytes
            if (received - lastReportedBytes >= progressThreshold) {
              logDebug(
                'recv_progress bytes=$received size=${fileDto.size}',
                source: 'LocalSend',
              );
              onReceiveProgress?.call(received, fileDto.size);
              lastReportedBytes = received;
            }
          }
        }
      } else {
        // Raw body streaming
        await for (final chunk in request) {
          _requireSendingSession(sessionId);
          received += chunk.length;
          await raf.writeFrom(chunk);
          _requireSendingSession(sessionId);
          // Report progress if we've received enough new bytes
          if (received - lastReportedBytes >= progressThreshold) {
            logDebug(
              'recv_progress bytes=$received size=${fileDto.size}',
              source: 'LocalSend',
            );
            onReceiveProgress?.call(received, fileDto.size);
            lastReportedBytes = received;
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
          source: 'LocalSend',
        );
      }

      // Check after the final I/O and preserve the live session before dispatch.
      final currentSession = _requireSendingSession(sessionId);
      releaseActiveUpload();
      final updatedCompleted = Set<String>.from(currentSession.completedFileIds)
        ..add(fileId);
      final noTokensLeft = currentSession.fileTokens?.isEmpty ?? true;
      final noActiveUploads = (_activeUploads[sessionId] ?? 0) == 0;
      final allFilesSettled = noTokensLeft &&
          noActiveUploads &&
          (updatedCompleted.length + currentSession.failedFileIds.length >=
              currentSession.files.length);
      final nextStatus = !allFilesSettled
          ? SessionStatus.sending
          : (currentSession.failedFileIds.isNotEmpty
              ? SessionStatus.finishedWithErrors
              : SessionStatus.finished);
      _sessions[sessionId] = currentSession.copyWith(
        completedFileIds: updatedCompleted,
        status: nextStatus,
        lastActivity: _now(),
      );

      if (onFileReceived != null) {
        onFileReceived!(tempFile.path);
        final cleanupDir = uploadTempDir;
        Future.delayed(const Duration(seconds: 30), () async {
          try {
            if (await cleanupDir.exists()) {
              await cleanupDir.delete(recursive: true);
            }
          } catch (e, stack) {
            logError(
              '[ReceiveController] temp file cleanup failed',
              error: e,
              stackTrace: stack,
              source: 'LocalSend',
            );
          }
        });
      } else {
        // No receiver callback to consume tempFile; clean up immediately.
        if (await uploadTempDir.exists()) {
          await uploadTempDir.delete(recursive: true);
        }
      }

      logInfo(
        'recv_upload_done session=$sessionId fileId=$fileId size=$finalSize path=${tempFile.path}',
        source: 'LocalSend',
      );
      // 最终完成进度
      onReceiveProgress?.call(finalSize, fileDto.size);
      return {
        'message': 'File uploaded successfully',
        'fileId': fileId,
        'size': finalSize,
      };
    } catch (e, stack) {
      releaseActiveUpload();
      if (tokenConsumed) {
        final currentSession = _sessions[sessionId];
        if (currentSession != null) {
          final updatedFailed = Set<String>.from(currentSession.failedFileIds)
            ..add(fileId);
          final noTokensLeft = currentSession.fileTokens?.isEmpty ?? true;
          final noActiveUploads = (_activeUploads[sessionId] ?? 0) == 0;
          final shouldFinalizeError =
              currentSession.status == SessionStatus.sending &&
                  noTokensLeft &&
                  noActiveUploads;
          _sessions[sessionId] = currentSession.copyWith(
            failedFileIds: updatedFailed,
            status: shouldFinalizeError
                ? SessionStatus.finishedWithErrors
                : currentSession.status,
            lastActivity: _now(),
          );
        }
      }
      logError(
        'recv_upload_fail session=$sessionId fileId=$fileId error=$e',
        error: e,
        stackTrace: stack,
        source: 'LocalSend',
      );
      try {
        await raf?.close();
      } catch (e, stack) {
        logError(
          '[ReceiveController] raf close error',
          error: e,
          stackTrace: stack,
          source: 'LocalSend',
        );
      }
      try {
        if (uploadTempDir != null && await uploadTempDir.exists()) {
          await uploadTempDir.delete(recursive: true);
        } else if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e, stack) {
        logError(
          '[ReceiveController] temp file cleanup error',
          error: e,
          stackTrace: stack,
          source: 'LocalSend',
        );
      }
      throw Exception('Upload failed: $e');
    } finally {
      releaseActiveUpload();
    }
  }

  ReceiveSession _requireSendingSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found');
    }
    if (_now().difference(session.lastActivity) > sessionTimeout) {
      _sessions.remove(sessionId);
      throw Exception('Session expired');
    }
    if (session.status != SessionStatus.sending) {
      throw Exception('接收已取消');
    }
    return session;
  }

  /// Get session info
  ReceiveSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  /// Cancel session
  void cancelSession(String sessionId) {
    final s = _sessions[sessionId];
    if (s != null) {
      _sessions[sessionId] = s.copyWith(
        status: SessionStatus.canceledByReceiver,
      );
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
    _activeUploads.clear();
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
  final Set<String> completedFileIds;
  final Set<String> failedFileIds;
  final DateTime lastActivity;

  const ReceiveSession({
    required this.sessionId,
    required this.senderInfo,
    required this.files,
    required this.status,
    this.fileTokens,
    this.completedFileIds = const {},
    this.failedFileIds = const {},
    required this.lastActivity,
  });

  ReceiveSession copyWith({
    String? sessionId,
    InfoRegisterDto? senderInfo,
    Map<String, FileDto>? files,
    SessionStatus? status,
    Map<String, String>? fileTokens,
    Set<String>? completedFileIds,
    Set<String>? failedFileIds,
    DateTime? lastActivity,
  }) {
    return ReceiveSession(
      sessionId: sessionId ?? this.sessionId,
      senderInfo: senderInfo ?? this.senderInfo,
      files: files ?? this.files,
      status: status ?? this.status,
      fileTokens: fileTokens ?? this.fileTokens,
      completedFileIds: completedFileIds ?? this.completedFileIds,
      failedFileIds: failedFileIds ?? this.failedFileIds,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}
