import 'dart:async';
import 'dart:isolate';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class PlatformHelper {
  @visibleForTesting
  static void Function(File lockFile)? debugBeforeLockCreateHook;

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

  /// Reads Android's IANA system timezone (`persist.sys.timezone`) without
  /// requiring an Activity-scoped MethodChannel, so headless WorkManager
  /// isolates can resolve the exact device timezone.
  static Future<String?> readAndroidSystemTimeZone() async {
    if (!Platform.isAndroid ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      final result = await Process.run(
        'getprop',
        const <String>['persist.sys.timezone'],
      ).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) {
        return null;
      }
      final tzId = result.stdout.toString().trim();
      return tzId.isEmpty ? null : tzId;
    } catch (_) {
      return null;
    }
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
  static final Map<String, Future<void>> _crossIsolateLocks =
      <String, Future<void>>{};
  static final Object _heldLocksZoneKey = Object();
  static String? _cachedCrossIsolateLockDir;
  static int _archiveStageSeq = 0;
  static int _staleLockSeq = 0;

  static Future<String> _resolveCrossIsolateLockFilePath(
    String lockName, {
    String? customLockFilePath,
  }) async {
    if (customLockFilePath != null && customLockFilePath.trim().isNotEmpty) {
      return p.normalize(customLockFilePath.trim());
    }
    final sanitized = lockName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    var baseDir = _cachedCrossIsolateLockDir;
    if (baseDir == null) {
      final candidates = <Future<String> Function()>[
        () async => (await getApplicationSupportDirectory()).path,
        () async => (await getApplicationDocumentsDirectory()).path,
        () async => p.join(Directory.systemTemp.path, 'thoughtecho_locks'),
      ];
      for (final resolveCandidate in candidates) {
        try {
          final candidatePath = await resolveCandidate();
          Directory(candidatePath).createSync(recursive: true);
          baseDir = candidatePath;
          break;
        } catch (_) {}
      }
      baseDir ??= Directory.systemTemp.path;
      _cachedCrossIsolateLockDir = baseDir;
    }
    return p.normalize(p.join(baseDir, '$sanitized.lock'));
  }

  static String? _readLockOwnerToken(File file) {
    try {
      if (!file.existsSync()) return null;
      return file.readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }

  static bool _isForeignProcessDefinitelyDead(String token) {
    if (!token.startsWith('v1|')) return false;
    final parts = token.split('|');
    if (parts.length < 3) return false;
    final holderPid = int.tryParse(parts[1]);
    if (holderPid == null || holderPid <= 0 || holderPid == pid) {
      return false;
    }
    if (Platform.isLinux || Platform.isAndroid) {
      try {
        if (Directory('/proc').existsSync()) {
          return !Directory('/proc/$holderPid').existsSync();
        }
      } catch (_) {}
    }
    return false;
  }

  static bool _isRetryableLockCreateError(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (code == null) {
      return true;
    }
    if (Platform.isWindows) {
      // ERROR_FILE_NOT_FOUND (2), ERROR_PATH_NOT_FOUND (3),
      // ERROR_ACCESS_DENIED (5, transient pending-delete on lockfile),
      // ERROR_SHARING_VIOLATION (32), ERROR_FILE_EXISTS (80),
      // ERROR_ALREADY_EXISTS (183).
      return code == 2 ||
          code == 3 ||
          code == 5 ||
          code == 32 ||
          code == 80 ||
          code == 183;
    }
    // POSIX (Android / Linux / iOS / macOS):
    // ENOENT (2), EINTR (4), EAGAIN/EWOULDBLOCK (11 / 35), EEXIST (17).
    // Persistent storage/permission errors such as EPERM (1), EACCES (13),
    // ENOTDIR (20), EISDIR (21), ENFILE (23), EMFILE (24), ENOSPC (28),
    // EROFS (30), ENAMETOOLONG (36), and EDQUOT (122) fail fast.
    return code == 2 || code == 4 || code == 11 || code == 17 || code == 35;
  }

  /// Serializes [action] both across async tasks within the current Isolate and
  /// across concurrent Isolates sharing the app's filesystem via `O_CREAT|O_EXCL`.
  ///
  /// Uses a single canonical lockfile path per [lockName], refreshes heartbeat
  /// timestamps while [action] is live so active holders are never evicted past
  /// [staleLockTimeout], and verifies owner identity before releasing or
  /// evicting any crashed lockfile.
  static Future<T> withCrossIsolateLock<T>(
    String lockName,
    Future<T> Function() action, {
    String? customLockFilePath,
    Duration staleLockTimeout = const Duration(seconds: 60),
    Duration acquireTimeout = const Duration(seconds: 180),
  }) async {
    final lockPath = await _resolveCrossIsolateLockFilePath(
      lockName,
      customLockFilePath: customLockFilePath,
    );
    final heldLocks = Zone.current[_heldLocksZoneKey];
    if (heldLocks is Set<String> && heldLocks.contains(lockPath)) {
      return action();
    }

    final previous = _crossIsolateLocks[lockPath] ?? Future<void>.value();
    final turnCompleter = Completer<void>();
    _crossIsolateLocks[lockPath] = turnCompleter.future;

    try {
      await previous;
    } catch (_) {}

    final lockFile = File(lockPath);
    final ownerSeq = ++_staleLockSeq;
    final ownerToken =
        'v1|$pid|${Isolate.current.hashCode}|${DateTime.now().microsecondsSinceEpoch}|$ownerSeq';
    var lockAcquired = false;
    Timer? heartbeatTimer;
    final effectiveStaleTimeout = staleLockTimeout <= Duration.zero
        ? const Duration(milliseconds: 50)
        : staleLockTimeout;
    final effectiveAcquireTimeout = acquireTimeout <= Duration.zero
        ? const Duration(milliseconds: 10)
        : acquireTimeout;
    final waitWatch = Stopwatch()..start();
    DateTime? observedModified;
    String? observedToken;
    Stopwatch? unchangedLockWatch;
    var attempt = 0;

    try {
      while (!lockAcquired) {
        var createdByCurrentAttempt = false;
        try {
          debugBeforeLockCreateHook?.call(lockFile);
          lockFile.createSync(recursive: true, exclusive: true);
          createdByCurrentAttempt = true;
          lockFile.writeAsStringSync(ownerToken, flush: true);
          lockAcquired = true;
          break;
        } on FileSystemException catch (e) {
          if (createdByCurrentAttempt) {
            try {
              lockFile.deleteSync();
            } catch (_) {}
            rethrow;
          }

          final lockEntityType = FileSystemEntity.typeSync(
            lockFile.path,
            followLinks: false,
          );
          if (lockEntityType == FileSystemEntityType.directory ||
              !_isRetryableLockCreateError(e)) {
            rethrow;
          }

          var evictedStaleLock = false;
          if (lockEntityType != FileSystemEntityType.notFound &&
              lockFile.existsSync()) {
            try {
              final modified = lockFile.statSync().modified;
              final currentToken = _readLockOwnerToken(lockFile);
              if (observedModified != modified ||
                  observedToken != currentToken) {
                observedModified = modified;
                observedToken = currentToken;
                unchangedLockWatch = Stopwatch()..start();
              }
              final ageByWallClock = DateTime.now().difference(modified);
              final ageByMonotonic =
                  unchangedLockWatch?.elapsed ?? Duration.zero;
              final deadForeignPid = currentToken != null &&
                  currentToken.isNotEmpty &&
                  _isForeignProcessDefinitelyDead(currentToken);
              final unrefreshedPastStale = currentToken != null &&
                  currentToken.isNotEmpty &&
                  ageByWallClock > effectiveStaleTimeout &&
                  ageByMonotonic > effectiveStaleTimeout;
              final abandonedEmptyInit =
                  (currentToken == null || currentToken.isEmpty) &&
                      ageByWallClock > effectiveStaleTimeout * 2 &&
                      ageByMonotonic > effectiveStaleTimeout * 2;
              if (deadForeignPid ||
                  unrefreshedPastStale ||
                  abandonedEmptyInit) {
                final latestToken = _readLockOwnerToken(lockFile);
                if (latestToken == currentToken) {
                  final seq = ++_staleLockSeq;
                  final stalePath = '${lockFile.path}.stale.$pid.$seq';
                  try {
                    final moved = lockFile.renameSync(stalePath);
                    final movedToken = _readLockOwnerToken(moved);
                    if (movedToken != null &&
                        movedToken.isNotEmpty &&
                        movedToken != currentToken &&
                        !lockFile.existsSync()) {
                      moved.renameSync(lockFile.path);
                    } else {
                      moved.deleteSync();
                      evictedStaleLock = true;
                    }
                  } catch (_) {}
                }
                observedModified = null;
                observedToken = null;
                unchangedLockWatch = null;
              }
            } catch (_) {}
          } else {
            observedModified = null;
            observedToken = null;
            unchangedLockWatch = null;
            final parentType = FileSystemEntity.typeSync(
              lockFile.parent.path,
              followLinks: false,
            );
            if (parentType != FileSystemEntityType.directory) {
              // Surface persistent parent-directory errors (e.g. parent path
              // occupied by a regular file, permission denied, or disk full)
              // instead of spinning on a path that can never hold a lockfile.
              lockFile.parent.createSync(recursive: true);
            }
          }

          if (waitWatch.elapsed >= effectiveAcquireTimeout) {
            throw FileSystemException(
              'Timed out acquiring cross-isolate lock ($lockName): ${e.message}',
              lockFile.path,
              e.osError,
            );
          }

          final delayMs = (evictedStaleLock && attempt == 0)
              ? 0
              : (attempt == 0
                  ? 1
                  : (attempt < 4 ? 5 : (attempt < 8 ? 10 : 20)));
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
      }

      final heartbeatMs =
          (effectiveStaleTimeout.inMilliseconds ~/ 4).clamp(10, 2000);
      heartbeatTimer = Timer.periodic(
        Duration(milliseconds: heartbeatMs),
        (_) {
          try {
            if (_readLockOwnerToken(lockFile) == ownerToken) {
              lockFile.setLastModifiedSync(DateTime.now());
            }
          } catch (_) {}
        },
      );

      final nextHeld = <String>{
        if (heldLocks is Set<String>) ...heldLocks,
        lockPath,
      };
      return await runZoned(
        action,
        zoneValues: <Object?, Object?>{_heldLocksZoneKey: nextHeld},
      );
    } finally {
      heartbeatTimer?.cancel();
      if (lockAcquired) {
        try {
          if (_readLockOwnerToken(lockFile) == ownerToken) {
            try {
              lockFile.setLastModifiedSync(DateTime.now());
            } catch (_) {}
            if (_readLockOwnerToken(lockFile) == ownerToken) {
              lockFile.deleteSync();
            }
          }
        } catch (_) {}
      }
      if (identical(_crossIsolateLocks[lockPath], turnCompleter.future)) {
        _crossIsolateLocks.remove(lockPath);
      }
      turnCompleter.complete();
    }
  }

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

  static Future<bool> _deleteStagingFiles(
    String mmkvFilePath, {
    required bool syncIo,
  }) async {
    final parentDir = File(mmkvFilePath).parent;
    final dirExists =
        syncIo ? parentDir.existsSync() : await parentDir.exists();
    if (!dirExists) {
      return false;
    }
    final baseName = p.basename(mmkvFilePath);
    final mainPrefix = '$baseName.archiving.';
    final crcPrefix = '$baseName.crc.archiving.';
    var deletedAny = false;
    final entities = syncIo
        ? parentDir.listSync(followLinks: false)
        : await parentDir.list(followLinks: false).toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(mainPrefix) || name.startsWith(crcPrefix)) {
        if (await _deleteIfExists(entity, syncIo: syncIo)) {
          deletedAny = true;
        }
      }
    }
    return deletedAny;
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
      if (!lockAcquired) {
        throw FileSystemException(
          'Could not acquire MMKV migration lock',
          lockFile.path,
        );
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
            if (await _deleteStagingFiles(mmkvFilePath, syncIo: syncIo)) {
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
