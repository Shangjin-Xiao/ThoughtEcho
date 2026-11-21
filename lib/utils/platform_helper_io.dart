import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/utils/app_logger.dart';

typedef _PosixMallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr size);
typedef _PosixMallocDart = ffi.Pointer<ffi.Void> Function(int size);
typedef _PosixFreeNative = ffi.Void Function(ffi.Pointer<ffi.Void> ptr);
typedef _PosixFreeDart = void Function(ffi.Pointer<ffi.Void> ptr);
typedef _PosixOpen2Native = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Int32 oflag,
);
typedef _PosixOpen2Dart = int Function(ffi.Pointer<ffi.Uint8> path, int oflag);
typedef _PosixFlockNative = ffi.Int32 Function(ffi.Int32 fd, ffi.Int32 op);
typedef _PosixFlockDart = int Function(int fd, int op);
typedef _PosixCloseNative = ffi.Int32 Function(ffi.Int32 fd);
typedef _PosixCloseDart = int Function(int fd);
typedef _PosixFdopenNative = ffi.Pointer<ffi.Void> Function(
  ffi.Int32 fd,
  ffi.Pointer<ffi.Uint8> mode,
);
typedef _PosixFdopenDart = ffi.Pointer<ffi.Void> Function(
  int fd,
  ffi.Pointer<ffi.Uint8> mode,
);
typedef _PosixFcloseNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> stream);
typedef _PosixFcloseDart = int Function(ffi.Pointer<ffi.Void> stream);

/// Guard token owning an exclusively locked POSIX `FILE*` / `fd`.
///
/// Attached to [_PosixFlockBindings._fcloseFinalizer] so that if a background
/// `FlutterEngine` / Dart `IsolateGroup` is torn down abruptly (e.g. Android
/// `WorkManager` `onStopped()` -> `stopEngine`) without running Dart `finally`
/// blocks, the VM's isolate-group shutdown runs `fclose(stream)` natively,
/// closing the underlying descriptor and releasing the `flock` lock in-process.
final class _PosixLockedFileHandle implements ffi.Finalizable {
  _PosixLockedFileHandle._(this.fd, this._stream);

  final int fd;
  final ffi.Pointer<ffi.Void> _stream;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _PosixFlockBindings.instance._detachFinalizer(this);
    try {
      _PosixFlockBindings.instance.unlock(fd);
    } catch (_) {}
    try {
      _PosixFlockBindings.instance._fcloseStream(_stream);
    } catch (_) {}
  }
}

/// POSIX open-file-description advisory lock bindings (`flock`).
///
/// Unlike `RandomAccessFile.lockSync` (which uses process-associated `fcntl`
/// locks on Linux/Android and therefore does not block sibling Dart `Isolate`s
/// within the same OS process), each `open()` call creates an independent open
/// file description whose `flock(LOCK_EX | LOCK_NB)` blocks both sibling
/// `Isolate`s and separate OS processes, and is automatically released by the
/// kernel if a holder process crashes or is killed, or via `NativeFinalizer`
/// (`fclose`) if a background `FlutterEngine` / `IsolateGroup` is destroyed
/// within a shared host process.
final class _PosixFlockBindings {
  _PosixFlockBindings._() {
    final lib = ffi.DynamicLibrary.process();
    _malloc = lib.lookupFunction<_PosixMallocNative, _PosixMallocDart>(
      'malloc',
    );
    _free = lib.lookupFunction<_PosixFreeNative, _PosixFreeDart>('free');
    _open2 = lib.lookupFunction<_PosixOpen2Native, _PosixOpen2Dart>('open');
    _flock = lib.lookupFunction<_PosixFlockNative, _PosixFlockDart>('flock');
    _close = lib.lookupFunction<_PosixCloseNative, _PosixCloseDart>('close');
    _fdopen = lib.lookupFunction<_PosixFdopenNative, _PosixFdopenDart>(
      'fdopen',
    );
    final fclosePtr = lib.lookup<ffi.NativeFunction<_PosixFcloseNative>>(
      'fclose',
    );
    _fclose = fclosePtr.asFunction<_PosixFcloseDart>();
    _fcloseFinalizer = ffi.NativeFinalizer(
      fclosePtr.cast<ffi.NativeFinalizerFunction>(),
    );
    final modeBuf = _malloc(3);
    if (modeBuf == ffi.nullptr) {
      throw const FileSystemException('Failed to allocate fdopen mode buffer');
    }
    _rwModePtr = modeBuf.cast<ffi.Uint8>()
      ..asTypedList(3).setAll(0, const <int>[0x72, 0x2B, 0]); // "r+\0"
  }

