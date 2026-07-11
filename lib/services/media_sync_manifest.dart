import 'dart:io';

import 'package:path/path.dart' as p;

/// Versioned inventory of media files stored below the app's `media/` folder.
class MediaSyncManifest {
  static const int currentVersion = 1;
  static const Set<String> _allowedFolders = {'images', 'videos', 'audios'};

  final Map<String, int> fileSizes;

  const MediaSyncManifest(this.fileSizes);

  static MediaSyncManifest? tryParse(Object? value) {
    if (value is! Map || value['version'] != currentVersion) return null;
    final rawFiles = value['files'];
    if (rawFiles is! Map) return null;

    final files = <String, int>{};
    for (final entry in rawFiles.entries) {
      if (entry.key is! String || entry.value is! int || entry.value < 0) {
        return null;
      }
      final normalized = normalizeRelativePath(entry.key as String);
      if (normalized == null) return null;
      files[normalized] = entry.value as int;
    }
    return MediaSyncManifest(Map.unmodifiable(files));
  }

  static Future<MediaSyncManifest> scan(Directory mediaRoot) async {
    final files = <String, int>{};
    if (!await mediaRoot.exists()) return MediaSyncManifest(files);

    await for (final entity
        in mediaRoot.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = p.relative(entity.path, from: mediaRoot.path);
      final normalized = normalizeRelativePath(relativePath);
      if (normalized == null) continue;
      files[normalized] = await entity.length();
    }
    return MediaSyncManifest(Map.unmodifiable(files));
  }

  Map<String, Object> toJson() => {
        'version': currentVersion,
        'files': fileSizes,
      };

  bool shouldTransfer(String archivePath, int localSize) {
    var relativePath = archivePath.replaceAll('\\', '/');
    if (relativePath.startsWith('media/')) {
      relativePath = relativePath.substring('media/'.length);
    }
    final normalized = normalizeRelativePath(relativePath);
    return normalized == null || fileSizes[normalized] != localSize;
  }

  static String? normalizeRelativePath(String value) {
    final withForwardSlashes = value.replaceAll('\\', '/');
    if (withForwardSlashes.isEmpty || p.posix.isAbsolute(withForwardSlashes)) {
      return null;
    }
    final normalized = p.posix.normalize(withForwardSlashes);
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      return null;
    }
    final segments = p.posix.split(normalized);
    if (segments.length < 2 || !_allowedFolders.contains(segments.first)) {
      return null;
    }
    return normalized;
  }
}
