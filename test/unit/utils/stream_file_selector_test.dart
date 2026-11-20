import 'dart:io';

import 'package:file_selector/file_selector.dart' as desktop_selector;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:thoughtecho/utils/stream_file_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StreamFileSelector', () {
    const channel = MethodChannel('thoughtecho/file_selector');
    const imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');

    setUp(() {
      StreamFileSelector.disableNativeSelector();
      StreamFileSelector.debugPlatformOverride = null;
      StreamFileSelector.debugOpenDesktopFile = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      StreamFileSelector.disableNativeSelector();
      StreamFileSelector.debugPlatformOverride = null;
      StreamFileSelector.debugOpenDesktopFile = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(imagePickerChannel, null);
    });

    test('enableNativeSelector should set _useNativeSelector to true',
        () async {
      StreamFileSelector.enableNativeSelector();
      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isTrue);
    });

    test('disableNativeSelector should set _useNativeSelector to false',
        () async {
      StreamFileSelector.enableNativeSelector();
      StreamFileSelector.disableNativeSelector();
      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });

    test(
        'isNativeFileSelectorAvailable should return false if useNativeSelector is false',
        () async {
      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });

    test('isNativeFileSelectorAvailable should handle timeout gracefully',
        () async {
      StreamFileSelector.enableNativeSelector();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          // 模拟超时
          await Future.delayed(const Duration(milliseconds: 2100));
          return true;
        }
        return null;
      });

      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });

    test('isNativeFileSelectorAvailable should handle exception gracefully',
        () async {
      StreamFileSelector.enableNativeSelector();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          throw Exception('Method call failed');
        }
        return null;
      });

      final isAvailable =
          await StreamFileSelector.isNativeFileSelectorAvailable();
      expect(isAvailable, isFalse);
    });

    test('selectVideoFile uses ImagePicker on Android and iOS', () async {
      final tempDir = await Directory.systemTemp.createTemp('video_pick_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sampleVideo = File(p.join(tempDir.path, 'sample.mp4'));
      await sampleVideo.writeAsBytes(List<int>.filled(128, 7));

      final pickerCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(imagePickerChannel, (call) async {
        pickerCalls.add(call);
        if (call.method == 'pickVideo') {
          return sampleVideo.path;
        }
        return null;
      });

      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        pickerCalls.clear();
        StreamFileSelector.debugPlatformOverride = platform;

        final result = await StreamFileSelector.selectVideoFile();

        expect(result, isNotNull, reason: 'Expected result on $platform');
        expect(result!.files, hasLength(1));
        expect(result.files.single.name, equals('sample.mp4'));
        expect(result.files.single.path, equals(sampleVideo.path));
        expect(result.files.single.size, equals(128));
        expect(pickerCalls, hasLength(1));
        expect(pickerCalls.single.method, equals('pickVideo'));
      }
    });

    test('selectVideoFile returns null when mobile picker is cancelled',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(imagePickerChannel, (call) async => null);

      StreamFileSelector.debugPlatformOverride = TargetPlatform.android;
      final result = await StreamFileSelector.selectVideoFile();
      expect(result, isNull);
    });

    test('selectVideoFile uses desktop file_selector on desktop platforms',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('desktop_video_pick_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final desktopVideo = File(p.join(tempDir.path, 'clip.mkv'));
      await desktopVideo.writeAsBytes(List<int>.filled(64, 3));

      var mobilePickerCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(imagePickerChannel, (call) async {
        mobilePickerCalled = true;
        return null;
      });

      StreamFileSelector.debugPlatformOverride = TargetPlatform.linux;
      StreamFileSelector.debugOpenDesktopFile = ({
        required acceptedTypeGroups,
      }) async {
        expect(acceptedTypeGroups, hasLength(1));
        return desktop_selector.XFile(desktopVideo.path);
      };

      final result = await StreamFileSelector.selectVideoFile();
      expect(result, isNotNull);
      expect(result!.files.single.name, equals('clip.mkv'));
      expect(result.files.single.path, equals(desktopVideo.path));
      expect(result.files.single.size, equals(64));
      expect(mobilePickerCalled, isFalse);
    });
  });
}
