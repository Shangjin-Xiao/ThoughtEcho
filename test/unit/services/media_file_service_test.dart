import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/services/media_file_service.dart';

import '../../test_harness.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    await TestHarness.initialize();
  });

  setUp(() async {
    tempDir = await TestHarness.createTempDirectory('media_file_service_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaFileService - Error Handling & Edge Cases', () {
    test('saveImage returns null when source file does not exist', () async {
      final nonExistentPath = path.join(tempDir.path, 'non_existent_image.png');
      final result = await MediaFileService.saveImage(nonExistentPath);

      expect(result, isNull);
    });

    test('saveImage successfully copies an existing image file', () async {
      final sourceFile = File(path.join(tempDir.path, 'test_image.png'));
      await sourceFile.writeAsString('fake image data');

      final result = await MediaFileService.saveImage(sourceFile.path);

      expect(result, isNotNull);
      expect(File(result!).existsSync(), isTrue);
      expect(await File(result).readAsString(), equals('fake image data'));
    });

    test('saveImage handles exception when cancelToken is cancelled', () async {
      final sourceFile = File(path.join(tempDir.path, 'cancel_image.png'));
      await sourceFile.writeAsString('image data to cancel');

      final cancelToken = CancelToken()..cancel();

      final result = await MediaFileService.saveImage(
        sourceFile.path,
        cancelToken: cancelToken,
      );

      expect(result, isNull);
    });

    test(
        'saveVideo returns null and notifies error when source file does not exist',
        () async {
      final nonExistentPath = path.join(tempDir.path, 'non_existent_video.mp4');
      String? lastStatus;

      final result = await MediaFileService.saveVideo(
        nonExistentPath,
        onStatusUpdate: (status) => lastStatus = status,
      );

      expect(result, isNull);
      expect(lastStatus, contains('保存失败'));
    });

    test('saveVideo handles cancellation correctly', () async {
      final sourceFile = File(path.join(tempDir.path, 'cancel_video.mp4'));
      await sourceFile.writeAsString('video data');

      final cancelToken = CancelToken()..cancel();
      String? lastStatus;

      final result = await MediaFileService.saveVideo(
        sourceFile.path,
        cancelToken: cancelToken,
        onStatusUpdate: (status) => lastStatus = status,
      );

      expect(result, isNull);
      expect(lastStatus, contains('操作已取消'));
    });

    test('saveVideo successfully copies video file', () async {
      final sourceFile = File(path.join(tempDir.path, 'sample_video.mp4'));
      await sourceFile.writeAsString('video content payload');

      final result = await MediaFileService.saveVideo(sourceFile.path);

      expect(result, isNotNull);
      expect(File(result!).existsSync(), isTrue);
    });

    test('saveAudio returns null when source file does not exist', () async {
      final nonExistentPath = path.join(tempDir.path, 'non_existent_audio.mp3');
      final result = await MediaFileService.saveAudio(nonExistentPath);

      expect(result, isNull);
    });

    test('saveAudio successfully copies audio file', () async {
      final sourceFile = File(path.join(tempDir.path, 'sample_audio.mp3'));
      await sourceFile.writeAsString('audio content payload');

      final result = await MediaFileService.saveAudio(sourceFile.path);

      expect(result, isNotNull);
      expect(File(result!).existsSync(), isTrue);
    });

    test(
        'saveTempHtmlFile saves file in temporary folder and returns target path',
        () async {
      final result = await MediaFileService.saveTempHtmlFile(
        '<html><body>Test</body></html>',
        'test.html',
      );

      expect(result, isNotNull);
      final file = File(result!);
      expect(file.existsSync(), isTrue);
      expect(
          await file.readAsString(), equals('<html><body>Test</body></html>'));
    });

    test('deleteMediaFile deletes file inside media directory', () async {
      final appDir = TestHarness.applicationDocumentsDirectory;
      final mediaFile =
          File(path.join(appDir.path, 'media', 'test_delete.txt'));
      await mediaFile.parent.create(recursive: true);
      await mediaFile.writeAsString('to be deleted');

      expect(mediaFile.existsSync(), isTrue);

      final success = await MediaFileService.deleteMediaFile(mediaFile.path);

      expect(success, isTrue);
      expect(mediaFile.existsSync(), isFalse);
    });

    test(
        'deleteMediaFile rejects deleting file outside media directory (sandbox defense)',
        () async {
      final outsideFile = File(path.join(tempDir.path, 'outside.txt'));
      await outsideFile.writeAsString('do not delete');

      final success = await MediaFileService.deleteMediaFile(outsideFile.path);

      expect(success, isFalse);
      expect(outsideFile.existsSync(), isTrue);
    });

    test(
        'deleteMediaFile returns false for non-existent file inside media directory',
        () async {
      final appDir = TestHarness.applicationDocumentsDirectory;
      final mediaFile =
          path.join(appDir.path, 'media', 'non_existent_file.png');

      final success = await MediaFileService.deleteMediaFile(mediaFile);

      expect(success, isFalse);
    });

    test('fileExists returns true when file exists, false otherwise', () async {
      final existingFile = File(path.join(tempDir.path, 'exists.txt'));
      await existingFile.writeAsString('hello');

      expect(await MediaFileService.fileExists(existingFile.path), isTrue);
      expect(
        await MediaFileService.fileExists(
          path.join(tempDir.path, 'does_not_exist.txt'),
        ),
        isFalse,
      );
    });

    test('getAllMediaFilePaths returns empty list if media folder is missing',
        () async {
      final appDir = TestHarness.applicationDocumentsDirectory;
      final mediaDir = Directory(path.join(appDir.path, 'media'));
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }

      final paths = await MediaFileService.getAllMediaFilePaths();
      expect(paths, isEmpty);
    });

    test('restoreMediaFiles returns false when backup dir does not exist',
        () async {
      final nonExistentBackupDir = path.join(tempDir.path, 'no_backup');
      final result =
          await MediaFileService.restoreMediaFiles(nonExistentBackupDir);

      expect(result, isFalse);
    });

    test('restoreMediaFiles successfully restores files from backup directory',
        () async {
      final backupDir = Directory(path.join(tempDir.path, 'backup_dir'));
      final mediaSubDir =
          Directory(path.join(backupDir.path, 'media', 'images'));
      await mediaSubDir.create(recursive: true);

      final backupFile = File(path.join(mediaSubDir.path, 'sample.jpg'));
      await backupFile.writeAsString('restored content');

      int reportedCurrent = 0;
      int reportedTotal = 0;

      final success = await MediaFileService.restoreMediaFiles(
        backupDir.path,
        onProgress: (current, total) {
          reportedCurrent = current;
          reportedTotal = total;
        },
      );

      expect(success, isTrue);
      expect(reportedCurrent, equals(1));
      expect(reportedTotal, equals(1));

      final restoredPath = path.join(
        TestHarness.applicationDocumentsDirectory.path,
        'media',
        'images',
        'sample.jpg',
      );
      expect(File(restoredPath).existsSync(), isTrue);
      expect(
          await File(restoredPath).readAsString(), equals('restored content'));
    });

    test(
        'importLargeFileSecurely returns null if source file missing or fails check',
        () async {
      final nonExistentPath = path.join(tempDir.path, 'large_file.bin');
      final targetDir = path.join(tempDir.path, 'target_dir');

      final result = await MediaFileService.importLargeFileSecurely(
        nonExistentPath,
        targetDir,
      );

      expect(result, isNull);
    });

    test('importFilesSecurely correctly imports images, videos, and audios',
        () async {
      final img = File(path.join(tempDir.path, 'a.png'));
      final vid = File(path.join(tempDir.path, 'b.mp4'));
      final aud = File(path.join(tempDir.path, 'c.mp3'));

      await img.writeAsString('img');
      await vid.writeAsString('vid');
      await aud.writeAsString('aud');

      final results = await MediaFileService.importFilesSecurely([
        img.path,
        vid.path,
        aud.path,
      ]);

      expect(results.length, equals(3));
      for (final res in results) {
        expect(File(res).existsSync(), isTrue);
      }
    });

    test('getMemoryUsageAdvice gives appropriate advice for files', () async {
      final file = File(path.join(tempDir.path, 'normal.txt'));
      await file.writeAsString('normal payload');

      final advice = await MediaFileService.getMemoryUsageAdvice([file.path]);
      expect(advice, contains('文件大小适中'));
    });
  });
}
