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

  @override
  String toString() {
    final rebased =
        rebasedPath != null && rebasedPath != path ? ', rebased: $rebasedPath' : '';
    return 'MissingMediaFileException: media file not found: $path$rebased';
  }
}

/// Reports missing media files. Each path goes to Sentry once per session at
/// warning level, with the path attached, instead of being reported again as a
/// generic error on every list rebuild.
class MissingMediaFileReporter {
  MissingMediaFileReporter._();

  static final Set<String> _reportedPaths = <String>{};

  /// Returns true if [error] is a missing-media exception (and has been handled).
  static bool handle(Object error, {StackTrace? stackTrace}) {
    if (error is! MissingMediaFileException) return false;
    if (!_reportedPaths.add(error.path)) return true;
    if (_reportedPaths.length > 500) {
      _reportedPaths.remove(_reportedPaths.first);
    }

    logWarning(error.toString(), source: 'MissingMediaFile');
    if (Sentry.isEnabled) {
      Sentry.captureMessage(
        'Missing media file referenced by note',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setContexts('missing_media', {
            'path': error.path,
            if (error.rebasedPath != null) 'rebased_path': error.rebasedPath,
            if (error.cause != null) 'cause': error.cause.toString(),
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
    } catch (_) {
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
        ErrorDescription('Path: ${file.path}'),
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
          final resolved = MediaPathResolver.resolveToLocal(originalPath, appPath);
          if (resolved != originalPath) {
            rebasedPath = resolved;
            final candidate = File(resolved);
            if (await candidate.exists()) {
              target = candidate;
            }
          }
        }
        if (identical(target, key.file)) {
          throw MissingMediaFileException(originalPath, rebasedPath: rebasedPath);
        }
      }

      final int lengthInBytes = await target.length();
      if (lengthInBytes == 0) {
        PaintingBinding.instance.imageCache.evict(key);
        throw StateError('$originalPath is empty and cannot be loaded as an image.');
      }
      final buffer = await ui.ImmutableBuffer.fromFilePath(target.path);
      return decode(buffer);
    } on PathNotFoundException catch (e) {
      // The file was deleted between the exists check and the read.
      PaintingBinding.instance.imageCache.evict(key);
      throw MissingMediaFileException(
        originalPath,
        rebasedPath: rebasedPath,
        cause: e,
      );
    } on MissingMediaFileException {
      // Evict so the next attempt re-checks (the file may have been synced).
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
  }
}
