import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/temporary_media_service.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempAppDir;
  MockPathProviderPlatform(this.tempAppDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempAppDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempAppDir;

  setUp(() async {
    tempAppDir = await Directory.systemTemp.createTemp('temp_media_benchmark_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempAppDir);
  });

  tearDown(() async {
    if (await tempAppDir.exists()) {
      await tempAppDir.delete(recursive: true);
    }
  });

  test('TemporaryMediaService.cleanupAllTemporaryFiles benchmark', () async {
    final tempMediaFolder = Directory(path.join(tempAppDir.path, 'temp_media'));
    await tempMediaFolder.create(recursive: true);

    const subfolderCount = 5;
    const filesPerSubfolder = 200;
    int expectedFileCount = 0;

    for (var s = 0; s < subfolderCount; s++) {
      final subDir = Directory(path.join(tempMediaFolder.path, 'sub_$s'));
      await subDir.create(recursive: true);
      for (var f = 0; f < filesPerSubfolder; f++) {
        final file = File(path.join(subDir.path, 'file_$f.tmp'));
        await file.writeAsString('test content $f');
        expectedFileCount++;
      }
    }

    final stopwatch = Stopwatch()..start();
    final cleanedCount = await TemporaryMediaService.cleanupAllTemporaryFiles();
    stopwatch.stop();

    debugPrint(
        'Benchmarked cleanupAllTemporaryFiles: $cleanedCount files in ${stopwatch.elapsedMilliseconds} ms');

    expect(cleanedCount, equals(expectedFileCount));
    final remainingFiles = tempMediaFolder.existsSync()
        ? await tempMediaFolder
            .list(recursive: true)
            .where((entity) => entity is File)
            .length
        : 0;
    expect(remainingFiles, equals(0));
  });
}
