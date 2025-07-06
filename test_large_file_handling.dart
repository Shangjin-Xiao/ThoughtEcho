import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'lib/services/large_file_manager.dart';
import 'lib/services/large_video_handler.dart';

/// 大文件处理功能测试
/// 
/// 这个测试文件验证我们的大文件处理优化是否正常工作
void main() {
  group('大文件处理测试', () {
    late Directory tempDir;
    
    setUpAll(() async {
      // 创建临时测试目录
      tempDir = await Directory.systemTemp.createTemp('large_file_test_');
    });
    
    tearDownAll(() async {
      // 清理测试目录
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    
    test('LargeFileManager - 文件检查功能', () async {
      // 创建一个测试文件
      final testFile = File('${tempDir.path}/test_video.mp4');
      await testFile.writeAsBytes(Uint8List.fromList([0, 1, 2, 3, 4]));
      
      // 测试文件检查
      final canProcess = await LargeFileManager.canProcessFile(testFile.path);
      expect(canProcess, isTrue);
      
      // 测试不存在的文件
      final canProcessNonExistent = await LargeFileManager.canProcessFile('${tempDir.path}/non_existent.mp4');
      expect(canProcessNonExistent, isFalse);
    });
    
    test('LargeFileManager - 文件大小获取', () async {
      // 创建一个已知大小的测试文件
      final testData = Uint8List(1024); // 1KB
      final testFile = File('${tempDir.path}/size_test.mp4');
      await testFile.writeAsBytes(testData);
      
      final fileSize = await LargeFileManager.getFileSizeSecurely(testFile.path);
      expect(fileSize, equals(1024));
    });
    
    test('LargeFileManager - 分块文件复制', () async {
      // 创建源文件
      final sourceData = Uint8List.fromList(List.generate(2048, (i) => i % 256)); // 2KB
      final sourceFile = File('${tempDir.path}/source.mp4');
      await sourceFile.writeAsBytes(sourceData);
      
      // 复制文件
      final targetFile = File('${tempDir.path}/target.mp4');
      
      double lastProgress = 0;
      await LargeFileManager.copyFileInChunks(
        sourceFile.path,
        targetFile.path,
        chunkSize: 512, // 使用小块大小进行测试
        onProgress: (current, total) {
          final progress = current / total;
          expect(progress, greaterThanOrEqualTo(lastProgress));
          lastProgress = progress;
        },
      );
      
      // 验证复制结果
      expect(await targetFile.exists(), isTrue);
      final targetData = await targetFile.readAsBytes();
      expect(targetData, equals(sourceData));
    });
    
    test('LargeVideoHandler - 视频文件信息获取', () async {
      // 创建一个模拟的MP4文件（带有正确的文件头）
      final mp4Header = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20, // 文件大小
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x69, 0x73, 0x6F, 0x6D, // 'isom'
        ...List.generate(16, (i) => 0), // 填充数据
      ]);
      
      final testFile = File('${tempDir.path}/test_video.mp4');
      await testFile.writeAsBytes(mp4Header);
      
      final videoInfo = await LargeVideoHandler.getVideoFileInfo(testFile.path);
      expect(videoInfo, isNotNull);
      expect(videoInfo!.fileName, equals('test_video.mp4'));
      expect(videoInfo.extension, equals('.mp4'));
      expect(videoInfo.fileSize, equals(mp4Header.length));
    });
    
    test('LargeVideoHandler - 视频文件预检查', () async {
      // 测试有效的MP4文件
      final validMp4 = File('${tempDir.path}/valid.mp4');
      await validMp4.writeAsBytes(Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20,
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        ...List.generate(16, (i) => 0),
      ]));
      
      // 这里我们需要访问私有方法，所以暂时跳过这个测试
      // 在实际应用中，预检查会在importLargeVideoSafely中自动执行
    });
    
    test('CancelToken - 取消令牌功能', () {
      final cancelToken = LargeFileManager.createCancelToken();
      
      expect(cancelToken.isCancelled, isFalse);
      
      cancelToken.cancel();
      expect(cancelToken.isCancelled, isTrue);
      
      expect(() => cancelToken.throwIfCancelled(), throwsA(isA<CancelledException>()));
    });
    
    test('LargeFileManager - 内存保护执行', () async {
      // 测试正常执行
      final result = await LargeFileManager.executeWithMemoryProtection(
        () async => 'success',
        operationName: '测试操作',
      );
      expect(result, equals('success'));
      
      // 测试异常处理
      final errorResult = await LargeFileManager.executeWithMemoryProtection(
        () async => throw Exception('测试异常'),
        operationName: '测试操作',
      );
      expect(errorResult, isNull);
    });
  });
  
  group('性能测试', () {
    test('大文件处理性能', () async {
      // 创建一个较大的测试文件（1MB）
      final largeData = Uint8List(1024 * 1024);
      for (int i = 0; i < largeData.length; i++) {
        largeData[i] = i % 256;
      }
      
      final tempDir = await Directory.systemTemp.createTemp('perf_test_');
      final sourceFile = File('${tempDir.path}/large_source.mp4');
      await sourceFile.writeAsBytes(largeData);
      
      final stopwatch = Stopwatch()..start();
      
      final canProcess = await LargeFileManager.canProcessFile(sourceFile.path);
      expect(canProcess, isTrue);
      
      final fileSize = await LargeFileManager.getFileSizeSecurely(sourceFile.path);
      expect(fileSize, equals(largeData.length));
      
      stopwatch.stop();
      
      // 性能检查：操作应该在合理时间内完成
      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 1秒内
      
      // 清理
      await tempDir.delete(recursive: true);
    });
  });
}

/// 辅助函数：创建模拟的视频文件
Future<File> createMockVideoFile(String path, int sizeInBytes) async {
  final file = File(path);
  final data = Uint8List(sizeInBytes);
  
  // 添加MP4文件头
  if (sizeInBytes >= 8) {
    data[4] = 0x66; // 'f'
    data[5] = 0x74; // 't'
    data[6] = 0x79; // 'y'
    data[7] = 0x70; // 'p'
  }
  
  await file.writeAsBytes(data);
  return file;
}