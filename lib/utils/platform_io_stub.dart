/// Platform stub implementations for non-IO environments (e.g., Web).
///
/// This file provides stub implementations of `dart:io` classes that are
/// used when the application runs on platforms that don't support `dart:io`,
/// such as the web. All methods either return safe defaults or throw
/// [UnsupportedError] to indicate the operation is not available.
library;

/// Stub implementation of [Platform] for non-IO environments.
///
/// Provides platform detection methods that always return `false` since
/// the actual platform cannot be determined without `dart:io`.
class Platform {
  static bool get isWindows => false;
  static bool get isAndroid => false;
}

/// Stub implementation of the `exit` function for non-IO environments.
///
/// Always throws [UnsupportedError] since process termination is not
/// supported on platforms without `dart:io` (e.g., Web).
Never exit(int code) {
  throw UnsupportedError('exit is not supported on this platform');
}

/// Stub implementation of [Directory] for non-IO environments.
///
/// Provides a minimal interface compatible with `dart:io` Directory,
/// but all operations return safe defaults (e.g., `exists()` returns `false`).
class Directory {
  /// Creates a [Directory] with the given [path].
  Directory(this.path);

  /// The path of this directory.
  final String path;

  /// Stub implementation that returns this directory without creating anything.
  Future<Directory> create({bool recursive = false}) async {
    return this;
  }

  /// Stub implementation that always returns `false`.
  Future<bool> exists() async {
    return false;
  }

  /// Stub implementation that always returns `false`.
  bool existsSync() {
    return false;
  }
}

/// Stub implementation of [File] for non-IO environments.
///
/// Provides a minimal interface compatible with `dart:io` File,
/// but all operations return safe defaults (e.g., `exists()` returns `false`).
class File {
  /// Creates a [File] with the given [path].
  File(this.path);

  /// The path of this file.
  final String path;

  /// Stub implementation that always returns `false`.
  Future<bool> exists() async {
    return false;
  }

  /// Stub implementation that always returns `false`.
  bool existsSync() {
    return false;
  }

  /// Stub implementation that returns a new [File] with [newPath].
  Future<File> copy(String newPath) async {
    return File(newPath);
  }
}