  static final _PosixFlockBindings instance = _PosixFlockBindings._();

  // Identical across Linux, Android (Bionic), macOS, and iOS (Darwin).
  static const int _oRdWr = 2;
  static const int _lockEx = 2;
  static const int _lockNb = 4;
  static const int _lockUn = 8;

  late final _PosixMallocDart _malloc;
  late final _PosixFreeDart _free;
  late final _PosixOpen2Dart _open2;
  late final _PosixFlockDart _flock;
  late final _PosixCloseDart _close;
  late final _PosixFdopenDart _fdopen;
  late final _PosixFcloseDart _fclose;
  late final ffi.NativeFinalizer _fcloseFinalizer;
  late final ffi.Pointer<ffi.Uint8> _rwModePtr;

  int openRdWr(String path) {
    final encoded = utf8.encode(path);
    final rawPtr = _malloc(encoded.length + 1);
    if (rawPtr == ffi.nullptr) {
      return -1;
    }
    final bytePtr = rawPtr.cast<ffi.Uint8>();
    try {
      bytePtr.asTypedList(encoded.length + 1)
        ..setRange(0, encoded.length, encoded)
        ..[encoded.length] = 0;
      return _open2(bytePtr, _oRdWr);
    } finally {
      _free(rawPtr);
    }
  }

  bool tryLockExclusive(int fd) => _flock(fd, _lockEx | _lockNb) == 0;

  _PosixLockedFileHandle? wrapLockedFd(int fd) {
    final stream = _fdopen(fd, _rwModePtr);
    if (stream == ffi.nullptr) {
      unlock(fd);
      closeFd(fd);
      return null;
    }
    final handle = _PosixLockedFileHandle._(fd, stream);
    _fcloseFinalizer.attach(handle, stream, detach: handle);
    return handle;
  }

  void _detachFinalizer(_PosixLockedFileHandle handle) {
    _fcloseFinalizer.detach(handle);
  }

  void _fcloseStream(ffi.Pointer<ffi.Void> stream) {
    _fclose(stream);
  }

  void unlock(int fd) {
    _flock(fd, _lockUn);
  }

