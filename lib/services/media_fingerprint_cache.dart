import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';

/// Cached cryptographic fingerprint and last-synced baseline for a local media file.
class MediaFingerprintEntry {
  static final RegExp _sha256HexPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _md5HexPattern = RegExp(r'^[0-9a-fA-F]{32}$');

  const MediaFingerprintEntry({
    required this.fileSize,
    required this.lastModifiedEpochMs,
    required this.sha256,
    this.md5,
    this.syncedSha256,
    this.syncedRemoteEtag,
  });

  final int fileSize;
  final int lastModifiedEpochMs;
  final String sha256;
  final String? md5;
  final String? syncedSha256;
  final String? syncedRemoteEtag;

  /// Creates a copy with updated fields; set [clearSyncedRemoteEtag] to drop
  /// a previously recorded ETag (for example, when a server switches to weak ETags).
  MediaFingerprintEntry copyWith({
    int? fileSize,
    int? lastModifiedEpochMs,
    String? sha256,
    String? md5,
    String? syncedSha256,
    String? syncedRemoteEtag,
    bool clearSyncedRemoteEtag = false,
  }) {
    return MediaFingerprintEntry(
      fileSize: fileSize ?? this.fileSize,
      lastModifiedEpochMs: lastModifiedEpochMs ?? this.lastModifiedEpochMs,
      sha256: sha256 ?? this.sha256,
      md5: md5 ?? this.md5,
      syncedSha256: syncedSha256 ?? this.syncedSha256,
      syncedRemoteEtag: clearSyncedRemoteEtag
          ? null
          : (syncedRemoteEtag ?? this.syncedRemoteEtag),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fileSize': fileSize,
      'lastModifiedEpochMs': lastModifiedEpochMs,
      'sha256': sha256,
      if (md5 != null) 'md5': md5,
      if (syncedSha256 != null) 'syncedSha256': syncedSha256,
      if (syncedRemoteEtag != null) 'syncedRemoteEtag': syncedRemoteEtag,
    };
  }

  factory MediaFingerprintEntry.fromJson(Map<String, dynamic> json) {
    final fileSize = json['fileSize'];
    if (fileSize is! int || fileSize < 0) {
      throw const FormatException('Invalid fileSize in MediaFingerprintEntry');
    }

    final lastModifiedEpochMs = json['lastModifiedEpochMs'];
    if (lastModifiedEpochMs is! int) {
      throw const FormatException(
        'Invalid lastModifiedEpochMs in MediaFingerprintEntry',
      );
    }

    final sha256 = _requireHexHash(json['sha256'], _sha256HexPattern, 'sha256');
    final md5 = _optionalHexHash(json['md5'], _md5HexPattern, 'md5');
    final syncedSha256 = _optionalHexHash(
      json['syncedSha256'],
      _sha256HexPattern,
      'syncedSha256',
    );

    final rawSyncedRemoteEtag = json['syncedRemoteEtag'];
    if (rawSyncedRemoteEtag != null && rawSyncedRemoteEtag is! String) {
      throw const FormatException(
        'Invalid syncedRemoteEtag in MediaFingerprintEntry',
      );
    }

    return MediaFingerprintEntry(
      fileSize: fileSize,
      lastModifiedEpochMs: lastModifiedEpochMs,
      sha256: sha256,
      md5: md5,
      syncedSha256: syncedSha256,
      syncedRemoteEtag: rawSyncedRemoteEtag as String?,
    );
  }

  static String _requireHexHash(Object? raw, RegExp pattern, String fieldName) {
    if (raw is! String || !pattern.hasMatch(raw)) {
      throw FormatException('Invalid $fieldName in MediaFingerprintEntry');
    }
    return raw.toLowerCase();
  }

  static String? _optionalHexHash(
    Object? raw,
    RegExp pattern,
    String fieldName,
  ) {
    if (raw == null) return null;
    return _requireHexHash(raw, pattern, fieldName);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaFingerprintEntry &&
        other.fileSize == fileSize &&
        other.lastModifiedEpochMs == lastModifiedEpochMs &&
        other.sha256 == sha256 &&
        other.md5 == md5 &&
        other.syncedSha256 == syncedSha256 &&
        other.syncedRemoteEtag == syncedRemoteEtag;
  }

  @override
  int get hashCode => Object.hash(
        fileSize,
        lastModifiedEpochMs,
        sha256,
        md5,
        syncedSha256,
        syncedRemoteEtag,
      );
}

/// Persistent JSON-backed cache mapping media relative paths to file stat &
/// streaming cryptographic fingerprints for WebDAV incremental media sync.
class MediaFingerprintCache {
  static const String defaultCacheFileName =
      'webdav_media_fingerprint_cache.json';
  static const int _cacheFormatVersion = 1;
  static const String _logSource = 'MediaFingerprintCache';

