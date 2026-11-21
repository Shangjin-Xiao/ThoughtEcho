import 'dart:async';
import 'dart:typed_data';

class PlatformHelper {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;

  static bool get is64BitProcess => false;
  static int get pointerBits => 32;

  static final Map<String, Future<void>> _webLocks = <String, Future<void>>{};
  static final Object _heldLocksZoneKey = Object();

  static Future<T> withCrossIsolateLock<T>(
    String lockName,
    Future<T> Function() action, {
    String? customLockFilePath,
  }) async {
    final lockKey = customLockFilePath ?? lockName;
    final heldLocks = Zone.current[_heldLocksZoneKey];
    if (heldLocks is Set<String> && heldLocks.contains(lockKey)) {
      return action();
    }

    final previous = _webLocks[lockKey] ?? Future<void>.value();
    final turnCompleter = Completer<void>();
    _webLocks[lockKey] = turnCompleter.future;

    try {
      await previous;
    } catch (_) {}

    try {
      final nextHeld = <String>{
        if (heldLocks is Set<String>) ...heldLocks,
        lockKey,
      };
      return await runZoned(
        action,
        zoneValues: <Object?, Object?>{_heldLocksZoneKey: nextHeld},
      );
    } finally {
      if (identical(_webLocks[lockKey], turnCompleter.future)) {
        _webLocks.remove(lockKey);
      }
      turnCompleter.complete();
    }
  }

  static Future<String> getCpuArchitecture() async {
    return 'web';
  }

  static Future<String?> readAndroidSystemTimeZone() async {
    return null;
  }

  static Future<Uint8List?> readFileBytesIfExists(String filePath) async {
    return null;
  }

  static Future<bool> archiveOrWipeMmkvFile(
    String mmkvFilePath, {
    required bool wipePlaintext,
  }) async {
    return false;
  }

  static Future<List<String>> resolveCandidateMmkvFiles({
    List<String>? customPaths,
  }) async {
    return customPaths ?? const [];
  }

  static Future<bool> hasPopulatedThoughtEchoDatabase({
    List<String>? customDbPaths,
    String? customDataDirectoryPath,
  }) async {
    return false;
  }
}
