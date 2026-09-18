import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/zip_stream_processor.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZipStreamProcessor Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await TestHarness.createTempDirectory('zip_processor_test_');
    });

    tearDown(() async {
      await TestHarness.deleteTempDirectory(tempDir);
    });

    test('createZipStreaming creates zip file skipping non-existent files',
        () async {
      final existingFile = File('${tempDir.path}/test1.txt');
      await existingFile.writeAsString('hello world');

      final zipPath = '${tempDir.path}/output.zip';
      final files = {
        'test1.txt': existingFile.path,
        'non_existent.txt': '${tempDir.path}/does_not_exist.txt',
      };

      int progressCurrent = 0;
      int progressTotal = 0;

      await ZipStreamProcessor.createZipStreaming(
        zipPath,
        files,
        onProgress: (current, total) {
          progressCurrent = current;
          progressTotal = total;
        },
      );

      expect(await File(zipPath).exists(), isTrue);
      expect(progressCurrent, equals(2));
      expect(progressTotal, equals(2));

      final zipInfo = await ZipStreamProcessor.getZipInfo(zipPath);
      expect(zipInfo, isNotNull);
      expect(zipInfo!.fileCount, equals(1));
      expect(zipInfo.fileNames, contains('test1.txt'));
    });
  });

  group('ZipInfo Tests', () {
    test('compressionRatio calculates correctly', () {
      final zipInfo = ZipInfo(
        compressedSize: 50,
        uncompressedSize: 100,
        fileCount: 2,
        fileNames: ['file1.txt', 'file2.txt'],
      );
      expect(zipInfo.compressionRatio, 0.5);
    });

    test('compressionRatio handles 0 uncompressedSize', () {
      final zipInfo = ZipInfo(
        compressedSize: 50,
        uncompressedSize: 0,
        fileCount: 0,
        fileNames: [],
      );
      expect(zipInfo.compressionRatio, 0.0);
    });

    test('compressedSizeFormatted formats to MB', () {
      final zipInfo = ZipInfo(
        compressedSize: 1024 * 1024 * 5, // 5 MB
        uncompressedSize: 100,
        fileCount: 2,
        fileNames: [],
      );
      expect(zipInfo.compressedSizeFormatted, '5.0MB');
    });

    test('uncompressedSizeFormatted formats to MB', () {
      final zipInfo = ZipInfo(
        compressedSize: 100,
        uncompressedSize: 1024 * 1024 * 10, // 10 MB
        fileCount: 2,
        fileNames: [],
      );
      expect(zipInfo.uncompressedSizeFormatted, '10.0MB');
    });

    test('toString formats correctly', () {
      final zipInfo = ZipInfo(
        compressedSize: 1024 * 1024 * 5, // 5 MB
        uncompressedSize: 1024 * 1024 * 10, // 10 MB
        fileCount: 2,
        fileNames: [],
      );
      expect(zipInfo.toString(),
          'ZipInfo(files: 2, compressed: 5.0MB, uncompressed: 10.0MB, ratio: 50.0%)');
    });
  });
}
