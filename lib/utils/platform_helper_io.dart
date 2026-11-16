import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/utils/app_logger.dart';

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
      // In Flutter test environments (testWidgets with FakeAsync), async file IO
      // will stall because FakeAsync does not pump the native OS file event loop.
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        if (!file.existsSync()) {
          return null;
        }
        return file.readAsBytesSync();
      }
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (e, stack) {
      AppLogger.w(
        'readFileBytesIfExists failed for $filePath',
        error: e,
        stackTrace: stack,
        source: 'PlatformHelper',
      );
      return null;
    }
  }

  static final Map<String, Future<void>> _archiveLocks =
      <String, Future<void>>{};
  static int _archiveStageSeq = 0;

  static Future<bool> _deleteIfExists(File file, {required bool syncIo}) async {
    if (syncIo) {
      if (!file.existsSync()) {
        return false;
      }
      file.deleteSync();
      return true;
    }
    if (!await file.exists()) {
      return false;
    }
    await file.delete();
    return true;
  }

  static Future<bool> _archiveSiblingFile(
    String srcPath,
    String destPath, {
    required bool syncIo,
  }) async {
    final srcFile = File(srcPath);
    final srcExists = syncIo ? srcFile.existsSync() : await srcFile.exists();
    if (!srcExists) {
      return false;
    }

    // Atomically claim the source file via a unique staging name before touching
    // any existing destination backup, so concurrent isolates can never delete
    // another isolate's newly archived `.migrated.bak` when the source is gone.
    final seq = ++_archiveStageSeq;
    final stagePath = '$srcPath.archiving.$pid.$seq';
    final File stagedFile;
    try {
      stagedFile = syncIo
          ? srcFile.renameSync(stagePath)
          : await srcFile.rename(stagePath);
    } on PathNotFoundException {
      return false;
    }

    try {
      await _deleteIfExists(File(destPath), syncIo: syncIo);
      if (syncIo) {
        stagedFile.renameSync(destPath);
      } else {
        await stagedFile.rename(destPath);
      }
      return true;
    } catch (e) {
      // Best-effort restore of the staged source if moving into destPath failed.
      try {
        final stillStaged =
            syncIo ? stagedFile.existsSync() : await stagedFile.exists();
        final srcBackExists =
            syncIo ? srcFile.existsSync() : await srcFile.exists();
        if (stillStaged && !srcBackExists) {
          if (syncIo) {
            stagedFile.renameSync(srcPath);
          } else {
            await stagedFile.rename(srcPath);
          }
        }
      } catch (_) {}
      rethrow;
    }
  }

  static Future<T> _withArchiveFileLock<T>(
    String basePath, {
    required bool syncIo,
    required Future<T> Function() action,
  }) async {
    final normalized = p.normalize(basePath);
    final previous = _archiveLocks[normalized] ?? Future<void>.value();
    final turnCompleter = Completer<void>();
    _archiveLocks[normalized] = turnCompleter.future;

    try {
      await previous;
    } catch (_) {}

    final lockFile = File('$normalized.migration.lock');
    var lockAcquired = false;
    try {
      for (var attempt = 0; attempt < 50; attempt++) {
        try {
          lockFile.createSync(recursive: true, exclusive: true);
          lockAcquired = true;
          break;
        } on FileSystemException {
          try {
            if (lockFile.existsSync()) {
              final modified = lockFile.statSync().modified;
              if (DateTime.now().difference(modified) >
                  const Duration(seconds: 30)) {
                lockFile.deleteSync();
                continue;
              }
            }
          } catch (_) {}
          if (syncIo) {
            // In FLUTTER_TEST FakeAsync, avoid unbounded async timer stalls.
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      return await action();
    } finally {
      if (lockAcquired) {
        try {
          if (lockFile.existsSync()) {
            lockFile.deleteSync();
          }
        } catch (_) {}
      }
      if (identical(_archiveLocks[normalized], turnCompleter.future)) {
        _archiveLocks.remove(normalized);
      }
      turnCompleter.complete();
    }
  }

  /// Archives a migrated `mmkv.default` file (and its `.crc` sibling) to
  /// `*.migrated.bak`, or wipes all plaintext copies when [wipePlaintext] is true.
  static Future<bool> archiveOrWipeMmkvFile(
    String mmkvFilePath, {
    required bool wipePlaintext,
  }) async {
    try {
      final syncIo = Platform.environment.containsKey('FLUTTER_TEST');
      final basePath = mmkvFilePath.endsWith('.migrated.bak')
          ? mmkvFilePath.substring(
              0,
              mmkvFilePath.length - '.migrated.bak'.length,
            )
          : mmkvFilePath;

      return await _withArchiveFileLock<bool>(
        basePath,
        syncIo: syncIo,
        action: () async {
          if (mmkvFilePath.endsWith('.migrated.bak')) {
            if (!wipePlaintext) {
              return false;
            }
            var anyDeleted = false;
            if (await _deleteIfExists(File(mmkvFilePath), syncIo: syncIo)) {
              anyDeleted = true;
            }
            if (await _deleteIfExists(
              File('$mmkvFilePath.crc'),
              syncIo: syncIo,
            )) {
              anyDeleted = true;
            }
            return anyDeleted;
          }

          if (wipePlaintext) {
            var anyDeleted = false;
            if (await _deleteIfExists(File(mmkvFilePath), syncIo: syncIo)) {
              anyDeleted = true;
            }
            if (await _deleteIfExists(
              File('$mmkvFilePath.crc'),
              syncIo: syncIo,
            )) {
              anyDeleted = true;
            }
            if (await _deleteIfExists(
              File('$mmkvFilePath.migrated.bak'),
              syncIo: syncIo,
            )) {
              anyDeleted = true;
            }
            if (await _deleteIfExists(
              File('$mmkvFilePath.migrated.bak.crc'),
              syncIo: syncIo,
            )) {
              anyDeleted = true;
            }
            return anyDeleted;
          }

          final archivedMain = await _archiveSiblingFile(
            mmkvFilePath,
            '$mmkvFilePath.migrated.bak',
            syncIo: syncIo,
          );
          if (!archivedMain) {
            return false;
          }
          await _archiveSiblingFile(
            '$mmkvFilePath.crc',
            '$mmkvFilePath.migrated.bak.crc',
            syncIo: syncIo,
          );
          return true;
        },
      );
    } catch (e, stack) {
      AppLogger.w(
        'archiveOrWipeMmkvFile failed for $mmkvFilePath',
        error: e,
        stackTrace: stack,
        source: 'PlatformHelper',
      );
      return false;
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

    const sqliteMagic = 'SQLite format 3\x00';

    for (final dbPath in candidates) {
      try {
        final file = File(dbPath);
        if (file.existsSync()) {
          final stat = file.statSync();
          // Empty or uninitialized SQLite file is <= 4096 bytes; a populated
          // ThoughtEcho database with tables/migrations is > 8192 bytes.
          if (stat.size > 8192) {
            final raf = file.openSync(mode: FileMode.read);
            try {
              final header = raf.readSync(16);
              if (header.length >= 16) {
                var matchesHeader = true;
                for (var i = 0; i < 16; i++) {
                  if (header[i] != sqliteMagic.codeUnitAt(i)) {
                    matchesHeader = false;
                    break;
                  }
                }
                if (matchesHeader) {
                  return true;
                }
              }
            } finally {
              raf.closeSync();
            }
          }
        }
      } catch (_) {}
    }

    return false;
  }
}
