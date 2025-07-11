import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/services/large_video_handler.dart';
import 'dart:io';
import 'dart:typed_data';

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
        final fileSize = await LargeFileManager.getFileSizeSecurely(testFile.path);
        expect(fileSize, testData.length);
        
        // 测试文件复制
        final targetFile = File('${tempDir.path}/test_copy.txt');
        await LargeFileManager.copyFileInChunks(
          testFile.path,
          targetFile.path,
        );
        
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
      final testSize = 5 * 1024 * 1024; // 5MB
      
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
          expect(progressUpdates[i] >= progressUpdates[i-1], true);
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
        
        // 延迟取消操作
        Future.delayed(const Duration(milliseconds: 100), () {
          cancelToken.cancel();
        });
        
        // 尝试复制文件，应该被取消
        expect(() async {
          await LargeFileManager.copyFileInChunks(
            testFile.path,
            targetFile.path,
            cancelToken: cancelToken,
          );
        }, throwsA(isA<CancelledException>()));
        
        // 验证目标文件不存在（被清理）
        await Future.delayed(const Duration(milliseconds: 200));
        expect(await targetFile.exists(), false);
      } finally {
        if (await testFile.exists()) {
          await testFile.delete();
        }
      }
    });
    
    test('内存保护功能应该正常工作', () async {
      String? result = await LargeFileManager.executeWithMemoryProtection(
        () async {
          return 'success';
        },
        operationName: '测试操作',
      );
      
      expect(result, 'success');
    });
    
    test('取消令牌应该正常工作', () {
      final cancelToken = LargeFileManager.createCancelToken();
      
      expect(cancelToken.isCancelled, false);
      
      cancelToken.cancel();
      expect(cancelToken.isCancelled, true);
      
      expect(() => cancelToken.throwIfCancelled(), throwsA(isA<CancelledException>()));
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
        final videoInfo = await LargeVideoHandler.getVideoFileInfo(videoFile.path);
        
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
      
      // 创建模拟视频内容
      final content = Uint8List.fromList(List.generate(1024 * 1024, (i) => i % 256)); // 1MB
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
  });
}
