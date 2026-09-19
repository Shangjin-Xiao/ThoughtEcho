import 'dart:io';

import 'package:dio/dio.dart';
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
  late PathProviderPlatform originalPlatform;

  setUp(() async {
    originalPlatform = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp('apk_download_test_');
    PathProviderPlatform.instance = MockPathProvider(tempDir.path);
    ApkDownloadService.cancelToken = null;
  });

  tearDown(() async {
    ApkDownloadService.cancelToken = null;
    PathProviderPlatform.instance = originalPlatform;
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

  test('cleanupApkFiles skips cleanup when download is in progress', () async {
    final downloadDirName = Platform.isAndroid ? 'Download' : 'downloads';
    final downloadDir = Directory('${tempDir.path}/$downloadDirName');
    await downloadDir.create(recursive: true);

    final apk1 = File('${downloadDir.path}/old_v1.apk');
    final apk2 = File('${downloadDir.path}/ThoughtEcho_latest.apk');
    await apk1.writeAsString('fake apk 1');
    await apk2.writeAsString('fake apk 2');

    // 模拟正在下载中
    ApkDownloadService.cancelToken = CancelToken();
    expect(ApkDownloadService.isDownloading, isTrue);

    await ApkDownloadService.cleanupApkFiles();

    // 因为正在下载，应直接跳过清理，所有文件保留
    expect(await apk1.exists(), isTrue);
    expect(await apk2.exists(), isTrue);
  });

  test('cleanupApkFiles proceeds with cleanup when download was cancelled',
      () async {
    final downloadDirName = Platform.isAndroid ? 'Download' : 'downloads';
    final downloadDir = Directory('${tempDir.path}/$downloadDirName');
    await downloadDir.create(recursive: true);

    final apk1 = File('${downloadDir.path}/old_v1.apk');
    final apk2 = File('${downloadDir.path}/ThoughtEcho_latest.apk');
    await apk1.writeAsString('fake apk 1');
    await apk2.writeAsString('fake apk 2');

    // 模拟已取消的令牌（例如用户取消后令牌未为 null 但已 cancelled）
    final token = CancelToken();
    token.cancel();
    ApkDownloadService.cancelToken = token;
    expect(ApkDownloadService.isDownloading, isFalse);

    await ApkDownloadService.cleanupApkFiles();

    // 已取消时不阻断清理，所有 apk（包括 latest apk）都应被清理
    expect(await apk1.exists(), isFalse);
    expect(await apk2.exists(), isFalse);
  });

  test('cancelDownload cancels token and resets cancelToken to null', () {
    final token = CancelToken();
    ApkDownloadService.cancelToken = token;
    expect(ApkDownloadService.isDownloading, isTrue);
    expect(token.isCancelled, isFalse);

    ApkDownloadService.cancelDownload();

    expect(token.isCancelled, isTrue);
    expect(ApkDownloadService.cancelToken, isNull);
    expect(ApkDownloadService.isDownloading, isFalse);
  });

  test('dispose resets cancelToken and leaves isDownloading false', () {
    final token = CancelToken();
    ApkDownloadService.cancelToken = token;
    expect(ApkDownloadService.isDownloading, isTrue);

    ApkDownloadService.dispose();

    expect(token.isCancelled, isTrue);
    expect(ApkDownloadService.cancelToken, isNull);
    expect(ApkDownloadService.isDownloading, isFalse);
  });
}