  void closeFd(int fd) {
    _close(fd);
  }
}

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

  static bool _isRetryableLockOpenError(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (code == null) {
      return false;
    }
    if (Platform.isWindows) {
      // ERROR_FILE_NOT_FOUND (2), ERROR_SHARING_VIOLATION (32),
      // ERROR_LOCK_VIOLATION (33).
      return code == 2 || code == 32 || code == 33;
    }
    // POSIX: ENOENT (2), EINTR (4), EAGAIN/EWOULDBLOCK (11 / 35).
    // Non-contention errors such as EPERM (1), EACCES (13), ENOTDIR (20),
    // EISDIR (21), ENFILE (23), EMFILE (24), ENOSPC (28), EROFS (30),
    // ENAMETOOLONG (36), and EDQUOT (122) fail fast.
    return code == 2 || code == 4 || code == 11 || code == 35;
  }

  /// Serializes [action] both across async tasks within the current Isolate and
  /// across concurrent Isolates / OS processes sharing the app's filesystem.
  ///
  /// Uses kernel-managed advisory locks on a permanent canonical lockfile per
  /// [lockName] (`flock` open-file-description locks on POSIX and per-handle
  /// `LockFileEx` via `RandomAccessFile.lockSync` on Windows) without renaming
  /// or unlinking the shared lockfile path. Crashed holders are automatically
  /// released by the OS kernel, and live holders can never be evicted.
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
    final effectiveAcquireTimeout = acquireTimeout <= Duration.zero
        ? const Duration(milliseconds: 10)
        : acquireTimeout;
    final waitWatch = Stopwatch()..start();
    var attempt = 0;
    _PosixLockedFileHandle? lockedPosixHandle;
    RandomAccessFile? lockedWindowsHandle;

    try {
      while (lockedPosixHandle == null && lockedWindowsHandle == null) {
        final entityType = FileSystemEntity.typeSync(
          lockFile.path,
          followLinks: false,
        );
        if (entityType == FileSystemEntityType.directory) {
          throw FileSystemException(
            'Cross-isolate lock path is a directory ($lockName)',
            lockFile.path,
          );
        }

        if (!lockFile.parent.existsSync()) {
          lockFile.parent.createSync(recursive: true);
        }

        var contended = false;
        OSError? lastOsError;

        if (Platform.isWindows) {
          RandomAccessFile? raf;
          try {
            raf = lockFile.openSync(mode: FileMode.append);
          } on FileSystemException catch (e) {
            if (!_isRetryableLockOpenError(e)) {
              rethrow;
            }
            contended = true;
            lastOsError = e.osError;
          }
          if (raf != null) {
            try {
              raf.lockSync(FileLock.exclusive);
              lockedWindowsHandle = raf;
              break;
            } on FileSystemException catch (e) {
              try {
                raf.closeSync();
              } catch (_) {}
              contended = true;
              lastOsError = e.osError;
            }
          }
        } else {
          if (!lockFile.existsSync()) {
            try {
              lockFile.createSync(exclusive: false);
            } on FileSystemException catch (e) {
              if (!_isRetryableLockOpenError(e)) {
                rethrow;
              }
              contended = true;
              lastOsError = e.osError;
            }
          }

          if (!contended) {
            final fd = _PosixFlockBindings.instance.openRdWr(lockFile.path);
            if (fd < 0) {
              if (!lockFile.existsSync()) {
                contended = true;
              } else {
                // Surface the concrete OS error (e.g. EACCES / EROFS / EISDIR)
                // via dart:io rather than spinning on a non-openable path.
                final probe = lockFile.openSync(mode: FileMode.append);
                probe.closeSync();
                throw FileSystemException(
                  'Failed to open cross-isolate lock file ($lockName)',
                  lockFile.path,
                );
              }
            } else if (_PosixFlockBindings.instance.tryLockExclusive(fd)) {
              final wrapped = _PosixFlockBindings.instance.wrapLockedFd(fd);
              if (wrapped == null) {
                throw FileSystemException(
                  'Failed to attach native finalizer to lock file ($lockName)',
                  lockFile.path,
                );
              }
              lockedPosixHandle = wrapped;
              break;
            } else {
              _PosixFlockBindings.instance.closeFd(fd);
              contended = true;
            }
          }
        }

        if (waitWatch.elapsed >= effectiveAcquireTimeout) {
          throw FileSystemException(
            'Timed out acquiring cross-isolate lock ($lockName)',
            lockFile.path,
            lastOsError,
          );
        }

        final delayMs =
            attempt == 0 ? 1 : (attempt < 4 ? 5 : (attempt < 8 ? 10 : 20));
        if (!Platform.isWindows &&
            attempt >= 3 &&
            (attempt == 3 || attempt % 4 == 0)) {
          // If a sibling Isolate in the same IsolateGroup was killed via
          // Isolate.kill(priority: Isolate.immediate) without running finally,
          // nudging young-space allocation under contention prompts Dart GC to
          // run _PosixLockedFileHandle's NativeFinalizer promptly. Separate
          // FlutterEngine / IsolateGroup teardown runs NativeFinalizer directly.
          for (var i = 0; i < 8; i++) {
            Uint8List(512 * 1024);
          }
        }
        attempt++;
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }

      final nextHeld = <String>{
        if (heldLocks is Set<String>) ...heldLocks,
        lockPath,
      };
      return await runZoned(
        action,
        zoneValues: <Object?, Object?>{_heldLocksZoneKey: nextHeld},
      );
    } finally {
      if (lockedPosixHandle != null) {
        lockedPosixHandle.release();
      }
      if (lockedWindowsHandle != null) {
        try {
          lockedWindowsHandle.unlockSync();
        } catch (_) {}
        try {
          lockedWindowsHandle.closeSync();
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
