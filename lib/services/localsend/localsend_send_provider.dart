import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

import '../device_identity_manager.dart';
import 'api_route_builder.dart';
import 'constants.dart';
import 'models/device.dart';
import 'models/file_dto.dart';
import 'models/file_type.dart';
import 'models/info_register_dto.dart';
import 'models/multicast_dto.dart';
import 'models/prepare_upload_request_dto.dart';
import 'models/prepare_upload_response_dto.dart';
import 'models/session_status.dart';

const _uuid = Uuid();

/// Simplified send provider for ThoughtEcho
/// Based on LocalSend's send_provider but with minimal dependencies
class LocalSendProvider {
  final Map<String, SendSession> _sessions = {};
  final Map<String, http.Client> _activeClients = {};
  final Set<String> _cancelledSessions = {};

  /// Start a file transfer session
  Future<String> startSession({
    required Device target,
    required List<File> files,
    bool background = true,
    void Function(int sentBytes, int totalBytes)? onProgress,
    void Function(String sessionId)? onSessionCreated,
  }) async {
    final sessionId = _uuid.v4();

    // 提前通知 sessionId 以支持取消操作
    try {
      onSessionCreated?.call(sessionId);
    } catch (e) {
      logDebug('[LocalSendSendProvider] onSessionCreated callback failed: $e');
    }

    // Create session
    final session = SendSession(
      sessionId: sessionId,
      target: target,
      files: files,
      status: SessionStatus.waiting,
    );

    _sessions[sessionId] = session;
    _cancelledSessions.remove(sessionId);

    try {
      // 0. Optional handshake: verify /info endpoint for better reliability
      await _handshakeWithTarget(target, sessionId);
      _throwIfCancelled(sessionId);

      // Prepare upload request
      final requestDto = PrepareUploadRequestDto(
        info: await _buildInfoRegisterDto(),
        files: {
          for (int i = 0; i < files.length; i++)
            'file_$i': FileDto(
              id: 'file_$i',
              fileName: files[i].path.split('/').last,
              size: await _ensureStableFileSize(files[i]),
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
      logInfo(
        'send_prepare target=${target.ip}:${target.port} url=$url session=$sessionId',
        source: 'LocalSend',
      );

      final client = http.Client();
      _activeClients[sessionId] = client;
      try {
        http.Response response = await client
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'ThoughtEcho/1.0',
              },
              body: jsonEncode(requestDto.toJson()),
            )
            .timeout(const Duration(seconds: 30));

        // Retry once with v1 route if server responded with 404 (version mismatch)
        if (response.statusCode == 404) {
          final fallbackUrl = ApiRoute.prepareUpload.targetRaw(
            target.ip ?? '127.0.0.1',
            target.port,
            target.https,
            '1.0',
          );
          logInfo('v2 route 404, trying v1 route: $fallbackUrl',
              source: 'LocalSend');
          response = await client
              .post(
                Uri.parse(fallbackUrl),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent': 'ThoughtEcho/1.0',
                },
                body: jsonEncode(requestDto.toJson()),
              )
              .timeout(const Duration(seconds: 30));
        }

        logDebug(
          'prepare_resp status=${response.statusCode} body=${_summarizeBody(response.body, maxLength: 50)}',
          source: 'LocalSend',
        );

        if (response.statusCode == 200) {
          final responseDto = PrepareUploadResponseDto.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );

          // Update session with response
          _sessions[sessionId] = session.copyWith(
            status: SessionStatus.sending,
            remoteSessionId: responseDto.sessionId,
            fileTokens: responseDto.files,
          );
          _throwIfCancelled(sessionId);

          // Start file uploads with progress
          await _uploadFiles(sessionId, onProgress: onProgress);

          return sessionId;
        } else {
          throw Exception(
            'Failed to prepare upload: ${response.statusCode} - ${_summarizeBody(response.body)}',
          );
        }
      } finally {
        if (identical(_activeClients[sessionId], client)) {
          _activeClients.remove(sessionId);
        }
        client.close();
      }
    } catch (e) {
      if (_cancelledSessions.contains(sessionId)) {
        _sessions[sessionId] = session.copyWith(
          status: SessionStatus.canceledBySender,
        );
      } else {
        _sessions[sessionId] = session.copyWith(
          status: SessionStatus.finishedWithErrors,
          errorMessage: e.toString(),
        );
      }
      rethrow;
    }
  }

  /// Upload files for a session with enhanced error handling and progress tracking
  Future<void> _uploadFiles(
    String sessionId, {
    void Function(int, int)? onProgress,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    try {
      // 计算总大小 (并发获取)
      final sizes = await Future.wait(session.files.map((f) async {
        if (await f.exists()) {
          return await f.length();
        }
        return 0;
      }));
      final totalSize = sizes.fold<int>(0, (sum, size) => sum + size);
      int sentBytes = 0;
      for (int i = 0; i < session.files.length; i++) {
        _throwIfCancelled(sessionId);
        final file = session.files[i];
        final fileId = 'file_$i';
        final token = session.fileTokens?[fileId];

        if (token == null) {
          logWarning('Skipping file $fileId: no token', source: 'LocalSend');
          continue;
        }

        // Verify file exists and is readable
        if (!await file.exists()) {
          throw Exception('File not found: ${file.path}');
        }

        final fileSize = await file.length();
        final fileName = file.path.split('/').last;
        logInfo('Preparing to upload file: $fileName ($fileSize bytes)',
            source: 'LocalSend');

        // Upload file with retry mechanism
        await _uploadSingleFile(
          sessionId,
          session,
          fileId,
          token,
          file,
          fileSize,
          onChunk: (c) {
            sentBytes += c;
            if (onProgress != null) {
              onProgress(sentBytes, totalSize == 0 ? 1 : totalSize);
            }
          },
        );
      }

      // Mark as completed
      _throwIfCancelled(sessionId);
      _sessions[sessionId] = session.copyWith(status: SessionStatus.finished);
      logInfo('All files uploaded for session: $sessionId',
          source: 'LocalSend');
    } catch (e) {
      logError('File upload failed: $e', source: 'LocalSend');
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.finishedWithErrors,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Upload a single file with retry mechanism
  Future<void> _uploadSingleFile(
    String sessionId,
    SendSession session,
    String fileId,
    String token,
    File file,
    int fileSize, {
    void Function(int chunkBytes)? onChunk,
  }) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      _throwIfCancelled(sessionId);
      http.Client? client;
      try {
        // 构建带查询参数的URL
        var url = ApiRoute.upload.target(
          session.target,
          query: {
            'sessionId': session.remoteSessionId!,
            'fileId': fileId,
            'token': token,
          },
        );
        logInfo(
          'Uploading file to: $url (file: ${file.path.split('/').last}, attempt: ${attempt + 1}/$maxRetries)',
          source: 'LocalSend',
        );

        final request = http.MultipartRequest('POST', Uri.parse(url));
        request.headers['User-Agent'] = 'ThoughtEcho/1.0';

        // 构建带进度的流
        final stream = file.openRead().transform<List<int>>(
          StreamTransformer.fromHandlers(
            handleData: (List<int> data, EventSink<List<int>> sink) {
              sink.add(data);
              onChunk?.call(data.length);
            },
          ),
        );
        final multipart = http.MultipartFile(
          'file',
          stream,
          fileSize,
          filename: file.path.split('/').last,
        );
        request.files.add(multipart);

        // Send request with timeout
        client = http.Client();
        _activeClients[sessionId] = client;
        final response = await client.send(request).timeout(
              const Duration(minutes: 5),
            );

        logDebug(
          'upload_resp status=${response.statusCode} file=${file.path.split('/').last}',
          source: 'LocalSend',
        );

        if (response.statusCode == 404) {
          // Try legacy v1 route if needed
          url =
              '${ApiRoute.upload.targetRaw(session.target.ip ?? '127.0.0.1', session.target.port, session.target.https, '1.0')}?sessionId=${Uri.encodeQueryComponent(session.remoteSessionId!)}&fileId=$fileId&token=$token';
          logInfo('v2 upload 404, trying v1 route: $url', source: 'LocalSend');
          final legacyReq = http.MultipartRequest('POST', Uri.parse(url));
          legacyReq.headers['User-Agent'] = 'ThoughtEcho/1.0';
          final legacyStream = file.openRead().transform<List<int>>(
            StreamTransformer.fromHandlers(
              handleData: (List<int> data, EventSink<List<int>> sink) {
                sink.add(data);
                onChunk?.call(data.length);
              },
            ),
          );
          legacyReq.files.add(
            http.MultipartFile(
              'file',
              legacyStream,
              fileSize,
              filename: file.path.split('/').last,
            ),
          );
          final legacyResp = await client.send(legacyReq).timeout(
                const Duration(minutes: 5),
              );
          if (legacyResp.statusCode == 200) {
            logInfo('File upload success (v1): $fileId', source: 'LocalSend');
            return;
          } else {
            final respBody = await legacyResp.stream.bytesToString();
            throw Exception(
              'Legacy upload failed with status ${legacyResp.statusCode}: ${_summarizeBody(respBody)}',
            );
          }
        }

        if (response.statusCode == 200) {
          logInfo(
            'upload_success attempt=${attempt + 1} file=${file.path.split('/').last} size=$fileSize',
            source: 'LocalSend',
          );
          return; // Success
        }
        final responseBody = await response.stream.bytesToString();
        final status = response.statusCode;
        final retriable = status >= 500 || status == 408 || status == 429;
        final summarizedBody = _summarizeBody(responseBody);
        if (!retriable) {
          throw Exception('Non-retriable status $status: $summarizedBody');
        }
        throw Exception('Retriable status $status: $summarizedBody');
      } catch (e) {
        if (_cancelledSessions.contains(sessionId)) {
          throw StateError('发送已取消');
        }
        attempt++;
        logWarning(
          'upload_retry attempt=$attempt file=${file.path.split('/').last} error=$e',
          source: 'LocalSend',
        );

        if (attempt >= maxRetries) {
          logError(
            'upload_give_up file=${file.path.split('/').last} error=$e',
            source: 'LocalSend',
          );
          throw Exception(
            'Failed to upload file after $maxRetries attempts: $e',
          );
        }

        // Exponential backoff (cap 8s)
        final delay = Duration(seconds: 1 << (attempt - 1));
        await Future.delayed(
          delay > const Duration(seconds: 8)
              ? const Duration(seconds: 8)
              : delay,
        );
      } finally {
        if (identical(_activeClients[sessionId], client)) {
          _activeClients.remove(sessionId);
        }
        client?.close();
      }
    }
  }

  void _throwIfCancelled(String sessionId) {
    if (_cancelledSessions.contains(sessionId)) {
      throw StateError('发送已取消');
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
      _cancelledSessions.add(sessionId);
      _activeClients.remove(sessionId)?.close();
      _sessions[sessionId] = session.copyWith(
        status: SessionStatus.canceledBySender,
      );
      // 通知对端（最佳努力，不影响本地状态）
      final remoteId = session.remoteSessionId;
      if (remoteId != null) {
        unawaited(_notifyCancellation(session, remoteId));
      }
    }
  }

  Future<void> _notifyCancellation(
    SendSession session,
    String remoteSessionId,
  ) async {
    final client = http.Client();
    try {
      final url =
          ApiRoute.info.target(session.target).replaceAll('/info', '/cancel');
      await client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sessionId': remoteSessionId}),
          )
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      logDebug('[LocalSendSendProvider] cancel notify failed: $e');
    } finally {
      client.close();
    }
  }

  /// Close a session
  void closeSession(String sessionId) {
    _sessions.remove(sessionId);
    _cancelledSessions.remove(sessionId);
    _activeClients.remove(sessionId)?.close();
  }

  /// Get all active sessions
  Map<String, SendSession> get sessions => Map.unmodifiable(_sessions);

  void dispose() {
    for (final client in _activeClients.values) {
      client.close();
    }
    _activeClients.clear();
    _cancelledSessions.clear();
    _sessions.clear();
  }

  /// Truncate long response bodies for logging
  String _summarizeBody(String body, {int maxLength = 100}) {
    if (body.length <= maxLength) return body;
    return '${body.substring(0, maxLength)}...';
  }

  /// Query target /info once to validate connectivity and possibly adapt route
  Future<void> _handshakeWithTarget(Device target, String sessionId) async {
    final client = http.Client();
    _activeClients[sessionId] = client;
    try {
      final infoUrl = ApiRoute.info.target(target);
      logDebug('Handshake check: $infoUrl', source: 'LocalSend');
      var resp = await client
          .get(Uri.parse(infoUrl))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 404) {
        final v1Url = ApiRoute.info.targetRaw(
          target.ip ?? '127.0.0.1',
          target.port,
          target.https,
          '1.0',
        );
        logInfo('v2 /info 404, trying v1: $v1Url', source: 'LocalSend');
        resp = await client
            .get(Uri.parse(v1Url))
            .timeout(const Duration(seconds: 5));
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        logDebug('Handshake success: /info status ${resp.statusCode}',
            source: 'LocalSend');
      } else {
        logWarning('Handshake warning: /info status ${resp.statusCode}',
            source: 'LocalSend');
      }
    } catch (e) {
      logWarning('Handshake failed: $e', source: 'LocalSend');
      // Do not throw; allow prepare step to try as well but keep logs
    } finally {
      if (identical(_activeClients[sessionId], client)) {
        _activeClients.remove(sessionId);
      }
      client.close();
    }
  }

  /// Build a stable sender info to be compatible with LocalSend
  Future<InfoRegisterDto> _buildInfoRegisterDto() async {
    final stableFingerprint = await DeviceIdentityManager.I.getFingerprint();
    return InfoRegisterDto(
      alias: 'ThoughtEcho',
      version: protocolVersion,
      deviceModel: 'ThoughtEcho App',
      deviceType: DeviceType.mobile,
      fingerprint: stableFingerprint,
      port: defaultPort,
      protocol: ProtocolType.http,
      download: true,
    );
  }

  /// Ensure file size is stable (not 0 after creation); retry short time if needed
  Future<int> _ensureStableFileSize(File f) async {
    int size = 0;
    for (int i = 0; i < 3; i++) {
      try {
        size = await f.length();
      } catch (_) {
        size = 0;
      }
      if (size > 0) return size;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (size == 0) {
      logError('file_size_zero path=${f.path}', source: 'LocalSend');
    }
    return size;
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
