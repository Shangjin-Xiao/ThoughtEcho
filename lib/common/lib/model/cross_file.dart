/// Cross file model for LocalSend integration
import 'dart:typed_data';
import 'file_type.dart';

class CrossFile {
  final String name;
  final String path;
  final int size;
  final Uint8List? bytes;
  final String? mimeType;
  final DateTime? lastModified;
  final DateTime? lastAccessed;
  final String? asset;

  const CrossFile({
    required this.name,
    required this.path,
    required this.size,
    this.bytes,
    this.mimeType,
    this.lastModified,
    this.lastAccessed,
    this.asset,
  });

  FileType get fileType {
    if (name.toLowerCase().endsWith('.txt')) return FileType.text;
    if (mimeType?.startsWith('image/') == true) return FileType.image;
    if (mimeType?.startsWith('video/') == true) return FileType.video;
    if (mimeType?.startsWith('audio/') == true) return FileType.audio;
    return FileType.other;
  }
}