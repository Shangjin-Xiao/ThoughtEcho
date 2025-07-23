import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/services/large_video_handler.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

void main() {
  group('大文件处理测试', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = Directory.systemTemp;
    });

    test('LargeFileManager 应该能够处理正常大小的文件', () async {
      // 创建一个临时测试文件
      final testFile = File('${tempDir.path}/test_file.txt');

      // 写入一些测试数据 (1MB)
      final testData = 'x' * (1024 * 1024);
      await testFile.writeAsString(testData);

      try {
        // 测试文件检查功能
        final canProcess = await LargeFileManager.canProcessFile(testFile.path);
        expect(canProcess, true);

        // 测试文件大小获取
        final fileSize = await LargeFileManager.getFileSizeSecurely(
          testFile.path,
        );
        expect(fileSize, testData.length);

        // 测试文件复制
        final targetFile = File('${tempDir.path}/test_copy.txt');
        await LargeFileManager.copyFileInChunks(testFile.path, targetFile.path);

        // 验证复制结果
        expect(await targetFile.exists(), true);
        expect(await targetFile.length(), testData.length);

        // 清理测试文件
        await targetFile.delete();
      } finally {
        // 清理测试文件
        if (await testFile.exists()) {
          await testFile.delete();
        }
      }
    });

    test('LargeFileManager 应该正确处理大文件复制进度', () async {
      // 创建一个较大的测试文件 (5MB)
      final testFile = File('${tempDir.path}/large_test_file.bin');
      const testSize = 5 * 1024 * 1024; // 5MB

      // 创建测试数据
      final buffer = Uint8List(testSize);
      for (int i = 0; i < testSize; i++) {
        buffer[i] = i % 256;
      }

      await testFile.writeAsBytes(buffer);

      try {
        final targetFile = File('${tempDir.path}/large_test_copy.bin');
        final progressUpdates = <double>[];

        await LargeFileManager.copyFileInChunks(
          testFile.path,
          targetFile.path,
          onProgress: (current, total) {
            final progress = current / total;
            progressUpdates.add(progress);
          },
        );

        // 验证复制结果
        expect(await targetFile.exists(), true);
        expect(await targetFile.length(), testSize);

        // 验证进度更新
        expect(progressUpdates.isNotEmpty, true);
        expect(progressUpdates.last, 1.0); // 最后进度应该是100%

        // 验证进度是递增的
        for (int i = 1; i < progressUpdates.length; i++) {
          expect(progressUpdates[i] >= progressUpdates[i - 1], true);
        }

        // 清理
        await targetFile.delete();
      } finally {
        if (await testFile.exists()) {
          await testFile.delete();
        }
      }
    });

    test('LargeFileManager 应该拒绝不存在的文件', () async {
      // 测试一个不存在的文件路径
      const fakeFilePath = '/fake/nonexistent/file.bin';

      final canProcess = await LargeFileManager.canProcessFile(fakeFilePath);
      expect(canProcess, false);
    });

    test('LargeFileManager 应该正确处理取消操作', () async {
      // 创建测试文件
      final testFile = File('${tempDir.path}/cancel_test.bin');
      final testData = 'x' * (2 * 1024 * 1024); // 2MB
      await testFile.writeAsString(testData);

      try {
        final targetFile = File('${tempDir.path}/cancel_test_copy.bin');
        final cancelToken = LargeFileManager.createCancelToken();

        // 立即取消操作
        cancelToken.cancel();

        // 尝试复制文件，应该被取消
        bool exceptionThrown = false;
        try {
          await LargeFileManager.copyFileInChunks(
            testFile.path,
            targetFile.path,
            cancelToken: cancelToken,
          );
        } catch (e) {
          if (e is CancelledException) {
            exceptionThrown = true;
          } else {
            rethrow;
          }
        }

        expect(exceptionThrown, true);

        // 验证目标文件不存在（被清理）
        expect(await targetFile.exists(), false);
      } finally {
        if (await testFile.exists()) {
          await testFile.delete();
        }
      }
    });

    test('LargeFileManager 应该能够处理延迟取消操作', () async {
      // 创建一个较大的测试文件以便有足够时间进行取消
      final testFile = File('${tempDir.path}/delayed_cancel_test.bin');
      final testData = 'x' * (10 * 1024 * 1024); // 10MB
      await testFile.writeAsString(testData);

      try {
        final targetFile = File('${tempDir.path}/delayed_cancel_copy.bin');
        final cancelToken = LargeFileManager.createCancelToken();

        // 延迟取消操作
        Timer(const Duration(milliseconds: 50), () {
          cancelToken.cancel();
        });

        // 尝试复制文件，应该被取消
        bool exceptionThrown = false;
        try {
          await LargeFileManager.copyFileInChunks(
            testFile.path,
            targetFile.path,
            cancelToken: cancelToken,
            chunkSize: 32 * 1024, // 使用较小的块大小确保有多次检查机会
          );
        } catch (e) {
          if (e is CancelledException) {
            exceptionThrown = true;
          } else {
            rethrow;
          }
        }

        expect(exceptionThrown, true);

        // 验证目标文件不存在（被清理）
        expect(await targetFile.exists(), false);
      } finally {
        if (await testFile.exists()) {
          await testFile.delete();
        }
      }
    });

    test('LargeFileManager 应该正确处理边界情况', () async {
      // 测试空文件
      final emptyFile = File('${tempDir.path}/empty_test.txt');
      await emptyFile.writeAsString('');

      try {
        final canProcess = await LargeFileManager.canProcessFile(
          emptyFile.path,
        );
        expect(canProcess, false); // 空文件应该不能处理

        final fileSize = await LargeFileManager.getFileSizeSecurely(
          emptyFile.path,
        );
        expect(fileSize, 0);
      } finally {
        if (await emptyFile.exists()) {
          await emptyFile.delete();
        }
      }

      // 测试不存在的文件
      const nonExistentPath = '/fake/path/that/does/not/exist.txt';
      final canProcessNonExistent = await LargeFileManager.canProcessFile(
        nonExistentPath,
      );
      expect(canProcessNonExistent, false);

      final nonExistentSize = await LargeFileManager.getFileSizeSecurely(
        nonExistentPath,
      );
      expect(nonExistentSize, 0);
    });

    test('取消令牌功能应该完整工作', () {
      final cancelToken = LargeFileManager.createCancelToken();

      expect(cancelToken.isCancelled, false);

      cancelToken.cancel();
      expect(cancelToken.isCancelled, true);

      expect(
        () => cancelToken.throwIfCancelled(),
        throwsA(isA<CancelledException>()),
      );
    });

    test('内存保护功能应该处理各种场景', () async {
      // 测试正常操作
      String? result = await LargeFileManager.executeWithMemoryProtection(
        () async {
          return 'success';
        },
        operationName: '测试操作',
      );

      expect(result, 'success');

      // 测试异常处理
      expect(() async {
        await LargeFileManager.executeWithMemoryProtection(() async {
          throw Exception('测试异常');
        }, operationName: '异常测试');
      }, throwsA(isA<Exception>()));
    });

    test('LargeVideoHandler 应该能够获取视频文件信息', () async {
      // 创建一个模拟的MP4文件（带有正确的文件头）
      final videoFile = File('${tempDir.path}/test_video.mp4');

      // MP4文件的基本文件头模拟
      final mp4Header = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // ftyp box
        0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
        0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32,
        0x61, 0x76, 0x63, 0x31, 0x6D, 0x70, 0x34, 0x31,
      ]);

      // 添加一些内容让文件有一定大小
      final content = List.generate(1024, (i) => i % 256);
      final allBytes = [...mp4Header, ...content];

      await videoFile.writeAsBytes(allBytes);

      try {
        final videoInfo = await LargeVideoHandler.getVideoFileInfo(
          videoFile.path,
        );

        expect(videoInfo, isNotNull);
        expect(videoInfo!.fileName, 'test_video.mp4');
        expect(videoInfo.extension, '.mp4');
        expect(videoInfo.fileSize, allBytes.length);
        expect(videoInfo.fileSizeMB, allBytes.length / (1024 * 1024));
      } finally {
        if (await videoFile.exists()) {
          await videoFile.delete();
        }
      }
    });

    test('LargeVideoHandler 应该能够安全导入视频文件', () async {
      // 创建测试视频文件
      final sourceVideo = File('${tempDir.path}/source_video.mp4');
      final targetDir = Directory('${tempDir.path}/video_target');

      // 创建模拟视频内容（带有MP4文件头）
      final mp4Header = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // ftyp box
        0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
        0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32,
        0x61, 0x76, 0x63, 0x31, 0x6D, 0x70, 0x34, 0x31,
      ]);
      final content = Uint8List.fromList([
        ...mp4Header,
        ...List.generate(1024 * 1024, (i) => i % 256),
      ]); // 1MB+
      await sourceVideo.writeAsBytes(content);

      try {
        final statusUpdates = <String>[];
        double? finalProgress;

        final result = await LargeVideoHandler.importLargeVideoSafely(
          sourceVideo.path,
          targetDir.path,
          onProgress: (progress) {
            finalProgress = progress;
          },
          onStatusUpdate: (status) {
            statusUpdates.add(status);
          },
        );

        expect(result, isNotNull);
        expect(File(result!).existsSync(), true);
        expect(statusUpdates.isNotEmpty, true);
        expect(statusUpdates.any((status) => status.contains('检查视频文件')), true);
        expect(statusUpdates.any((status) => status.contains('导入完成')), true);
        expect(finalProgress, 1.0);

        // 验证文件内容一致性
        final targetFile = File(result);
        final targetContent = await targetFile.readAsBytes();
        expect(targetContent.length, content.length);

        // 清理
        await targetFile.delete();
        if (await targetDir.exists()) {
          await targetDir.delete(recursive: true);
        }
      } finally {
        if (await sourceVideo.exists()) {
          await sourceVideo.delete();
        }
      }
    });

    test('LargeVideoHandler 应该正确处理错误情况', () async {
      // 测试不存在的文件
      final result1 = await LargeVideoHandler.importLargeVideoSafely(
        '/fake/nonexistent/video.mp4',
        tempDir.path,
      );
      expect(result1, isNull);

      // 测试无效的文件格式
      final invalidFile = File('${tempDir.path}/invalid.txt');
      await invalidFile.writeAsString('This is not a video file');

      try {
        final result2 = await LargeVideoHandler.importLargeVideoSafely(
          invalidFile.path,
          tempDir.path,
        );
        expect(result2, isNull);
      } finally {
        if (await invalidFile.exists()) {
          await invalidFile.delete();
        }
      }

      // 测试获取不存在文件的信息
      final videoInfo = await LargeVideoHandler.getVideoFileInfo(
        '/fake/video.mp4',
      );
      expect(videoInfo, isNull);
    });

    test('LargeVideoHandler 应该正确处理取消操作', () async {
      // 创建一个较大的测试视频文件
      final sourceVideo = File('${tempDir.path}/large_cancel_video.mp4');
      final targetDir = Directory('${tempDir.path}/cancel_target');

      // 创建模拟视频内容（较大，以便有时间取消）
      final mp4Header = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // ftyp box
        0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
        0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32,
        0x61, 0x76, 0x63, 0x31, 0x6D, 0x70, 0x34, 0x31,
      ]);
      final content = Uint8List.fromList([
        ...mp4Header,
        ...List.generate(5 * 1024 * 1024, (i) => i % 256),
      ]); // 5MB+
      await sourceVideo.writeAsBytes(content);

      try {
        final cancelToken = LargeFileManager.createCancelToken();

        // 延迟取消操作
        Timer(const Duration(milliseconds: 100), () {
          cancelToken.cancel();
        });

        final result = await LargeVideoHandler.importLargeVideoSafely(
          sourceVideo.path,
          targetDir.path,
          cancelToken: cancelToken,
        );

        // 取消操作应该导致返回null
        expect(result, isNull);

        // 验证目标目录没有残留文件
        if (await targetDir.exists()) {
          final files = await targetDir.list().toList();
          expect(files.isEmpty, true);
        }
      } finally {
        if (await sourceVideo.exists()) {
          await sourceVideo.delete();
        }
        if (await targetDir.exists()) {
          await targetDir.delete(recursive: true);
        }
      }
    });

    test('文件复制应该能够处理各种大小的文件', () async {
      // 测试小文件
      final smallFile = File('${tempDir.path}/small_test.txt');
      await smallFile.writeAsString('Small content');

      // 测试中等文件
      final mediumFile = File('${tempDir.path}/medium_test.bin');
      final mediumData = Uint8List(512 * 1024); // 512KB
      for (int i = 0; i < mediumData.length; i++) {
        mediumData[i] = i % 256;
      }
      await mediumFile.writeAsBytes(mediumData);

      try {
        // 测试小文件复制
        final smallTarget = File('${tempDir.path}/small_copy.txt');
        await LargeFileManager.copyFileInChunks(
          smallFile.path,
          smallTarget.path,
        );
        expect(await smallTarget.exists(), true);
        expect(await smallTarget.length(), await smallFile.length());
        await smallTarget.delete();

        // 测试中等文件复制
        final mediumTarget = File('${tempDir.path}/medium_copy.bin');
        final progressUpdates = <double>[];

        await LargeFileManager.copyFileInChunks(
          mediumFile.path,
          mediumTarget.path,
          onProgress: (current, total) {
            progressUpdates.add(current / total);
          },
        );

        expect(await mediumTarget.exists(), true);
        expect(await mediumTarget.length(), mediumData.length);
        expect(progressUpdates.isNotEmpty, true);
        expect(progressUpdates.last, 1.0);

        await mediumTarget.delete();
      } finally {
        if (await smallFile.exists()) await smallFile.delete();
        if (await mediumFile.exists()) await mediumFile.delete();
      }
    });
  });
}
