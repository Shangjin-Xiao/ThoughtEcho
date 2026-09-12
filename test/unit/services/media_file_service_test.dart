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
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String absPath(String rel) => path.join(tempDir.path, rel);

  Future<File> createTestFile(String relPath,
      {String content = 'test data'}) async {
    final file = File(absPath(relPath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  group('MediaFileService.saveAudio', () {
    test('保存不存在的音频文件时捕获异常并返回 null', () async {
      final nonExistentPath = absPath('non_existent.mp3');
      final result = await MediaFileService.saveAudio(nonExistentPath);
      expect(result, isNull);
    });

    test('成功保存存在的音频文件并返回目标路径', () async {
      final sourceFile =
          await createTestFile('sample.mp3', content: 'audio content');
      double? lastProgress;

      final savedPath = await MediaFileService.saveAudio(
        sourceFile.path,
        onProgress: (p) => lastProgress = p,
      );

      expect(savedPath, isNotNull);
      expect(File(savedPath!).existsSync(), isTrue);
      expect(await File(savedPath).readAsString(), equals('audio content'));
      expect(lastProgress, equals(1.0));
    });

    test('取消令牌已取消时保存音频返回 null', () async {
      final sourceFile =
          await createTestFile('sample_cancel.mp3', content: 'cancel content');
      final cancelToken = CancelToken();
      cancelToken.cancel();

      final savedPath = await MediaFileService.saveAudio(
        sourceFile.path,
        cancelToken: cancelToken,
      );

      expect(savedPath, isNull);
    });
  });

  group('MediaFileService.saveImage', () {
    test('保存不存在的图片文件时返回 null', () async {
      final nonExistentPath = absPath('non_existent.png');
      final result = await MediaFileService.saveImage(nonExistentPath);
      expect(result, isNull);
    });

    test('成功保存存在的图片文件', () async {
      final sourceFile =
          await createTestFile('sample.png', content: 'image bytes');
      double? progress;

      final savedPath = await MediaFileService.saveImage(
        sourceFile.path,
        onProgress: (p) => progress = p,
      );

      expect(savedPath, isNotNull);
      expect(File(savedPath!).existsSync(), isTrue);
      expect(await File(savedPath).readAsString(), equals('image bytes'));
      expect(progress, equals(1.0));
    });

    test('取消令牌已取消时保存图片返回 null', () async {
      final sourceFile =
          await createTestFile('sample_cancel.png', content: 'image bytes');
      final cancelToken = CancelToken();
      cancelToken.cancel();

      final savedPath = await MediaFileService.saveImage(
        sourceFile.path,
        cancelToken: cancelToken,
      );

      expect(savedPath, isNull);
    });
  });

  group('MediaFileService.saveVideo', () {
    test('保存不存在的视频文件时返回 null 并更新状态', () async {
      final nonExistentPath = absPath('non_existent.mp4');
      String? lastStatus;

      final result = await MediaFileService.saveVideo(
        nonExistentPath,
        onStatusUpdate: (s) => lastStatus = s,
      );

      expect(result, isNull);
      expect(lastStatus, contains('保存失败'));
    });

    test('成功保存存在的视频文件', () async {
      final sourceFile =
          await createTestFile('sample.mp4', content: 'video data');
      double? progress;
      final statuses = <String>[];

      final savedPath = await MediaFileService.saveVideo(
        sourceFile.path,
        onProgress: (p) => progress = p,
        onStatusUpdate: (s) => statuses.add(s),
      );

      expect(savedPath, isNotNull);
      expect(File(savedPath!).existsSync(), isTrue);
      expect(await File(savedPath).readAsString(), equals('video data'));
      expect(progress, equals(1.0));
      expect(statuses, isNotEmpty);
    });

    test('已取消时保存视频返回 null 并呈现取消状态消息', () async {
      final sourceFile =
          await createTestFile('sample_cancel.mp4', content: 'video data');
      final cancelToken = CancelToken();
      cancelToken.cancel();
      String? status;

      final savedPath = await MediaFileService.saveVideo(
        sourceFile.path,
        cancelToken: cancelToken,
        onStatusUpdate: (s) => status = s,
      );

      expect(savedPath, isNull);
      expect(status, contains('操作已取消'));
    });
  });

  group('MediaFileService.saveTempHtmlFile', () {
    test('保存临时 HTML 文件成功返回文件路径', () async {
      const htmlContent = '<html><body>Test</body></html>';
      const fileName = 'test.html';

      final savedPath =
          await MediaFileService.saveTempHtmlFile(htmlContent, fileName);

      expect(savedPath, isNotNull);
      final file = File(savedPath!);
      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), equals(htmlContent));
    });
  });

  group('MediaFileService 辅助与校验方法', () {
    test('getFileSizeSecurely 正确获取存在文件的大小或不存在时返回 -1', () async {
      final file = await createTestFile('size_test.txt', content: '12345');
      final size = await MediaFileService.getFileSizeSecurely(file.path);
      expect(size, equals(5));

      final nonExistentSize =
          await MediaFileService.getFileSizeSecurely(absPath('missing.txt'));
      expect(nonExistentSize, equals(-1));
    });

    test('hasEnoughSpace 返回 true', () async {
      final file = await createTestFile('space_test.txt', content: 'space');
      final hasSpace = await MediaFileService.hasEnoughSpace(file.path);
      expect(hasSpace, isTrue);
    });

    test('fileExists 正确判断文件存在状态', () async {
      final file = await createTestFile('exists.txt', content: 'exists');
      expect(await MediaFileService.fileExists(file.path), isTrue);
      expect(
          await MediaFileService.fileExists(absPath('not_here.txt')), isFalse);
    });

    test('deleteMediaFile 严格限制在 App 媒体目录沙箱内删除', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final validMediaDir = Directory(path.join(appDocsDir.path, 'media'));
      await validMediaDir.create(recursive: true);
      final validFile = File(path.join(validMediaDir.path, 'valid.jpg'));
      await validFile.writeAsString('valid');

      final deleteResult =
          await MediaFileService.deleteMediaFile(validFile.path);
      expect(deleteResult, isTrue);
      expect(validFile.existsSync(), isFalse);

      final externalFile =
          await createTestFile('external.jpg', content: 'external');
      final externalDeleteResult =
          await MediaFileService.deleteMediaFile(externalFile.path);
      expect(externalDeleteResult, isFalse);
      expect(externalFile.existsSync(), isTrue);
    });
  });

  group('MediaFileService 遍历、恢复与导入', () {
    test('getAllMediaFilePaths 收集媒体路径', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final mediaDir = Directory(path.join(appDocsDir.path, 'media'));
      await mediaDir.create(recursive: true);
      final file1 = File(path.join(mediaDir.path, 'm1.jpg'));
      await file1.writeAsString('m1');

      final paths = await MediaFileService.getAllMediaFilePaths();
      expect(paths, contains(file1.path));
    });

    test('restoreMediaFiles 从备份恢复文件', () async {
      final backupDir =
          await TestHarness.createTempDirectory('backup_media_test');
      final subFile = File(path.join(backupDir.path, 'media', 'sub', 'b.jpg'));
      await subFile.parent.create(recursive: true);
      await subFile.writeAsString('backup content');

      int progressCurrent = 0;
      int progressTotal = 0;

      final success = await MediaFileService.restoreMediaFiles(
        backupDir.path,
        onProgress: (cur, tot) {
          progressCurrent = cur;
          progressTotal = tot;
        },
      );

      expect(success, isTrue);
      expect(progressCurrent, equals(1));
      expect(progressTotal, equals(1));

      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final restoredFile =
          File(path.join(appDocsDir.path, 'media', 'sub', 'b.jpg'));
      expect(restoredFile.existsSync(), isTrue);
      expect(await restoredFile.readAsString(), equals('backup content'));
    });

    test('restoreMediaFiles 不存在目录返回 false', () async {
      final success = await MediaFileService.restoreMediaFiles(
          absPath('non_existent_backup'));
      expect(success, isFalse);
    });

    test('importLargeFileSecurely 导入文件到目标目录', () async {
      final sourceFile =
          await createTestFile('large.dat', content: 'large content');
      final targetDir = Directory(absPath('imported_large'));

      final importedPath = await MediaFileService.importLargeFileSecurely(
        sourceFile.path,
        targetDir.path,
      );

      expect(importedPath, isNotNull);
      expect(File(importedPath!).existsSync(), isTrue);
      expect(await File(importedPath).readAsString(), equals('large content'));
    });

    test('importFilesSecurely 批量导入不同类型文件', () async {
      final audioFile = await createTestFile('batch.mp3', content: 'audio');
      final imageFile = await createTestFile('batch.jpg', content: 'image');
      final videoFile = await createTestFile('batch.mp4', content: 'video');

      final results = await MediaFileService.importFilesSecurely(
        [audioFile.path, imageFile.path, videoFile.path],
      );

      expect(results.length, equals(3));
      for (final res in results) {
        expect(File(res).existsSync(), isTrue);
      }
    });

    test('getMemoryUsageAdvice 根据文件列表计算建议', () async {
      final smallFile =
          await createTestFile('small_advice.txt', content: 'small');
      final advice =
          await MediaFileService.getMemoryUsageAdvice([smallFile.path]);

      expect(advice, contains('文件大小适中'));
    });
  });
}
