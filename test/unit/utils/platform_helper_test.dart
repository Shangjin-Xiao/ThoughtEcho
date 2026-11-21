import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/platform_helper_io.dart';

Future<void> _holdLockInWorkerIsolate(List<Object> args) async {
  final lockPath = args[0] as String;
  final mainSendPort = args[1] as SendPort;
  final releaseReceivePort = ReceivePort();
  final releaseSignal = Completer<void>();
  releaseReceivePort.listen((_) {
    if (!releaseSignal.isCompleted) {
      releaseSignal.complete();
    }
    releaseReceivePort.close();
  });

  await PlatformHelper.withCrossIsolateLock<void>(
    'worker_held_lock',
    () async {
      mainSendPort.send(releaseReceivePort.sendPort);
      await releaseSignal.future;
    },
    customLockFilePath: lockPath,
    acquireTimeout: const Duration(seconds: 5),
  );
  mainSendPort.send('released');
}

Future<void> _holdLockUntilKilledAbruptly(List<Object> args) async {
  final lockPath = args[0] as String;
  final mainSendPort = args[1] as SendPort;
  final finallyMarkerPath = args[2] as String;
  final keepAlivePort = ReceivePort();
  final hang = Completer<void>();
  keepAlivePort.listen((_) {
    if (!hang.isCompleted) {
      hang.complete();
    }
    keepAlivePort.close();
  });
  try {
    await PlatformHelper.withCrossIsolateLock<void>(
      'abrupt_worker_lock',
      () async {
        mainSendPort.send(pid);
        await hang.future;
      },
      customLockFilePath: lockPath,
      acquireTimeout: const Duration(seconds: 5),
    );
  } finally {
    File(finallyMarkerPath).writeAsStringSync('finally', flush: true);
  }
}

