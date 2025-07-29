import 'dart:typed_data';
import 'file_dto.dart';
import 'file_status.dart';

class SendingFile {
  final FileDto file;
  final FileStatus status;
  final String? token;
  final Uint8List? thumbnail;
  final dynamic asset; // for thumbnails - simplified from AssetEntity
  final String? path; // android, iOS, desktop
  final List<int>? bytes; // web
  final String? errorMessage; // when status == failed

  const SendingFile({
    required this.file,
    required this.status,
    required this.token,
    required this.thumbnail,
    required this.asset,
    required this.path,
    required this.bytes,
    required this.errorMessage,
  });

  SendingFile copyWith({
    FileDto? file,
    FileStatus? status,
    String? token,
    Uint8List? thumbnail,
    dynamic asset,
    String? path,
    List<int>? bytes,
    String? errorMessage,
  }) {
    return SendingFile(
      file: file ?? this.file,
      status: status ?? this.status,
      token: token ?? this.token,
      thumbnail: thumbnail ?? this.thumbnail,
      asset: asset ?? this.asset,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Custom toString() to avoid printing the bytes.
  @override
  String toString() {
    return 'SendingFile(file: $file, status: $status, token: $token, thumbnail: ${thumbnail != null ? thumbnail!.length : 'null'}, asset: $asset, path: $path, bytes: ${bytes != null ? bytes!.length : 'null'}, errorMessage: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SendingFile &&
        other.file == file &&
        other.status == status &&
        other.token == token &&
        other.path == path &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(file, status, token, path, errorMessage);
  }
}
