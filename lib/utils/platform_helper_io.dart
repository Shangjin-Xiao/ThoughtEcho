import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PlatformHelper {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;

  /// True when the current Dart VM / app process uses 64-bit pointers (8 bytes).
  ///
  /// Unlike `getprop ro.product.cpu.abi`, this reflects the actual process ABI
  /// (so a 32-bit APK installed on a 64-bit Android kernel is accurately
  /// reported as 32-bit) and completes in 0ns without spawning a subprocess.
  static bool get is64BitProcess => ffi.sizeOf<ffi.IntPtr>() == 8;

  /// Process pointer width in bits (`64` or `32`).
  static int get pointerBits => ffi.sizeOf<ffi.IntPtr>() * 8;

  static Future<String> getCpuArchitecture() async {
    return is64BitProcess ? '64-bit' : '32-bit';
  }

  /// Reads raw bytes from [filePath] if the file exists on disk, or returns `null`.
  static Future<Uint8List?> readFileBytesIfExists(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Resolves candidate `mmkv.default` file paths in priority order:
  /// 1. `<ApplicationDocumentsDirectory>/mmkv/mmkv.default` (Flutter `MMKV.initialize()` rootDir)
  /// 2. `<ApplicationSupportDirectory>/mmkv/mmkv.default` (Android `files/mmkv/mmkv.default`)
  static Future<List<String>> resolveCandidateMmkvFiles({
    List<String>? customPaths,
  }) async {
    if (customPaths != null) {
      return List<String>.unmodifiable(customPaths);
    }
    final candidates = <String>[];
    void addCandidate(String path) {
      final normalized = p.normalize(path);
      if (!candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      addCandidate(p.join(docsDir.path, 'mmkv', 'mmkv.default'));
      if (Platform.isAndroid) {
        addCandidate(
          p.join(p.dirname(docsDir.path), 'files', 'mmkv', 'mmkv.default'),
        );
      }
    } catch (_) {
      // Ignore if path_provider is unavailable in unit test environment
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      addCandidate(p.join(supportDir.path, 'mmkv', 'mmkv.default'));
    } catch (_) {
      // Ignore if path_provider is unavailable
    }

    return candidates;
  }

  /// Heuristic check for whether a populated `thoughtecho.db` SQLite database
  /// exists on disk (used as Channel 3 self-healing for `app_installed_v2` and
  /// `hasCompletedOnboarding` if KV storage was lost).
  static Future<bool> hasPopulatedThoughtEchoDatabase({
    List<String>? customDbPaths,
    String? customDataDirectoryPath,
  }) async {
    final candidates = <String>[];
    if (customDbPaths != null) {
      candidates.addAll(customDbPaths);
    } else {
      if (customDataDirectoryPath != null &&
          customDataDirectoryPath.trim().isNotEmpty) {
        final dir = customDataDirectoryPath.trim();
        candidates.add(p.join(dir, 'databases', 'thoughtecho.db'));
        candidates.add(p.join(dir, 'thoughtecho.db'));
      }
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        candidates.add(p.join(docsDir.path, 'databases', 'thoughtecho.db'));
        candidates.add(
          p.join(docsDir.path, 'ThoughtEcho', 'databases', 'thoughtecho.db'),
        );
        candidates.add(p.join(docsDir.path, 'thoughtecho.db'));
        candidates.add(
          p.join(p.dirname(docsDir.path), 'databases', 'thoughtecho.db'),
        );
      } catch (_) {}
      try {
        final supportDir = await getApplicationSupportDirectory();
        candidates.add(p.join(supportDir.path, 'databases', 'thoughtecho.db'));
        candidates.add(p.join(supportDir.path, 'thoughtecho.db'));
      } catch (_) {}
    }

    for (final dbPath in candidates) {
      try {
        final file = File(dbPath);
        if (await file.exists()) {
          final stat = await file.stat();
          // Empty or uninitialized SQLite file is <= 4096 bytes; a populated
          // ThoughtEcho database with tables/migrations is > 8192 bytes.
          if (stat.size > 8192) {
            return true;
          }
        }
      } catch (_) {}
    }
    return false;
  }
}