void main() {
  group('PlatformHelper.withCrossIsolateLock', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('platform_lock_test_');
    });

    tearDown(() async {
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
      'fails fast when lock parent path is occupied by a regular file or lock path is a directory',
      () async {
        final blockerFile = File('${tempDir.path}/not_a_directory');
        await blockerFile.writeAsString('blocker');

        final parentWatch = Stopwatch()..start();
        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'invalid_parent_lock',
            () async {},
            customLockFilePath: '${blockerFile.path}/child.lock',
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );
        parentWatch.stop();
        expect(parentWatch.elapsed, lessThan(const Duration(seconds: 1)));

        final existingDirAsLock = Directory('${tempDir.path}/dir.lock')
          ..createSync();
        final dirWatch = Stopwatch()..start();
        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'dir_as_lock',
            () async {},
            customLockFilePath: existingDirAsLock.path,
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );
        dirWatch.stop();
        expect(dirWatch.elapsed, lessThan(const Duration(seconds: 1)));
      },
    );

    test(
      'fails fast without spinning event loop when POSIX directory or lockfile lacks write permission',
      () async {
        if (Platform.isWindows) {
          return;
        }
        final uidResult = await Process.run('id', const <String>['-u']);
        if (uidResult.stdout.toString().trim() == '0') {
          // Root bypasses POSIX permission checks.
          return;
        }

        final readOnlyDir = Directory('${tempDir.path}/readonly_dir')
          ..createSync();
        final chmodDirRes = await Process.run(
          'chmod',
          <String>['0555', readOnlyDir.path],
        );
        expect(chmodDirRes.exitCode, equals(0));

        final dirWatch = Stopwatch()..start();
        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'readonly_dir_lock',
            () async {},
            customLockFilePath: '${readOnlyDir.path}/app.lock',
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );
        dirWatch.stop();
        expect(dirWatch.elapsed, lessThan(const Duration(seconds: 1)));

        final readOnlyLockFile = File('${tempDir.path}/readonly_file.lock')
          ..writeAsStringSync('');
        final chmodFileRes = await Process.run(
          'chmod',
          <String>['0444', readOnlyLockFile.path],
        );
        expect(chmodFileRes.exitCode, equals(0));

        final fileWatch = Stopwatch()..start();
        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'readonly_file_lock',
            () async {},
            customLockFilePath: readOnlyLockFile.path,
            acquireTimeout: const Duration(seconds: 5),
          ),
          throwsA(isA<FileSystemException>()),
        );
        fileWatch.stop();
        expect(fileWatch.elapsed, lessThan(const Duration(seconds: 1)));
      },
    );

    test(
      'yields to event loop and honors acquireTimeout under real cross-isolate lock contention without evicting holder',
      () async {
        final lockPath = '${tempDir.path}/real_contention.lock';
        final handshakePort = ReceivePort();
        addTearDown(handshakePort.close);

        final releasePortCompleter = Completer<SendPort>();
        final workerReleasedCompleter = Completer<void>();
        handshakePort.listen((message) {
          if (message is SendPort && !releasePortCompleter.isCompleted) {
            releasePortCompleter.complete(message);
          } else if (message == 'released' &&
              !workerReleasedCompleter.isCompleted) {
            workerReleasedCompleter.complete();
          }
        });

        await Isolate.spawn(
          _holdLockInWorkerIsolate,
          <Object>[lockPath, handshakePort.sendPort],
        );
        final workerReleasePort = await releasePortCompleter.future.timeout(
          const Duration(seconds: 5),
        );

        var timerTicks = 0;
        final ticker = Timer.periodic(
          const Duration(milliseconds: 5),
          (_) => timerTicks++,
        );
        addTearDown(ticker.cancel);

        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'real_contention_timeout_lock',
            () async {},
            customLockFilePath: lockPath,
            staleLockTimeout: const Duration(milliseconds: 20),
            acquireTimeout: const Duration(milliseconds: 65),
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

        expect(
          timerTicks,
          greaterThan(0),
          reason: '竞争等待期间必须异步让出事件循环，不得同步阻塞主 Isolate 定时器',
        );

        // 释放后台 Isolate 持有的内核文件锁后，主 Isolate 应能立即正常获取同一路径互斥锁
        workerReleasePort.send('release');
        await workerReleasedCompleter.future.timeout(
          const Duration(seconds: 5),
        );

        var acquiredAfterRelease = false;
        await PlatformHelper.withCrossIsolateLock<void>(
          'real_contention_timeout_lock',
          () async {
            acquiredAfterRelease = true;
          },
          customLockFilePath: lockPath,
          acquireTimeout: const Duration(seconds: 2),
        );
        expect(acquiredAfterRelease, isTrue);
      },
    );

    test(
      'serializes concurrent multi-isolate contenders without lock stealing or lost updates',
      () async {
        final lockPath = '${tempDir.path}/multi_contender.lock';
        final stateFile = File('${tempDir.path}/state.txt')
          ..writeAsStringSync('0');
        final activeFile = File('${tempDir.path}/active.txt')
          ..writeAsStringSync('0');

        Future<void> runContenderRound(int id) {
          return Isolate.run(() async {
            await PlatformHelper.withCrossIsolateLock<void>(
              'multi_contender_lock',
              () async {
                final activeNow = int.parse(activeFile.readAsStringSync()) + 1;
                if (activeNow != 1) {
                  throw StateError(
                    'Detected concurrent critical section entry: $activeNow',
                  );
                }
                activeFile.writeAsStringSync('$activeNow', flush: true);
                final current = int.parse(stateFile.readAsStringSync());
                await Future<void>.delayed(const Duration(milliseconds: 12));
                stateFile.writeAsStringSync('${current + 1}', flush: true);
                activeFile.writeAsStringSync('0', flush: true);
              },
              customLockFilePath: lockPath,
              staleLockTimeout: const Duration(milliseconds: 20),
              acquireTimeout: const Duration(seconds: 10),
            );
          });
        }

        await Future.wait(<Future<void>>[
          for (var i = 0; i < 6; i++) runContenderRound(i),
        ]);

        expect(int.parse(stateFile.readAsStringSync()), equals(6));
        expect(int.parse(activeFile.readAsStringSync()), equals(0));
      },
    );

    test(
      'releases POSIX lock via NativeFinalizer when worker isolate stops abruptly without running finally',
      () async {
        if (Platform.isWindows) {
          return;
        }

        final lockPath = '${tempDir.path}/abrupt_worker.lock';
        final finallyFile = File('${tempDir.path}/worker_finally_ran.txt');
        final readyPort = ReceivePort();
        addTearDown(readyPort.close);

        final workerIsolate = await Isolate.spawn(
          _holdLockUntilKilledAbruptly,
          <Object>[lockPath, readyPort.sendPort, finallyFile.path],
        );
        addTearDown(() => workerIsolate.kill(priority: Isolate.immediate));

        final workerPid = await readyPort.first.timeout(
          const Duration(seconds: 5),
        );
        expect(workerPid, equals(pid));

        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'abrupt_worker_lock',
            () async {},
            customLockFilePath: lockPath,
            acquireTimeout: const Duration(milliseconds: 25),
          ),
          throwsA(isA<FileSystemException>()),
        );

        final exitPort = ReceivePort();
        addTearDown(exitPort.close);
        workerIsolate.addOnExitListener(exitPort.sendPort);
        workerIsolate.kill(priority: Isolate.immediate);
        await exitPort.first.timeout(const Duration(seconds: 5));

        expect(
          finallyFile.existsSync(),
          isFalse,
          reason: 'Worker 被强行销毁时 Dart finally 块不会执行',
        );

        var reacquiredInSameProcess = false;
        await PlatformHelper.withCrossIsolateLock<void>(
          'abrupt_worker_lock',
          () async {
            reacquiredInSameProcess = true;
          },
          customLockFilePath: lockPath,
          acquireTimeout: const Duration(seconds: 2),
        );
        expect(reacquiredInSameProcess, isTrue);
      },
    );

    test(
      'releases OS file lock immediately when a separate Dart VM process holding the lock is killed with SIGKILL',
      () async {
        if (Platform.isWindows) {
          return;
        }

        String? dartExecutable;
        final sdkDart = File(
          '${File(Platform.resolvedExecutable).parent.parent.parent.path}/dart-sdk/bin/dart',
        );
        if (sdkDart.existsSync()) {
          dartExecutable = sdkDart.path;
        } else {
          final whichRes = await Process.run('which', const <String>['dart']);
          if (whichRes.exitCode == 0) {
            final resolved = (whichRes.stdout as String).trim();
            if (resolved.isNotEmpty) {
              dartExecutable = resolved;
            }
          }
        }
        expect(dartExecutable, isNotNull);

        final lockPath = '${tempDir.path}/subprocess_holder.lock';
        final readyPath = '${tempDir.path}/subprocess_ready.txt';
        final helperScript = File('${tempDir.path}/hold_posix_flock.dart');
        await helperScript.writeAsString('''
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

typedef _OpenNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32);
typedef _OpenDart = int Function(ffi.Pointer<ffi.Uint8>, int, int);
typedef _FlockNative = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _FlockDart = int Function(int, int);
typedef _MallocNative = ffi.Pointer<ffi.Uint8> Function(ffi.IntPtr);
typedef _MallocDart = ffi.Pointer<ffi.Uint8> Function(int);

Future<void> main(List<String> args) async {
  final lockPath = args[0];
  final readyPath = args[1];
  File(lockPath).createSync(recursive: true);
  final lib = ffi.DynamicLibrary.process();
  final malloc = lib.lookupFunction<_MallocNative, _MallocDart>('malloc');
  final openFn = lib.lookupFunction<_OpenNative, _OpenDart>('open');
  final flockFn = lib.lookupFunction<_FlockNative, _FlockDart>('flock');
  final bytes = utf8.encode(lockPath);
  final ptr = malloc(bytes.length + 1);
  for (var i = 0; i < bytes.length; i++) {
    ptr[i] = bytes[i];
  }
  ptr[bytes.length] = 0;
  final fd = openFn(ptr, 2, 438);
  if (fd < 0) exit(2);
  if (flockFn(fd, 2 | 4) != 0) exit(3);
  File(readyPath).writeAsStringSync('\$pid', flush: true);
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');

        final child = await Process.start(
          dartExecutable!,
          <String>[helperScript.path, lockPath, readyPath],
        );
        addTearDown(() => child.kill(ProcessSignal.sigkill));

        final readyWatch = Stopwatch()..start();
        while (!File(readyPath).existsSync() &&
            readyWatch.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(File(readyPath).existsSync(), isTrue);

        await expectLater(
          PlatformHelper.withCrossIsolateLock<void>(
            'subprocess_holder_lock',
            () async {},
            customLockFilePath: lockPath,
            acquireTimeout: const Duration(milliseconds: 30),
          ),
          throwsA(isA<FileSystemException>()),
        );

        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 5));

        var reacquiredAfterSigkill = false;
        await PlatformHelper.withCrossIsolateLock<void>(
          'subprocess_holder_lock',
          () async {
            reacquiredAfterSigkill = true;
          },
          customLockFilePath: lockPath,
          acquireTimeout: const Duration(seconds: 1),
        );
        expect(reacquiredAfterSigkill, isTrue);
      },
    );
  });
}
