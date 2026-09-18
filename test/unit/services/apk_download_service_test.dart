import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/apk_download_service.dart';

class MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String testPath;

  MockPathProvider(this.testPath);

  @override
  Future<String?> getExternalStoragePath() async {
    return testPath;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return testPath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('apk_download_test_');
    PathProviderPlatform.instance = MockPathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('cleanupApkFiles removes all .apk files and keeps non-apk files',
      () async {
    final downloadDirName = Platform.isAndroid ? 'Download' : 'downloads';
    final downloadDir = Directory('${tempDir.path}/$downloadDirName');
    await downloadDir.create(recursive: true);

    final apk1 = File('${downloadDir.path}/old_v1.apk');
    final apk2 = File('${downloadDir.path}/ThoughtEcho_latest.APK');
    final txtFile = File('${downloadDir.path}/notes.txt');

    await apk1.writeAsString('fake apk 1');
    await apk2.writeAsString('fake apk 2');
    await txtFile.writeAsString('text file');

    expect(await apk1.exists(), isTrue);
    expect(await apk2.exists(), isTrue);
    expect(await txtFile.exists(), isTrue);

    await ApkDownloadService.cleanupApkFiles();

    expect(await apk1.exists(), isFalse);
    expect(await apk2.exists(), isFalse);
    expect(await txtFile.exists(), isTrue);
  });
}
