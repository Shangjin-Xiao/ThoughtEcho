import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/media_file_service.dart';

void main() {
  test('MediaFileService.getMemoryUsageAdvice benchmark', () async {
    // 1. Setup: Create temporary files
    final tempDir = await Directory.systemTemp.createTemp('media_benchmark');
    final filePaths = <String>[];
    const fileCount = 1000;

    // Create files
    for (var i = 0; i < fileCount; i++) {
      final file = File('${tempDir.path}/file_$i.txt');
      await file.writeAsString('content');
      filePaths.add(file.path);
    }

    // 2. Measure
    final stopwatch = Stopwatch()..start();

    // CURRENT (Asynchronous) implementation:
    final result = await MediaFileService.getMemoryUsageAdvice(filePaths);

    stopwatch.stop();
    print('Processed $fileCount files in ${stopwatch.elapsedMilliseconds} ms');
    print('Result: $result');

    // 3. Cleanup
    await tempDir.delete(recursive: true);
  });
}
