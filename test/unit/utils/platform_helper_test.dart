import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/platform_helper_io.dart';

void main() {
  group('PlatformHelper.withCrossIsolateLock', () {
    late Directory tempDir;

    setUp(() async {
      PlatformHelper.debugBeforeLockCreateHook = null;
      tempDir = await Directory.systemTemp.createTemp('platform_lock_test_');
    });

    tearDown(() async {
      PlatformHelper.debugBeforeLockCreateHook = null;
      if (tempDir.existsSync()) {
        try {
          if (!Platform.isWindows) {
            await Process.run('chmod', <String>['-R', 'u+rwx', tempDir.path]);
          }
        } catch (_) {}
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'fails fast without blocking event loop on non-contention storage errors (ENOSPC / EACCES)',
      () async {
        var createAttempts = 0;
        final lockPath = '${tempDir.path}/nospace.lock';
        final noSpaceCode = Platform.isWindows ? 112 : 28;
        PlatformHelper.debugBeforeLockCreateHook = (_) {
          createAttempts++;
          throw FileSystemException(
            'Cannot create file',
            lockPath,
            OSError('No space left on device', noSpaceCode),
          );
        };

        final watch = Stopwatch()..start();
        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'test_nospace_lock',
            () async {},
            customLockFilePath: lockPath,
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );
        watch.stop();

        expect(createAttempts, equals(1));
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      },
    );

    test(
      'fails fast when lock parent path is occupied by a regular file or lock path is a directory',
      () async {
        final blockerFile = File('${tempDir.path}/not_a_directory');
        await blockerFile.writeAsString('blocker');

        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'invalid_parent_lock',
            () async {},
            customLockFilePath: '${blockerFile.path}/child.lock',
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );

        final existingDirAsLock = Directory('${tempDir.path}/dir.lock')
          ..createSync();
        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'dir_as_lock',
            () async {},
            customLockFilePath: existingDirAsLock.path,
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test(
      'fails fast when POSIX directory lacks write permission',
      () async {
        if (Platform.isWindows) {
          return;
        }
        final uidResult = await Process.run('id', const <String>['-u']);
        if (uidResult.stdout.toString().trim() == '0') {
          // Root bypasses POSIX 0555 directory write checks.
          return;
        }

        final readOnlyDir = Directory('${tempDir.path}/readonly_dir')
          ..createSync();
        final chmodRes = await Process.run(
          'chmod',
          <String>['0555', readOnlyDir.path],
        );
        expect(chmodRes.exitCode, equals(0));

        final watch = Stopwatch()..start();
        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'readonly_dir_lock',
            () async {},
            customLockFilePath: '${readOnlyDir.path}/app.lock',
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );
        watch.stop();
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      },
    );

    test(
      'yields to event loop and honors acquireTimeout when retryable create errors leave no lockfile',
      () async {
        final lockPath = '${tempDir.path}/missing_retry.lock';
        var attempts = 0;
        PlatformHelper.debugBeforeLockCreateHook = (_) {
          attempts++;
          throw FileSystemException(
            'Transient contention without file',
            lockPath,
            const OSError('No such file or directory', 2),
          );
        };

        var timerTicks = 0;
        final ticker = Timer.periodic(
          const Duration(milliseconds: 5),
          (_) => timerTicks++,
        );
        addTearDown(ticker.cancel);

        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'missing_file_timeout_lock',
            () async {},
            customLockFilePath: lockPath,
            acquireTimeout: const Duration(milliseconds: 45),
          ),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              contains('Timed out acquiring cross-isolate lock'),
            ),
          ),
        );
        ticker.cancel();

        expect(attempts, greaterThan(1));
        expect(
          timerTicks,
          greaterThan(0),
          reason: '重试循环必须异步让出事件循环，不得同步空转阻塞主 Isolate 定时器',
        );
      },
    );
  });
}
