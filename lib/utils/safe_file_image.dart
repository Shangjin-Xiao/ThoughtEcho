import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_logger.dart';
import 'media_path_resolver.dart';

/// Thrown when a note's media file can't be found on disk.
///
/// The note's Delta still points to a file under `media/` that no longer
/// exists (deleted, never synced, or saved under another device/app container).
/// Unlike the raw `PathNotFoundException`, this exception carries the
/// offending path, and [MissingMediaFileReporter] reports it once per path.
class MissingMediaFileException implements Exception {
  MissingMediaFileException(this.path, {this.rebasedPath, this.cause});

  /// The path recorded in the note.
  final String path;

  /// The path rebased onto this device's documents directory (if different).
  final String? rebasedPath;

  /// The original IO error (if any).
  final Object? cause;

  /// Path with the device-specific prefix removed (e.g. `media/images/a.jpg`).
  /// Use this for logs and reports so usernames and container IDs never leak.
  String get redactedPath => MissingMediaFileReporter.redact(path);

  @override
  String toString() {
    return 'MissingMediaFileException: media file not found: $redactedPath';
  }
}

/// Reports missing media files. Each path goes to Sentry once per session at
/// warning level, with the redacted path attached, instead of being reported
/// again as a generic error on every list rebuild.
class MissingMediaFileReporter {
  MissingMediaFileReporter._();

  /// Max distinct paths reported per session. Once reached, new paths are
  /// only logged locally; already reported paths are never reported again.
  static const int _maxReportedPaths = 500;

  static final Set<String> _reportedPaths = <String>{};
  static bool _capLogged = false;

  /// Removes the device-specific prefix from [path] and keeps only
  /// `media/<subfolder>/<file>` (or just the file name if not recognized).
  static String redact(String path) {
    final tail = MediaPathResolver.mediaRelativeTail(path);
    if (tail != null) return tail;
    final segments = path.split(RegExp(r'[\\/]'));
    return segments.isEmpty ? path : segments.last;
  }

  /// Returns true if [error] is a missing-media exception (already handled).
  static bool handle(Object error, {StackTrace? stackTrace}) {
    if (error is! MissingMediaFileException) return false;
    if (_reportedPaths.contains(error.path)) return true;

    final redactedPath = error.redactedPath;
    if (_reportedPaths.length >= _maxReportedPaths) {
      logDebug(
        'Missing media file (not reported, session cap reached): $redactedPath',
        source: 'MissingMediaFile',
      );
      if (!_capLogged) {
        _capLogged = true;
        logWarning(
          'Missing media report cap ($_maxReportedPaths) reached this session',
          source: 'MissingMediaFile',
        );
      }
      return true;
    }
    _reportedPaths.add(error.path);

    logWarning(error.toString(), source: 'MissingMediaFile');
    if (Sentry.isEnabled) {
      final cause = error.cause;
      Sentry.captureMessage(
        'Missing media file referenced by note',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setContexts('missing_media', {
            'path': redactedPath,
            'rebased': error.rebasedPath != null,
            if (cause != null) 'cause_type': cause.runtimeType.toString(),
            if (cause is FileSystemException)
              'os_error_code': cause.osError?.errorCode,
          });
        },
      );
    }
    return true;
  }
}

/// A [FileImage] that handles missing files: it checks that the file exists
/// asynchronously (never blocking `build`), tries to rebase paths from another
/// device/old iOS container onto this device's `media/` directory, and if
/// the file is still missing throws [MissingMediaFileException] so
/// `errorBuilder` shows the broken-image placeholder.
///
/// The missing file is reported here (deduplicated per path), because an
/// `Image` with an `errorBuilder` consumes the error and it never reaches
/// `FlutterError.onError`.
///
/// Equality/hash are inherited from [FileImage] (`runtimeType` + path + scale).
/// Warmup and rendering both go through `createOptimizedImageProvider`, so
/// cache keys stay identical.
@immutable
class SafeFileImage extends FileImage {
  const SafeFileImage(super.file, {super.scale});

  static String? _appPathCache;

  static Future<String?> _appPath() async {
    if (_appPathCache != null) return _appPathCache;
    try {
      _appPathCache = (await getApplicationDocumentsDirectory()).path;
    } catch (e, stack) {
      logError(
        'Failed to get the documents directory; skipping media path rebase',
        error: e,
        stackTrace: stack,
        source: 'SafeFileImage',
      );
      return null;
    }
    return _appPathCache;
  }

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadSafely(key, decode),
      scale: key.scale,
      debugLabel: key.file.path,
      informationCollector: () => <DiagnosticsNode>[
        ErrorDescription('Path: ${MissingMediaFileReporter.redact(file.path)}'),
      ],
    );
  }

  Future<ui.Codec> _loadSafely(
    FileImage key,
    ImageDecoderCallback decode,
  ) async {
    final originalPath = key.file.path;
    File target = key.file;
    String? rebasedPath;

    try {
      if (!await target.exists()) {
        final appPath = await _appPath();
        if (appPath != null) {
          final resolved = MediaPathResolver.resolveToLocal(
            originalPath,
            appPath,
          );
          if (resolved != originalPath) {
            rebasedPath = resolved;
            final candidate = File(resolved);
            if (await candidate.exists()) {
              target = candidate;
            }
          }
        }
        if (identical(target, key.file)) {
          final missing = MissingMediaFileException(
            originalPath,
            rebasedPath: rebasedPath,
          );
          MissingMediaFileReporter.handle(missing);
          throw missing;
        }
      }

      final int lengthInBytes = await target.length();
      if (lengthInBytes == 0) {
        PaintingBinding.instance.imageCache.evict(key);
        throw StateError(
          '${MissingMediaFileReporter.redact(originalPath)} is empty '
          'and cannot be loaded as an image.',
        );
      }
      final buffer = await ui.ImmutableBuffer.fromFilePath(target.path);
      return decode(buffer);
    } on PathNotFoundException catch (e) {
      // The file was deleted between the exists check and the read.
      PaintingBinding.instance.imageCache.evict(key);
      final missing = MissingMediaFileException(
        originalPath,
        rebasedPath: rebasedPath,
        cause: e,
      );
      MissingMediaFileReporter.handle(missing);
      throw missing;
    } on MissingMediaFileException {
      // Evict so the next attempt re-checks (the file may have been synced).
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
  }
}
