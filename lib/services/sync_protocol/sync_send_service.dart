/// 同步发送服务
library;

import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models/device_info.dart';
import 'models/file_transfer_dto.dart';
import 'utils/http_client.dart';
import 'utils/api_routes.dart';
import 'constants.dart' as sync_constants;

const _uuid = Uuid();

/// 发送进度回调
typedef ProgressCallback = void Function(double progress, String status);

/// 同步发送服务
class SyncSendService {
  final SyncHttpClient _httpClient = SyncHttpClient();
  final Map<String, TransferSession> _sessions = {};

  /// 发送文件到目标设备
  Future<String> sendFile({
    required NetworkDevice targetDevice,
    required File file,
    ProgressCallback? onProgress,
  }) async {
    final sessionId = _uuid.v4();
    
    try {
      // 1. 创建会话
      onProgress?.call(0.1, '准备发送...');
      
      final fileInfo = FileInfo(
        id: 'sync_file',
        fileName: file.path.split('/').last,
        size: await file.length(),
      );

      final session = TransferSession(
        sessionId: sessionId,
        remoteDeviceId: targetDevice.info.fingerprint,
        status: TransferStatus.preparing,
        files: {'sync_file': fileInfo},
      );

      _sessions[sessionId] = session;

      // 2. 准备上传请求
      onProgress?.call(0.2, '连接目标设备...');
      
      final prepareRequest = PrepareUploadRequest(
        info: _createDeviceInfo(),
        files: {'sync_file': fileInfo},
      );

      final prepareUrl = ApiRoutes.prepareUpload(targetDevice);
      final prepareResponse = await _httpClient.post(
        prepareUrl,
        body: prepareRequest.toJson(),
      );

      if (!prepareResponse.isSuccess) {
        throw Exception('准备上传失败: ${prepareResponse.statusCode}');
      }

      final prepareResponseDto = PrepareUploadResponse.fromJson(
        prepareResponse.jsonBody!,
      );

      // 3. 更新会话状态
      _sessions[sessionId] = session.copyWith(
        status: TransferStatus.sending,
        fileTokens: prepareResponseDto.files,
      );

      // 4. 上传文件
      onProgress?.call(0.3, '发送文件...');
      
      final token = prepareResponseDto.files['sync_file'];
      if (token == null) {
        throw Exception('未获取到文件上传令牌');
      }

      final uploadUrl = ApiRoutes.upload(
        targetDevice,
        sessionId: prepareResponseDto.sessionId,
        fileId: 'sync_file',
        token: token,
      );

      final uploadResponse = await _httpClient.uploadFile(
        uploadUrl,
        file,
        fileFieldName: 'file',
        fields: {
          'sessionId': prepareResponseDto.sessionId,
          'fileId': 'sync_file',
          'token': token,
        },
      );

      if (!uploadResponse.isSuccess) {
        throw Exception('文件上传失败: ${uploadResponse.statusCode}');
      }

      // 5. 完成
      onProgress?.call(1.0, '发送完成');
      
      _sessions[sessionId] = session.copyWith(
        status: TransferStatus.completed,
        progress: 1.0,
      );

      return sessionId;

    } catch (e) {
      // 错误处理
      _sessions[sessionId] = _sessions[sessionId]?.copyWith(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      ) ?? TransferSession(
        sessionId: sessionId,
        remoteDeviceId: targetDevice.info.fingerprint,
        status: TransferStatus.failed,
        files: {},
        errorMessage: e.toString(),
      );

      onProgress?.call(0.0, '发送失败: $e');
      rethrow;
    }
  }

  /// 获取会话状态
  TransferSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  /// 取消传输
  Future<void> cancelTransfer(String sessionId, NetworkDevice targetDevice) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    try {
      final cancelUrl = ApiRoutes.cancel(targetDevice, sessionId: sessionId);
      await _httpClient.post(cancelUrl);
    } catch (e) {
      debugPrint('取消传输请求失败: $e');
    }

    _sessions[sessionId] = session.copyWith(
      status: TransferStatus.cancelled,
    );
  }

  /// 创建设备信息
  DeviceInfo _createDeviceInfo() {
    return DeviceInfo(
      alias: 'ThoughtEcho',
      version: sync_constants.protocolVersion,
      deviceModel: 'ThoughtEcho App',
      deviceType: DeviceType.mobile,
      fingerprint: 'thoughtecho-${DateTime.now().millisecondsSinceEpoch}',
      port: sync_constants.defaultPort,
      protocol: ProtocolType.http,
      download: true,
    );
  }

  /// 清理资源
  void dispose() {
    _httpClient.dispose();
    _sessions.clear();
  }
}
