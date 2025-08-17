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
import '../device_identity_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

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
    void Function(int sentBytes, int totalBytes)? onProgress,
    void Function(String sessionId)? onSessionCreated,
  }) async {
    final sessionId = _uuid.v4();

    // 提前通知 sessionId 以支持取消操作
    try {
      onSessionCreated?.call(sessionId);
    } catch (_) {}

    // Create session
    final session = SendSession(
      sessionId: sessionId,
      target: target,
      files: files,
      status: SessionStatus.waiting,
    );

    _sessions[sessionId] = session;

    try {
      // 0. Optional handshake: verify /info endpoint for better reliability
      await _handshakeWithTarget(target);

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
          source: 'LocalSend');

      final client = http.Client();
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
          debugPrint('v2路由返回404，尝试v1路由: $fallbackUrl');
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

        logDebug('prepare_resp status=${response.statusCode}',
            source: 'LocalSend');
        final previewLen =
            response.body.length < 200 ? response.body.length : 200;
        debugPrint('响应内容: ${response.body.substring(0, previewLen)}...');

        if (response.statusCode == 200) {
          final responseDto = PrepareUploadResponseDto.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>);

          // Update session with response
          _sessions[sessionId] = session.copyWith(
            status: SessionStatus.sending,
            remoteSessionId: responseDto.sessionId,
            fileTokens: responseDto.files,
          );

          // Start file uploads with progress
          await _uploadFiles(sessionId, onProgress: onProgress);

          return sessionId;
        } else {
          throw Exception(
              'Failed to prepare upload: ${response.statusCode} - ${response.body}');
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
  Future<void> _uploadFiles(String sessionId,
      {void Function(int, int)? onProgress}) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    try {
      // 计算总大小
      int totalSize = 0;
      for (final f in session.files) {
        if (await f.exists()) {
          totalSize += await f.length();
        }
      }
      int sentBytes = 0;
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
        await _uploadSingleFile(
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
      SendSession session, String fileId, String token, File file, int fileSize,
      {void Function(int chunkBytes)? onChunk}) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        // 构建带查询参数的URL
        var url = ApiRoute.upload.target(session.target, query: {
          'sessionId': session.remoteSessionId!,
          'fileId': fileId,
          'token': token,
        });
        debugPrint(
            '上传文件到: $url (文件: ${file.path}, 尝试: ${attempt + 1}/$maxRetries)');

        final request = http.MultipartRequest('POST', Uri.parse(url));
        request.headers['User-Agent'] = 'ThoughtEcho/1.0';

        // 构建带进度的流
        final stream = file.openRead().transform<List<int>>(
          StreamTransformer.fromHandlers(
              handleData: (List<int> data, EventSink<List<int>> sink) {
            sink.add(data);
            onChunk?.call(data.length);
          }),
        );
        final multipart = http.MultipartFile(
          'file',
          stream,
          fileSize,
          filename: file.path.split('/').last,
        );
        request.files.add(multipart);

        // Send request with timeout
        final response =
            await request.send().timeout(const Duration(minutes: 5));

        logDebug('upload_resp status=${response.statusCode} file=${file.path}',
            source: 'LocalSend');

        if (response.statusCode == 404) {
          // Try legacy v1 route if needed
          url = '${ApiRoute.upload.targetRaw(
            session.target.ip ?? '127.0.0.1',
            session.target.port,
            session.target.https,
            '1.0',
          )}?sessionId=${Uri.encodeQueryComponent(session.remoteSessionId!)}&fileId=$fileId&token=$token';
          debugPrint('v2上传返回404，尝试v1路由: $url');
          final legacyReq = http.MultipartRequest('POST', Uri.parse(url));
          legacyReq.headers['User-Agent'] = 'ThoughtEcho/1.0';
          final legacyStream = file.openRead().transform<List<int>>(
            StreamTransformer.fromHandlers(
                handleData: (List<int> data, EventSink<List<int>> sink) {
              sink.add(data);
              onChunk?.call(data.length);
            }),
          );
          legacyReq.files.add(http.MultipartFile(
            'file',
            legacyStream,
            fileSize,
            filename: file.path.split('/').last,
          ));
          final legacyResp =
              await legacyReq.send().timeout(const Duration(minutes: 5));
          if (legacyResp.statusCode == 200) {
            debugPrint('文件上传成功(v1): ${file.path}');
            return;
          } else {
            final respBody = await legacyResp.stream.bytesToString();
            throw Exception(
                'Legacy upload failed with status ${legacyResp.statusCode}: $respBody');
          }
        }

        if (response.statusCode == 200) {
          logInfo(
              'upload_success attempt=${attempt + 1} file=${file.path} size=$fileSize',
              source: 'LocalSend');
          return; // Success
        }
        final responseBody = await response.stream.bytesToString();
        final status = response.statusCode;
        final retriable = status >= 500 || status == 408 || status == 429;
        if (!retriable) {
          throw Exception('Non-retriable status $status: $responseBody');
        }
        throw Exception('Retriable status $status: $responseBody');
      } catch (e) {
        attempt++;
        logWarning('upload_retry attempt=$attempt file=${file.path} error=$e',
            source: 'LocalSend');

        if (attempt >= maxRetries) {
          logError('upload_give_up file=${file.path} error=$e',
              source: 'LocalSend');
          throw Exception(
              'Failed to upload file after $maxRetries attempts: $e');
        }

        // Exponential backoff (cap 8s)
        final delay = Duration(seconds: 1 << (attempt - 1));
        await Future.delayed(delay > const Duration(seconds: 8)
            ? const Duration(seconds: 8)
            : delay);
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
      // 通知对端（最佳努力，不影响本地状态）
      final remoteId = session.remoteSessionId;
      if (remoteId != null) {
        final url =
            ApiRoute.info.target(session.target).replaceAll('/info', '/cancel');
        try {
          final client = http.Client();
          client
              .post(Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'sessionId': remoteId}))
              .timeout(const Duration(seconds: 2))
              .catchError((_) => http.Response('{}', 499));
        } catch (_) {}
      }
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

  /// Query target /info once to validate connectivity and possibly adapt route
  Future<void> _handshakeWithTarget(Device target) async {
    final client = http.Client();
    try {
      final infoUrl = ApiRoute.info.target(target);
      debugPrint('握手检查: $infoUrl');
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
        debugPrint('v2 /info 404，尝试 v1: $v1Url');
        resp = await client
            .get(Uri.parse(v1Url))
            .timeout(const Duration(seconds: 5));
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        debugPrint('握手成功: /info 响应 ${resp.statusCode}');
      } else {
        debugPrint('握手警告: /info 响应 ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('握手失败: $e');
      // Do not throw; allow prepare step to try as well but keep logs
    } finally {
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
