import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/media_file_service.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  final String docsPath;

  FakePathProviderPlatform({required this.tempPath, required this.docsPath});

  @override
  Future<String?> getTemporaryPath() async => tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaFileService Unit Tests', () {
    late Directory tempDir;
    late Directory docsDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('media_service_test_');
      docsDir = Directory('${tempDir.path}/docs');
      await docsDir.create(recursive: true);

      PathProviderPlatform.instance = FakePathProviderPlatform(
        tempPath: tempDir.path,
        docsPath: docsDir.path,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'getFileSizeSecurely returns correct size for valid file and handles error/nonexistent path',
        () async {
      final testFile = File('${tempDir.path}/sample.txt');
      await testFile.writeAsString('12345'); // 5 bytes

      final size = await MediaFileService.getFileSizeSecurely(testFile.path);
      expect(size, 5);

      final nonexistentPath =
          '${tempDir.path}/nonexistent_file_${DateTime.now().millisecondsSinceEpoch}.txt';
      final nonexistentSize =
          await MediaFileService.getFileSizeSecurely(nonexistentPath);
      expect(nonexistentSize, isA<int>());
    });

    test(
        'hasEnoughSpace returns true for normal size and handles invalid file path gracefully',
        () async {
      final testFile = File('${tempDir.path}/sample.txt');
      await testFile.writeAsString('hello');

      final result = await MediaFileService.hasEnoughSpace(testFile.path);
      expect(result, isTrue);

      final nonexistentPath = '${tempDir.path}/nonexistent.txt';
      final errorResult =
          await MediaFileService.hasEnoughSpace(nonexistentPath);
      expect(errorResult, isTrue);
    });

    test('fileExists returns true when file exists and false when it does not',
        () async {
      final testFile = File('${tempDir.path}/exists.txt');
      await testFile.writeAsString('content');

      expect(await MediaFileService.fileExists(testFile.path), isTrue);

      final nonexistentPath = '${tempDir.path}/does_not_exist.txt';
      expect(await MediaFileService.fileExists(nonexistentPath), isFalse);
    });

    test(
        'saveAudio, saveImage and saveVideo handle non-existent source path error gracefully',
        () async {
      final nonexistentPath = '${tempDir.path}/nonexistent_media.mp3';

      final audioResult = await MediaFileService.saveAudio(nonexistentPath);
      expect(audioResult, isNull);

      final imageResult =
          await MediaFileService.saveImage('${tempDir.path}/nonexistent.jpg');
      expect(imageResult, isNull);

      String? lastStatus;
      final videoResult = await MediaFileService.saveVideo(
        '${tempDir.path}/nonexistent.mp4',
        onStatusUpdate: (status) {
          lastStatus = status;
        },
      );
      expect(videoResult, isNull);
      expect(lastStatus, contains('保存失败'));
    });

    test('saveTempHtmlFile saves content and handles errors gracefully',
        () async {
      final htmlPath = await MediaFileService.saveTempHtmlFile(
          '<h1>Hello</h1>', 'test.html');
      expect(htmlPath, isNotNull);
      final file = File(htmlPath!);
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), '<h1>Hello</h1>');
    });

    test('deleteMediaFile respects sandbox boundaries and deletes valid files',
        () async {
      // 1. Valid file inside media folder
      final mediaDir = Directory('${docsDir.path}/media');
      await mediaDir.create(recursive: true);

      final validFile = File('${mediaDir.path}/photo.jpg');
      await validFile.writeAsString('fake image data');

      final deleteResult =
          await MediaFileService.deleteMediaFile(validFile.path);
      expect(deleteResult, isTrue);
      expect(await validFile.exists(), isFalse);

      // 2. Out of sandbox file
      final outsideFile = File('${tempDir.path}/outside.txt');
      await outsideFile.writeAsString('sensitive');

      final deleteOutsideResult =
          await MediaFileService.deleteMediaFile(outsideFile.path);
      expect(deleteOutsideResult, isFalse);
      expect(await outsideFile.exists(), isTrue);
    });

    test('getMemoryUsageAdvice returns correct advice for small total size',
        () async {
      final file1 = File('${tempDir.path}/f1.txt');
      await file1.writeAsString('hello');

      final advice = await MediaFileService.getMemoryUsageAdvice([file1.path]);
      expect(advice, contains('文件大小适中'));
    });

    test('getMemoryUsageAdvice handles non-existent file paths gracefully',
        () async {
      final nonexistentPath = '${tempDir.path}/nonexistent.txt';

      final advice =
          await MediaFileService.getMemoryUsageAdvice([nonexistentPath]);
      expect(advice, contains('文件大小适中'));
    });

    test('Testing helpers create, write, read and delete files correctly',
        () async {
      final helperDir =
          await MediaFileService.createTempDirForTesting('media_helper_');
      expect(await helperDir.exists(), isTrue);

      final filePath = '${helperDir.path}/helper_file.txt';
      final fileWritten = await MediaFileService.writeFileForTesting(
          filePath, 'helper content');
      expect(await fileWritten.exists(), isTrue);

      final retrievedFile = await MediaFileService.getFileForTesting(filePath);
      expect(retrievedFile.path, filePath);
      expect(await retrievedFile.readAsString(), 'helper content');

      await MediaFileService.deleteForTesting(filePath);
      expect(await fileWritten.exists(), isFalse);

      await MediaFileService.deleteForTesting(helperDir.path, recursive: true);
      expect(await helperDir.exists(), isFalse);
    });
  });
}
