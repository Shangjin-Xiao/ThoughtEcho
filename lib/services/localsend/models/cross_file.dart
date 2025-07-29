import 'dart:typed_data';
import 'file_type.dart';

/// Simplified CrossFile model for ThoughtEcho
/// Based on LocalSend's CrossFile but adapted for our needs
class CrossFile {
  final String name;
  final int size;
  final FileType fileType;
  final Uint8List? thumbnail;
  final dynamic asset; // Simplified from AssetEntity
  final String? path;
  final List<int>? bytes;
  final DateTime? lastModified;
  final DateTime? lastAccessed;

  const CrossFile({
    required this.name,
    required this.size,
    required this.fileType,
    this.thumbnail,
    this.asset,
    this.path,
    this.bytes,
    this.lastModified,
    this.lastAccessed,
  });

  @override
  String toString() {
    return 'CrossFile(name: $name, size: $size, fileType: $fileType, path: $path, bytes: ${bytes?.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CrossFile &&
        other.name == name &&
        other.size == size &&
        other.fileType == fileType &&
        other.path == path;
  }

  @override
  int get hashCode {
    return Object.hash(name, size, fileType, path);
  }
}
