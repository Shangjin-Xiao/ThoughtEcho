import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/motion_photo_utils.dart';
import 'package:thoughtecho/widgets/motion_photo_preview_page.dart';
import 'package:video_player/video_player.dart';

import '../../test_harness.dart';

class _HangingMotionPhotoUtils extends MotionPhotoUtils {
  final Completer<MotionPhotoInfo?> completer = Completer<MotionPhotoInfo?>();
  int detectCallCount = 0;

  @override
  Future<MotionPhotoInfo?> detect(String filePath) {
    detectCallCount++;
    return completer.future;
  }

  @override
  Future<String> extractVideoToTemporaryFile(
    String filePath, {
    MotionPhotoInfo? info,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteTemporaryVideo(String filePath) async {}
}

void main() {
  setUpAll(TestHarness.initialize);
  tearDownAll(TestHarness.tearDown);

  group('Motion photo preview playback', () {
    test('auto returns to still image when playback reaches the end', () {
      final value = VideoPlayerValue(
        duration: const Duration(milliseconds: 1200),
        position: const Duration(milliseconds: 1200),
        isInitialized: true,
        isPlaying: false,
      );

      expect(shouldAutoReturnToStillImage(value), isTrue);
    });

    test('does not auto return while playback is still running', () {
      final value = VideoPlayerValue(
        duration: const Duration(milliseconds: 1200),
        position: const Duration(milliseconds: 400),
        isInitialized: true,
        isPlaying: true,
      );

      expect(shouldAutoReturnToStillImage(value), isFalse);
    });

    test('does not auto return for uninitialized or zero-duration states', () {
      final uninitialized = VideoPlayerValue.uninitialized();
      final zeroDuration = VideoPlayerValue(
        duration: Duration.zero,
        position: Duration.zero,
        isInitialized: true,
        isPlaying: false,
      );

      expect(shouldAutoReturnToStillImage(uninitialized), isFalse);
      expect(shouldAutoReturnToStillImage(zeroDuration), isFalse);
    });
  });

  group('MotionPhotoPreviewPage lifecycle and disposal', () {
    testWidgets(
      'does not throw or leak state when destroyed before detection completes',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final fakeUtils = _HangingMotionPhotoUtils();
          final tempDir =
              Directory.systemTemp.createTempSync('motion_page_test');
          addTearDown(() => tempDir.deleteSync(recursive: true));
          final testFile = File('${tempDir.path}/test.jpg');
          testFile.writeAsBytesSync(List<int>.filled(50, 0), flush: true);

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: MotionPhotoPreviewPage(
                imageUrl: testFile.path,
                motionPhotoUtils: fakeUtils,
              ),
            ),
          );

          // Initial build: post-frame callback has been registered and executed post-frame
          expect(fakeUtils.detectCallCount, 1);

          // Now immediately destroy/unmount the page before detect finishes
          await tester.pumpWidget(const SizedBox());

          // Resolve the hanging detection after the page has been disposed
          fakeUtils.completer.complete(
            const MotionPhotoInfo(videoStart: 0, videoEnd: 50),
          );

          // Pump to process any asynchronous microtasks and timers
          await tester.pump();

          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'does not throw or log crash when error occurs after page is destroyed',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final fakeUtils = _HangingMotionPhotoUtils();
          final tempDir =
              Directory.systemTemp.createTempSync('motion_page_err_test');
          addTearDown(() => tempDir.deleteSync(recursive: true));
          final testFile = File('${tempDir.path}/test.jpg');
          testFile.writeAsBytesSync(List<int>.filled(50, 0), flush: true);

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: MotionPhotoPreviewPage(
                imageUrl: testFile.path,
                motionPhotoUtils: fakeUtils,
              ),
            ),
          );

          expect(fakeUtils.detectCallCount, 1);

          // Destroy the page
          await tester.pumpWidget(const SizedBox());

          // Complete with error
          fakeUtils.completer.completeError(
            const FileSystemException('File deleted during isolate scan'),
          );

          await tester.pump();
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'safely ignores detection result when popped during transition',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final fakeUtils = _HangingMotionPhotoUtils();
          final tempDir =
              Directory.systemTemp.createTempSync('motion_page_nav_test');
          addTearDown(() => tempDir.deleteSync(recursive: true));
          final testFile = File('${tempDir.path}/test.jpg');
          testFile.writeAsBytesSync(List<int>.filled(50, 0), flush: true);

          late BuildContext savedContext;
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Builder(
                builder: (context) {
                  savedContext = context;
                  return const Scaffold(body: Text('Root'));
                },
              ),
            ),
          );

          // Push the route
          unawaited(
            Navigator.of(savedContext).push(
              MaterialPageRoute(
                builder: (_) => MotionPhotoPreviewPage(
                  imageUrl: testFile.path,
                  motionPhotoUtils: fakeUtils,
                ),
              ),
            ),
          );

          await tester.pump(); // Start push transition
          expect(fakeUtils.detectCallCount, 1);

          // Immediately pop before detection finishes
          Navigator.of(savedContext).pop();
          // Finish pop transition with bounded pump
          await tester.pump(const Duration(milliseconds: 500));

          // Now complete the detection
          fakeUtils.completer.complete(
            const MotionPhotoInfo(videoStart: 0, videoEnd: 50),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
