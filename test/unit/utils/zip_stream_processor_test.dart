import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/zip_stream_processor.dart';

void main() {
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
