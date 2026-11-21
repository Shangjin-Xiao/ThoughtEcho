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
  });
}
