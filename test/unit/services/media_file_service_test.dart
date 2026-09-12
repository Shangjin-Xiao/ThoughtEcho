import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/services/media_file_service.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;

  FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return tempDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaFileService.saveVideo error handling tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('media_file_service_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('源文件不存在时，捕获异常并回调错误状态信息且返回 null', () async {
      final nonExistentPath = path.join(tempDir.path, 'non_existent_video.mp4');
      String? updatedStatus;

      final result = await MediaFileService.saveVideo(
        nonExistentPath,
        onStatusUpdate: (status) {
          updatedStatus = status;
        },
      );

      expect(result, isNull);
      expect(updatedStatus, isNotNull);
      expect(updatedStatus, contains('源文件不存在'));
    });

    test('取消操作抛出 CancelledException 时，捕获异常并返回对应取消提示信息', () async {
      final sourceFile = File(path.join(tempDir.path, 'test_video.mp4'));
      await sourceFile.writeAsBytes([0, 1, 2, 3]);

      String? updatedStatus;

      final result = await MediaFileService.saveVideo(
        sourceFile.path,
        onProgress: (_) {
          throw const CancelledException();
        },
        onStatusUpdate: (status) {
          updatedStatus = status;
        },
      );

      expect(result, isNull);
      expect(updatedStatus, equals('视频导入已取消'));
    });

    test('捕获包含"权限"等其他异常信息时更新对应错误提示', () async {
      final sourceFile = File(path.join(tempDir.path, 'dummy_video.mp4'));
      await sourceFile.writeAsBytes([1, 2, 3]);

      String? updatedStatus;

      final result = await MediaFileService.saveVideo(
        sourceFile.path,
        onProgress: (_) {
          throw Exception('无法访问文件，权限拒绝');
        },
        onStatusUpdate: (status) {
          updatedStatus = status;
        },
      );

      expect(result, isNull);
      expect(updatedStatus, equals('无法访问文件，请检查文件权限'));
    });
  });
}
