/// Web send file model
import 'dart:typed_data';
import '../../../dto/file_dto.dart';

class WebSendFile {
  final FileDto file;
  final String? asset;
  final String? path;
  final Uint8List? bytes;

  const WebSendFile({
    required this.file,
    this.asset,
    this.path,
    this.bytes,
  });

  WebSendFile copyWith({
    FileDto? file,
    String? asset,
    String? path,
    Uint8List? bytes,
  }) {
    return WebSendFile(
      file: file ?? this.file,
      asset: asset ?? this.asset,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
    );
  }
}