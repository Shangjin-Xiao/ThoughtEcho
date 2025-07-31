/// 文件传输相关的DTO
/// 简化版本的LocalSend文件传输协议
library;

import 'device_info.dart';

/// 文件信息DTO
class FileInfo {
  final String id;
  final String fileName;
  final int size;
  final String? hash;

  const FileInfo({
    required this.id,
    required this.fileName,
    required this.size,
    this.hash,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'size': size,
      if (hash != null) 'hash': hash,
    };
  }

  static FileInfo fromJson(Map<String, dynamic> json) {
    return FileInfo(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      size: json['size'] as int,
      hash: json['hash'] as String?,
    );
  }
}

/// 准备上传请求DTO
class PrepareUploadRequest {
  final DeviceInfo info;
  final Map<String, FileInfo> files;

  const PrepareUploadRequest({
    required this.info,
    required this.files,
  });

  Map<String, dynamic> toJson() {
    return {
      'info': info.toJson(),
      'files': files.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  static PrepareUploadRequest fromJson(Map<String, dynamic> json) {
    final filesJson = json['files'] as Map<String, dynamic>;
    final files = filesJson.map(
      (key, value) => MapEntry(key, FileInfo.fromJson(value as Map<String, dynamic>)),
    );

    return PrepareUploadRequest(
      info: DeviceInfo.fromJson(json['info'] as Map<String, dynamic>),
      files: files,
    );
  }
}

/// 准备上传响应DTO
class PrepareUploadResponse {
  final String sessionId;
  final Map<String, String> files; // fileId -> token

  const PrepareUploadResponse({
    required this.sessionId,
    required this.files,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'files': files,
    };
  }

  static PrepareUploadResponse fromJson(Map<String, dynamic> json) {
    return PrepareUploadResponse(
      sessionId: json['sessionId'] as String,
      files: Map<String, String>.from(json['files'] as Map),
    );
  }
}

/// 传输会话状态
enum TransferStatus {
  waiting,
  preparing,
  sending,
  receiving,
  completed,
  failed,
  cancelled,
}

/// 传输会话信息
class TransferSession {
  final String sessionId;
  final String remoteDeviceId;
  final TransferStatus status;
  final Map<String, FileInfo> files;
  final Map<String, String>? fileTokens;
  final String? errorMessage;
  final double progress;

  const TransferSession({
    required this.sessionId,
    required this.remoteDeviceId,
    required this.status,
    required this.files,
    this.fileTokens,
    this.errorMessage,
    this.progress = 0.0,
  });

  TransferSession copyWith({
    String? sessionId,
    String? remoteDeviceId,
    TransferStatus? status,
    Map<String, FileInfo>? files,
    Map<String, String>? fileTokens,
    String? errorMessage,
    double? progress,
  }) {
    return TransferSession(
      sessionId: sessionId ?? this.sessionId,
      remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
      status: status ?? this.status,
      files: files ?? this.files,
      fileTokens: fileTokens ?? this.fileTokens,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
    );
  }
}
