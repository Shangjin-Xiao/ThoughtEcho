import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/services/media_file_service.dart';

import '../../test_harness.dart';

void main() {
  setUp(() async {
    await TestHarness.initialize();
  });

  group('MediaFileService - saveTempHtmlFile', () {
    test('saveTempHtmlFile成功保存临时HTML文件', () async {
      const content = '<html><body><h1>Test HTML</h1></body></html>';
      const fileName = 'test_page.html';

      final filePath =
          await MediaFileService.saveTempHtmlFile(content, fileName);

      expect(filePath, isNotNull);
      final savedFile = File(filePath!);
      expect(await savedFile.exists(), isTrue);
      expect(await savedFile.readAsString(), equals(content));
    });

    test('saveTempHtmlFile在处理非法文件名引发异常时捕获并返回null', () async {
      const content = '<html><body>Error</body></html>';
      // 包含空字符 \x00 的文件名会导致底层 File/path 操作抛出 ArgumentError 或 FileSystemException
      const invalidFileName = '\x00invalid_file.html';

      final result =
          await MediaFileService.saveTempHtmlFile(content, invalidFileName);

      expect(result, isNull);
    });
  });

  group('MediaFileService - 媒体文件存储 (Image / Video / Audio)', () {
    test('saveImage成功与源文件不存在处理', () async {
      // 准备临时源文件
      final tempDir = await TestHarness.createTempDirectory('media_src');
      final srcFile = File(path.join(tempDir.path, 'sample.jpg'));
      await srcFile.writeAsString('fake image data');

      final savedPath = await MediaFileService.saveImage(srcFile.path);
      expect(savedPath, isNotNull);
      expect(await File(savedPath!).exists(), isTrue);

      // 源文件不存在
      final nonExistentPath = path.join(tempDir.path, 'non_existent.jpg');
      final failedResult = await MediaFileService.saveImage(nonExistentPath);
      expect(failedResult, isNull);
    });

    test('saveVideo成功与源文件不存在处理', () async {
      final tempDir = await TestHarness.createTempDirectory('video_src');
      final srcFile = File(path.join(tempDir.path, 'sample.mp4'));
      await srcFile.writeAsString('fake video data');

      final savedPath = await MediaFileService.saveVideo(srcFile.path);
      expect(savedPath, isNotNull);
      expect(await File(savedPath!).exists(), isTrue);

      final failedResult = await MediaFileService.saveVideo(
        path.join(tempDir.path, 'missing.mp4'),
      );
      expect(failedResult, isNull);
    });

    test('saveAudio成功与源文件不存在处理', () async {
      final tempDir = await TestHarness.createTempDirectory('audio_src');
      final srcFile = File(path.join(tempDir.path, 'sample.mp3'));
      await srcFile.writeAsString('fake audio data');

      final savedPath = await MediaFileService.saveAudio(srcFile.path);
      expect(savedPath, isNotNull);
      expect(await File(savedPath!).exists(), isTrue);

      final failedResult = await MediaFileService.saveAudio(
        path.join(tempDir.path, 'missing.mp3'),
      );
      expect(failedResult, isNull);
    });
  });

  group('MediaFileService - deleteMediaFile 沙箱防护', () {
    test('允许删除媒体目录内的文件', () async {
      final tempDir = await TestHarness.createTempDirectory('dummy_media');
      final dummyFile = File(path.join(tempDir.path, 'sample.png'));
      await dummyFile.writeAsString('test');

      final savedPath = await MediaFileService.saveImage(dummyFile.path);
      expect(savedPath, isNotNull);
      final nonNullPath = savedPath!;
      expect(await File(nonNullPath).exists(), isTrue);

      final deleted = await MediaFileService.deleteMediaFile(nonNullPath);
      expect(deleted, isTrue);
      expect(await File(nonNullPath).exists(), isFalse);
    });

    test('拒绝删除媒体目录外的任意文件（沙箱防护）', () async {
      final outerDir = await TestHarness.createTempDirectory('outer');
      final outerFile = File(path.join(outerDir.path, 'sensitive.txt'));
      await outerFile.writeAsString('important');

      final deleted = await MediaFileService.deleteMediaFile(outerFile.path);
      expect(deleted, isFalse);
      expect(await outerFile.exists(), isTrue);
    });

    test('删除不存在的媒体文件返回 false', () async {
      final appDir = TestHarness.applicationDocumentsDirectory;
      final nonExistentMedia =
          path.join(appDir.path, 'media', 'images', 'ghost.jpg');

      final result = await MediaFileService.deleteMediaFile(nonExistentMedia);
      expect(result, isFalse);
    });
  });

  group('MediaFileService - 工具函数与信息获取', () {
    test('fileExists, getFileSizeSecurely, hasEnoughSpace', () async {
      final tempDir = await TestHarness.createTempDirectory('utils_test');
      final file = File(path.join(tempDir.path, 'data.txt'));
      await file.writeAsString('1234567890');

      expect(await MediaFileService.fileExists(file.path), isTrue);
      expect(
          await MediaFileService.fileExists(
              path.join(tempDir.path, 'none.txt')),
          isFalse);

      final size = await MediaFileService.getFileSizeSecurely(file.path);
      expect(size, equals(10));

      final hasSpace = await MediaFileService.hasEnoughSpace(file.path);
      expect(hasSpace, isTrue);
    });

    test('getMemoryUsageAdvice 返回合理建议', () async {
      final tempDir = await TestHarness.createTempDirectory('advice_test');
      final file1 = File(path.join(tempDir.path, 'f1.txt'))
        ..writeAsStringSync('a');
      final file2 = File(path.join(tempDir.path, 'f2.txt'))
        ..writeAsStringSync('b');

      final advice = await MediaFileService.getMemoryUsageAdvice([
        file1.path,
        file2.path,
      ]);

      expect(advice, contains('文件大小适中'));
    });

    test('getAllMediaFilePaths 与 restoreMediaFiles', () async {
      final tempDir = await TestHarness.createTempDirectory('backup_src');
      final dummyFile = File(path.join(tempDir.path, 'test_media.jpg'));
      await dummyFile.writeAsString('media bytes');

      final savedPath = await MediaFileService.saveImage(dummyFile.path);
      expect(savedPath, isNotNull);

      final allPaths = await MediaFileService.getAllMediaFilePaths();
      expect(allPaths, contains(savedPath));

      // 备份与还原
      final backupDir = await TestHarness.createTempDirectory('backup_dir');
      final backupFile =
          File(path.join(backupDir.path, 'media', 'images', 'restored.png'));
      await backupFile.parent.create(recursive: true);
      await backupFile.writeAsString('restored content');

      final restoreSuccess =
          await MediaFileService.restoreMediaFiles(backupDir.path);
      expect(restoreSuccess, isTrue);
    });

    test('测试暴露的ForTesting辅助函数', () async {
      final tempDir =
          await MediaFileService.createTempDirForTesting('test_prefix_');
      expect(await tempDir.exists(), isTrue);

      final filePath = path.join(tempDir.path, 'sub', 'file.txt');
      await Directory(path.join(tempDir.path, 'sub')).create(recursive: true);
      final file =
          await MediaFileService.writeFileForTesting(filePath, 'hello testing');
      expect(await file.exists(), isTrue);

      final retrievedFile = await MediaFileService.getFileForTesting(filePath);
      expect(await retrievedFile.readAsString(), equals('hello testing'));

      await MediaFileService.deleteForTesting(filePath);
      expect(await retrievedFile.exists(), isFalse);

      await MediaFileService.deleteForTesting(tempDir.path, recursive: true);
      expect(await tempDir.exists(), isFalse);
    });
  });
}
