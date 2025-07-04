import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'dart:io';

void main() {
  group('大文件处理测试', () {
    test('LargeFileManager 应该能够处理正常大小的文件', () async {
      // 创建一个临时测试文件
      final tempDir = Directory.systemTemp;
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
    
    test('LargeFileManager 应该拒绝过大的文件', () async {
      // 测试一个不存在的大文件路径
      const fakeGiantFilePath = '/fake/giant/file.bin';
      
      final canProcess = await LargeFileManager.canProcessFile(fakeGiantFilePath);
      expect(canProcess, false);
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
  });
}