  MediaFingerprintCache({File? cacheFile, Directory? directory})
      : _cacheFile = cacheFile,
        _directory = directory;

  final File? _cacheFile;
  final Directory? _directory;
  File? _resolvedFile;

  final Map<String, MediaFingerprintEntry> _entries =
      <String, MediaFingerprintEntry>{};
  bool _isDirty = false;

  @visibleForTesting
  int hashComputeCount = 0;

  @visibleForTesting
  int sha256ComputeCount = 0;

  @visibleForTesting
  int md5ComputeCount = 0;

  bool get isDirty => _isDirty;

  int get length => _entries.length;

  /// Returns whether [raw] uses HTTP weak ETag syntax (`W/"..."` / `w/"..."`).
  static bool isWeakEtag(String? raw) {
    if (raw == null) return false;
    final trimmed = raw.trim();
    return trimmed.startsWith('W/') || trimmed.startsWith('w/');
  }

  /// Strips surrounding quotes from a strong ETag, returning `null` for
  /// `null`, empty strings, or weak ETags.
  static String? cleanStrongEtag(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim();
    if (cleaned.isEmpty || isWeakEtag(cleaned)) return null;
    if (cleaned.length >= 2 &&
        cleaned.startsWith('"') &&
        cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _normalizePath(String relativePath) =>
      relativePath.replaceAll('\\', '/');

  Future<File> _resolveTargetFile() async {
    if (_resolvedFile != null) return _resolvedFile!;
    if (_cacheFile != null) {
      _resolvedFile = _cacheFile;
    } else if (_directory != null) {
      _resolvedFile = File(p.join(_directory.path, defaultCacheFileName));
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _resolvedFile = File(p.join(appDir.path, defaultCacheFileName));
    }
    return _resolvedFile!;
  }

  /// Loads cached entries from disk. Missing files initialize an empty clean
  /// cache; malformed JSON resets the cache and marks it dirty so the next
  /// [save] heals the file.
  Future<void> load() async {
    final target = await _resolveTargetFile();
    if (!await target.exists()) {
      _entries.clear();
      _isDirty = false;
      return;
    }

    try {
      final content = await target.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('顶层 JSON 结构不是对象');
      }

      final Map<dynamic, dynamic> rawEntries;
      if (decoded.containsKey('entries')) {
        if (decoded.containsKey('version') &&
            decoded['version'] != _cacheFormatVersion) {
          throw FormatException('不支持的缓存版本: ${decoded['version']}');
        }
        final entriesNode = decoded['entries'];
        if (entriesNode is! Map) {
          throw const FormatException('entries 字段不是对象');
        }
        rawEntries = entriesNode;
      } else if (decoded.containsKey('version')) {
        throw const FormatException('缺少 entries 字段');
      } else {
        rawEntries = decoded;
      }

      final nextEntries = <String, MediaFingerprintEntry>{};
      var hadMalformedEntry = false;

      for (final pair in rawEntries.entries) {
        final rawKey = pair.key;
        final rawValue = pair.value;
        if (rawKey is! String || rawKey.trim().isEmpty || rawValue is! Map) {
          hadMalformedEntry = true;
          logWarning('跳过损坏的媒体指纹缓存条目 ($rawKey)', source: _logSource);
          continue;
        }

        final normalizedKey = _normalizePath(rawKey);
        try {
          final entry = MediaFingerprintEntry.fromJson(
            Map<String, dynamic>.from(rawValue),
          );
          nextEntries[normalizedKey] = entry;
        } catch (e) {
          hadMalformedEntry = true;
          logWarning('跳过损坏的媒体指纹缓存条目 ($normalizedKey): $e', source: _logSource);
        }
      }

      _entries
        ..clear()
        ..addAll(nextEntries);
      _isDirty = hadMalformedEntry;
    } catch (e) {
      logWarning('媒体指纹缓存损坏，已重置缓存: $e', source: _logSource);
      _entries.clear();
      _isDirty = true;
    }
  }

  /// Atomically persists the cache via a `.tmp` file + rename (with copy/delete
  /// fallback). No-op when clean unless [force] is `true`.
  Future<void> save({bool force = false}) async {
    if (!_isDirty && !force) return;

    final target = await _resolveTargetFile();
    final tmpFile = File('${target.path}.tmp');
    await target.parent.create(recursive: true);

    final encoded = jsonEncode(<String, dynamic>{
      'version': _cacheFormatVersion,
      'entries': _entries.map((key, value) => MapEntry(key, value.toJson())),
    });

    try {
      await tmpFile.writeAsString(encoded, flush: true);
      try {
        await tmpFile.rename(target.path);
      } catch (_) {
        await tmpFile.copy(target.path);
        await tmpFile.delete();
      }
      _isDirty = false;
    } catch (_) {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  MediaFingerprintEntry? peek(String relativePath) {
    return _entries[_normalizePath(relativePath)];
  }

  void putEntry(String relativePath, MediaFingerprintEntry entry) {
    _entries[_normalizePath(relativePath)] = entry;
    _isDirty = true;
  }

  /// Returns a valid cached entry when [fileSize] and [lastModifiedEpochMs]
  /// match, lazily computing MD5 if [requireMd5] is `true` and MD5 is absent.
  /// On miss or stat mismatch, streams SHA-256 (and MD5 when [requireMd5] is
  /// `true`) while preserving any prior sync baseline (`syncedSha256` / ETag).
  Future<MediaFingerprintEntry> getOrCompute(
    String relativePath,
    File file, {
    int? knownSize,
    DateTime? knownLastModified,
    bool requireMd5 = false,
  }) async {
    final key = _normalizePath(relativePath);
    final size = knownSize ?? await file.length();
    final mtimeMs = (knownLastModified ?? await file.lastModified())
        .toUtc()
        .millisecondsSinceEpoch;

    final existing = _entries[key];
    if (existing != null &&
        existing.fileSize == size &&
        existing.lastModifiedEpochMs == mtimeMs) {
      if (requireMd5 && (existing.md5 == null || existing.md5!.isEmpty)) {
        final computedMd5 = await _computeStreamingMd5(file);
        final updated = existing.copyWith(md5: computedMd5);
        _entries[key] = updated;
        _isDirty = true;
        return updated;
      }
      return existing;
    }

    final computedSha256 = await _computeStreamingSha256(file);
    final computedMd5 = requireMd5 ? await _computeStreamingMd5(file) : null;

    final entry = MediaFingerprintEntry(
      fileSize: size,
      lastModifiedEpochMs: mtimeMs,
      sha256: computedSha256,
      md5: computedMd5,
      syncedSha256: existing?.syncedSha256 ?? existing?.sha256,
      syncedRemoteEtag: existing?.syncedRemoteEtag,
    );
    _entries[key] = entry;
    _isDirty = true;
    return entry;
  }

  /// Updates the synced baseline after an upload or download completes,
  /// reusing [knownSha256] when file stat metadata is also provided to skip
  /// redundant streaming hashes.
  Future<MediaFingerprintEntry> markSynced(
    String relativePath,
    File file, {
    String? remoteEtag,
    String? knownSha256,
    String? knownMd5,
    int? knownSize,
    DateTime? knownLastModified,
  }) async {
    final key = _normalizePath(relativePath);
    final strongEtag = cleanStrongEtag(remoteEtag);

    final MediaFingerprintEntry baseEntry;
    if (knownSha256 != null) {
      final size = knownSize ?? await file.length();
      final mtimeMs = (knownLastModified ?? await file.lastModified())
          .toUtc()
          .millisecondsSinceEpoch;
      final existing = _entries[key];
      final normalizedSha256 = knownSha256.toLowerCase();
      final preservedMd5 = existing != null &&
              existing.fileSize == size &&
              existing.lastModifiedEpochMs == mtimeMs &&
              existing.sha256 == normalizedSha256
          ? existing.md5
          : null;
      baseEntry = MediaFingerprintEntry(
        fileSize: size,
        lastModifiedEpochMs: mtimeMs,
        sha256: normalizedSha256,
        md5: knownMd5?.toLowerCase() ?? preservedMd5,
      );
    } else {
      final current = await getOrCompute(
        key,
        file,
        knownSize: knownSize,
        knownLastModified: knownLastModified,
      );
      baseEntry = knownMd5 != null
          ? current.copyWith(md5: knownMd5.toLowerCase())
          : current;
    }

    final syncedEntry = baseEntry.copyWith(
      syncedSha256: baseEntry.sha256,
      syncedRemoteEtag: strongEtag,
      clearSyncedRemoteEtag: strongEtag == null,
    );
    _entries[key] = syncedEntry;
    _isDirty = true;
    return syncedEntry;
  }

  /// Removes cached entries whose normalized paths are absent from
  /// [existingRelativePaths], returning the number of removed entries.
  int pruneMissingFiles(Iterable<String> existingRelativePaths) {
    final existingSet = existingRelativePaths.map(_normalizePath).toSet();
    final before = _entries.length;
    _entries.removeWhere((key, _) => !existingSet.contains(key));
    final removed = before - _entries.length;
    if (removed > 0) {
      _isDirty = true;
    }
    return removed;
  }

  Future<String> _computeStreamingSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    hashComputeCount++;
    sha256ComputeCount++;
    return digest.toString().toLowerCase();
  }

  Future<String> _computeStreamingMd5(File file) async {
    final digest = await md5.bind(file.openRead()).first;
    hashComputeCount++;
    md5ComputeCount++;
    return digest.toString().toLowerCase();
  }
}
