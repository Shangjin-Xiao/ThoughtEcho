import 'package:collection/collection.dart';
import 'package:mime/mime.dart';
import 'file_type.dart';

class FileMetadata {
  final DateTime? lastModified;
  final DateTime? lastAccessed;

  const FileMetadata({required this.lastModified, required this.lastAccessed});

  Map<String, dynamic> toJson() {
    return {
      'modified': lastModified?.toIso8601String(),
      'accessed': lastAccessed?.toIso8601String(),
    };
  }

  static FileMetadata fromJson(Map<String, dynamic> json) {
    return FileMetadata(
      lastModified: json['modified'] != null
          ? DateTime.parse(json['modified'] as String)
          : null,
      lastAccessed: json['accessed'] != null
          ? DateTime.parse(json['accessed'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileMetadata &&
        other.lastModified == lastModified &&
        other.lastAccessed == lastAccessed;
  }

  @override
  int get hashCode => Object.hash(lastModified, lastAccessed);
}

/// The file DTO that is sent between server and client.
class FileDto {
  final String id; // unique inside session
  final String fileName;
  final int size;
  final FileType fileType;
  final String? hash;
  final String? preview;
  final FileMetadata? metadata;

  /// This is only used internally to determine if fileType is a mime type or a legacy enum.
  /// It is not serialized.
  final bool legacy;

  const FileDto({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
    required this.hash,
    required this.preview,
    required this.legacy,
    required this.metadata,
  });

  String lookupMime() => lookupMimeType(fileName) ?? 'application/octet-stream';

  FileDto copyWith({
    String? id,
    String? fileName,
    int? size,
    FileType? fileType,
    String? hash,
    String? preview,
    bool? legacy,
    FileMetadata? metadata,
  }) {
    return FileDto(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      size: size ?? this.size,
      fileType: fileType ?? this.fileType,
      hash: hash ?? this.hash,
      preview: preview ?? this.preview,
      legacy: legacy ?? this.legacy,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'size': size,
      'fileType': legacy ? fileType.name : lookupMime(),
      if (hash != null) 'hash': hash,
      if (preview != null) 'preview': preview,
      if (metadata != null) 'metadata': metadata!.toJson(),
    };
  }

  static FileDto fromJson(Map<String, dynamic> map) {
    final String rawFileType = map['fileType'] as String;
    final FileType fileType;
    if (rawFileType.contains('/')) {
      // parse mime
      fileType = decodeFromMime(rawFileType);
    } else {
      // parse legacy enum to internal internal enum
      fileType =
          FileType.values.firstWhereOrNull((e) => e.name == rawFileType) ??
          FileType.other;
    }

    return FileDto(
      id: map['id'] as String,
      fileName: map['fileName'] as String,
      size: map['size'] as int,
      fileType: fileType,
      hash: map['hash'] as String?,
      preview: map['preview'] as String?,
      legacy: false,
      metadata: switch (map['metadata']) {
        Map<String, dynamic> metadata => FileMetadata.fromJson(metadata),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileDto &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fileName == other.fileName &&
          size == other.size &&
          fileType == other.fileType &&
          hash == other.hash &&
          preview == other.preview &&
          legacy == other.legacy;

  @override
  int get hashCode =>
      Object.hash(id, fileName, size, fileType, hash, preview, legacy);
}

FileType decodeFromMime(String mime) {
  if (mime.startsWith('image/')) {
    return FileType.image;
  } else if (mime.startsWith('video/')) {
    return FileType.video;
  } else if (mime == 'application/pdf') {
    return FileType.pdf;
  } else if (mime.startsWith('text/')) {
    return FileType.text;
  } else if (mime == 'application/vnd.android.package-archive') {
    return FileType.apk;
  } else {
    return FileType.other;
  }
}
